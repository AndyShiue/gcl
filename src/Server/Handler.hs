{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}

module Server.Handler
  ( handlers
  ) where

-- import qualified Server.CustomMethod as Custom

import           Control.Lens                   ( (^.) )
import           Control.Monad.Except
import qualified Data.Aeson                    as JSON
import           Data.Loc.Range
import qualified Data.Text                     as Text
import           GCL.Predicate                  ( Spec(..) )
import           Language.LSP.Server
import           Language.LSP.Types      hiding ( Range
                                                , TextDocumentSyncClientCapabilities(..)
                                                )
import           Pretty
import           Render
import           Server.CustomMethod
import           Server.DSL
import           Server.Diagnostic              ( ToDiagnostics(toDiagnostics) )
import           Server.Interpreter.RealWorld

-- import qualified Language.LSP.Types            as J
import qualified Language.LSP.Types.Lens       as J
import qualified Server.Handler.AutoCompletion as AutoCompletion

-- handlers of the LSP server
handlers :: Handlers ServerM
handlers = mconcat
  [ -- autocompletion
    requestHandler STextDocumentCompletion $ \req responder -> do
    let completionContext = req ^. J.params . J.context
    let position          = req ^. J.params . J.position
    AutoCompletion.handler position completionContext >>= responder . Right
  ,
      -- custom methods, not part of LSP
    requestHandler (SCustomMethod "guabao") $ \req responderPrim -> do
    let responder = responderPrim . Right . JSON.toJSON
    let RequestMessage _ _ _ params = req
    -- JSON Value => Request => Response
    case JSON.fromJSON params of
      JSON.Error msg -> do
        logText " --> CustomMethod: CannotDecodeRequest"
        responder $ CannotDecodeRequest $ show msg ++ "\n" ++ show params
      JSON.Success request@(Req filepath kind) -> do
        logText $ " --> Custom Reqeust: " <> Text.pack (show request)
        -- convert Request to Response
        interpret filepath (Just responder) $ do
          case kind of
            -- Inspect
            ReqInspect range -> do
              setLastSelection range
              result <- readCachedResult
              generateResponseAndDiagnosticsFromResult result

            -- Refine
            ReqRefine range -> do
              mute True
              setLastSelection range
              source          <- getSource
              (spec, content) <- refine source range


              -- remove the Spec
              source' <- editText (specRange spec) (Text.stripStart content)

              program         <- parseProgram source'
              typeCheck program
              mute False
              result <- sweep program
              cacheResult (Right result)
              generateResponseAndDiagnosticsFromResult (Right result)

            ReqDebug -> return $ error "crash!"
  ,
      -- when the client saved the document, store the text for later use
      -- notificationHandler STextDocumentDidSave $ \ntf -> do
      --   logText " --> TextDocumentDidSave"
      --   let NotificationMessage _ _ (DidSaveTextDocumentParams (TextDocumentIdentifier uri) source') = ntf
      --   case source' of
      --     Nothing -> pure ()
      --     Just source ->
      --       case uriToFilePath uri of
      --         Nothing -> pure ()
      --         Just filepath -> do
      --           let cmdEnv = CmdEnv filepath Nothing
      --           interpret cmdEnv $ do
      --             program <- parseProgram source
      --             typeCheck program
      --             generateResponseAndDiagnostics program,
      -- when the client opened the document
    notificationHandler STextDocumentDidChange $ \ntf -> do
    m <- getMute
    logText $ " --> TextDocumentDidChange (muted: " <> Text.pack (show m) <> ")"
    unless m $ do
      let
        NotificationMessage _ _ (DidChangeTextDocumentParams (VersionedTextDocumentIdentifier uri _) change)
          = ntf
      logText $ Text.pack $ " --> " <> show change
      case uriToFilePath uri of
        Nothing       -> pure ()
        Just filepath -> do
          interpret filepath Nothing $ do
            source  <- getSource
            program <- parseProgram source
            typeCheck program
            result <- sweep program
            cacheResult (Right result)
            generateResponseAndDiagnosticsFromResult (Right result)
  , notificationHandler STextDocumentDidOpen $ \ntf -> do
    logText " --> TextDocumentDidOpen"
    let
      NotificationMessage _ _ (DidOpenTextDocumentParams (TextDocumentItem uri _ _ source))
        = ntf
    case uriToFilePath uri of
      Nothing       -> pure ()
      Just filepath -> do
        interpret filepath Nothing $ do
          program <- parseProgram source
          typeCheck program
          result <- sweep program
          cacheResult (Right result)
          generateResponseAndDiagnosticsFromResult (Right result)
  ]

generateResponseAndDiagnosticsFromResult :: Result -> CmdM [ResKind]
generateResponseAndDiagnosticsFromResult (Left errors) = throwError errors
generateResponseAndDiagnosticsFromResult (Right (pos, specs, globalProps, warnings))
  = do
  -- leave only POs & Specs around the mouse selection
    lastSelection <- getLastSelection
    let overlappedSpecs = case lastSelection of
          Nothing  -> specs
          Just sel -> filter (withinRange sel) specs
    let overlappedPOs = case lastSelection of
          Nothing  -> pos
          Just sel -> filter (withinRange sel) pos
    -- render stuff
    let warningsSection = if null warnings
          then []
          else headerE "Warnings" : map renderBlock warnings
    let globalPropsSection = if null globalProps
          then []
          else headerE "Global Properties" : map renderBlock globalProps
    let specsSection = if null overlappedSpecs
          then []
          else headerE "Specs" : map renderBlock overlappedSpecs
    let poSection = if null overlappedPOs
          then []
          else headerE "Proof Obligations" : map renderBlock overlappedPOs
    let blocks = mconcat
          [warningsSection, specsSection, poSection, globalPropsSection]

    version <- bumpVersion
    let encodeSpec spec =
          ( specID spec
          , toText $ render (specPreCond spec)
          , toText $ render (specPostCond spec)
          , specRange spec
          )

    let responses =
          [ResDisplay version blocks, ResUpdateSpecs (map encodeSpec specs)]
    let diagnostics =
          concatMap toDiagnostics pos ++ concatMap toDiagnostics warnings
    sendDiagnostics diagnostics

    return responses
