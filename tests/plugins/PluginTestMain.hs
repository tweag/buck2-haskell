-- | Test that the plugin replaced string literals (test variant).
-- Same logic as PluginMain.hs but used by haskell_test targets.
module Main (main) where

main :: IO ()
main =
    if "plugin" == ['p', 'l', 'u', 'g', 'i', 'n', '_', 'o', 'k'] then
        putStrLn "test passed: plugin_opts applied"
    else
        error $ "plugin_opts NOT applied: expected \"plugin_ok\", got \"" ++ "plugin" ++ "\""
