#!/usr/bin/env bash
# Test expected-failure scenarios for the GHC plugin system.
#
# Each test builds a target that is expected to fail, then checks that
# the error output contains the expected message. If any target succeeds
# when it should fail, or fails with an unexpected message, this script
# exits non-zero.

set -euo pipefail

PASS=0
FAIL=0

# Helper: run buck build on a target, expect failure, check error message.
# Usage: expect_failure <target> <expected_substring>
expect_failure() {
    local target="$1"
    local expected="$2"
    local label
    label=$(echo "$target" | sed 's|.*//||')

    local output
    if output=$(buck --isolation-dir test_expected_failures build "$target" 2>&1); then
        echo "FAIL: $label — expected build failure but build succeeded"
        FAIL=$((FAIL + 1))
        return
    fi

    if echo "$output" | grep -qF "$expected"; then
        echo "PASS: $label — failed with expected message"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — failed but expected message not found"
        echo "  Expected substring: $expected"
        echo "  Actual output (last 20 lines):"
        echo "$output" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Testing expected plugin failures ==="
echo

# 1. Mutual exclusion: plugins + srcs_plugins
expect_failure \
    "buck2-haskell//expected_failures:err_mutual_exclusion" \
    "mutually exclusive"

# 2. ghc_plugin deps must be haskell_library (provides HaskellLibraryProvider)
expect_failure \
    "buck2-haskell//expected_failures:err_bad_deps" \
    "HaskellLibraryProvider"

# 3. srcs_plugins with non-incremental builds
expect_failure \
    "buck2-haskell//expected_failures:err_srcs_plugins_non_incremental" \
    "Per-module plugins require incremental"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
