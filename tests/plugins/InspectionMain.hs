{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fplugin=Test.Inspection.Plugin #-}
-- | Test using inspection-testing as a toolchain-library GHC plugin.
-- The plugin verifies at compile time that GHC sees @myId@ and @myId2@
-- as the same Core expression.
module Main (main) where

import Test.Inspection

myId :: a -> a
myId x = x

myId2 :: a -> a
myId2 x = x

inspect $ 'myId === 'myId2

main :: IO ()
main = putStrLn "inspection-testing plugin OK"
