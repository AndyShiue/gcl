{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module Server.Handler.CustomMethod where

import           Control.Monad.Except           ( throwError )
import           Control.Monad.State
import qualified Data.Aeson                    as JSON
import qualified Data.IntMap                   as IntMap
import           Data.Loc                       ( Located(locOf)
                                                , posCol
                                                )
import           Data.Loc.Range
import qualified Data.Text                     as Text
import           Data.Text                      ( Text )
import           Error                          ( Error(Others) )
import           GCL.Predicate
import qualified GCL.Substitution              as Substitution
import           Render                         ( Render(render) )
import           Server.CustomMethod
import           Server.DSL
import           Server.Interpreter.RealWorld
import           Syntax.Abstract                ( Redex(redexExpr) )
import           Syntax.Abstract.Util           ( programToScopeForSubstitution
                                                )

handleInspect :: Range -> CmdM [ResKind]
handleInspect range = do
  setLastSelection range
  result <- readCachedResult
  case result of
    Just v  -> generateResponseAndDiagnosticsFromResult v
    Nothing -> return []

handleRefine :: Range -> CmdM [ResKind]
handleRefine range = do
  mute True
  setLastSelection range
  source               <- getSource
  (spec, payloadLines) <- refine source range

  -- remove the Spec
  let indentedPayload = case payloadLines of
        []  -> ""
        [x] -> x
        (x : xs) ->
          let indentation =
                Text.replicate (posCol (rangeStart (specRange spec)) - 1) " "
          in  Text.unlines $ x : map (indentation <>) xs
  source' <- editText (specRange spec) indentedPayload

  program <- parseProgram source'
  typeCheck program
  mute False
  result <- sweep program
  cacheResult (Right result)
  generateResponseAndDiagnosticsFromResult (Right result)

handleInsertAnchor :: Text -> CmdM [ResKind]
handleInsertAnchor hash = do
  -- mute the event listener before editing the source 
  mute True
  -- template of proof to be appended to the source  
  let template = "{- #" <> hash <> "\n\n-}"
  -- range for appending the template of proof 
  source  <- getSource
  program <- parseProgram source
  range   <- case fromLoc (locOf program) of
    Nothing -> throwError [Others "Cannot read the range of the program"]
    Just x  -> return x

  source' <- editText (Range (rangeEnd range) (rangeEnd range))
                      ("\n\n" <> template)

  program' <- parseProgram source'
  typeCheck program'
  mute False
  result <- sweep program'
  cacheResult (Right result)
  generateResponseAndDiagnosticsFromResult (Right result)

handleSubst :: Int -> CmdM [ResKind]
handleSubst i = do
  result <- readCachedResult
  case result of
    Just (Left  _error) -> return []
    Just (Right cache ) -> do
      logM $ Text.pack $ "Substituting Redex " <> show i

      case IntMap.lookup i (cacheRedexes cache) of
        Nothing    -> return []
        Just redex -> do
          let scope = programToScopeForSubstitution (cacheProgram cache)
          let (expr, counter) = runState
                (Substitution.step scope (redexExpr redex))
                (cacheCounter cache)
          let newCache = cache { cacheCounter = counter }
          cacheResult (Right newCache)
          return [ResSubstitute i (render expr)]
    Nothing -> return []

handleCustomMethod :: ReqKind -> CmdM [ResKind]
handleCustomMethod = \case
  ReqInspect      range -> handleInspect range
  ReqRefine       range -> handleRefine range
  ReqInsertAnchor hash  -> handleInsertAnchor hash
  ReqSubstitute   i     -> handleSubst i
  ReqDebug              -> return $ error "crash!"

handler :: JSON.Value -> (Response -> ServerM ()) -> ServerM ()
handler params responder = do
    -- JSON Value => Request => Response
  case JSON.fromJSON params of
    JSON.Error msg -> do
      logText
        $  " --> CustomMethod: CannotDecodeRequest "
        <> Text.pack (show msg)
        <> " "
        <> Text.pack (show params)
      responder $ CannotDecodeRequest $ show msg ++ "\n" ++ show params
    JSON.Success requests -> handleRequests requests
 where
      -- make the type explicit to appease the type checker 
  handleRequests :: [Request] -> ServerM ()
  handleRequests = mapM_ handleRequest

  handleRequest :: Request -> ServerM ()
  handleRequest request@(Req filepath kind) = do
    logText $ " --> Custom Reqeust: " <> Text.pack (show request)
    -- convert Request to Response
    interpret filepath
              (customRequestResponder filepath responder)
              (handleCustomMethod kind)

