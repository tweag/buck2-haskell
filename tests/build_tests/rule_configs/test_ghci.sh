#!/usr/bin/env bash
# Tests haskell_ghci targets by running them via buck2 and checking that
# Lib.greeting is accessible, and that GHC plugins work in GHCi.
set -euo pipefail

# --- Non-plugin GHCi tests ---
for target in \
    buck2-haskell//tests/build_tests/rule_configs:ghci_release \
    buck2-haskell//tests/build_tests/rule_configs:ghci_debug
do
    if ! buck2 run --isolation-dir ghci_tests "$target" -- \
           -e ':set -v0' -e 'putStrLn Lib.greeting' | grep -q "Hello from Lib"; then
        echo "FAIL $target"
        exit 1
    fi
    echo "PASS $target"
done

# --- GHCi plugin tests ---
# real_plugin: the plugin replaces all string literals with "plugin_ok".
# Loading GhciPluginTest.hs in GHCi should produce the replaced value.
target="buck2-haskell//tests/plugins:ghci_real_plugin"
if ! buck2 run --isolation-dir ghci_tests "$target" -- \
       -e ':set -v0' -e ':load buck2-haskell/tests/plugins/ghci_src/GhciPluginTest.hs' -e 'putStrLn testGreeting' \
       | grep -q "plugin_ok"; then
    echo "FAIL $target (expected 'plugin_ok')"
    exit 1
fi
echo "PASS $target"

# order_plugin: plugin_opts must arrive as ["alpha","beta","gamma"].
# If GHCi loads the source successfully, the plugin received the right opts.
target="buck2-haskell//tests/plugins:ghci_order_plugin"
if ! buck2 run --isolation-dir ghci_tests "$target" -- \
       -e ':set -v0' -e ':load buck2-haskell/tests/plugins/ghci_src/GhciOrderTest.hs' -e 'putStrLn hello' \
       | grep -q "order plugin ok"; then
    echo "FAIL $target (expected 'order plugin ok')"
    exit 1
fi
echo "PASS $target"
