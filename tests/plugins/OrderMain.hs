-- | Test that the OrderPlugin received its options in the expected order.
-- If compilation succeeds, the plugin got ["alpha", "beta", "gamma"].
module Main (main) where

main :: IO ()
main = putStrLn "test passed: plugin_opts arrived in order"
