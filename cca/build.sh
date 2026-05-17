#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for the CCA prototype
# ============================================================
# Currently only `aspects.fgd` (the bus + sample aspects).
# As real CCA systems land, add them to the loop.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FRAMEC="${FRAMEC:-framec}"

if ! command -v "$FRAMEC" >/dev/null 2>&1; then
    echo "error: '$FRAMEC' not found"
    echo "set FRAMEC env var to the binary path, e.g.:"
    echo "  FRAMEC=/path/to/framec ./build.sh"
    exit 1
fi

mkdir -p generated godot/scripts

ARCADE_DIR="$SCRIPT_DIR/../arcade/godot/scripts"

for name in aspects npcs puzzles cca; do
    echo "==> $FRAMEC compile frame/$name.fgd"
    "$FRAMEC" compile "frame/$name.fgd" --language gdscript -o generated/

    echo "==> copying generated/$name.gd -> godot/scripts/$name.gd"
    cp "generated/$name.gd" "godot/scripts/$name.gd"

    # Mirror to the arcade chapter so both runtimes load the same
    # FSM. Without this sync, the arcade's cca.gd drifts behind
    # the standalone every time the FSM is rebuilt — which has
    # bitten us before with NonexistentFunction errors at launch.
    if [ -d "$ARCADE_DIR" ]; then
        echo "==> mirroring generated/$name.gd -> arcade/godot/scripts/$name.gd"
        cp "generated/$name.gd" "$ARCADE_DIR/$name.gd"
    fi
done

# canonical_journey.fgd is a TEST scaffold — Frame state machine
# describing the canonical CCA happy path that the FSM-driven
# journey test (tests/test_cca_canonical_journey.gd) walks. NOT
# mirrored to the arcade; the arcade has no need for the test
# scaffold and we don't want it shipping in the cabinet build.
echo "==> $FRAMEC compile frame/canonical_journey.fgd"
"$FRAMEC" compile "frame/canonical_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/canonical_journey.gd -> godot/scripts/canonical_journey.gd"
cp "generated/canonical_journey.gd" "godot/scripts/canonical_journey.gd"

# topology.gd is hand-written canon data (140 rooms + 75 gates),
# not framec-generated, but it MUST also stay in sync between
# the standalone and arcade copies — both `driver.gd` and
# `cca_main.gd` preload it. We had a silent value drift on three
# canon gates (room 25 plant climbs) caught only by a manual
# diff; the mirror below makes that impossible going forward.
if [ -d "$ARCADE_DIR" ]; then
    echo "==> mirroring godot/scripts/topology.gd -> arcade/godot/scripts/topology.gd"
    cp "godot/scripts/topology.gd" "$ARCADE_DIR/topology.gd"
fi

echo "done."
