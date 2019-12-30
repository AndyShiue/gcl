{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric #-}

module GCL.PreCond where

import Control.Monad.State hiding (guard)
import Control.Monad.Writer hiding (guard)

import qualified Data.Map as Map
-- import Data.Map (Map)
import Data.Loc (Loc(..))
import Data.Text.Lazy (pack)
import GHC.Generics

import Syntax.Abstract

data Obligation = Obligation Index Pred Pred deriving (Show, Generic)
data Hardness = Hard | Soft deriving (Show, Generic)
data Specification = Specification
  { specID       :: Int
  , specHardness :: Hardness
  , specPreCond  :: Pred
  , specPostCond :: Pred
  , specLoc      :: Loc
  } deriving (Show, Generic)

type M = WriterT [Obligation] (WriterT [Specification] (State (Int, Int, Int)))

runM :: M a -> ((a, [Obligation]), [Specification])
runM p = evalState (runWriterT (runWriterT p)) (0, 0, 0)

-- SCM: I thought these would be useful,
--        but it turns out that I do not need them yet.

censorObli :: ([Obligation] -> [Obligation]) -> M a -> M a
censorObli = censor

censorSpec :: ([Specification] -> [Specification]) -> M a -> M a
censorSpec f = mapWriterT (censor f)

-- creates a proof obligation
obligate :: Pred -> Pred -> M ()
obligate p q = do

  -- NOTE: this could use some love
  let samePredicate = predEq p q

  unless samePredicate $ do
    (i, j, k) <- get
    put (succ i, j, k)
    tell [Obligation i p q]

tellSpec :: Hardness -> Pred -> Pred -> Loc -> M ()
tellSpec harsness p q loc = do
  (i, j, k) <- get
  put (i, succ j, k)
  lift $ tell [Specification j harsness p q loc]
-- tellSpec harsness p q stmts loc = do
--   let lastLoc = locOf $ last stmts
--   lift $ tell [Specification harsness p q (Just lastLoc) loc]

-- SCM: generating a fresh internal name.
--      I am assuming that we do not allow user defined variables
--      to start with underline.
--      We can specify a prefix for readability.

freshInternal :: String -> M Var
freshInternal prefix = do
  (i, j, k) <- get
  put (i, j, succ k)
  return (pack ("_" ++ prefix ++ show k))

precondStmts :: [Stmt] -> Pred -> M Pred
precondStmts [] post = return post
precondStmts (x:[]) post = case x of
  -- SOFT
  Spec loc -> do
    tellSpec Soft post post loc
    return post
  _ -> do
    precond x post

precondStmts (x:(y:xs)) post = case (x, y) of
  -- HARD
  (Assert asserted _, Spec loc) -> do
    -- calculate the precondition of xs
    post' <- precondStmts xs post

    tellSpec Hard asserted post' loc

    -- SCM: I don't think there should be an obligation here,
    --   because it is just a spec to be filled.
    -- obligate asserted post'

    return asserted
  -- SOFT
  (Spec loc, _) -> do
    pre <- precondStmts (y:xs) post
    -- pre <- precondStmts stmts post'
    tellSpec Soft pre pre loc
    return pre
  _ -> do
    precondStmts (y:xs) post >>= precond x


-- calculating the weakest precondition
precond :: Stmt -> Pred -> M Pred

precond (Abort _) _ = return (Lit (Bol False))

precond (Skip _) post = return post

precond (Assert pre _) post = do
  obligate pre post
  return pre

precond (Assign xs es _) post = return $ subst (Map.fromList (zip xs es)) post

precond (If (Just pre) branches _) post = do

  forM_ branches $ \(GdCmd guard body) -> do
    let body' = Assert (pre `conj` guard) NoLoc : body
    precondStmts body' post
    {- SCM: the proof obligations should be generated by precondStmts.
      obligate
      (pre `conj` guard)    -- HARD precondition AND the guard
      p                     -- precondition of the statements
    -}

  let guards = getGuards branches
  obligate
    pre
    (disjunct guards)

  return pre

precond (If Nothing branches _) post = do
  brConds <- mapM (precondGuard post) branches
  let guards = getGuards branches

  return (conjunct brConds `conj` disjunct guards)

precond (Do inv bnd branches _) post = do
  oldbnd <- freshInternal "bnd"
  let invB = inv `conj` (bnd `eqq` Var oldbnd)
  forM_ branches $ \(GdCmd guard body) -> do
    let body' = Assert (invB `conj` guard) NoLoc : body
    precondStmts body' (inv `conj` (bnd `gt` Var oldbnd))
    {- SCM: the proof obligations should be generated by precondStmts.
    obligate
      (inv `conj` guard)    -- invariant AND the guard
      p                     -- precondition of the statements
     -}

  let guards = getGuards branches

  -- after the loop, the invariant should still hold and all guards should fail
  obligate
    (inv `conj` (conjunct (map neg guards)))
    post -- empty branches?

  -- termination of the whole statement
  obligate
    (inv `conj` disjunct guards)
    (bnd `gte` (Lit (Num 0)))

  return inv

precond (Spec _) post = return post

precondGuard :: Pred -> GdCmd -> M Pred
precondGuard post (GdCmd guard body) = implies guard <$> precondStmts body post
