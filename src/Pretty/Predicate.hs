{-# LANGUAGE OverloadedStrings #-}

module Pretty.Predicate where

import Data.Loc (unLoc)
import Data.Text.Prettyprint.Doc
import Pretty.Abstract ()
import Pretty.Util
import Syntax.Predicate
import Prelude hiding (Ordering (..))

--------------------------------------------------------------------------------

-- | Pred
instance PrettyPrec Pred where
  prettyPrec = fromRenderPrec

instance Pretty Pred where
  pretty = prettyPrec 0

--------------------------------------------------------------------------------

-- | Struct & Stmt
instance Show Struct where
  show = show . pretty

instance Pretty Struct where
  pretty (Struct pre xs next) =
    "----------------------------------------------------------------"
      <> line
      <> braces (pretty pre)
      <> line
      <> vsep (map (indent 2 . pretty) xs)
      <> line
      <> pretty next
  pretty (Postcond post) =
    "----------------------------------------------------------------"
      <> line
      <> braces (pretty post)

instance Show Stmt where
  show = show . pretty

instance Pretty Stmt where
  pretty (Skip l) = braces (pretty (unLoc l)) <> line <> "Skip"
  pretty (Abort l) = braces (pretty (unLoc l)) <> line <> "Abort"
  pretty (Assign l _ _) = braces (pretty (unLoc l)) <> line <> "Assign"
  pretty (Do l _ xs) =
    braces (pretty (unLoc l)) <> line <> "Loop" <> line <> vsep (map pretty xs)
  pretty (If l xs) =
    braces (pretty (unLoc l)) <> line <> "If" <> line <> vsep (map pretty xs)
  pretty (Spec l _) = braces (pretty (unLoc l)) <> line <> "Spec"

instance Show GdCmd where
  show = show . pretty

instance Pretty GdCmd where
  pretty (GdCmd guard struct) =
    "  |" <+> pretty guard <+> "=>" <+> line <> "    " <> align (pretty struct)

--------------------------------------------------------------------------------

-- | Origin
instance Pretty Origin where
  pretty = fromRender

--------------------------------------------------------------------------------

-- | Obligation & Specification
instance Pretty PO where
  pretty (PO i p q os) =
    lbracket
      <> pretty i
      <> rbracket
      <+> line
      <> indent 2 (pretty p)
      <> line
      <> indent 2 (pretty q)
      <> line
      <> indent 2 (pretty os)
      <> line

instance Pretty Spec where
  pretty (Specification i p q _) =
    lbracket
      <> pretty i
      <> rbracket
      <> line
      <> indent 2 (pretty p)
      <> line
      <> indent 2 (pretty q)
      <> line
