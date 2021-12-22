module Syntax.Abstract.Instances.Located where

import           Data.Loc
import           Prelude                 hiding ( Ordering(..) )
import           Syntax.Abstract.Types
import           Syntax.Common                  ( )

instance Located Program where
  locOf (Program _ _ _ _ l) = l

instance Located Declaration where
  locOf (ConstDecl _ _ _ l) = l
  locOf (VarDecl   _ _ _ l) = l

instance Located FuncDefnClause where
  locOf (FuncDefnClause _ _ _ l) = l

instance Located TypeDefn where
  locOf (TypeDefn _ _ _ l) = l

instance Located TypeDefnCtor where
  locOf (TypeDefnCtor l r) = l <--> r

instance Located Stmt where
  locOf (Skip  l            ) = l
  locOf (Abort l            ) = l
  locOf (Assign _ _ l       ) = l
  locOf (AAssign _ _ _ l    ) = l
  locOf (Assert _ l         ) = l
  locOf (LoopInvariant _ _ l) = l
  locOf (Do    _ l          ) = l
  locOf (If    _ l          ) = l
  locOf (Spec  _ l          ) = locOf l
  locOf (Proof _ l          ) = l
  locOf (Alloc   _ _ l      ) = l
  locOf (HLookup _ _ l      ) = l
  locOf (HMutate _ _ l      ) = l
  locOf (Dispose _ l        ) = l
  locOf (Block   _ l        ) = l

instance Located GdCmd where
  locOf (GdCmd _ _ l) = l

instance Located Endpoint where
  locOf (Including e) = locOf e
  locOf (Excluding e) = locOf e

instance Located Interval where
  locOf (Interval _ _ l) = l

instance Located Type where
  locOf (TBase _ l   ) = l
  locOf (TArray _ _ l) = l
  locOf (TTuple _    ) = NoLoc
  locOf (TFunc _ _ l ) = l
  locOf (TCon  _ _ l ) = locOf l
  locOf (TVar _ l    ) = l
  locOf (TMetaVar _  ) = NoLoc

instance Located Expr where
  locOf (Var   _ l         ) = l
  locOf (Const _ l         ) = l
  locOf (Lit   _ l         ) = l
  locOf (Op op             ) = locOf op
  locOf (App _ _ l         ) = l
  locOf (Lam _ _ l         ) = l
  locOf (Tuple _           ) = NoLoc
  locOf (Quant _ _ _ _ l   ) = l
  locOf (RedexStem es _ _ _) = locOf es
  locOf (Redex x           ) = locOf x
  locOf (ArrIdx _ _ l      ) = l
  locOf (ArrUpd _ _ _ l    ) = l
  locOf (Case _ _ l        ) = l

instance Located CaseConstructor where
  locOf (CaseConstructor l r) = l <--> r

instance Located Pattern where
  locOf (PattLit      l     ) = locOf l
  locOf (PattBinder   l     ) = locOf l
  locOf (PattWildcard l     ) = locOf l
  locOf (PattConstructor l r) = l <--> r

instance Located Redex where
  locOf = locOf . redexExpr

instance Located Lit where
  locOf _ = NoLoc
