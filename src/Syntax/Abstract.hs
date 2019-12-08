{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}

module Syntax.Abstract where

import Control.Monad.State
import Control.Monad.Except

import Data.Aeson
import Data.Text.Lazy (Text)
import Data.Map (Map)
import Data.Loc
import qualified Data.Map as Map
import GHC.Generics

import qualified Syntax.Concrete as C
import Syntax.Type

type Index = Int

data Program = Program
                [Declaration]           -- declarations
                (Maybe ([Stmt], Pred))  -- statements + postcondition
              deriving (Show)

data Declaration
  = ConstDecl [Const] Type
  | VarDecl [Var] Type
  deriving (Show)

data Stmt
  = Skip                          Loc
  | Abort                         Loc
  | Assign  [Var] [Expr]          Loc
  | Assert  Pred                  Loc
  | Do      Pred Expr [GdCmd]     Loc
  | If      (Maybe Pred) [GdCmd]  Loc
  | Spec                          Loc
  deriving (Show)

instance Located Stmt where
  locOf (Skip l)        = l
  locOf (Abort l)       = l
  locOf (Assign _ _ l)  = l
  locOf (Assert _ l)    = l
  locOf (Do _ _ _ l)    = l
  locOf (If _ _ l)      = l
  locOf (Spec l)        = l

data GdCmd = GdCmd Pred [Stmt] deriving (Show)

getGuards :: [GdCmd] -> [Pred]
getGuards = fst . unzipGdCmds

unzipGdCmds :: [GdCmd] -> ([Pred], [[Stmt]])
unzipGdCmds = unzip . map (\(GdCmd x y) -> (x, y))

--------------------------------------------------------------------------------
-- | Affixing assertions to DO or IF constructs.

infixr 3 <:>
(<:>) :: Monad m => m a -> m [a] -> m [a]
(<:>) = liftM2 (:)

affixAssertions :: [C.Stmt] -> AbstractM [Stmt]
-- affixAssertions = undefined
affixAssertions      []  = return []
affixAssertions (  x:[]) = (:) <$> fromConcrete x <*> pure []
affixAssertions (x:y:xs) = case (x, y) of
  -- AssertWithBnd + DO : affix!
  (C.AssertWithBnd p e _, C.Do q loc) ->
    Do  <$> fromConcrete p <*> fromConcrete e <*> mapM fromConcrete q <*> pure loc
        <:> affixAssertions xs

  -- AssertWithBnd + _
  (C.AssertWithBnd _ _ loc, _) -> throwError $ TransformError $ ExcessBound loc

  -- Assert + DO
  (C.Assert _ loc, C.Do _ _) -> throwError $ TransformError $ MissingBound loc

  -- Assert + If : affix!
  (C.Assert p _, C.If q loc) ->
    If  <$> fmap Just (fromConcrete p)
        <*> mapM fromConcrete q
        <*> pure loc
        <:> affixAssertions xs

  -- _ + Do
  (_, C.Do _ loc) -> throwError $ TransformError $ MissingAssertion loc

  -- otherwise
  _  -> fromConcrete x <:> affixAssertions (y:xs)

--------------------------------------------------------------------------------
-- | Predicates

data BinRel = Eq | LEq | GEq | LTh | GTh
  deriving (Show, Eq, Generic)

data Pred = Term    BinRel Expr Expr
          | Implies Pred Pred
          | Conj    Pred Pred
          | Disj    Pred Pred
          | Neg     Pred
          | Lit     Bool
          | Hole    Index
          deriving (Show, Eq, Generic)

instance ToJSON BinRel where
instance ToJSON Pred where

predEq :: Pred -> Pred -> Bool
predEq = (==)

substP :: Map Text Expr -> Pred -> Pred
substP env (Term rel e1 e2) = Term rel (substE env e1) (substE env e2)
substP env (Implies p q)    = Implies (substP env p) (substP env q)
substP env (Conj p q)       = Conj (substP env p) (substP env q)
substP env (Disj p q)       = Disj (substP env p) (substP env q)
substP env (Neg p)          = Neg (substP env p)
substP _   (Lit b)          = Lit b
substP _   (Hole i)         = Hole i -- undefined -- do we need it?

