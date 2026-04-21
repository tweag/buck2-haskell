-- | A GHC plugin that verifies its command-line options arrive in the
-- expected order. The plugin expects exactly three options:
-- @["alpha", "beta", "gamma"]@. If the options are missing, out of order,
-- or not exactly those three strings, compilation fails with an error.
--
-- This tests that @plugin_opts@ in the @ghc_plugin@ rule are actually
-- threaded to the plugin in the declared order.
module OrderPlugin (plugin) where

import GHC.Plugins

plugin :: Plugin
plugin = defaultPlugin { installCoreToDos = install }

install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install opts todo
    | opts == ["alpha", "beta", "gamma"] = return todo
    | otherwise =
        error $
            "OrderPlugin: expected options [\"alpha\", \"beta\", \"gamma\"], got: "
            ++ show opts
