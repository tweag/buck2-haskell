module Main where

import Lib (greeting)

main :: IO ()
main = putStrLn ("Test passed: " ++ greeting)
