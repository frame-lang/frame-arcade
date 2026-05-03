#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for Chapter 2 (Breakout)
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

echo "==> framec compile frame/breakout.fgd"
framec compile frame/breakout.fgd --language gdscript -o generated/

echo "==> copying generated/breakout.gd -> godot/scripts/breakout.gd"
cp generated/breakout.gd godot/scripts/breakout.gd

echo "done."
