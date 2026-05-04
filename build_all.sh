#!/usr/bin/env bash
# ============================================================
# build_all.sh — transpile every chapter in the arcade
# ============================================================
# Walks every chapter directory (ch01..ch08, plus cca/) and
# runs its build.sh. Aborts on the first failure.
#
# Usage:
#     FRAMEC=/path/to/framec ./build_all.sh
#
# If FRAMEC is unset, falls back to `framec` on PATH.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CHAPTERS=(
    ch01-pong
    ch02-breakout
    ch03-invaders
    ch04-asteroids
    ch05-pacman
    ch06-platformer
    ch07-shooter
    ch08-stealth
    cca
)

FAILED=()

for ch in "${CHAPTERS[@]}"; do
    if [[ ! -d "$ch" ]]; then
        echo "SKIP   $ch (directory missing)"
        continue
    fi
    if [[ ! -x "$ch/build.sh" ]]; then
        echo "SKIP   $ch (no executable build.sh)"
        continue
    fi
    echo "==================================================="
    echo "  $ch"
    echo "==================================================="
    if ( cd "$ch" && ./build.sh ); then
        echo "OK     $ch"
    else
        echo "FAIL   $ch"
        FAILED+=("$ch")
    fi
    echo
done

echo "==================================================="
if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "  All chapters built successfully."
    exit 0
else
    echo "  Failed: ${FAILED[*]}"
    exit "${#FAILED[@]}"
fi
