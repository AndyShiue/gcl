module SCM.Test where

import qualified Data.Text.Lazy.IO             as Text

import           Prelude
import           Data.Text.Prettyprint.Doc
import           Data.Text.Internal.Lazy

-- import REPL
import           Syntax.Parser.Lexer            ( TokStream )
import qualified Syntax.Parser.Lexer           as Lexer
import qualified Syntax.Parser                 as Parser
import           Syntax.Concrete

-- import System.Random

-- import GCL.Type

-- import GCL.Exec
-- import GCL.Exec.ExNondet
-- import GCL.Exec.ExRand
import           GCL.WP

import           Pretty.Abstract                ( )
import           Pretty.Predicate               ( )

runtst :: String -> IO ()
runtst filepath = do
      -- let filepath = "SCM/tst1.gcl"
  raw <- Text.readFile filepath

  case scan filepath raw of
    Left  errors  -> print errors
    Right scanned ->
   -- let parsed = scan filepath raw >>=
   --               parseProgram filepath
                     case parseProgram filepath scanned of
      Left  errors                -> print errors
      Right (Program _ _ stmts _) -> do
       -- print program
       -- putStr "\n"
       -- Either StructError ((a, [Obligation]), [Specification])
        case runSM (structProg stmts) (0, 0, 0) of
          Left  err                        -> print err
          Right (((_, obs), specs), state) -> do
            putStrLn "== obligations"
            pprintLs obs
            putStrLn "== specs"
            pprintLs specs
            putStrLn "== state"
            print state
           {-
           case runTM' (checkProg program) of
             (Left terr, tstate) -> print terr >> putStr "\n" >> print tstate
             (Right _, tstate) -> do
                print "typechecked"
                putStr "\n"
                print tstate
                putStr "\n"
                print (runExRand (execProg program) prelude (mkStdGen 813))
            -}

pprintLs :: Pretty a => [a] -> IO ()
pprintLs [] = return ()
pprintLs (x : xs) =
  putStrLn (show (pretty x)) >>
  -- putStr "\n" >>
                                pprintLs xs

-- Copied from REPL, so that I can run this file
--   without making all changes consistant across all modules

scan
  :: FilePath
  -> Data.Text.Internal.Lazy.Text
  -> Either Lexer.LexicalError TokStream
scan filepath = Lexer.scan filepath

parse
  :: Parser.Parser a
  -> FilePath
  -> TokStream
  -> Either [Parser.SyntacticError] a
parse parser filepath = Parser.parse parser filepath

parseProgram :: FilePath -> TokStream -> Either [Parser.SyntacticError] Program
parseProgram = parse Parser.program
