{-# LANGUAGE TemplateHaskell #-}
-- | Test using inspection-testing as a toolchain-library GHC plugin.
-- The plugin verifies at compile time that GHC sees @myId@ equal to itself.
module Main (main) where

import Test.Inspection

myId :: a -> a
myId x = x

inspect $ 'myId === 'myId

main :: IO ()
main = putStrLn "inspection-testing plugin OK"
