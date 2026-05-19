#!/usr/bin/env bash
# ============================================================
# run_tests.sh — execute all CCA smoke tests under headless Godot
# ============================================================
# Each test file in tests/ is a SceneTree script that prints
# "PASS" or "FAIL" and exits with the failure count. We run
# them sequentially and report the summary.
#
# Usage:
#     ./run_tests.sh                   # run all tests
#     ./run_tests.sh tests/test_cca_lamp.gd ...  # run subset
#
# Exit code: 0 if every test passed, otherwise the number of
# failed tests.
#
# Dependencies: a `godot` binary on PATH (Godot 4.x). The test
# files preload res://scripts/cca.gd, so the FSM must already
# have been built (run ./build.sh first).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v godot >/dev/null 2>&1; then
    echo "error: godot not found on PATH"
    exit 1
fi

# Verify the FSM has been built.
if [[ ! -f godot/scripts/cca.gd ]]; then
    echo "error: godot/scripts/cca.gd not found — run ./build.sh first"
    exit 1
fi

# Tests to run: argv if given, otherwise all tests/*.gd
if [[ $# -gt 0 ]]; then
    TESTS=("$@")
else
    # Portable across macOS bash 3.x and modern bash. Globbing
    # produces a sorted list naturally.
    TESTS=()
    for f in tests/test_cca_*.gd; do
        TESTS+=("$f")
    done
fi

PASSED=0
FAILED=0
FAILED_NAMES=()

for t in "${TESTS[@]}"; do
    name="$(basename "$t" .gd)"
    printf "%-32s  " "$name"
    # godot --script needs a path relative to the project root
    # OR an absolute one. We pass an absolute path and the
    # --path flag pointed at the godot project.
    abs="$(cd "$(dirname "$t")" && pwd)/$(basename "$t")"
    # Per-test timeout: 300s. Most tests finish in <10s; the
    # monkey fuzzer (~75-90s) and the milestone-seeded BFS
    # tests (~110-180s, esp. multi-seed at deep milestones)
    # legitimately take longer. Bumped from 120s in 2026-05-18
    # after the multi-seed BFS test was being truncated to
    # fit the budget rather than the budget being raised to
    # fit the test — the same canon-fidelity anti-pattern
    # that earlier surfaced lowered hint thresholds. Tests
    # should be honest about their cost; the harness
    # accommodates.
    if out=$(timeout 300 godot --headless --path godot/ --script "$abs" 2>&1); then
        verdict=$(echo "$out" | grep -E "^PASS|^FAIL|FAIL —|PASS —" | head -1)
        echo "$verdict"
        if echo "$verdict" | grep -q "^PASS"; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_NAMES+=("$name")
        fi
    else
        echo "FAIL — godot exited non-zero"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
done

echo
echo "====================================="
echo "  PASSED: $PASSED   FAILED: $FAILED"
echo "====================================="

if [[ $FAILED -gt 0 ]]; then
    echo "Failed tests:"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - $n"
    done
    exit "$FAILED"
fi

exit 0
