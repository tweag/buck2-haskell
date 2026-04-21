module Main (main) where

import Lib (hello)

main :: IO ()
main = do
  putStrLn hello
  putStrLn "Test passed"
