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
#     ./run_tests.sh --fast            # skip slow BFS tests (~3 min total)
#     ./run_tests.sh tests/test_cca_lamp.gd ...  # run subset
#
# --fast mode skips the long-running BFS / fuzzer tests listed in
# SLOW_TESTS below. Pre-commit runs in this mode by default so the
# hook stays under ~3 min; full coverage runs on demand or in CI.
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

# Tests skipped in --fast mode. These are the long-running BFS
# state-space tests (2-4 min each) and the fuzzer. They catch
# coverage / state-graph regressions; the structural tests
# (verb effects, canon conformance, etc.) catch most behavioral
# regressions at low cost. Pre-commit runs --fast; full coverage
# runs on demand and in CI.
SLOW_TESTS=(
    "tests/test_cca_state_space.gd"
    "tests/test_cca_state_space_seeded.gd"
    "tests/test_cca_state_space_seeded_progression.gd"
    "tests/test_cca_state_space_seeded_post_bridge.gd"
    "tests/test_cca_state_space_seeded_endgame.gd"
    "tests/test_cca_state_space_seeded_multiseed.gd"
    "tests/test_cca_monkey.gd"
    "tests/test_cca_probe.gd"
    "tests/test_cca_area_explorer.gd"
    "tests/test_cca_dag_coverage.gd"
    # Retired BFS coverage audits. Superseded by the deterministic
    # journey-DAG (test_cca_dag_coverage), which now reaches all 134
    # graph rooms + 6 transient-prose = 140/140 canon in seconds.
    # These four are the old global-BFS / JourneyTree convergence
    # measurements (slow + seed-sensitive). Kept for history and the
    # gap-annotation tooling, but skipped by default — run explicitly
    # (`./run_tests.sh tests/test_cca_journey_tree_audit.gd`) if you
    # ever need the BFS gap report again.
    "tests/test_cca_journey_tree_audit.gd"
    "tests/test_cca_journey_tree_audit_union.gd"
    "tests/test_cca_journey_tree_plant_unlock.gd"
    "tests/test_cca_journey_tree_rusty_door.gd"
)

FAST_MODE=0
if [[ $# -gt 0 && "$1" == "--fast" ]]; then
    FAST_MODE=1
    shift
fi

# Tests to run: argv if given (after --fast), otherwise all
# tests/*.gd minus the slow set (when --fast).
if [[ $# -gt 0 ]]; then
    TESTS=("$@")
else
    # Portable across macOS bash 3.x and modern bash. Globbing
    # produces a sorted list naturally.
    TESTS=()
    for f in tests/test_cca_*.gd; do
        if [[ $FAST_MODE -eq 1 ]]; then
            skip=0
            for s in "${SLOW_TESTS[@]}"; do
                if [[ "$f" == "$s" ]]; then skip=1; break; fi
            done
            [[ $skip -eq 1 ]] && continue
        fi
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
    # Per-test timeout: 600s. Most tests finish in <10s; the
    # monkey fuzzer (~75-90s), the milestone-seeded BFS tests
    # (~110-180s), and the LampLit-seeded BFS (~3:40 at cap
    # 10000 once the prompts-state-leak fix landed and the
    # graph fully expands) legitimately take longer. Bumped
    # from 120s → 300s → 600s as the BFS reaches more of the
    # cave per the same canon-fidelity-over-budget principle:
    # tests should be honest about their cost; the harness
    # accommodates.
    if out=$(timeout 600 godot --headless --path godot/ --script "$abs" 2>&1); then
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
