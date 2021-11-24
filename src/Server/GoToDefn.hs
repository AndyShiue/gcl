{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Server.GoToDefn
  ( collectLocationLinks
  ) where

import           Control.Monad.RWS
import           Data.Loc                       ( Located
                                                , locOf
                                                )
import           Data.Loc.Range
import           Data.Map                       ( Map )
import qualified Data.Map                      as Map
import           Data.Text                      ( Text )
import           Language.LSP.Types             ( LocationLink(..) )
import qualified Language.LSP.Types            as J
import           Pretty                         ( Pretty(..) )
import qualified Server.SrcLoc                 as SrcLoc
import qualified Server.TokenMap               as TokenMap
import           Server.TokenMap
import           Syntax.Abstract
import           Syntax.Common

collectLocationLinks :: Program -> TokenMap LocationLink
collectLocationLinks program = runM (programToScopes program) (collect program)

instance Pretty LocationLink where
  pretty = pretty . show


--------------------------------------------------------------------------------

type LocationLinkToBe = Range -> LocationLink

-- | Extracts Scopes from a Program 
programToScopes :: Program -> [Scope LocationLinkToBe]
programToScopes (Program (Definitions typeDefns _funcDefnSigs funcDefns) decls _ _ _)
  = [topLevelScope]
 where
  topLevelScope :: Map Text LocationLinkToBe
  topLevelScope = Map.mapKeys nameToText locationLinks

  locationLinks :: Map Name LocationLinkToBe
  locationLinks =
    locationLinksFromFuncDefns
      <> locationLinksFromDecls
      <> locationLinksFromTypeDefns

  locationLinksFromDecls :: Map Name LocationLinkToBe
  locationLinksFromDecls =
    makeLocationLinks $ Map.fromList $ concatMap splitDecl decls

  locationLinksFromFuncDefns :: Map Name LocationLinkToBe
  locationLinksFromFuncDefns = makeLocationLinks funcDefns

  locationLinksFromTypeDefns :: Map Name LocationLinkToBe
  locationLinksFromTypeDefns = makeLocationLinks typeDefns

  -- split a parallel declaration into many simpler declarations
  splitDecl :: Declaration -> [(Name, Declaration)]
  splitDecl decl@(ConstDecl names _ _ _) = [ (name, decl) | name <- names ]
  splitDecl decl@(VarDecl   names _ _ _) = [ (name, decl) | name <- names ]

--  Helper function for converting 
--      a Map of "names" and "targets" 
--   to a Map of "names" and functions 
--        (which will become LocationLinks when supplied with the range of "origin")
--
--  For example: 
--
--    ╔═════ where the user clicks ════╗
--    ║                                ║
--    ║             double 3           ║
--    ║  origin ──▶ ~~~~~~             ║
--    ║                                ║
--    ╚════════════════════════════════╝
--
--    ╔═══════ where it leads to ══════╗
--    ║                                ║
--    ║             double x = x * 2   ║
--    ║    name ──▶ ~~~~~~             ║
--    ║  target ──▶ ~~~~~~~~~~~~~~~~   ║
--    ║                                ║
--    ╚════════════════════════════════╝

makeLocationLinks :: Located a => Map Name a -> Map Name LocationLinkToBe
makeLocationLinks = Map.mapMaybeWithKey $ \name target -> do
  targetRange          <- fromLoc (locOf target)
  targetSelectionRange <- fromLoc (locOf name)
  let toLocationLink originSelectionRange = LocationLink
        { -- Span of the origin of this link.
          -- Used as the underlined span for mouse interaction. Defaults to the word
          -- range at the mouse position.
          J._originSelectionRange = Just
                                      $ SrcLoc.toLSPRange originSelectionRange
          -- The target resource identifier of this link.
        , J._targetUri            = J.filePathToUri (rangeFile targetRange)
          -- The full target range of this link. If the target for example is a
          -- symbol then target range is the range enclosing this symbol not including
          -- leading/trailing whitespace but everything else like comments. This
          -- information is typically used to highlight the range in the editor.
        , J._targetRange          = SrcLoc.toLSPRange targetRange
          -- The range that should be selected and revealed when this link is being
          -- followed, e.g the name of a function. Must be contained by the the
          -- '_targetRange'
        , J._targetSelectionRange = SrcLoc.toLSPRange targetSelectionRange
        }
  return toLocationLink

scopeFromLocalBinders :: [Name] -> Scope LocationLinkToBe
scopeFromLocalBinders names =
  Map.mapKeys nameToText $ makeLocationLinks $ Map.fromList $ zip names names

--------------------------------------------------------------------------------
-- Names

instance Collect LocationLinkToBe LocationLink Name where
  collect name = do
    result <- lookupScopes (nameToText name)
    case result of
      Nothing               -> return ()
      Just locationLinkToBe -> case fromLoc (locOf name) of
        Nothing    -> return ()
        Just range -> tell $ TokenMap.singleton range (locationLinkToBe range)

--------------------------------------------------------------------------------
-- Program

instance Collect LocationLinkToBe LocationLink Program where
  collect (Program defns decls _ stmts _) = do
    collect defns
    collect decls
    collect stmts

--------------------------------------------------------------------------------
-- Definition

instance Collect LocationLinkToBe LocationLink Definitions where
  collect defns = do
    -- collect (defnTypes defns)
    collect (defnFuncSigs defns)
    collect (defnFuncs defns)

instance Collect LocationLinkToBe LocationLink FuncDefnSig where
  collect (FuncDefnSig _name t prop _) = do
    collect t
    collect prop

--------------------------------------------------------------------------------
-- Declaration

instance Collect LocationLinkToBe LocationLink Declaration where
  collect = \case
    ConstDecl a _ c _ -> do
      collect a
      collect c
    VarDecl a _ c _ -> do
      collect a
      collect c

--------------------------------------------------------------------------------
-- Stmt

instance Collect LocationLinkToBe LocationLink Stmt where
  collect = \case
    Assign a b _ -> do
      collect a
      collect b
    Assert a _          -> collect a
    LoopInvariant a b _ -> do
      collect a
      collect b
    Do a _ -> collect a
    If a _ -> collect a
    _      -> return ()

instance Collect LocationLinkToBe LocationLink GdCmd where
  collect (GdCmd gd stmts _) = do
    collect gd
    collect stmts

--------------------------------------------------------------------------------

instance Collect LocationLinkToBe LocationLink Expr where
  collect = \case
    Lit   _ _           -> return ()
    Var   a _           -> collect a
    Const a _           -> collect a
    Op op               -> collect op
    App a b _           -> (<>) <$> collect a <*> collect b
    Lam _ b _           -> collect b
    Quant op args c d _ -> do
      collect op
      localScope (scopeFromLocalBinders args) $ do
        collect c
        collect d
    -- RedexStem/Redex will only appear in proof obligations, not in code 
    RedexStem{}  -> return ()
    Redex _      -> return ()
    ArrIdx e i _ -> do
      collect e
      collect i
    ArrUpd e i f _ -> do
      collect e
      collect i
      collect f
    -- TODO: provide types for tokens in patterns 
    Case e _ _ -> do
      collect e
      -- collect patterns

-- instance Collect CaseConstructor where
--   collect (CaseConstructor ctor args body) = do
--     collect ctor
--     localScope args $ do
--       collect body

instance Collect LocationLinkToBe LocationLink Op where
  collect _ = return ()
  -- collect (ChainOp op) = collect op
  -- collect (ArithOp op) = collect op

instance Collect LocationLinkToBe LocationLink QuantOp' where
  collect (Left  op  ) = collect op
  collect (Right expr) = collect expr

--------------------------------------------------------------------------------
-- | Types 

instance Collect LocationLinkToBe LocationLink Type where
  collect = \case
    TBase _ _    -> return ()
    TArray i x _ -> collect i >> collect x
    TFunc  x y _ -> collect x >> collect y
    TCon   x _ _ -> collect x
    TVar _ _     -> return ()
    TMetaVar _   -> return ()

instance Collect LocationLinkToBe LocationLink Interval where
  collect (Interval x y _) = collect x >> collect y

instance Collect LocationLinkToBe LocationLink Endpoint where
  collect = \case
    Including x -> collect x
    Excluding x -> collect x