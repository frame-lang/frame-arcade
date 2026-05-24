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

# win_journey.fgd — the deterministic full-win rail (test scaffold,
# like canonical_journey but plays the real treasure economy to a
# genuine BLAST). Not mirrored to the arcade.
echo "==> $FRAMEC compile frame/win_journey.fgd"
"$FRAMEC" compile "frame/win_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/win_journey.gd -> godot/scripts/win_journey.gd"
cp "generated/win_journey.gd" "godot/scripts/win_journey.gd"

# death_journeys.fgd — deterministic death rails (test scaffold).
echo "==> $FRAMEC compile frame/death_journeys.fgd"
"$FRAMEC" compile "frame/death_journeys.fgd" --language gdscript -o generated/
echo "==> copying generated/death_journeys.gd -> godot/scripts/death_journeys.gd"
cp "generated/death_journeys.gd" "godot/scripts/death_journeys.gd"

# plant_journey.fgd — the plant/beanstalk branch rail (test scaffold).
echo "==> $FRAMEC compile frame/plant_journey.fgd"
"$FRAMEC" compile "frame/plant_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/plant_journey.gd -> godot/scripts/plant_journey.gd"
cp "generated/plant_journey.gd" "godot/scripts/plant_journey.gd"

# troll_journey.fgd — the troll-cross branch rail (test scaffold).
echo "==> $FRAMEC compile frame/troll_journey.fgd"
"$FRAMEC" compile "frame/troll_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/troll_journey.gd -> godot/scripts/troll_journey.gd"
cp "generated/troll_journey.gd" "godot/scripts/troll_journey.gd"

# maze_journey.fgd — the all-alike maze branch rail (test scaffold).
echo "==> $FRAMEC compile frame/maze_journey.fgd"
"$FRAMEC" compile "frame/maze_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/maze_journey.gd -> godot/scripts/maze_journey.gd"
cp "generated/maze_journey.gd" "godot/scripts/maze_journey.gd"

# rusty_journey.fgd — the rusty-door branch rail (test scaffold).
echo "==> $FRAMEC compile frame/rusty_journey.fgd"
"$FRAMEC" compile "frame/rusty_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/rusty_journey.gd -> godot/scripts/rusty_journey.gd"
cp "generated/rusty_journey.gd" "godot/scripts/rusty_journey.gd"

# room110_journey.fgd — the bedquilt→110 branch rail (test scaffold).
echo "==> $FRAMEC compile frame/room110_journey.fgd"
"$FRAMEC" compile "frame/room110_journey.fgd" --language gdscript -o generated/
echo "==> copying generated/room110_journey.gd -> godot/scripts/room110_journey.gd"
cp "generated/room110_journey.gd" "godot/scripts/room110_journey.gd"

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
