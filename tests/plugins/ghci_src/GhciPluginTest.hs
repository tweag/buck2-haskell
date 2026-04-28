-- | Module loaded interactively in GHCi with the real_plugin active.
-- The plugin replaces all string literals with the replacement from plugin_opts.
module GhciPluginTest (testGreeting) where

testGreeting :: String
testGreeting = "original"
