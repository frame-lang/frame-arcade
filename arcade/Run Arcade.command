#!/usr/bin/env bash
cd "$(dirname "$0")"
exec /usr/local/bin/godot --path godot/ scenes/menu.tscn
