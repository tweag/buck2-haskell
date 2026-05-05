{-# LANGUAGE LambdaCase #-}
-- | A GHC compiler plugin that:
-- 1. Invokes the tool named in the first option via @readProcess@ — the
--    compilation fails if the tool is not found on PATH.
-- 2. Replaces every Haskell string literal with the second option —
--    the test binary checks that this replacement happened at runtime.
--
-- Inspired by the rules_haskell binary-with-plugin test.
module PluginLibBackend (plugin) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as Char8
import GHC.Plugins
import GHC.Types.Literal
import System.Process (readProcess)

plugin :: Plugin
plugin = defaultPlugin { installCoreToDos = install }

-- | @install ["tool_name", "replacement"]@ invokes @tool_name@ (must be on
-- PATH) and installs a Core-to-Core pass that replaces every string literal
-- with @replacement@.
install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install [toolName, replacement] todo = do
    -- Execute the tool.  If it is not on PATH, readProcess throws an
    -- IOException and GHC reports a plugin error ⇒ compilation fails.
    _ <- liftIO $ readProcess toolName [] ""
    return $ CoreDoPluginPass "StringReplacer" (pass (Char8.pack replacement)) : todo
install opts _ =
    error $ "Plugin: expected exactly 2 options [tool, replacement], got: " ++ show opts

pass :: ByteString -> ModGuts -> CoreM ModGuts
pass bs guts = return guts { mg_binds = map (replaceInBind bs) (mg_binds guts) }

replaceInBind :: ByteString -> CoreBind -> CoreBind
replaceInBind bs (NonRec b e) = NonRec b (replaceInExpr bs e)
replaceInBind bs (Rec bnds)   = Rec [(b, replaceInExpr bs e) | (b, e) <- bnds]

replaceInExpr :: ByteString -> CoreExpr -> CoreExpr
replaceInExpr bs = go
  where
    go = \case
        App e0 e1       -> App (go e0) (go e1)
        Lam b e         -> Lam b (go e)
        Let bnd e       -> Let (replaceInBind bs bnd) (go e)
        Case e0 b t alts ->
            Case (go e0) b t [Alt a bs' (go e') | Alt a bs' e' <- alts]
        Cast e c        -> Cast (go e) c
        Tick t e        -> Tick t (go e)
        Lit LitString{} -> Lit (LitString bs)
        e               -> e
