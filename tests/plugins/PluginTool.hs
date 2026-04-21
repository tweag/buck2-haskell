-- | A trivial tool binary that the GHC plugin invokes via @readProcess@.
-- It prints a message and exits successfully. If this tool is not
-- on PATH when the plugin runs, compilation fails.
module Main (main) where

main :: IO ()
main = putStrLn "plugin-tool: ok"
