#!/usr/bin/env bash
# ============================================================
# build.sh — compile all 8 chapter Frame sources for the cabinet
# ============================================================
# Walks each ch??-* directory and copies its compiled .gd into
# our godot/scripts/ folder. The cabinet's per-game driver
# scripts (e.g. pong_main.gd) preload these by their bare name.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCADE_DIR="$SCRIPT_DIR"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

FRAMEC="${FRAMEC:-framec}"

if ! command -v "$FRAMEC" >/dev/null 2>&1; then
    echo "error: '$FRAMEC' not found"
    echo "set FRAMEC env var to the binary path, e.g.:"
    echo "  FRAMEC=/path/to/framec ./build.sh"
    exit 1
fi

mkdir -p "$ARCADE_DIR/godot/scripts"

# Each chapter has frame/<name>.gd. We compile each one and
# copy the result to arcade/godot/scripts/<name>.gd.
#
# ch04-asteroids is intentionally absent from this list: the
# cabinet uses its own variant (arcade/frame/asteroids.fgd)
# that adds @@[persist] save/resume on top of the chapter's
# state machine. See the cabinet-only loop below.
for entry in \
    "ch01-pong:pong" \
    "ch02-breakout:breakout" \
    "ch03-invaders:invaders" \
    "ch05-pacman:pacman" \
    "ch06-platformer:platformer" \
    "ch07-shooter:shooter" \
    "ch08-stealth:stealth"
do
    chapter="${entry%%:*}"
    name="${entry##*:}"

    src="$REPO_DIR/$chapter/frame/$name.fgd"
    out_dir="$ARCADE_DIR/generated"
    dst="$ARCADE_DIR/godot/scripts/$name.gd"

    if [[ ! -f "$src" ]]; then
        echo "warning: $src not found; skipping"
        continue
    fi

    mkdir -p "$out_dir"
    echo "==> $FRAMEC compile $chapter/frame/$name.fgd"
    "$FRAMEC" compile "$src" --language gdscript -o "$out_dir/"

    echo "==> copying $out_dir/$name.gd -> $dst"
    cp "$out_dir/$name.gd" "$dst"
done

# ------------------------------------------------------------
# Cabinet-only Frame sources.
#
#   scoreboard — high-score table (cabinet exclusive).
#
#   asteroids  — cabinet variant that overrides the chapter
#                source. Adds @@[persist] to all three systems
#                (Ship, AsteroidField, Asteroids) and switches
#                $InGame.pause()/Paused.resume() to push$/pop$
#                so save/resume preserves the actual paused
#                sub-state. The chapter source stays untouched
#                as a clean teaching artifact.
# ------------------------------------------------------------
for cabinet_name in scoreboard asteroids; do
    src="$ARCADE_DIR/frame/$cabinet_name.fgd"
    out_dir="$ARCADE_DIR/generated"
    dst="$ARCADE_DIR/godot/scripts/$cabinet_name.gd"

    if [[ ! -f "$src" ]]; then
        echo "warning: $src not found; skipping"
        continue
    fi

    mkdir -p "$out_dir"
    echo "==> $FRAMEC compile arcade/frame/$cabinet_name.fgd"
    "$FRAMEC" compile "$src" --language gdscript -o "$out_dir/"

    echo "==> copying $out_dir/$cabinet_name.gd -> $dst"
    cp "$out_dir/$cabinet_name.gd" "$dst"
done

echo
echo "done. Run with:"
echo "  godot --path godot/ scenes/menu.tscn"
