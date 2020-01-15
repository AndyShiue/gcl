import Test.Tasty

import qualified Test.Parser as Parser
import qualified Test.Pretty as Pretty

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests"
    [ Parser.tests
    , Pretty.tests
    ]
  -- [ testCase "2+2=4" $
  --     2+2 @?= 4
  -- , testCase "7 is even" $
  --     asserTBase TBool "Oops, 7 is odd" (even 7)
  -- ]