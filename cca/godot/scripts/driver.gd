# ============================================================
# CCA driver — text-adventure UI + parser + maze data
# ============================================================
# Owns a CCA Adventure FSM, hosts the player-facing text I/O
# (RichTextLabel scrolling log + LineEdit input), and bridges
# typed commands to Frame events.
#
# Architecture mirrors every other "Frame is the brain, the
# driver is the body" pattern in this repo, scaled up for a
# turn-based parser game:
#
#   Player types into LineEdit
#       ↓
#   _process_input(text)                — driver-side
#       ↓ parse to (verb, noun)
#       ↓ resolve direction → room id (maze data table)
#       ↓ handle UI verbs (inventory, score, save, load, hint, quit)
#       ↓ otherwise:
#   fsm.do_command(verb, noun)          — Frame side
#       returns String response (driver prints)
#       ↓
#   fsm.tick()                          — Frame side
#       advances lamp battery, endgame timer, hint observation,
#       pirate threshold, etc.
#       ↓
#   driver checks per-turn consequences (pirate steals, dwarf
#       attacks, endgame reaches repository) and prints them.
#
# The maze data (room exits, dark flags) lives in this driver
# because it's *world geometry* the FSM doesn't need to model.
# Per-room descriptions live in the FSM's _verb_look — the FSM
# already overlays NPC presence dynamically, so concentrating
# room text there keeps the truth in one place.
# ============================================================
extends Control

const CcaFSM = preload("res://scripts/cca.gd")

# Item IDs — must match Adventure's domain constants.
const BIRD_ID := 100
const CHAIN_ID := 101
const GOLD_ID := 110
const SILVER_ID := 111
const DIAMONDS_ID := 112
const JEWELRY_ID := 113
const PEARL_ID := 114
const VASE_ID := 115
const EGGS_ID := 116
const TRIDENT_ID := 117
const EMERALD_ID := 118
const SPICES_ID := 119
const CHEST_ID := 120
const PYRAMID_ID := 121
const RUG_ID := 122
const COINS_ID := 123
const STATUETTE_ID := 124

# ------------------------------------------------------------
# Maze topology
# ------------------------------------------------------------
# Each room maps direction → destination room. Compass
# directions, plus contextual ones (in/out, up/down).
#
# Mapping intent:
#   0  End of road / outside building   (lit, surface)
#   1  Inside well house                 (lit; DEPOSIT_ROOM)
#   2  Debris room                       (dark; gold)
#   3  Cave entrance corridor            (dark; transit)
#   4  Y2 marker                         (dark; silver; magic-word hub)
#   5  Bird chamber                      (dark; bird)
#   6  Plover Room                       (dark; pearl; magic-word access only)
#   7  End of long passage               (dark; snake blocking east)
#   8  Stone dragon cavern               (dark; dragon, diamonds, rug)
#   9  Bedquilt / bear chamber           (dark; bear, chain)
#   10 Troll bridge                      (dark; troll blocking east)
#   11 Beyond the bridge                 (dark; jewelry)
#   12 Cobble crawl                      (dark; transit to deep cave)
#   13 Oriental Room                     (dark; vase)
#   14 Giant Room                        (dark; eggs)
#   15 Sapphire Hallway                  (dark; trident)
#   16 Vast Hall                         (dark; emerald)
#   17 Alcove                            (dark; spices)
#   18 Chest Room                        (dark; chest)
#   19 Pyramid Chamber                   (dark; pyramid)
#   20 Coin Niche                        (dark; coins)
#   21 Sloping Passage                   (dark; statuette)
#   22 Repository                        (endgame destination)
#
# Magic-word teleports (handled by the FSM's MagicWordTeleport
# aspect, not these tables):
#   XYZZY  pairs 0 ↔ 2
#   PLUGH  pairs 0 ↔ 4
#   PLOVER pairs 4 ↔ 6
# ------------------------------------------------------------
var room_exits: Dictionary = {
    0:  {"north": 1, "in": 1, "enter": 1, "down": 3, "east": 3},
    1:  {"south": 0, "out": 0, "down": 3},
    2:  {"out": 0, "up": 0},
    3:  {"up": 0, "down": 4, "north": 4},
    4:  {"up": 3, "south": 3, "down": 5, "east": 7, "west": 9},
    5:  {"up": 4, "out": 4},
    6:  {},                                  # Plover Room — only magic exits
    7:  {"west": 4, "east": 8},               # snake-east gated below
    8:  {"west": 7, "north": 9},
    9:  {"south": 8, "east": 10, "west": 4},
    10: {"west": 9, "east": 11},              # troll-east gated below
    11: {"west": 10, "east": 12},
    # Deep cave loop — accessible after crossing troll bridge.
    # Linear chain east-west with each room hosting a treasure.
    12: {"west": 11, "east": 13},
    13: {"west": 12, "east": 14},
    14: {"west": 13, "east": 15},
    15: {"west": 14, "east": 16},
    16: {"west": 15, "east": 17},
    17: {"west": 16, "east": 18},
    18: {"west": 17, "east": 19},
    19: {"west": 18, "east": 20},
    20: {"west": 19, "east": 21},
    21: {"west": 20},
    22: {},                                  # Repository — terminal endgame room
}

