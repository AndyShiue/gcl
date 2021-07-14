{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module GCL.Substitution
    ( run
    , Scope
    ) where

import           Control.Monad.RWS
import           Data.Loc                       ( locOf )
import           Data.Map                       ( Map )
import qualified Data.Map                      as Map
import qualified Data.Set                      as Set
import           Data.Set                       ( Set )
import           Data.Text                      ( Text )
import           GCL.Common                     ( Free(fv)
                                                , Fresh(fresh, freshWithLabel)
                                                )
import           GCL.Predicate                  ( Pred(..) )
import           Syntax.Abstract                ( Expr(..)
                                                , Mapping
                                                )
import           Syntax.Common                  ( Name(Name)
                                                , nameToText
                                                )

------------------------------------------------------------------

run
    :: (Substitutable a)
    => Scope -- declarations
    -> [Name] -- name of variables to be substituted
    -> [Expr] -- values to be substituted for  
    -> a
    -> a
run scope names exprs predicate = fst
    $ evalRWS (subst mapping predicate) scope 0
  where
    mapping :: Mapping
    mapping = mappingFromSubstitution names exprs

mappingFromSubstitution :: [Name] -> [Expr] -> Mapping
mappingFromSubstitution xs es =
    Map.mapKeys nameToText $ Map.fromList $ zip xs es

------------------------------------------------------------------

type Scope = Map Text (Maybe Expr)
type M = RWS Scope () Int

instance Fresh M where
    fresh = do
        i <- get
        put (succ i)
        return i

------------------------------------------------------------------



--      a                  x    ~~~~~~~~~~~>    b
--             (\n . body) x    ~~~~~~~~~~~>           c
-- --------------------------------------------------------------- [reduce-App-Expand-Lam]
--      (a ===> \n . body) x    ~~~~~~~~~~~>    b ===> c
--  
--  
--      body                    ~[ x / n ]~>    b
-- --------------------------------------------------------------- [reduce-App-Lam]
--      (\n . body) x           ~~~~~~~~~~~>    b
--
--
-- --------------------------------------------------------------- [reduce-Others]
--      other constructs        ~~~~~~~~~~~>    other constructs
-- 

-- perform substitution when there's a redex
reduce :: Expr -> M Expr
reduce expr = case expr of
    App f x l1 -> case f of
        -- [reduce-App-Expand-Lam]
        Expand before (Lam n body l2) ->
            Expand <$> reduce (App before x l1) <*> reduce
                (App (Lam n body l2) x l1)
        -- [reduce-App-Lam]
        Lam n body _ -> subst (mappingFromSubstitution [n] [x]) body
        -- [Others]
        _            -> return expr
    -- [Others]

    _ -> return expr

------------------------------------------------------------------

class Substitutable a where
    subst :: Mapping -> a -> M a

instance Substitutable Expr where
    subst mapping expr = case expr of

-- 
--       a                  ~[.../...]~>    a'
-- ---------------------------------------------------------------[subst-Paren]
--       Paren a            ~[.../...]~>    Paren a'
-- 
        Paren e l  -> Paren <$> subst mapping e <*> pure l

-- 
-- ---------------------------------------------------------------[subst-Lit]
--      Lit a               ~[.../...]~>    Lit a
-- 
        Lit{}      -> return expr

-- 
--      a                   ~~~~~~~~~~~>    a'
-- ---------------------------------------------------------------[subst-Var-substituted]
--      Var x               ~[ a / x ]~>    a'
-- 
-- 
--      x                   is defined as   a
--      a                   ~[.../...]~>    a'
-- ---------------------------------------------------------------[subst-Var-defined]
--      Var x               ~[.../...]~>    Var x ===> a'
-- 
-- 
--      x                   is not defined
-- ---------------------------------------------------------------[subst-Var-not-defined]
--      Var x               ~[.../...]~>    Var x
-- 
        Var name _ -> case Map.lookup (nameToText name) mapping of
            Just value -> reduce value -- [subst-Var-substituted]
            Nothing    -> do
                scope <- ask
                case Map.lookup (nameToText name) scope of
                    -- [subst-Var-defined]
                    Just (Just binding) -> do
                        after <- subst mapping binding
                        let before = Subst2 expr mapping
                        return $ Expand before after
                    -- [subst-Var-defined]
                    Just Nothing -> return expr
                    Nothing      -> return expr

-- 
--      a                   ~~~~~~~~~~~>    a'
-- ---------------------------------------------------------------[subst-Const-substituted]
--      Const x             ~[ a / x ]~>    a'
-- 
-- 
--      x                   is defined as   a
--      a                   ~[.../...]~>    a'
-- ---------------------------------------------------------------[subst-Const-defined]
--      Const x             ~[.../...]~>    Const x ===> a'
-- 
-- 
--      x                   is not defined
-- ---------------------------------------------------------------[subst-Const-not-defined]
--      Const x             ~[.../...]~>    Const x
-- 
        Const name _ -> case Map.lookup (nameToText name) mapping of
            Just value -> reduce value -- [subst-Const-substituted]
            Nothing    -> do
                scope <- ask
                case Map.lookup (nameToText name) scope of
                    -- [subst-Const-defined]
                    Just (Just binding) -> do
                        after <- subst mapping binding
                        let before = Subst2 expr mapping
                        return $ Expand before after
                    -- [subst-Const-not-defined]
                    Just Nothing -> return expr
                    Nothing      -> return expr

-- 
-- ---------------------------------------------------------------[subst-Op]
--      Op a                ~[.../...]~>    Op a
-- 
        Op{} -> return expr

-- 
--      a                   ~[.../...]~>    a'
--      b                   ~[.../...]~>    b'
-- ---------------------------------------------------------------[subst-Chain]
--      Chan a op b         ~[.../...]~>    Op a' op b' 
-- 
        Chain a op b l ->
            Chain <$> subst mapping a <*> pure op <*> subst mapping b <*> pure l

-- 
--      f                   ~[.../...]~>    f'
--      x                   ~[.../...]~>    x'
--      f' x'               ~~~~~~~~~~~>    y 
-- ---------------------------------------------------------------[subst-App]
--      f  x                ~[.../...]~>    y
-- 
        App f x l ->
            reduce =<< App <$> subst mapping f <*> subst mapping x <*> pure l

-- 
--      n                   ~~~rename~~>    n'
--      body                ~[.../...]~>    body'
-- ---------------------------------------------------------------[subst-Lam]
--      \n . body           ~[.../...]~>    \n' . body'
-- 
        Lam binder body l -> do

            -- rename the binder to avoid capturing only when necessary! 
            let (capturableNames, shrinkedMapping) =
                    getCapturableNames mapping body

            (binder', alphaRenameMapping) <- rename capturableNames binder

            Lam binder'
                <$> subst (alphaRenameMapping <> shrinkedMapping) body
                <*> pure l

-- 
--      ns                  ~~~rename~~>    ns'
--      a                   ~[.../...]~>    a'
--      b                   ~[.../...]~>    b'
-- ---------------------------------------------------------------[subst-Quant]
--      Quant op ns a b     ~[.../...]~>    Quant op ns' a' b'
-- 
        Quant op binders range body l -> do
            -- rename binders to avoid capturing only when necessary! 
            let (capturableNames, shrinkedMapping) =
                    getCapturableNames mapping expr

            (binders', alphaRenameMapping) <-
                unzip <$> mapM (rename capturableNames) binders

            -- combine individual renamings to get a new mapping 
            -- and use that mapping to rename other stuff
            let alphaRenameMappings = mconcat alphaRenameMapping

            Quant op binders'
                <$> subst (alphaRenameMappings <> shrinkedMapping) range
                <*> subst (alphaRenameMappings <> shrinkedMapping) body
                <*> pure l

        Subst{}           -> return expr

-- 
-- ---------------------------------------------------------------[subst-Subst]
--      Subst a mapping     ~[.../...]~>    Subst a mapping'
-- 
        Subst2 e mapping' -> return $ Subst2 e (mapping' <> mapping)

-- 
--      a                   ~[.../...]~>    a'
--      b                   ~[.../...]~>    b'
-- ---------------------------------------------------------------[subst-Expand]
--      a ===> b            ~[.../...]~>    a' ===> b'
-- 
        Expand before after ->
            Expand <$> subst mapping before <*> subst mapping after

-- 
--      a                   ~[.../...]~>    a'
--      b                   ~[.../...]~>    b'
-- ---------------------------------------------------------------[subst-ArrIdx]
--      ArrIdx a b          ~[.../...]~>    ArrIdx a b
-- 
        ArrIdx array index l ->
            ArrIdx <$> subst mapping array <*> subst mapping index <*> pure l

-- 
--      a                   ~[.../...]~>    a'
--      b                   ~[.../...]~>    b'
--      c                   ~[.../...]~>    c'
-- ---------------------------------------------------------------[subst-ArrUpd]
--      ArrUpd a b c        ~[.../...]~>    ArrUpd a b c
-- 
        ArrUpd array index value l ->
            ArrUpd
                <$> subst mapping array
                <*> subst mapping index
                <*> subst mapping value
                <*> pure l

instance Substitutable Pred where
    subst mapping = \case
        Constant a    -> Constant <$> subst mapping a
        GuardIf   a l -> GuardIf <$> subst mapping a <*> pure l
        GuardLoop a l -> GuardLoop <$> subst mapping a <*> pure l
        Assertion a l -> Assertion <$> subst mapping a <*> pure l
        LoopInvariant a b l ->
            LoopInvariant <$> subst mapping a <*> subst mapping b <*> pure l
        Bound a l   -> Bound <$> subst mapping a <*> pure l
        Conjunct as -> Conjunct <$> mapM (subst mapping) as
        Disjunct as -> Disjunct <$> mapM (subst mapping) as
        Negate   a  -> Negate <$> subst mapping a


------------------------------------------------------------------
-- | Perform Alpha renaming only when necessary

-- rename a binder if it is in the set of "capturableNames"
-- returns the renamed binder and the mapping of alpha renaming (for renaming other stuff)
rename :: Set Text -> Name -> M (Name, Mapping)
rename capturableNames binder =
    if Set.member (nameToText binder) capturableNames
        -- CAPTURED! 
        -- returns the alpha renamed binder along with its mapping 
        then do
            binder' <- Name <$> freshWithLabel (nameToText binder) <*> pure
                (locOf binder)
            return
                ( binder'
                , Map.singleton (nameToText binder) (Var binder' (locOf binder))
                )
        -- not captured, returns the original binder 
        else return (binder, Map.empty)

-- returns a set of free names that is susceptible to capturing 
-- also returns a Mapping that is reduced further with free variables in "body" 
getCapturableNames :: Mapping -> Expr -> (Set Text, Mapping)
getCapturableNames mapping body =
    let
        -- collect all free variables in "body"
        freeVarsInBody  = Set.map nameToText (fv body)
        -- reduce the mapping further with free variables in "body" 
        shrinkedMapping = Map.restrictKeys mapping freeVarsInBody
        -- collect all free varialbes in the mapped expressions 
        mappedExprs     = Map.elems shrinkedMapping
        freeVarsInMappedExprs =
            Set.map nameToText $ Set.unions (map fv mappedExprs)
    in
        (freeVarsInMappedExprs, shrinkedMapping)