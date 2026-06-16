-- | Module loaded interactively in GHCi with the order_plugin active.
-- If compilation succeeds, the plugin received its options correctly.
{-# OPTIONS_GHC -fplugin=OrderPlugin #-}
module GhciOrderTest (hello) where

hello :: String
hello = "order plugin ok"