# Movements that require a clear NPC to traverse. Each entry:
# (from_room, direction) → (npc query name, blocked-message).
# Adventure exposes snake/troll blocking via accessor; we
# check them before letting the player through.
var gated_exits: Dictionary = {
    "7:east":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "10:east": {"check": "troll",  "msg": "The troll bars your way until you pay tribute."},
}

# Verb synonym table. Maps user input to a canonical verb
# the FSM (or a UI-only handler) understands.
var verb_synonyms: Dictionary = {
    "n": "north", "s": "south", "e": "east", "w": "west",
    "u": "up", "d": "down",
    "i": "inventory", "inv": "inventory",
    "l": "look",
    "g": "look",                          # CCA tradition: G = look
    "x": "examine",                       # IF tradition: X = examine
    "get": "take", "grab": "take", "pick": "take",
    "extinguish": "extinguish", "off": "extinguish",
    "light": "light", "on": "light",
    "kill": "attack", "fight": "attack",
    "hurl": "throw",
    "y": "yes",                            # n is north; "no" must be typed
    "quit": "quit", "exit": "quit",
    "save": "save", "restore": "load", "load": "load",
    "score": "score",
    "help": "help", "?": "help",
    "hint": "hint",
}

# Direction keywords that map to room navigation. These get
# resolved against room_exits per the player's current room.
const DIRECTIONS := ["north", "south", "east", "west", "up", "down",
                     "in", "out", "enter"]

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var fsm
var output: RichTextLabel
var input: LineEdit
var _last_room: int = -1
var _save_path: String = "user://cca_save.dat"

# Pirate-stalking starts only after the player has carried
# treasures past a threshold. We track that the pirate has
# stolen this run so we don't double-steal.
var _pirate_already_stole: bool = false

# ============================================================
func _ready() -> void:
    fsm = CcaFSM.new()
    fsm.setup_default_aspects()
    fsm.wake_dwarves()
    _build_ui()
    _print_welcome()
    _print_room()

func _build_ui() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)

    var bg := ColorRect.new()
    bg.color = Color(0.05, 0.06, 0.09)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    var vbox := VBoxContainer.new()
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
    vbox.add_theme_constant_override("separation", 4)
    add_child(vbox)

    output = RichTextLabel.new()
    output.size_flags_vertical = Control.SIZE_EXPAND_FILL
    output.bbcode_enabled = true
    output.scroll_following = true
    output.add_theme_font_size_override("normal_font_size", 16)
    output.add_theme_color_override("default_color", Color(0.85, 0.92, 0.96))
    vbox.add_child(output)

    var prompt_row := HBoxContainer.new()
    prompt_row.size_flags_vertical = Control.SIZE_SHRINK_END
    vbox.add_child(prompt_row)

    var prompt := Label.new()
    prompt.text = "> "
    prompt.add_theme_font_size_override("font_size", 16)
    prompt.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
    prompt_row.add_child(prompt)

    input = LineEdit.new()
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.add_theme_font_size_override("font_size", 16)
    input.placeholder_text = "type a command (LOOK, NORTH, TAKE GOLD, HELP, ...)"
    input.text_submitted.connect(_on_text_submitted)
    prompt_row.add_child(input)

    input.grab_focus()

# ============================================================
func _on_text_submitted(text: String) -> void:
    var trimmed: String = text.strip_edges().to_lower()
    input.clear()
    if trimmed.is_empty():
        return
    _print_player_input(text)
    _process_input(trimmed)

