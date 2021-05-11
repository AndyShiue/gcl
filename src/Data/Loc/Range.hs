{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
module Data.Loc.Range where 


import Data.Loc
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Data.Aeson (ToJSON(..), FromJSON(..))
import GHC.Generics (Generic)

-- | Invariant: the second position should be greater than the first position
data Range = Range Pos Pos
    deriving (Eq, Show, Generic)

-- | Starting position of the range
rangeStart :: Range -> Pos 
rangeStart (Range a _) = a

-- | Ending position of the range
rangeEnd :: Range -> Pos 
rangeEnd (Range _ b) = b

fromLoc :: Loc -> Maybe Range
fromLoc NoLoc = Nothing 
fromLoc (Loc x y) = Just (Range x y)

-- | Calculates the distance between the two positions
span :: Range -> Int 
span (Range a b) = posCol b - posCol a + 1

-- | Compares the starting position
instance Ord Range where 
  Range a _ `compare` Range b _ = a `compare` b

instance Located Range where 
  locOf (Range x y) = Loc x y

-- | Merge two ranges by filling their gap
instance Semigroup Range where 
  Range a b <> Range c d = case (a `compare` c, b `compare` d) of 
    (LT, LT) -> Range a d 
    (LT, EQ) -> Range a d 
    (LT, GT) -> Range a b
    (EQ, LT) -> Range a d
    (EQ, EQ) -> Range a b
    (EQ, GT) -> Range a b
    (GT, LT) -> Range c d 
    (GT, EQ) -> Range c d 
    (GT, GT) -> Range c b

--------------------------------------------------------------------------------
-- | Like "Located"

class Ranged a where 
  rangeOf :: a -> Range 

instance Ranged a => Ranged (NonEmpty a) where 
  rangeOf xs = rangeOf (NE.head xs) <> rangeOf (NE.last xs)

--------------------------------------------------------------------------------
-- | A value of type @R a@ is a value of type @a@ with an associated 'Range', but
-- this location is ignored when performing comparisons.

data R a = R Range a 
  deriving (Functor)

unRange :: R a -> a
unRange (R _ a) = a

instance Eq x => Eq (R x) where
    (R _ x) == (R _ y) = x == y

instance Ord x => Ord (R x) where
    compare (R _ x) (R _ y) = compare x y

instance Show x => Show (R x) where
    show (R _ x) = show x

instance Ranged (R a) where
    rangeOf (R range _) = range

--------------------------------------------------------------------------------

-- | Make Pos instances of FromJSON and ToJSON
instance ToJSON Pos where
  toJSON (Pos filepath line column offset) = toJSON (filepath, line, column, offset)

instance FromJSON Pos where
  parseJSON v = do
    (filepath, line, column, offset) <- parseJSON v
    return $ Pos filepath line column offset

-- | Make Range instances  of FromJSON and ToJSON
instance FromJSON Range where
instance ToJSON Range where