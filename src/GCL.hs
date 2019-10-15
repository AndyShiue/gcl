{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}

module GCL where

import Control.Arrow ((***))
import Control.Monad

import Control.Monad.Gensym

import GCL.Expr
import GCL.Pred
import GCL.EnumHole

type OIdx = Int
-- newtype OIdx = OIdx {unOIdx :: Int}
--    deriving Show
type Branch = (Pred, Stmt)
data Stmt = Skip
          | Assign [VName] [Expr]
          | Seq Stmt Stmt
          | Assert Pred
          | If [Branch]
          | Do Pred Expr [Branch]
  deriving Show

instance EnumHole Stmt where
  enumHole Skip = return Skip
  enumHole (Assign xs es) =
    Assign xs <$> mapM enumHole es
  enumHole (Seq c1 c2) =
    liftM2 Seq (enumHole c1) (enumHole c2)
  enumHole (Assert p) =
    Assert <$> enumHole p
  enumHole (If branches) =
    If <$> mapM enumHole branches
  enumHole (Do inv bnd branches) =
    liftM3 Do (enumHole inv)
              (enumHole bnd)
              (mapM enumHole branches)

instance EnumHole Branch where
  enumHole (guard, body) = liftM2 (,) (enumHole guard) (enumHole body)

precond :: (MonadSymGen Idx m) => Stmt -> Pred -> m ([(Idx, Pred)], Pred)
precond Skip post =
   return ([], post)
precond (Assign xs es) post =
   return ([], substP (zip xs es) post)
precond (Seq c1 c2) post =
   do (obs2, pre ) <- precond c2 post
      (obs1, pre') <- precond c1 pre
      return (obs1 ++ obs2, pre')
precond (Assert p) post =
  do i <- gensym
     return ([(i, p `Implies` post)], p)
precond (If branches) post =
   undefined
 {-  where guards = map fst branches
        bodies = map snd branches
        conds = map (flip precond post) bodies -}
precond (Do inv bnd branches) post =
   do (obs, brConds) <-
          (concat *** id) . unzip <$> mapM branchCond branches
      (obsT, termConds2) <-
          (concat *** id) . unzip <$> mapM termCond2 branches
      brConds'    <- enumWithIdx brConds
      termConds2' <- enumWithIdx termConds2
      i1 <- gensym
      i2 <- gensym
      return ((i1, baseCond) : (i2, termCond1) :
              brConds' ++ termConds2' ++ obs ++ obsT
             , inv)
  where (guards, bodies) = unzip branches
        baseCond = (inv `Conj` (foldr1 Conj (map Neg guards)))
                      `Implies` post -- empty branches?
        branchCond :: (MonadSymGen Idx m) =>
                      (Pred, Stmt) -> m ([(Idx, Pred)], Pred)
        branchCond (guard, body) =
          (id *** Implies (inv `Conj` guard)) <$>
              precond body inv
        termCond1 = (inv `Conj` foldr1 Disj guards) `Implies`
                      (Term GEq bnd (Lit (Num 0)))
        termCond2 (guard, body) =
          do (obs, pre) <- precond body (Term LTh bnd (Lit (Num 100)))
             return (obs,
               (inv `Conj` guard `Conj` (Term Eq bnd (Lit (Num 100))))
                 `Implies` pre)

enumWithIdx :: (MonadSymGen i m) => [a] -> m [(i,a)]
enumWithIdx [] = return []
enumWithIdx (p:ps) = do i <- gensym
                        ps' <- enumWithIdx ps
                        return ((i,p):ps')
---

gcdExample = Assign ["x"] [Var "X"] `Seq`
      Assign ["y"] [Var "Y"] `Seq`
      Do (Term Eq (Op "gcd" [Var "x", Var "y"])
                  (Op "gcd" [Var "X", Var "Y"]))
         (HoleE Nothing [])
         [(Term GTh (Var "x") (Var "y"),
           Assign ["x"] [Op "-" [Var "x", Var "y"]]),
          (Term LTh (Var "x") (Var "y"),
           Assign ["y"] [Op "-" [Var "y", Var "x"]])
          ]
post = (Term Eq (Var "x")
                (Op "gcd" [Var "X", Var "Y"]))


tst = runSymbolGen $ do
  let gcd' = runEnumHole gcdExample
  precond gcd' post

--

{-
let (stmt', obs, pre)  = runSymbolGen (precond GCL.gcd post)

--
Seq (Seq (Assign ["x"] [Var "X"])
         (Assign ["y"] [Var "Y"]))
 (Do (Term Eq (Op "gcd" [Var "x",Var "y"])
              (Op "gcd" [Var "X",Var "Y"]))
     (HoleE (Just 0))
     [(Term GTh (Var "x") (Var "y"),
         Assign ["x"] [Op "-" [Var "x",Var "y"]]),
      (Term LTh (Var "x") (Var "y"),
         Assign ["y"] [Op "-" [Var "y",Var "x"]])])
--

[(5,"((((gcd x y) = (gcd X Y)) && ((not (x > y)) && (not (x < y)))) => (x = (gcd X Y)))"),
(6,"((((gcd x y) = (gcd X Y)) && ((x > y) || (x < y))) => ([0] >= 0))"),
(1,"((((gcd x y) = (gcd X Y)) && (x > y)) => ((gcd (x - y) y) = (gcd X Y)))"),
(2,"((((gcd x y) = (gcd X Y)) && (x < y)) => ((gcd x (y - x)) = (gcd X Y)))"),
(3,"(((((gcd x y) = (gcd X Y)) && (x > y)) && ([0] = 100)) => ([0] < 100))"),
(4,"(((((gcd x y) = (gcd X Y)) && (x < y)) && ([0] = 100)) => ([0] < 100))")]

-}
