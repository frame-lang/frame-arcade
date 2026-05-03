#!/usr/bin/env bash
# ============================================================
# build.sh — transpile Frame source for Chapter 4 (Asteroids)
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

echo "==> framec compile frame/asteroids.fgd"
framec compile frame/asteroids.fgd --language gdscript -o generated/

echo "==> copying generated/asteroids.gd -> godot/scripts/asteroids.gd"
cp generated/asteroids.gd godot/scripts/asteroids.gd

echo "done."
