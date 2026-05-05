{-# LANGUAGE LambdaCase #-}
-- | See "PluginLibBackend" for details on the plugin.
--
-- This module is here to test for transitive dependencies in plugins.
module Plugin (plugin) where

import PluginLibBackend (plugin)
