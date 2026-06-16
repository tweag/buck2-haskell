-- | Module loaded interactively in GHCi with the real_plugin active.
-- The plugin replaces all string literals with the replacement from plugin_opts.
{-# OPTIONS_GHC -fplugin=Plugin #-}
module GhciPluginTest (testGreeting) where

testGreeting :: String
testGreeting = "original"
