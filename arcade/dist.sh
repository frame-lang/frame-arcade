#!/usr/bin/env bash
# ============================================================
# dist.sh — build the Frame Arcade distributables for itch.io
# ============================================================
# Two artifacts produced under arcade/dist/:
#   web/index.html  +  index.pck / index.wasm / index.js
#                   ↑ upload this folder zipped, mark itch.io
#                     "kind of project: HTML" → playable in
#                     browser
#   mac/FrameArcade.zip
#                   ↑ upload as macOS native (universal arm64
#                     + x86_64). Unsigned; users right-click →
#                     Open the first time. itch.io's app
#                     handles this gracefully.
#
# Workflow:
#   1. Compile every chapter's Frame source via build_all.sh
#      so the Godot project sees fresh .gd scripts.
#   2. Ask Godot to export each preset to arcade/dist/.
#   3. Print upload-ready paths.
#
# Usage:
#     ./dist.sh                    # both presets
#     ./dist.sh web                # web only
#     ./dist.sh mac                # mac only
#
# Env:
#     GODOT       Path to godot binary. Defaults to `godot` on PATH.
#     FRAMEC      Path to framec binary. Defaults to `framec` on PATH.
#
# Pre-reqs:
#   - Godot 4.6.x with matching export templates installed at
#     ~/Library/Application Support/Godot/export_templates/4.6.2.stable/
#   - framec on PATH (or set FRAMEC=/path/to/framec)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCADE_DIR="$SCRIPT_DIR"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$ARCADE_DIR/godot"
DIST_DIR="$ARCADE_DIR/dist"

GODOT_BIN="${GODOT:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    echo "error: '$GODOT_BIN' not found"
    echo "set GODOT env var to the binary path, e.g.:"
    echo "  GODOT=/usr/local/bin/godot ./dist.sh"
    exit 1
fi

# Step 1 — transpile every chapter's Frame source. The arcade
# Godot project bundles every chapter's compiled .gd, so we
# need them all fresh before the export grabs them.
echo "==> transpile Frame sources (build_all.sh)"
( cd "$REPO_DIR" && ./build_all.sh )

# Step 2 — pick which presets to run.
WHICH="${1:-all}"
DO_WEB=false
DO_MAC=false
case "$WHICH" in
    all)     DO_WEB=true; DO_MAC=true ;;
    web)     DO_WEB=true ;;
    mac|macos) DO_MAC=true ;;
    *)
        echo "error: unknown target '$WHICH' (expected: all | web | mac)"
        exit 1
        ;;
esac

# Step 3 — export each requested preset. Each export gets a
# clean output directory so partial files from a previous run
# don't sneak into the upload.
if $DO_WEB; then
    echo "==> export Web → $DIST_DIR/web/"
    rm -rf "$DIST_DIR/web"
    mkdir -p "$DIST_DIR/web"
    "$GODOT_BIN" --headless --path "$PROJECT_DIR" \
        --export-release "Web" "$DIST_DIR/web/index.html"
fi

if $DO_MAC; then
    echo "==> export macOS → $DIST_DIR/mac/FrameArcade.zip"
    rm -rf "$DIST_DIR/mac"
    mkdir -p "$DIST_DIR/mac"
    "$GODOT_BIN" --headless --path "$PROJECT_DIR" \
        --export-release "macOS" "$DIST_DIR/mac/FrameArcade.zip"
fi

# Step 4 — summarise. itch.io's upload form takes a .zip per
# platform; print a couple of one-liners the human can paste.
echo
echo "==> built artifacts:"
if $DO_WEB; then
    if [[ -f "$DIST_DIR/web/index.html" ]]; then
        echo "    Web:   $DIST_DIR/web/   (zip the whole folder for itch.io)"
        ( cd "$DIST_DIR/web" && du -sh . | awk '{print "           total: "$1}' )
    else
        echo "    Web:   FAILED — no index.html produced"
        exit 1
    fi
fi
if $DO_MAC; then
    if [[ -f "$DIST_DIR/mac/FrameArcade.zip" ]]; then
        echo "    macOS: $DIST_DIR/mac/FrameArcade.zip   (upload directly to itch.io)"
        du -sh "$DIST_DIR/mac/FrameArcade.zip" | awk '{print "           size: "$1}'
    else
        echo "    macOS: FAILED — no zip produced"
        exit 1
    fi
fi
