module Lib (greeting, Example) where

import Test.Hspec (Example)

-- | Just a greeting text. We refer to 'Example' to test haddock.
greeting :: String
greeting = "Hello from Lib"
