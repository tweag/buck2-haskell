module NoopPlugin (plugin) where

import GHC.Plugins

plugin :: Plugin
plugin = defaultPlugin
