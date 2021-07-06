{-# LANGUAGE DeriveGeneric #-}

module Syntax.Abstract.Types where

import Data.Loc ( Loc )
import Data.Map (Map)
import Data.Text (Text)
import GHC.Generics (Generic)
import Syntax.Common ( Op, Name )
import Prelude hiding (Ordering (..))
import Data.Loc.Range ( Range )

--------------------------------------------------------------------------------

type Const = Text

type Var = Text

type TypeVar = Text

--------------------------------------------------------------------------------

-- | Program
data Program
  = Program
      [Declaration] -- constant and variable declarations
      [Expr] -- global properties
      Defns -- let bindings
      [Stmt] -- main program
      Loc
  deriving (Eq, Show)

type Defns = Map Name Expr

--------------------------------------------------------------------------------

-- | Declaration
data Declaration
  = ConstDecl [Name] Type (Maybe Expr) Loc
  | VarDecl [Name] Type (Maybe Expr) Loc
  | LetDecl DeclBody Loc
  | BlockDecl [Name] Type (Maybe Expr) [DeclBody] Loc
  deriving (Eq, Show)

data DeclBody = DeclBody Name [Name] Expr deriving (Eq, Show)
--------------------------------------------------------------------------------

data Stmt
  = Skip Loc
  | Abort Loc
  | Assign [Name] [Expr] Loc
  | AAssign Expr Expr Expr Loc
  | Assert Expr Loc
  | LoopInvariant Expr Expr Loc
  | Do [GdCmd] Loc
  | If [GdCmd] Loc
  | Spec Text Range
  | Proof [ProofAnchor] Loc
    -- pointer operations
  | Alloc   Name [Expr] Loc    --  p := new (e1,e2,..,en)
  | HLookup Name Expr Loc      --  x := *e
  | HMutate Expr Expr Loc      --  *e1 := e2
  | Dispose Expr Loc           --  free e

  deriving (Eq, Show)

data GdCmd = GdCmd Expr [Stmt] Loc deriving (Eq, Show)
data ProofAnchor = ProofAnchor Text Range deriving (Eq, Ord, Show)

--------------------------------------------------------------------------------

-- | Endpoint
data Endpoint = Including Expr | Excluding Expr deriving (Eq, Show, Generic)

-- | Interval
data Interval = Interval Endpoint Endpoint Loc deriving (Eq, Show, Generic)

-- | Base Types
data TBase = TInt | TBool | TChar
  deriving (Show, Eq, Generic)

-- | Types
data Type
  = TBase TBase Loc
  | TArray Interval Type Loc
  | TFunc Type Type Loc
  | TVar Name Loc
  deriving (Eq, Show, Generic)

--------------------------------------------------------------------------------

-- | Expressions
data Expr
  = Paren Expr Loc
  | Lit Lit Loc
  | Var Name Loc
  | Const Name Loc
  | Op Op
  | Chain Expr Op Expr Loc
  | App Expr Expr Loc
  | Lam Name Expr Loc
  | Quant Expr [Name] Expr Expr Loc
  | Subst Expr Subst Expr
  | Click Expr Expr
  | ArrIdx Expr Expr Loc
  | ArrUpd Expr Expr Expr Loc
  deriving (Eq, Show, Generic)

type QuantOp' = Either Op Expr

data Bindings =
  AssignBinding Expr
  | LetBinding Expr
  | BetaBinding Expr
  | AlphaBinding Expr
  deriving (Eq, Show, Generic)

type Subst = Map Name Bindings

----------------------------------------------------------------

-- | Literals
data Lit = Num Int | Bol Bool | Chr Char | Emp
  deriving (Show, Eq, Generic)

----------------------------------------------------------------