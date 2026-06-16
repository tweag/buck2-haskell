-- | Library module compiled with the string-replacing plugin.
-- The function @greeting@ returns a string literal that the plugin will
-- replace with the value passed via plugin_opts.
{-# OPTIONS_GHC -fplugin=Plugin #-}
module PluginLib (greeting) where

greeting :: String
greeting = "plugin"