func _process_input(text: String) -> void:
    var parsed := _parse(text)
    var verb: String = parsed[0]
    var noun: String = parsed[1]

    if verb == "":
        _println("I don't understand.")
        return

    # UI-only verbs (driver-handled, never reach the FSM).
    match verb:
        "help":
            _print_help()
            return
        "quit":
            _println("Goodbye.")
            await get_tree().create_timer(0.5).timeout
            get_tree().quit()
            return
        "score":
            _println("[b]Score: %d[/b] — treasures %d (%d/15 deposited), visits %d, hints %d, endgame %d" % [
                fsm.score(),
                fsm.treasure_score(), fsm.treasures_deposited(),
                fsm.visit_score(),
                fsm.hint_penalty(),
                fsm.endgame_score()])
            return
        "inventory":
            _println(_format_inventory())
            return
        "save":
            _save_game()
            return
        "load":
            _load_game()
            return
        "hint":
            var hint_name: String = noun if noun != "" else "bird"
            _println(fsm.request_hint(hint_name))
            return

    # Direction verbs become MOVE with a resolved room ID.
    if verb in DIRECTIONS:
        _handle_movement(verb)
        return

    # All other verbs: pass to the FSM. Adventure's bus
    # dispatches through the aspects (DarknessGate may
    # consume look/examine in dark rooms, MagicWordTeleport
    # transforms xyzzy/plugh/plover into MOVE, etc.) and
    # returns the response string.
    var response: String = fsm.do_command(verb, noun)
    _println(response)

    # Per-turn upkeep: lamp battery, endgame timer, hint
    # observation, pirate activation. Frame side handles all
    # of these in tick().
    fsm.tick()

    # Driver-side per-turn checks: pirate-steals, lamp
    # warnings, endgame phase changes. We surface text the
    # FSM can't know how to render.
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _maybe_print_room_after_move()

# ============================================================
# Parsing
# ============================================================
func _parse(text: String) -> Array:
    # Split on whitespace; first token = verb, rest = noun.
    # Apply synonym table to the verb only.
    var parts: PackedStringArray = text.split(" ", false)
    if parts.is_empty():
        return ["", ""]
    var raw_verb: String = parts[0]
    var canonical: String = verb_synonyms.get(raw_verb, raw_verb)
    var noun: String = ""
    if parts.size() > 1:
        # Allow synonyms on the noun too (e.g. "the bird" → "bird").
        # Strip articles and join the rest.
        var rest: PackedStringArray = parts.slice(1)
        var filtered: Array = []
        for w in rest:
            if w != "the" and w != "a" and w != "an":
                filtered.append(w)
        noun = " ".join(filtered)
    return [canonical, noun]

# ============================================================
# Movement
# ============================================================
func _handle_movement(direction: String) -> void:
    var current: int = fsm.player_room()
    var exits: Dictionary = room_exits.get(current, {})
    if not direction in exits:
        _println("You can't go %s from here." % direction)
        return

    var dest: int = exits[direction]

    # Gated exits — snake at room 7 east, troll at room 10 east.
    var gate_key: String = "%d:%s" % [current, direction]
    if gate_key in gated_exits:
        var gate: Dictionary = gated_exits[gate_key]
        if gate.check == "snake" and fsm.snake.is_blocking():
            _println(gate.msg)
            return
        if gate.check == "troll" and fsm.troll.is_blocking_bridge():
            _println(gate.msg)
            return

    # Plover Room special: when leaving room 6 normally without
    # PLOVER, you can't. Stuck unless you use the magic word.
    # That's handled by the room having empty exits — the player
    # just gets the "you can't go that way" branch above.

    # Tell the FSM to move; the FSM's _verb_move parses the noun
    # to_int and moves the player. The bus walks first (darkness
    # might consume "move" if dark — actually no, darkness only
    # gates look/examine; CCA-canon: you CAN move in the dark,
    # but you might fall in a pit).
    var response: String = fsm.do_command("move", str(dest))
    # We use our own room descriptions (via FSM's look) rather
    # than the FSM's move-response — it's more atmospheric.
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _print_room()

# ============================================================
# Per-turn consequences
# ============================================================
func _check_pirate_steal() -> void:
    if _pirate_already_stole:
        return
    if fsm.pirate_state() != "stalking":
        return
    if fsm.pirate_try_steal():
        _pirate_already_stole = true
        _println("[color=#cc8855][i]A bearded pirate appears out of the gloom, snatches one of your treasures, and vanishes with a snicker![/i][/color]")
        # Drop the first treasure we find in inventory
        for tid in [GOLD_ID, SILVER_ID, DIAMONDS_ID, JEWELRY_ID, PEARL_ID,
                    VASE_ID, EGGS_ID, TRIDENT_ID, EMERALD_ID, SPICES_ID,
                    CHEST_ID, PYRAMID_ID, RUG_ID, COINS_ID, STATUETTE_ID]:
            if fsm.player.carrying(tid):
                fsm.player.drop(tid)
                # Real CCA puts stolen treasures in the chest
                # room; this prototype just removes them from
                # carry. The Treasure FSM still thinks it's in
                # the player's last-known room — TODO: fix.
                break

func _check_lamp_warnings() -> void:
    var msg: String = fsm.get_lamp_message()
    if msg != "":
        _println("[color=#ddaa66]%s[/color]" % msg)

