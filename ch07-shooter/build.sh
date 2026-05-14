#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for Chapter 7 (Shooter)
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

echo "==> $FRAMEC compile frame/shooter.fgd"
"$FRAMEC" compile frame/shooter.fgd --language gdscript -o generated/

echo "==> copying generated/shooter.gd -> godot/scripts/shooter.gd"
cp generated/shooter.gd godot/scripts/shooter.gd

echo "done."
