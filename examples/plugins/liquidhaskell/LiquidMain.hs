-- | Example: LiquidHaskell refinement type checking via GHC plugin.
--
-- In this file it will check that head is not called on an empty list,
-- so compilation is supposed to fail as there is a call to head on an
-- empty list.
module Main where

main :: IO ()
main = do
  putStrLn "LiquidHaskell plugin test passed"
  print (head [] :: Int)
