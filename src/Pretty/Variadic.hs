module Pretty.Variadic where

import           Data.Text.Prettyprint.Doc
import           Control.Monad                  ( (>=>) )

data Variadic a b = Expect (a -> Variadic a b) | Complete b

instance Functor (Variadic a) where
  fmap f (Complete x) = Complete (f x)
  fmap f (Expect   g) = Expect (\arg -> fmap f (g arg))

instance Applicative (Variadic a) where
  pure = Complete
  Complete f <*> Complete x = Complete (f x)
  Expect   f <*> Complete x = Expect (\arg -> f arg <*> pure x)
  Complete f <*> Expect   g = Expect (\arg -> pure f <*> g arg)
  Expect   f <*> Expect   g = Expect (\arg -> f arg <*> g arg)

instance Monad (Variadic a) where
  return = Complete
  Complete x >>= f = f x
  Expect   g >>= f = Expect (g >=> f)

parensIf :: Int -> Int -> Doc ann -> Doc ann
parensIf n m | n > m     = parens
             | otherwise = id

var :: Variadic a a
var = Expect Complete
