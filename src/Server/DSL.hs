{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module Server.DSL where

import Control.Monad.Cont
import Control.Monad.Except
import Control.Monad.Trans.Free
import Control.Monad.Writer
import Data.List (find, sortOn)
import Data.Loc
import Data.Loc.Range
import Data.Text (Text)
import qualified Data.Text as Text
import Error
import qualified GCL.Type as TypeChecking
import GCL.WP (StructWarning)
import qualified GCL.WP as WP
import Language.LSP.Types ( Diagnostic )
import Server.CustomMethod
import qualified Syntax.Abstract as A
import Syntax.Concrete.ToAbstract
import Syntax.Parser (Parser, pProgram, pStmts, runParse)
import Syntax.Predicate (PO, Spec (specLoc), specPayload)
import Prelude hiding (span)

--------------------------------------------------------------------------------

-- The "Syntax" of the DSL for handling LSP requests and responses
data Cmd next
  = EditText Range Text (Text -> next)
  | GetFilePath (FilePath -> next)
  | GetSource (Text -> next)
  | PutLastSelection Range next
  | GetLastSelection (Maybe Range -> next)
  | BumpResponseVersion (Int -> next)
  | Log Text next
  | Terminate [ResKind] [Diagnostic]
  deriving (Functor)

type CmdM = FreeT Cmd (Except [Error])

runCmdM :: CmdM a -> Either [Error] (FreeF Cmd a (CmdM a))
runCmdM = runExcept . runFreeT

editText :: Range -> Text -> CmdM Text
editText range text = liftF (EditText range text id)

getFilePath :: CmdM FilePath
getFilePath = liftF (GetFilePath id)

getSource :: CmdM Text
getSource = liftF (GetSource id)

setLastSelection :: Range -> CmdM ()
setLastSelection selection = liftF (PutLastSelection selection ())

getLastSelection :: CmdM (Maybe Range)
getLastSelection = liftF (GetLastSelection id)

logM :: Text -> CmdM ()
logM text = liftF (Log text ())

bumpVersion :: CmdM Int
bumpVersion = liftF (BumpResponseVersion id)

terminate :: [ResKind] -> [Diagnostic] -> CmdM ()
terminate x y = liftF (Terminate x y)

------------------------------------------------------------------------------

-- converts the "?" at a given location to "[!   !]"
-- and returns the modified source and the difference of source length
digHole :: Pos -> CmdM Text
digHole pos = do
  let indent = Text.replicate (posCol pos - 1) " "
  let holeText = "[!\n" <> indent <> "\n" <> indent <> "!]"
  editText (Range pos pos) holeText

-- | Try to parse a piece of text in a Spec
refine :: Text -> Range -> CmdM (Spec, Text)
refine source range  = do
  result <- findPointedSpec
  case result of
    Nothing -> throwError [Others "Please place the cursor in side a Spec to refine it"]
    Just spec -> do
      source' <- getSource
      let payload = Text.unlines $ specPayload source' spec
      -- HACK, `pStmts` will kaput if we feed empty strings into it
      let payloadIsEmpty = Text.null (Text.strip payload)
      if payloadIsEmpty
        then return ()
        else void $ parse pStmts payload
      return (spec, payload)
  where
    findPointedSpec :: CmdM (Maybe Spec)
    findPointedSpec = do
      program <- parseProgram source
      (_, specs, _, _) <- sweep program
      return $ find (withinRange range) specs

typeCheck :: A.Program -> CmdM ()
typeCheck p = case runExcept (TypeChecking.checkProg p) of
  Left e -> throwError [TypeError e]
  Right v -> return v

sweep :: A.Program -> CmdM ([PO], [Spec], [A.Expr], [StructWarning])
sweep program@(A.Program _ globalProps _ _ _) =
  case WP.sweep program of
    Left e -> throwError [StructError e]
    Right (pos, specs, warings) -> do
      return (sortOn locOf pos, sortOn locOf specs, globalProps, warings)

--------------------------------------------------------------------------------

-- | Parse with a parser
parse :: Parser a -> Text -> CmdM a
parse p source = do
  filepath <- getFilePath
  case runParse p filepath source of
    Left errors -> throwError $ map SyntacticError errors
    Right val -> return val

parseProgram :: Text -> CmdM A.Program
parseProgram source = do
  concrete <- parse pProgram source
  case runExcept (toAbstract concrete) of
    Left NoLoc -> throwError [Others "NoLoc in parseProgram"]
    Left (Loc start _) -> digHole start >>= parseProgram
    Right program -> return program

--------------------------------------------------------------------------------

