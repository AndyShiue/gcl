{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}

module Syntax.Abstract where

import Control.Monad.Except
import Control.Monad.State
import Data.Text (Text)
import Data.Map (Map)
import qualified Data.Map as Map

import qualified Syntax.Concrete as C

type Index = Int

data Program = Program [Declaration] Stmts
  deriving (Show)

data Declaration
  = ConstDecl [Const] Type
  | VarDecl [Var] Type
  deriving (Show)

data Stmt
  = Skip
  | Abort
  -- | Seq     Stmt Stmt
  | Assign  [Var] [Expr]
  -- | Assert  Pred
  | Do      Expr [GdCmd]
  | If      [GdCmd]
  | Spec    Pred Pred
  deriving (Show)

data GdCmd = GdCmd Pred Stmts deriving (Show)

unzipGdCmds :: [GdCmd] -> ([Pred], [Stmts])
unzipGdCmds = unzip . map (\(GdCmd x y) -> (x, y))

--------------------------------------------------------------------------------
-- | Sequenced Statments

data Stmts  = Seq (Maybe Pred) Stmt Stmts   -- cons
            | Postcondition Pred            -- nil
            deriving (Show)

--------------------------------------------------------------------------------
-- | Predicates

data BinRel = Eq | LEq | GEq | LTh | GTh
  deriving (Show, Eq)

data Pred = Term    BinRel Expr Expr
          | Implies Pred Pred
          | Conj    Pred Pred
          | Disj    Pred Pred
          | Neg     Pred
          | Lit     Bool
          | Hole    Index
          deriving (Show, Eq)

predEq :: Pred -> Pred -> Bool
predEq = (==)

substP :: Map Text Expr -> Pred -> Pred
substP env (Term rel e1 e2) = Term rel (substE env e1) (substE env e2)
substP env (Implies p q)    = Implies (substP env p) (substP env q)
substP env (Conj p q)       = Conj (substP env p) (substP env q)
substP env (Disj p q)       = Disj (substP env p) (substP env q)
substP env (Neg p)          = Neg (substP env p)
substP _   (Lit b)          = Lit b
substP _   (Hole _)         = undefined -- do we need it?

--------------------------------------------------------------------------------
-- | Expressions

data Lit  = Num Int
          | Bol Bool
          deriving (Show, Eq)

type OpName = Text
data Expr = VarE    Var
          | ConstE  Const
          | LitE    Lit
          | OpE     Expr   [Expr]
          | HoleE   Index  [Subst]
          deriving (Show, Eq)

type Subst = Map Text Expr

substE :: Subst -> Expr -> Expr
substE env (VarE x) =
  case Map.lookup x env of
    Just e -> e
    Nothing -> VarE x
substE env (ConstE x) =
  case Map.lookup x env of
    Just e -> e
    Nothing -> ConstE x
substE _   (LitE n)     = LitE n
substE env (OpE op es)  = OpE op (map (substE env) es)
substE env (HoleE idx subs) = HoleE idx (env:subs)

--------------------------------------------------------------------------------
-- | Variables and stuff

type Const = Text
type Var = Text
type Type = Text

--------------------------------------------------------------------------------
-- Converting from Concrete Syntax Tree

-- NOTE: dunno whether this error should be semantical or syntatical
data SyntaxError
  = PostConditionMissing
  | TwoConsecutiveAssertion Pred Pred
  deriving (Show)

type AbstractM = ExceptT SyntaxError (State Index)

abstract :: FromConcrete a b => a -> Either SyntaxError b
abstract = runAbstractM . fromConcrete

convertStmt :: C.Stmt -> AbstractM (Either Pred Stmt)
convertStmt (C.Assert p   _) = Left  <$> fromConcrete p
convertStmt (C.Skip       _) = Right <$> pure Skip
convertStmt (C.Abort      _) = Right <$> pure Abort
convertStmt (C.Assign p q _) = Right <$> (Assign  <$> mapM fromConcrete p
                                                  <*> mapM fromConcrete q)
convertStmt (C.Do     p q _) = Right <$> (Do      <$> fromConcrete p
                                                  <*> mapM fromConcrete q)
