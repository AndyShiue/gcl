{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}

module Server.Handler (handlers) where

-- import qualified Server.CustomMethod as Custom

import Control.Monad.Except
import qualified Data.Aeson as JSON
import Data.Loc
import Data.Loc.Range
import Data.Text (Text, pack)
import qualified Data.Text as Text
import Error
import Language.LSP.Server
import Language.LSP.Types hiding
  ( Range,
    TextDocumentSyncClientCapabilities (..),
  )
import qualified Language.LSP.Types as LSP
import Pretty
import Render
import Server.CustomMethod
import Server.Diagnostic
  ( ToDiagnostics (toDiagnostics),
  )
import Server.ExportPO ()
import Server.Monad
import qualified Syntax.Abstract as A
import Syntax.Predicate (Spec (..))

-- handlers of the LSP server
handlers :: Handlers ServerM
handlers =
  mconcat
    [ -- autocompletion
      requestHandler STextDocumentCompletion $ \req responder -> do
        let RequestMessage _ _ _ params = req
        let CompletionParams (TextDocumentIdentifier _uri) position _progress _partial completionContext = params

        -- only gets triggered when a backslash "\" is typed, or when the previous completion is incomplete
        let triggered = case completionContext of
              (Just (CompletionContext CtTriggerCharacter (Just "\\"))) -> True
              (Just (CompletionContext CtTriggerForIncompleteCompletions _)) -> True
              _ -> False
        if triggered
          then do
            let Position ln col = position
            let replaceRange = LSP.Range (Position ln (col - 1)) position
            let removeSlash = Just $ List [TextEdit replaceRange ""]

            let makeItem label kind symbol detail doc =
                  CompletionItem
                    label
                    kind
                    Nothing
                    (Just detail)
                    (Just $ CompletionDocString doc)
                    Nothing
                    Nothing
                    Nothing
                    Nothing
                    (Just symbol)
                    (Just PlainText)
                    Nothing
                    Nothing
                    removeSlash
                    Nothing
                    Nothing
                    Nothing

            let items =
                  [ makeItem "->" (Just CiOperator) "→" "\"→\" Rightwards Arrow" "The Unicode variant of \"->\"",
                    makeItem "/=" (Just CiOperator) "≠" "\"≠\" Not Equal To" "The Unicode variant of \"/=\"",
                    makeItem ">=" (Just CiOperator) "≥" "\"≥\" Greater-Than or Equal To" "The Unicode variant of \">=\"",
                    makeItem "<=" (Just CiOperator) "≤" "\"≤\" Less-Than or Equal To" "The Unicode variant of \"<=\"",
                    makeItem "=>" (Just CiOperator) "⇒" "\"⇒\" Rightwards Double Arrow" "The Unicode variant of \"=>\"",
                    makeItem "&&" (Just CiOperator) "∧" "\"∧\" Logical And" "The Unicode variant of \"&&\"",
                    makeItem "||" (Just CiOperator) "∨" "\"∨\" Logical Or" "The Unicode variant of \"||\"",
                    makeItem "~" (Just CiOperator) "¬" "\"¬\" Not Sign" "The Unicode variant of \"~\"",
                    makeItem "<|" (Just CiValue) "⟨" "\"⟨\" Left Angle Bracket" "The Unicode variant of \"<|\"",
                    makeItem "|>" (Just CiValue) "⟩" "\"⟩\" Right Angle Bracket" "The Unicode variant of \"|>\"",
                    makeItem "min" (Just CiValue) "↓" "\"↓\" Downwards Arrow" "The Unicode variant of \"min\"",
                    makeItem "max" (Just CiValue) "↑" "\"↑\" Upwards Arrow" "The Unicode variant of \"max\""
                  ]

            let isComplete = True
            let completionList = CompletionList isComplete (List items)
            responder $ Right $ InR completionList
          else responder $ Right $ InR $ CompletionList True (List []),
      -- custom methods, not part of LSP
      requestHandler (SCustomMethod "guacamole") $ \req responderPrim -> do
        let responder = responderPrim . Right . JSON.toJSON
        let RequestMessage _ _ _ params = req
        -- JSON Value => Request => Response
        case JSON.fromJSON params of
          JSON.Error msg -> do
            logText " --> CustomMethod: CannotDecodeRequest"
            responder $ CannotDecodeRequest $ show msg ++ "\n" ++ show params
          JSON.Success request@(Req filepath kind) -> do
            logText $ " --> Custom Reqeust: " <> pack (show request)
            let effEnv = EffEnv filepath (Just responder)
            -- convert Request to Response
            case kind of
              -- Inspect
              ReqInspect selStart selEnd -> do
                interpret effEnv $ do
                  updateLastMouseSelection (selStart, selEnd)
                  source <- savedSource
                  program <- parseProgram source

                  -- typeCheck program
                  -- (pos, _specs, _globalProps, warnings) <- sweep program
                  -- -- display all POs
                  -- let diagnostics = concatMap toDiagnostics pos ++ concatMap toDiagnostics warnings
                  -- -- response with only POs in the vinicity of the cursor
                  -- let filteredPOs = filterPOs (selStart, selEnd) pos
                  -- version <- bumpVersion

                  -- let responses = [ResDisplay version (headerE "Proof Obligaitons" : map renderBlock filteredPOs)]
                  -- terminate responses diagnostics

                  -- parse + type check + sweep
                  temp program (Just (selStart, selEnd))

              -- Refine
              ReqRefine selStart selEnd -> do
                interpret effEnv $ do
                  updateLastMouseSelection (selStart, selEnd)
                  source <- latestSource
                  -- refine (parse + sweep)

                  (spec, content) <- refine source (selStart, selEnd)

                  -- logM "*** SPEC CONTENT ------"
                  -- logM text
                  -- logM "************"

                  -- remove the Spec
                  case specLoc spec of
                    NoLoc -> throwError [Others "NoLoc in ReqRefine"]
                    Loc start end -> do
                      source' <- editText (Range start end) (Text.stripStart content)
                      -- logM $ "*** AFTER REMOVING SPEC\n" <> source'
                      checkAndSendResponsePrim (Just (selStart, selEnd)) source'

              -- Substitute
              ReqSubstitute index expr subst -> do
                interpret effEnv $ do
                  source <- savedSource
                  program <- parseProgram source
                  let expr' = substitute program expr subst
                  terminate [ResSubstitute index expr'] []

              -- ExportProofObligations
              ReqExportProofObligations ->
                responder $ Res filepath [ResConsoleLog "Export"]
              ReqDebug -> return $ error "crash!",
      -- when the client saved the document, store the text for later use
      notificationHandler STextDocumentDidSave $ \ntf -> do
        logText " --> TextDocumentDidSave"
        let NotificationMessage _ _ (DidSaveTextDocumentParams (TextDocumentIdentifier uri) source') = ntf
        case source' of
          Nothing -> pure ()
          Just source ->
            case uriToFilePath uri of
              Nothing -> pure ()
              Just filepath -> do
                let effEnv = EffEnv filepath Nothing
                interpret effEnv $ do
                  updateSavedSource source
                  lastSelection <- readLastMouseSelection
                  checkAndSendResponsePrim lastSelection source,
      -- when the client opened the document
      notificationHandler STextDocumentDidOpen $ \ntf -> do
        logText " --> TextDocumentDidOpen"
        let NotificationMessage _ _ (DidOpenTextDocumentParams (TextDocumentItem uri _ _ source)) = ntf
        case uriToFilePath uri of
          Nothing -> pure ()
          Just filepath -> do
            let effEnv = EffEnv filepath Nothing
            interpret effEnv $ do
              updateSavedSource source
              lastSelection <- readLastMouseSelection
              checkAndSendResponsePrim lastSelection source
    ]

temp :: A.Program -> Maybe (Int, Int) -> EffM ()
temp program lastSelection = do
  (pos, specs, globalProps, warnings) <- sweep program
  let overlappedSpecs = case lastSelection of
        Nothing -> specs
        Just sel -> filterOverlapped sel specs
  let overlappedPOs = case lastSelection of
        Nothing -> pos
        Just sel -> filterOverlapped sel pos
  let warningsSection = if null warnings then [] else headerE "Warnings" : map renderBlock warnings
  let globalPropsSection = if null globalProps then [] else headerE "Global Properties" : map renderBlock globalProps
  let specsSection = if null overlappedSpecs then [] else headerE "Specs" : map renderBlock overlappedSpecs
  let poSection = if null overlappedPOs then [] else headerE "Proof Obligations" : map renderBlock overlappedPOs
  let blocks =
        mconcat
          [ warningsSection,
            specsSection,
            poSection,
            globalPropsSection
          ]

  version <- bumpVersion
  let encodeSpec spec = (specID spec, toText $ render (specPreCond spec), toText $ render (specPostCond spec), specLoc spec)

  let responses = [ResDisplay version blocks, ResUpdateSpecs (map encodeSpec specs)]
  let diagnostics = concatMap toDiagnostics pos ++ concatMap toDiagnostics warnings

  terminate responses diagnostics

-- parse + type check + sweep
checkAndSendResponsePrim :: Maybe (Int, Int) -> Text -> EffM ()
checkAndSendResponsePrim lastSelection source = do
  program <- parseProgram source
  typeCheck program
  temp program lastSelection