var _last_endgame_state: String = "active"
func _check_endgame_phase_change() -> void:
    var s: String = fsm.endgame_state()
    if s == _last_endgame_state:
        return
    _last_endgame_state = s
    if s == "closing":
        _println("[color=#cc7777][b]A sepulchral voice intones: 'The cave is closing now. Your final chance to deposit treasures has begun.'[/b][/color]")
    elif s == "in_repository":
        _println("[color=#cc7777][b]The cave closes shut. You are teleported to the repository — all your treasures lie at your feet, plus a single stick of dynamite. Try DETONATE.[/b][/color]")
    elif s == "won":
        _println("[color=#88dd88][b]You have escaped! Final score: %d. Thank you for playing.[/b][/color]" % fsm.total_score())

func _maybe_print_room_after_move() -> void:
    var current: int = fsm.player_room()
    if current != _last_room:
        _last_room = current
        _print_room()

# ============================================================
# Room display
# ============================================================
func _print_room() -> void:
    _last_room = fsm.player_room()
    var desc: String = fsm.do_command("look", "")
    _println("[color=#aabbcc][b]%s[/b][/color]" % desc)

# ============================================================
# Inventory
# ============================================================
func _format_inventory() -> String:
    var items: Array = []
    if fsm.player.carrying(BIRD_ID):      items.append("a small bird")
    if fsm.player.carrying(CHAIN_ID):     items.append("the bear's chain")
    if fsm.player.carrying(GOLD_ID):      items.append("a gold nugget")
    if fsm.player.carrying(SILVER_ID):    items.append("silver bars")
    if fsm.player.carrying(DIAMONDS_ID):  items.append("diamonds")
    if fsm.player.carrying(JEWELRY_ID):   items.append("fine jewelry")
    if fsm.player.carrying(PEARL_ID):     items.append("a pearl")
    if fsm.player.carrying(VASE_ID):      items.append("a Ming vase")
    if fsm.player.carrying(EGGS_ID):      items.append("a nest of golden eggs")
    if fsm.player.carrying(TRIDENT_ID):   items.append("a jewel-encrusted trident")
    if fsm.player.carrying(EMERALD_ID):   items.append("an enormous emerald")
    if fsm.player.carrying(SPICES_ID):    items.append("rare spices")
    if fsm.player.carrying(CHEST_ID):     items.append("a treasure chest")
    if fsm.player.carrying(PYRAMID_ID):   items.append("a golden pyramid")
    if fsm.player.carrying(RUG_ID):       items.append("a Persian rug")
    if fsm.player.carrying(COINS_ID):     items.append("rare coins")
    if fsm.player.carrying(STATUETTE_ID): items.append("a jade statuette")
    if items.is_empty():
        return "You aren't carrying anything."
    return "You are carrying: " + ", ".join(items) + "."

# ============================================================
# Save / load
# ============================================================
func _save_game() -> void:
    var bytes: PackedByteArray = fsm.save_state()
    var f := FileAccess.open(_save_path, FileAccess.WRITE)
    if f == null:
        _println("Save failed.")
        return
    f.store_buffer(bytes)
    f.close()
    _println("Saved.")

func _load_game() -> void:
    if not FileAccess.file_exists(_save_path):
        _println("No saved game found.")
        return
    var f := FileAccess.open(_save_path, FileAccess.READ)
    if f == null:
        _println("Load failed.")
        return
    var bytes := f.get_buffer(f.get_length())
    f.close()
    fsm.restore_state(bytes)
    _last_endgame_state = fsm.endgame_state()
    _last_room = -1
    _println("Restored.")
    _print_room()

# ============================================================
# Output helpers
# ============================================================
func _println(text: String) -> void:
    output.append_text(text)
    output.append_text("\n\n")

func _print_player_input(text: String) -> void:
    output.append_text("[color=#888888]> %s[/color]\n" % text)

func _print_welcome() -> void:
    _println("[b]COLOSSAL CAVE ADVENTURE[/b] (Frame port)")
    _println("Built on the Frame state machine DSL. Type [b]HELP[/b] for a list of commands.")

func _print_help() -> void:
    _println("""
[b]Movement:[/b] NORTH/SOUTH/EAST/WEST, UP/DOWN, IN/OUT, or N/S/E/W/U/D.
[b]Looking:[/b] LOOK (L), EXAMINE <thing> (X), READ <thing>.
[b]Items:[/b]   TAKE <thing>, DROP <thing>, INVENTORY (I).
[b]Combat:[/b]  ATTACK <foe>, THROW AXE.
[b]Special:[/b] LIGHT (lamp), EXTINGUISH, FEED BEAR, RELEASE BIRD.
[b]Magic:[/b]   XYZZY, PLUGH, PLOVER (in the right places).
[b]Meta:[/b]    SAVE, LOAD, SCORE, HINT [name], QUIT.
""")
