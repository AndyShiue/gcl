{-# LANGUAGE OverloadedStrings #-}

module Render.Predicate where

import GCL.WP
import Render.Class
import Render.Element
import Render.Syntax.Abstract ()
import Syntax.Predicate
import Data.Loc.Range (fromLoc)
import Data.Loc (locOf)

instance Render StructWarning where
  render (MissingBound _) = "Bound missing at the end of the assertion before the DO construct \" , bnd : ... }\""
  render (ExcessBound _) = "The bound annotation at this assertion is unnecessary"

instance RenderBlock StructWarning where
  renderBlock x = case x of
    MissingBound range -> blockE (Just "Bound Missing") (Just range) (render x)
    ExcessBound range -> blockE (Just "Excess Bound") (Just range) (render x)

instance RenderBlock Spec where
  renderBlock (Specification _ pre post loc) =
    proofObligationE
      Nothing
      (fromLoc loc)
      (render pre)
      (render post)

instance Render Pred where
  renderPrec n x = case x of
    Constant p -> renderPrec n p
    GuardIf p _ -> renderPrec n p
    GuardLoop p _ -> renderPrec n p
    Assertion p _ -> renderPrec n p
    LoopInvariant p _ _ -> renderPrec n p
    Bound p _ -> renderPrec n p
    Conjunct ps -> punctuateE " ∧" (map render ps)
    Disjunct ps -> punctuateE " ∨" (map render ps)
    Negate p -> "¬" <+> renderPrec n p

instance RenderBlock PO where
  renderBlock (PO _ pre post origin) =
    proofObligationE
      (Just $ show $ render origin)
      (fromLoc (locOf origin))
      (render pre)
      (render post)

instance Render Origin where
  render AtAbort {} = "Abort"
  render AtSkip {} = "Skip"
  render AtSpec {} = "Spec"
  render AtAssignment {} = "Assigment"
  render AtAssertion {} = "Assertion"
  render AtIf {} = "Conditional"
  render AtLoop {} = "Loop Invariant"
  render AtTermination {} = "Loop Termination"