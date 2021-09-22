{-# LANGUAGE OverloadedStrings #-}

module Syntax.ConstExpr where

import           Data.List                      ( partition )
import           Data.Maybe                     ( mapMaybe )
import           Syntax.Abstract
import           Syntax.Abstract.Util           ( extractAssertion )
import           Syntax.Common

constExpr :: [Name] -> Expr -> Bool
constExpr _     (Lit   _ _  ) = True
constExpr bvars (Var   v _  ) = v `elem` bvars
constExpr _     (Const _ _  ) = True
constExpr _     (Op _       ) = True
constExpr bvars (App e1 e2 _) = constExpr bvars e1 && constExpr bvars e2
constExpr bvars (Lam x  e  _) = constExpr (x : bvars) e
constExpr bvars (Quant op bvs range body _) =
  constExpr bvars op
    && constExpr (bvs ++ bvars) range
    && constExpr (bvs ++ bvars) body
constExpr _     Subst{}          = error "constExpr Subst to be implemented"
constExpr _     Expand{}         = error "constExpr Expand to be implemented"
constExpr bvars (ArrIdx e1 e2 _) = constExpr bvars e1 && constExpr bvars e2
constExpr bvars (ArrUpd e1 e2 e3 _) =
  constExpr bvars e1 && constExpr bvars e2 && constExpr bvars e3

-- extract assertions from declarations
pickGlobals :: [Declaration] -> ([Expr], [Expr])
pickGlobals = partition (constExpr []) . mapMaybe extractAssertion
