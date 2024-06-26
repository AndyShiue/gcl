module Syntax.Typed where

import Data.Text ( Text )
import Data.Loc ( Loc )
import Data.Loc.Range ( Range )
import Syntax.Abstract.Types ( Lit, Type )
import Syntax.Common.Types ( Name, Op )

data TypedProgram = Program [TypedDefinition] -- definitions (the functional language part)
                            [TypedDeclaration] -- constant and variable declarations
                            [TypedExpr] -- global properties
                            [TypedStmt] -- main program
                            Loc
  deriving (Eq, Show)

data TypedDefinition
  = TypeDefn Name [Name] [TypedTypeDefnCtor] Loc
  | FuncDefnSig Name Type (Maybe TypedExpr) Loc
  | FuncDefn Name TypedExpr
  deriving (Eq, Show)

data TypedTypeDefnCtor = TypedTypeDefnCtor Name [Name]
  deriving (Eq, Show)

data TypedDeclaration
  = ConstDecl [Name] Type (Maybe TypedExpr) Loc
  | VarDecl [Name] Type (Maybe TypedExpr) Loc
  deriving (Eq, Show)

data TypedStmt
  = Skip Loc
  | Abort Loc
  | Assign [Name] [TypedExpr] Loc
  | AAssign TypedExpr TypedExpr TypedExpr Loc
  | Assert TypedExpr Loc
  | LoopInvariant TypedExpr TypedExpr Loc
  | Do [TypedGdCmd] Loc
  | If [TypedGdCmd] Loc
  | Spec Text Range
  | Proof Text Text Range
  | Alloc   Name [TypedExpr] Loc    --  p := new (e1,e2,..,en)
  | HLookup Name TypedExpr Loc      --  x := *e
  | HMutate TypedExpr TypedExpr Loc --  *e1 := e2
  | Dispose TypedExpr Loc           --  dispose e
  | Block TypedProgram Loc
  deriving (Eq, Show)

data TypedGdCmd = TypedGdCmd TypedExpr [TypedStmt] Loc
  deriving (Eq, Show)

data TypedExpr
  = Lit Lit Type Loc
  | Var Name Type Loc
  | Const Name Type Loc
  | Op Op Type
  | Chain TypedChain
  | App TypedExpr TypedExpr Loc
  | Lam Name Type TypedExpr Loc
  | Quant TypedExpr [Name] TypedExpr TypedExpr Loc
  | ArrIdx TypedExpr TypedExpr Loc
  | ArrUpd TypedExpr TypedExpr TypedExpr Loc
  deriving (Eq, Show)
  -- FIXME: Other constructors.

data TypedChain
  = Pure TypedExpr
  | More TypedChain Op Type TypedExpr
  deriving (Eq, Show)