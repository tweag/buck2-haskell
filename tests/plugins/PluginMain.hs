-- | Test that the plugin replaced string literals.
-- The string @"plugin"@ is a literal in the source; if the plugin ran
-- correctly with option @"plugin_ok"@, it will have been replaced with
-- @"plugin_ok"@ at compile time. We compare against the char-list form
-- which is NOT a string literal and therefore is not modified by the plugin.
module Main (main) where

main :: IO ()
main =
    if "plugin" == ['p', 'l', 'u', 'g', 'i', 'n', '_', 'o', 'k'] then
        putStrLn "test passed: plugin_opts applied"
    else
        error $ "plugin_opts NOT applied: expected \"plugin_ok\", got \"" ++ "plugin" ++ "\""
