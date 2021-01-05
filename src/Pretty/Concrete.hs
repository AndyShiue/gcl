{-# LANGUAGE OverloadedStrings #-}

module Pretty.Concrete where

import Data.Text.Prettyprint.Doc
import Pretty.Abstract ()
import Pretty.Util
import Syntax.Concrete
import Syntax.Location
import Data.Loc
import Data.List (sortBy)
import Data.Function (on)



-- Prettifier that respects Locs
-- adds space and newlines in between the Docs 
-- so that their relative position respects the Locations
prettyWithLocs :: [(Doc ann, Loc)] -> Doc ann 
prettyWithLocs = prettyWithLocs' . sortBy cmpLoc
  where 
    cmpLoc :: (Doc ann, Loc) -> (Doc ann, Loc) -> Ordering
    cmpLoc = compare `on` snd

    prettyWithLocs' :: [(Doc ann, Loc)] -> Doc ann 
    prettyWithLocs' [] = mempty 
    prettyWithLocs' [(x, _)] = x
    prettyWithLocs' ((x, loc1):(y, loc2):xs) = x <> fillGapWithLoc loc1 loc2 <> prettyWithLocs ((y, loc2):xs)

fillGap :: Pos -> Pos -> Doc ann 
fillGap this next = 
  let lineDiff = posLine next - posLine this 
  in if lineDiff == 0 
      -- on the same line, just pad them with spaces
      then let offsetDiff = posCoff next - posCoff this 
          in  mconcat (replicate offsetDiff space) 
      -- on different lines
      else mconcat (replicate lineDiff "\n" ++ replicate (posCol next) space)

fillGapWithLoc :: Loc -> Loc -> Doc ann 
fillGapWithLoc NoLoc _ = mempty
fillGapWithLoc _ NoLoc = mempty
fillGapWithLoc (Loc _ this) (Loc next _) = fillGap this next 

--------------------------------------------------------------------------------

-- | Program
instance Pretty Program where
  pretty (Program decls _ _ stmts _) =
    vsep (map pretty decls ++ map pretty stmts)

--------------------------------------------------------------------------------

-- | Declaration
instance Pretty Declaration where
  pretty (ConstDecl names t Nothing _) =
    "con" <+> hsep (punctuate comma (map pretty names)) <+> ":" <+> pretty t
  pretty (ConstDecl names t (Just p) _) =
    "con"
      <+> hsep (punctuate comma (map pretty names))
      <+> ":"
      <+> pretty t
      <+> braces (pretty p)
  pretty (VarDecl names t Nothing _) =
    "var" <+> hsep (punctuate comma (map pretty names)) <+> ":" <+> pretty t
  pretty (VarDecl names t (Just p) _) =
    "var"
      <+> hsep (punctuate comma (map pretty names))
      <+> ":"
      <+> pretty t
      <+> braces (pretty p)
  pretty (LetDecl name args expr _) =
    "let" <+> pretty name <+> hsep (map pretty args) <+> "=" <+> pretty expr

-- vsep (map pretty decls ++ map pretty stmts)

--------------------------------------------------------------------------------

-- | Name
instance Pretty Name where
  pretty (Name n _) = pretty n

--------------------------------------------------------------------------------

-- | Stmt
instance Pretty Stmt where
  pretty (Skip _) = "skip"
  pretty (Abort _) = "abort"
  pretty (Assign xs es _) =
    hsep (punctuate comma (map (pretty . depart) xs)) <+> ":="
      <+> hsep
        (punctuate comma (map (pretty . depart) es))
  pretty (Assert p _) = lbrace <+> pretty p <+> rbrace
  pretty (LoopInvariant p bnd _) =
    lbrace <+> pretty p <+> ", bnd:" <+> pretty bnd <+> rbrace
  pretty (Do gdCmds _) = "do" <+> align (encloseSep mempty mempty " | " (map pretty gdCmds)) <> line <> "od"
  pretty (If gdCmds _) = "if" <+> align (encloseSep mempty mempty " | " (map pretty gdCmds)) <> line <> "fi"
  pretty (SpecQM _) = "?"
  pretty (Spec _) = "{!  !}"
  pretty (Proof _) = "{-  -}"

instance Pretty GdCmd where
  pretty (GdCmd guard body _) = pretty guard <+> "->" <+> align (vsep (map pretty body))

--------------------------------------------------------------------------------

-- | Expr
instance PrettyPrec Expr where
  prettyPrec n = prettyPrec n . depart

prettyHole :: Loc -> Doc ann 
prettyHole loc = case loc of 
    NoLoc -> "{!!}"
    Loc (Pos p1 l1 c1 o1) (Pos p2 l2 c2 o2) -> 
      let start' = Pos p1 l1 (c1 + 2) (o1 + 2)
          end' = Pos p2 l2 (c2 - 2) (o2 - 2)
      in  "{!" <> fillGap start' end' <> "!}"

instance Pretty Expr where
  pretty = pretty . depart 
  -- pretty (Lit x _) = pretty x
  -- pretty (Var x _) = pretty x 
  -- pretty (Const x _) = pretty x 
  -- pretty (Op x _) = pretty x 
  -- pretty (App x y _) = prettyWithLocs [(pretty x, locOf x), (pretty y, locOf y)]
  -- pretty (Lam x y _) = prettyWithLocs [(pretty x, locOf x), (pretty y, locOf y)]
  -- pretty (Hole loc) = case loc of 
  --   NoLoc -> "{!!}"
  --   Loc (Pos p1 l1 c1 o1) (Pos p2 l2 c2 o2) -> 
  --     let start' = Pos p1 l1 (c1 + 2) (o1 + 2)
  --         end' = Pos p2 l2 (c2 - 2) (o1 - 2)
  --     in  "{!" <> fillGap start' end' <> "!}"
  -- pretty (Quant a b c d) = 
  -- | Quant Expr [Name] Expr Expr Loc
  -- | Subst Expr Subst -- internal. Location not necessary?

--------------------------------------------------------------------------------

-- | Type

-- instance Pretty Endpoint where
--   pretty (Including e) = ""
instance Pretty Interval where
  pretty = pretty . depart

instance Pretty Type where
  pretty = pretty . depart
