# ============================================================
# arcade.gd — autoload (singleton) for the cabinet
# ============================================================
# Provides:
#   1. Scene navigation between the menu and the seven games.
#      Each game scene is a self-contained Godot scene with
#      the chapter's driver script attached to a Node2D root.
#      To go back to the menu, any game can call:
#          Arcade.return_to_menu()
#      or the player can press Escape (handled per-driver).
#
#   2. Cabinet-level high-score persistence via the
#      `Scoreboard` Frame system. Each scored game's driver
#      calls `Arcade.record_score(name, score)` on game-over;
#      the menu reads `Arcade.get_high_score(name)` to render
#      best scores. Scores survive across cabinet sessions
#      because Scoreboard is persisted to user://scoreboard.dat
#      via Frame's @@[persist] save_state/restore_state pair.
# ============================================================
extends Node

const MENU_SCENE: String = "res://scenes/menu.tscn"
const SCOREBOARD_PATH: String = "user://scoreboard.dat"
const ScoreboardScript = preload("res://scripts/scoreboard.gd")

# Game registry. Keep this in book/menu order.
#
# `name` is the stable identifier passed to the Scoreboard;
# don't change it once scores have been written under that
# key, or persisted entries become orphaned. `scored = false`
# games (Ghost Maze, Platformer) are demos of their respective
# Frame patterns rather than scoring games — they don't appear
# in the high-score column.
const GAMES: Array = [
    {
        "title": "1. Pong",
        "name": "pong",
        "scored": false,
        "scene": "res://scenes/games/pong.tscn",
        "blurb": "Core FSM, enter/exit handlers, domain variables",
    },
    {
        "title": "2. Breakout",
        "name": "breakout",
        "scored": true,
        "scene": "res://scenes/games/breakout.tscn",
        "blurb": "Multi-system composition, state variables",
    },
    {
        "title": "3. Space Invaders",
        "name": "invaders",
        "scored": true,
        "scene": "res://scenes/games/invaders.tscn",
        "blurb": "Hierarchical state machines, parent inheritance",
    },
    {
        "title": "4. Asteroids",
        "name": "asteroids",
        "scored": true,
        "scene": "res://scenes/games/asteroids.tscn",
        "blurb": "State stack (push$/pop$), parameterized systems",
    },
    {
        "title": "5. Ghost Maze",
        "name": "pacman",
        "scored": false,
        "scene": "res://scenes/games/pacman.tscn",
        "blurb": "HSM showcase, two-stack coordination",
    },
    {
        "title": "6. Platformer",
        "name": "platformer",
        "scored": false,
        "scene": "res://scenes/games/platformer.tscn",
        "blurb": "Orthogonal-state problem, HSM vs composition",
    },
    {
        "title": "7. Side-Scrolling Shooter",
        "name": "shooter",
        "scored": true,
        "scene": "res://scenes/games/shooter.tscn",
        "blurb": "Capstone — boss HSM, parameterized enemies",
    },
    {
        "title": "8. Stealth",
        "name": "stealth",
        "scored": false,
        "scene": "res://scenes/games/stealth.tscn",
        "blurb": "Agent AI — Frame as an alternative to behavior trees",
    },
    {
        "title": "9. Colossal Cave Adventure",
        "name": "cca",
        "scored": false,
        "scene": "res://scenes/games/cca.tscn",
        "blurb": "Capstone — 24 FSMs, 140 rooms, aspect bus + cross-FSM orchestration",
    },
]

# Live Scoreboard instance. Populated in _ready, persisted on
# every record_score call. The script-level reference is held
# here so the menu and game drivers can both reach it via the
# autoload singleton without each managing their own copy.
var _scoreboard

# Index of the most recently launched game. -1 before any
# launch. The menu reads this on _ready to pre-select the
# row the user just came from, so Esc-back-from-game returns
# them to where they were rather than the top of the list.
var last_played_index: int = -1

func _ready() -> void:
    _scoreboard = ScoreboardScript.new()
    _load_scoreboard()

# --- Scene navigation ----------------------------------------

func launch_game(index: int) -> void:
    if index < 0 or index >= GAMES.size():
        return
    last_played_index = index
    get_tree().change_scene_to_file(GAMES[index].scene)

func return_to_menu() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)

# --- Scoreboard ----------------------------------------------

# Drivers call this when their game session ends. Returns true
# if `score` is a new high. Persists immediately to disk on a
# new high so a cabinet crash doesn't lose records.
func record_score(name: String, score: int) -> bool:
    var is_new_high: bool = _scoreboard.record_score(name, score)
    if is_new_high:
        _save_scoreboard()
    return is_new_high

func get_high_score(name: String) -> int:
    return _scoreboard.get_high_score(name)

# --- Per-game saved runs --------------------------------------
#
# Some games (currently just Asteroids) support save-and-resume
# of an in-progress run. The save file lives at
# `user://<game>.save` where <game> is the entry's `name` field.
# Each game owns the bundle format inside that file; arcade.gd
# only knows how to construct the path, check existence, and
# delete on the user's behalf.
#
# These helpers are used by:
#   - menu.gd           — to show a "Continue / New game" prompt
#                         when the player picks a game with a
#                         saved run, and to delete the save when
#                         they choose "New game"
#   - <game>_main.gd    — to derive the save path consistently
#                         with the cabinet's expectation
#
# Games that don't support saves never write to their path, so
# has_save() returns false for them and the menu skips the
# prompt.

func save_path(name: String) -> String:
    return "user://" + name + ".save"

func has_save(name: String) -> bool:
    return FileAccess.file_exists(save_path(name))

func delete_save(name: String) -> void:
    var p := save_path(name)
    if FileAccess.file_exists(p):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

# --- Scoreboard internals (high-score persistence) -----------

func _load_scoreboard() -> void:
    if not FileAccess.file_exists(SCOREBOARD_PATH):
        return
    var f := FileAccess.open(SCOREBOARD_PATH, FileAccess.READ)
    if f == null:
        push_warning("Scoreboard load: could not open " + SCOREBOARD_PATH)
        return
    var data := f.get_buffer(f.get_length())
    f.close()
    if data.size() == 0:
        return
    _scoreboard.restore_state(data)

func _save_scoreboard() -> void:
    var f := FileAccess.open(SCOREBOARD_PATH, FileAccess.WRITE)
    if f == null:
        push_warning("Scoreboard save: could not write " + SCOREBOARD_PATH)
        return
    f.store_buffer(_scoreboard.save_state())
    f.close()
