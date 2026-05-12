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

for name in aspects cca; do
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

echo "done."