convertStmt (C.If     p   _) = Right <$> (If      <$> mapM fromConcrete p)

sequenceStmts :: [C.Stmt] -> AbstractM Stmts
sequenceStmts [] = throwError PostConditionMissing
sequenceStmts (x:[]) = do
  result <- convertStmt x
  case result of
    Left p  -> return $ Postcondition p
    Right p -> error $ show p -- throwError PostConditionMissing
sequenceStmts (x:y:xs) = do
  result1 <- convertStmt x
  case result1 of
    Left p -> do
      result2 <- convertStmt y
      case result2 of
        -- two consecutive assertions
        Left q -> throwError $ TwoConsecutiveAssertion p q
        -- an assertion followed by an ordinary statement
        Right s -> Seq (Just p) s <$> sequenceStmts xs
    Right s -> Seq Nothing s <$> sequenceStmts (y:xs)

runAbstractM :: AbstractM a -> Either SyntaxError a
runAbstractM f = evalState (runExceptT f) 0

-- returns the current index and increment it in the state
index :: AbstractM Index
index = do
  i <- get
  put (succ i)
  return i


class FromConcrete a b | a -> b where
  fromConcrete :: a -> AbstractM b

instance FromConcrete C.Lit Lit where
  fromConcrete (C.Num x) = Num <$> pure x
  fromConcrete (C.Bol x) = Bol <$> pure x

instance FromConcrete C.Const Const where
  fromConcrete (C.Const x _) = pure x

instance FromConcrete C.Var Var where
  fromConcrete (C.Var x _) = pure x

instance FromConcrete C.Type Type where
  fromConcrete (C.Type x _) = pure x

instance FromConcrete C.Expr Expr where
  fromConcrete (C.VarE x    _) = VarE   <$> fromConcrete x
  fromConcrete (C.ConstE x  _) = ConstE <$> fromConcrete x
  fromConcrete (C.LitE x    _) = LitE   <$> fromConcrete x
  fromConcrete (C.OpE x xs  _) = OpE    <$> fromConcrete x <*> mapM fromConcrete xs
  fromConcrete (C.HoleE     _) = HoleE  <$> index <*> pure []

instance FromConcrete C.BinRel BinRel where
  fromConcrete (C.Eq  _) = pure Eq
  fromConcrete (C.LEq _) = pure LEq
  fromConcrete (C.GEq _) = pure GEq
  fromConcrete (C.LTh _) = pure LTh
  fromConcrete (C.GTh _) = pure GTh

instance FromConcrete C.Pred Pred where
  fromConcrete (C.Term p r q  _) = Term     <$> fromConcrete r
                                            <*> fromConcrete p
                                            <*> fromConcrete q
  fromConcrete (C.Implies p q _) = Implies  <$> fromConcrete p
                                            <*> fromConcrete q
  fromConcrete (C.Conj p q    _) = Conj     <$> fromConcrete p
                                            <*> fromConcrete q
  fromConcrete (C.Disj p q    _) = Disj     <$> fromConcrete p
                                            <*> fromConcrete q
  fromConcrete (C.Neg p       _) = Neg      <$> fromConcrete p
  fromConcrete (C.Lit p       _) = Lit      <$> pure p
  fromConcrete (C.Hole        _) = Hole     <$> index

instance FromConcrete C.GdCmd GdCmd where
  fromConcrete (C.GdCmd p q _) = GdCmd  <$> fromConcrete p
                                        <*> sequenceStmts q

instance FromConcrete C.Declaration Declaration where
  fromConcrete (C.ConstDecl p q _) = ConstDecl  <$> mapM fromConcrete p
                                                <*> fromConcrete q
  fromConcrete (C.VarDecl   p q _) = VarDecl    <$> mapM fromConcrete p
                                                <*> fromConcrete q

instance FromConcrete C.Program Program where
  fromConcrete (C.Program p q _) = Program  <$> mapM fromConcrete p
                                            <*> sequenceStmts q
                                             -- (seqAll <$> mapM fromConcrete q)
-- seqAll :: [Stmt] -> Stmt
-- seqAll [] = Skip
-- seqAll (x:xs) = foldl Seq x xs
