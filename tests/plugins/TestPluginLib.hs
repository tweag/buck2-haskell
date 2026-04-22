-- | Test that the plugin replaced string literals in PluginLib.
-- If the plugin ran correctly with option @"plugin_ok"@, greeting will be
-- @"plugin_ok"@.
module Main (main) where

import PluginLib(greeting)

main :: IO ()
main =
    if "plugin_ok" == greeting then
        putStrLn "test passed: plugin_opts applied"
    else
        error $ "plugin_opts NOT applied: expected \"plugin_ok\", got \"" ++ greeting ++ "\""
