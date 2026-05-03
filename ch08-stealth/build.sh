#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for Chapter 8 (Stealth)
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

echo "==> $FRAMEC compile frame/stealth.fgd"
"$FRAMEC" compile frame/stealth.fgd --language gdscript -o generated/

echo "==> copying generated/stealth.gd -> godot/scripts/stealth.gd"
cp generated/stealth.gd godot/scripts/stealth.gd

echo "done."
