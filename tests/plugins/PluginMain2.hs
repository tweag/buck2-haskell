-- | Test that the plugin does not run on this file.
--
-- This test is meant to check that when modules aren't placed in
-- srcs_plugins, the per-module plugins aren't accidentally applied to them.
--
-- The string @"plugin"@ is a literal in the source; if the plugin ran
-- correctly with option @"plugin_ok"@, it will have been replaced with
-- @"plugin_ok"@ at compile time. We compare against the char-list form
-- which is NOT a string literal and therefore is not modified by the plugin.
--
-- The test could also fail if the plugin runs because the plugin tool is
-- correctly excluded.
module PluginMain2 where

main2 :: IO ()
main2 =
    if "plugin" == ['p', 'l', 'u', 'g', 'i', 'n', '_', 'o', 'k'] then
        error "plugin run when not expected"
    else
        putStrLn "test passed: plugin_opts were not applied"
