{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Server.Monad
  ( ServerM
  , GlobalEnv(globalChan)
  , initGlobalEnv
  , runServerM
  , customRequestResponder
  , customRequestToNotification
  , interpret
  ) where

import           Control.Concurrent             ( Chan
                                                , newChan
                                                , writeChan
                                                )
import           Control.Monad.Reader
import           Control.Monad.Trans.Free
import qualified Data.Aeson                    as JSON
import           Data.IORef                     ( IORef
                                                , modifyIORef'
                                                , newIORef
                                                , readIORef
                                                , writeIORef
                                                )
import           Data.Map                       ( Map )
import qualified Data.Map                      as Map
import qualified Data.Maybe                    as Maybe
import           Data.Text                      ( Text )
import           Error
import qualified Language.LSP.Diagnostics      as J
import qualified Language.LSP.Server           as J
import qualified Language.LSP.Types            as J
import qualified Language.LSP.VFS              as J
import           Pretty                         ( toText )
import           Render
import           Server.CustomMethod
import           Server.DSL                     ( Cmd(..)
                                                , CmdM
                                                , CmdState(..)
                                                , initState
                                                , runCmdM
                                                )
import qualified Server.DSL                    as DSL
import           Server.Handler.Diagnostic      ( collect )
import qualified Server.SrcLoc                 as SrcLoc

--------------------------------------------------------------------------------

interpret
  :: Show a
  => J.Uri
  -> (([Error], Maybe a) -> ServerM ())
  -> CmdM a
  -> ServerM ()
interpret uri continuation p = case J.uriToFilePath uri of
  Nothing       -> pure ()
  Just filepath -> executeOneStep filepath continuation p

executeOneStep
  :: Show a
  => FilePath
  -> (([Error], Maybe a) -> ServerM ())
  -> CmdM a
  -> ServerM ()
executeOneStep filepath continuation p = do
  state <- getState filepath
  case runCmdM filepath state p of
    Right (result, newState, ()) -> do
      -- persist the new state 
      setState filepath newState
      -- see if the computation has completed 
      case result of
        Pure value   -> continuation (cmdErrors newState, Just value)
        Free command -> handleCommand filepath continuation command
    Left errors -> do -- got errors from computation

      oldState <- getState filepath
      logText "      [ event ] unmute"
      let newState =
            oldState { cmdErrors = errors -- update errors for later inspection 
                                         , cmdMute = False } -- unmute on error! 
      setState filepath newState

      continuation (errors, Nothing)

handleCommand
  :: Show a
  => FilePath
  -> (([Error], Maybe a) -> ServerM ())
  -> Cmd (CmdM a)
  -> ServerM ()
handleCommand filepath continuation = \case
  EditText range text next -> do
    -- apply edit
    let removeSpec = J.TextEdit (SrcLoc.toLSPRange range) text

    let identifier =
          J.VersionedTextDocumentIdentifier (J.filePathToUri filepath) (Just 0)
    let textDocumentEdit =
          J.TextDocumentEdit identifier (J.List [J.InL removeSpec])
    let change = J.InL textDocumentEdit
    let workspaceEdit =
          J.WorkspaceEdit Nothing (Just (J.List [change])) Nothing
    let applyWorkspaceEditParams =
          J.ApplyWorkspaceEditParams (Just "Resolve Spec") workspaceEdit
    let callback _ = executeOneStep filepath continuation $ do
          DSL.getSource >>= next

    void $ J.sendRequest J.SWorkspaceApplyEdit applyWorkspaceEditParams callback
  GetSource next -> do
    result <- fmap J.virtualFileText
      <$> J.getVirtualFile (J.toNormalizedUri (J.filePathToUri filepath))
    case result of
      Nothing     -> continuation ([CannotReadFile filepath], Nothing)
      Just source -> executeOneStep filepath continuation (next source)
  Log text next -> do
    logText text
    executeOneStep filepath continuation next
  SendDiagnostics diagnostics next -> do
    -- send diagnostics
    sendDiagnostics filepath diagnostics
    executeOneStep filepath continuation next

--------------------------------------------------------------------------------

-- | State shared by all clients and requests
data GlobalEnv = GlobalEnv
  { -- Channel for printing log
    globalChan         :: Chan Text
  ,
    -- Counter for generating fresh numbers
    globalCounter      :: IORef Int
  , globalCurrentStage :: IORef (Map FilePath CmdState)
  }

-- | Constructs an initial global state
initGlobalEnv :: IO GlobalEnv
initGlobalEnv =
  GlobalEnv
    <$> newChan
    -- <*> newIORef Map.empty
    <*> newIORef 0
    <*> newIORef Map.empty

--------------------------------------------------------------------------------

type ServerM = J.LspT () (ReaderT GlobalEnv IO)

runServerM :: GlobalEnv -> J.LanguageContextEnv () -> ServerM a -> IO a
runServerM env ctxEnv program = runReaderT (J.runLspT ctxEnv program) env

--------------------------------------------------------------------------------
-- | Helper functions for side effects 

-- display Text
logText :: Text -> ServerM ()
logText s = do
  chan <- lift $ asks globalChan
  liftIO $ writeChan chan s

-- send diagnostics
sendDiagnostics :: FilePath -> [J.Diagnostic] -> ServerM ()
sendDiagnostics filepath diagnostics = do
  version <- bumpVersion
  -- only send diagnostics when it's not empty
  -- otherwise the existing diagnostics would be erased 
  unless (null diagnostics) $ do
    J.publishDiagnostics 100
                         (J.toNormalizedUri (J.filePathToUri filepath))
                         (Just version)
                         (J.partitionBySource diagnostics)

bumpVersion :: ServerM Int
bumpVersion = do
  ref <- lift $ asks globalCounter
  n   <- liftIO $ readIORef ref
  liftIO $ writeIORef ref (succ n)
  return n

setState :: FilePath -> CmdState -> ServerM ()
setState filepath state = do
  ref <- lift $ asks globalCurrentStage
  liftIO $ modifyIORef' ref (Map.insert filepath state)

getState :: FilePath -> ServerM CmdState
getState filepath = do
  ref     <- lift $ asks globalCurrentStage
  mapping <- liftIO $ readIORef ref
  case Map.lookup filepath mapping of
    Nothing    -> return $ initState filepath
    Just state -> return state

--------------------------------------------------------------------------------

convertErrors :: FilePath -> [Error] -> ServerM [ResKind]
convertErrors filepath errors = do

  -- convert [Error] to [ResKind]
  version <- bumpVersion
  let responses =
        [ResDisplay version (map renderSection errors), ResUpdateSpecs []]

  -- collect Diagnostics from [Error] 
  let diagnostics = errors >>= collect
  sendDiagnostics filepath diagnostics

  return responses

-- when responding to CustomMethod requests
-- ignore `result` when there's `error`
customRequestResponder
  :: FilePath
  -> (Response -> ServerM ())
  -> ([Error], Maybe [ResKind])
  -> ServerM ()
customRequestResponder filepath responder (errors, result) = if null errors
  then do
    let responses = Maybe.fromMaybe [] result
    responder (Res filepath responses)
  else do
    responsesFromError <- convertErrors filepath errors
    responder (Res filepath responsesFromError)

-- when responding to events like `STextDocumentDidChange`
-- combine both `result` AND `error`
customRequestToNotification :: J.Uri -> ([Error], Maybe [ResKind]) -> ServerM ()
customRequestToNotification uri (errors, result) = case J.uriToFilePath uri of
  Nothing       -> pure ()
  Just filepath -> do
    responsesFromError <- convertErrors filepath errors
    let responses = case result of
          Nothing -> responsesFromError
          Just xs -> responsesFromError <> xs

    logText
      $  "    < Respond with "
      <> toText (length result)
      <> " responses and "
      <> toText (length errors)
      <> " errors"
    -- send responses
    J.sendNotification (J.SCustomMethod "guabao") $ JSON.toJSON $ Res
      filepath
      responses
