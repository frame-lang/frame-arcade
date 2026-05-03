#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for Chapter 6 (Platformer)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v framec >/dev/null 2>&1; then
    echo "error: framec not found on PATH"
    echo "install with:  cargo install framec"
    exit 1
fi

mkdir -p generated godot/scripts

echo "==> framec compile frame/platformer.fgd"
framec compile frame/platformer.fgd --language gdscript -o generated/

echo "==> copying generated/platformer.gd -> godot/scripts/platformer.gd"
cp generated/platformer.gd godot/scripts/platformer.gd

echo "done."
