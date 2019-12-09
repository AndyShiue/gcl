module Syntax.Concrete where

import Data.Loc
import Data.Text.Lazy (Text)

data Program = Program [Declaration] [Stmt] Loc
  deriving (Show)

data Declaration
  = ConstDecl [Const] Type Loc
  | VarDecl [Var] Type Loc
  deriving (Show)

data Stmt
  = Skip                      Loc
  | Abort                     Loc
  | Assign  [Var] [Expr]      Loc
  | Assert  Pred              Loc
  | AssertWithBnd  Pred Expr  Loc
  | Do            [GdCmd]     Loc
  | If            [GdCmd]     Loc
  | Hole                      Loc -- ?      to be rewritten as {!!} by the frontend
  | Spec                      Loc
  deriving (Show)

data GdCmd = GdCmd Pred [Stmt] Loc deriving (Show)

--------------------------------------------------------------------------------
-- | Predicates

data BinRel = EQ Loc | LTE Loc | GTE Loc | LT Loc | GT Loc
  deriving Show

data Pred = Term    Expr BinRel Expr  Loc
          | Implies Pred Pred         Loc
          | Conj    Pred Pred         Loc
          | Disj    Pred Pred         Loc
          | Neg     Pred              Loc
          | Lit     Bool              Loc
          | HoleP                     Loc
          deriving (Show)

instance Located Pred where
  locOf (Term _ _ _ l)  = l
  locOf (Implies _ _ l) = l
  locOf (Conj _ _ l)    = l
  locOf (Disj _ _ l)    = l
  locOf (Neg _ l)       = l
  locOf (Lit _ l)       = l
  locOf (HoleP l)       = l

--------------------------------------------------------------------------------
-- | Expressions

data Lit  = Num Int
          | Bol Bool
          deriving Show

data Expr = VarE    Var           Loc
          | ConstE  Const         Loc
          | LitE    Lit           Loc
          | ApE     Expr Expr     Loc
          | HoleE                 Loc
          deriving Show

instance Located Expr where
  locOf (VarE _ l)   = l
  locOf (ConstE _ l) = l
  locOf (LitE _ l)   = l
  locOf (ApE _ _ l)  = l
  locOf (HoleE l)    = l

--------------------------------------------------------------------------------
-- | Variables and stuff

data Const = Const Text Loc
  deriving (Show)

data Var = Var Text Loc
  deriving (Show)

data Type = Type Text Loc
  deriving (Show)
