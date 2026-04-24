#!/usr/bin/env bash
# Tests haskell_ghci targets by running them via buck2 and checking that
# Lib.greeting is accessible.
set -euo pipefail

expected="Hello from Lib"

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