--------------------------------------------------------------------------------
-- | Expressions

data Lit  = Num Int
          | Bol Bool
          deriving (Show, Eq, Generic)

data Expr = VarE    Var
          | ConstE  Const
          | LitE    Lit
          | ApE     Expr   Expr
          | HoleE   Index  [Subst]
          deriving (Show, Eq, Generic)

instance ToJSON Lit where
instance ToJSON Expr where

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
substE env (ApE e1 e2)  = ApE (substE env e1) (substE env e2)
substE env (HoleE idx subs) = HoleE idx (env:subs)

--------------------------------------------------------------------------------
-- | Variables and stuff

type Const = Text
type Var = Text
data Type = TInt | TBool | TArray Type
          | TFun Type Type
      deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Converting from Concrete Syntax Tree

type AbstractM = ExceptT SyntaxError (State Index)

abstract :: FromConcrete a b => a -> Either SyntaxError b
abstract = runAbstractM . fromConcrete

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
  fromConcrete (C.Type "Int" _) = return TInt
  fromConcrete (C.Type "Bool" _) = return TBool
  fromConcrete (C.Type _ _) = return TBool

instance FromConcrete C.Expr Expr where
  fromConcrete (C.VarE x    _) = VarE   <$> fromConcrete x
  fromConcrete (C.ConstE x  _) = ConstE <$> fromConcrete x
  fromConcrete (C.LitE x    _) = LitE   <$> fromConcrete x
  fromConcrete (C.ApE x y   _) = ApE    <$> fromConcrete x <*> fromConcrete y
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
  fromConcrete (C.HoleP       _) = Hole     <$> index

instance FromConcrete C.Stmt Stmt where
  fromConcrete (C.Assert p   loc) = Assert  <$> fromConcrete p <*> pure loc
  fromConcrete (C.Skip       loc) = Skip    <$> pure loc
  fromConcrete (C.Abort      loc) = Abort   <$> pure loc
  fromConcrete (C.Assign p q loc) = Assign  <$> mapM fromConcrete p
                                            <*> mapM fromConcrete q
                                            <*> pure loc
  fromConcrete (C.If     p   loc) = If      <$> pure Nothing
                                            <*> mapM fromConcrete p
                                            <*> pure loc

  -- Panic because these cases should've been handled by `affixAssertions`
  fromConcrete (C.AssertWithBnd _ _ _) = throwError $ TransformError $ Panic "AssertWithBnd"
  fromConcrete (C.Do     _ _) = throwError $ TransformError $ Panic "Do"
  -- Holes and specs
  fromConcrete (C.Hole loc) = throwError $ TransformError $ DigHole loc
  fromConcrete (C.Spec loc) = Spec <$> pure loc

-- deals with missing Assertions and Bounds
instance FromConcrete [C.Stmt] [Stmt] where
  fromConcrete      []  = return []
  fromConcrete (x : []) = case x of
    C.Do _ loc -> throwError $ TransformError $ MissingAssertion loc
    _          -> fromConcrete x <:> pure []
  fromConcrete (x:y:xs) = affixAssertions (x:y:xs)

instance FromConcrete C.GdCmd GdCmd where
  fromConcrete (C.GdCmd p q _) = GdCmd  <$> fromConcrete p
                                        <*> fromConcrete q

instance FromConcrete C.Declaration Declaration where
  fromConcrete (C.ConstDecl p q _) = ConstDecl  <$> mapM fromConcrete p
                                                <*> fromConcrete q
  fromConcrete (C.VarDecl   p q _) = VarDecl    <$> mapM fromConcrete p
                                                <*> fromConcrete q

instance FromConcrete C.Program Program where
  fromConcrete (C.Program p q _) = Program  <$> mapM fromConcrete p
                                            <*> (fromConcrete q >>= checkStatements)
    where
      -- check if the postcondition of the whole program is missing
      checkStatements :: [Stmt] -> AbstractM (Maybe ([Stmt], Pred))
      checkStatements [] = return Nothing
      checkStatements xs = case last xs of
        Assert r _ -> return (Just (init xs, r))
        _          -> throwError $ TransformError MissingPostcondition
