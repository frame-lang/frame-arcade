#!/usr/bin/env bash
# ============================================================
# run_smoke_test.sh — arcade chapter smoke checks (headless)
# ============================================================
# Tier 1b of the V1.2 plan: a minimal arcade-side verification
# that the chapter's main scripts can compose their FSM and run
# end-to-end without the structural class of regression that
# bit us on 2026-05-10 (stale FSM mirror, NonexistentFunction
# crash on first call).
#
# Currently runs:
#   - test_arcade_cca_smoke.gd  (CCA chapter)
#
# Add more `arcade/tests/test_arcade_*_smoke.gd` files as other
# chapters need coverage — the runner discovers them by glob.
#
# Usage:
#     ./run_smoke_test.sh
# Exit code: 0 if every test passed, otherwise the failure count.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v godot >/dev/null 2>&1; then
    echo "error: godot not found on PATH"
    exit 1
fi

FAILED=0
PASSED=0
echo
echo "=========================================="
echo "  Arcade smoke tests"
echo "=========================================="

for f in tests/test_arcade_*_smoke.gd; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f" .gd)"
    rel="res://../tests/$(basename "$f")"
    printf "%-40s " "$name"
    if godot --headless --path godot/ --script "$rel" > /tmp/_arcade_smoke.log 2>&1; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        sed 's/^/    /' /tmp/_arcade_smoke.log
        FAILED=$((FAILED + 1))
    fi
done

echo
echo "=========================================="
echo "  PASSED: $PASSED   FAILED: $FAILED"
echo "=========================================="

exit "$FAILED"
