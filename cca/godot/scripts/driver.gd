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
const Topology = preload("res://scripts/topology.gd")

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
# Non-treasure carriables (mirror Adventure.ROD_ID / KEYS_ID /
# BOTTLE_ID + the Phase 6 mechanism items in cca/frame/cca.fgd).
const ROD_ID := 130
const KEYS_ID := 131
const BOTTLE_ID := 132
const CAGE_ID := 133
const FOOD_ID := 134
const PILLOW_ID := 135
const AXE_ID := 136
const CLAM_ID := 137
const OYSTER_ID := 138
const BATTERIES_ID := 139
const MAGAZINE_ID := 140
const MARK_ROD_ID := 141

# ------------------------------------------------------------
# Maze topology — see topology.gd for the room map and design
# rationale. Aliased here so the rest of the driver code reads
# unchanged.
# ------------------------------------------------------------
var room_exits: Dictionary = Topology.ROOMS
var gated_exits: Dictionary = Topology.GATES


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
    # Canon SUSPEND / PAUSE map to SAVE per msg #142 INFO text.
    "suspend": "save", "pause": "save",
    "score": "score",
    "help": "help", "?": "help",
    "info": "info",
    "hint": "hint",
}

# Direction keywords that map to room navigation. These get
# resolved against room_exits per the player's current room.
const DIRECTIONS := ["north", "south", "east", "west", "up", "down",
                     "in", "out", "enter"]

# Motion-like verbs that aren't compass directions but still
# represent the player attempting to traverse — needed for canon's
# dark-room pit-fall hazard, which canonically triggers on any
# motion attempt while the player is in a dark cave room without
# a lit lamp.
const MOTION_VERBS := ["north", "south", "east", "west", "up", "down",
                       "in", "out", "enter", "back", "forward",
                       "jump", "climb", "pit", "steps", "dome",
                       "passage", "slit", "stream", "cross", "over",
                       "across", "left", "right", "ne", "nw", "se",
                       "sw", "stairs", "crawl", "depression",
                       "building", "house", "road", "hill", "valley",
                       "forest", "gully", "outdoors", "surface"]

# Canon dark-pit-fall probability per move attempt (matches the
# Crowther/Woods 35% chance — see Quux ODWY0350/advent.c, the
# per-turn `pct(35)` check after the "pitch dark" warning).
const DARK_PIT_PCT := 35

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var fsm
var output: RichTextLabel
var input: LineEdit
var _last_room: int = -1
# Tracks whether the player has already been warned about the
# darkness in their current room. Canon CCA gives one free turn —
# the warning fires, and only on the *next* move attempt does the
# pit-fall roll happen.
var _dark_warned_room: int = -1
var _save_path: String = "user://cca_save.dat"

# Pirate-stalking starts only after the player has carried
# treasures past a threshold. We track that the pirate has
# stolen this run so we don't double-steal.
var _pirate_already_stole: bool = false

# Resurrection-prompt state. When the player dies (bear
# mauling, dwarf axe), the FSM transitions Player → $Dead.
# The driver detects this on the next post-command check,
# prints the resurrection prompt, and pauses normal verb
# processing until the player answers yes/no.
var _awaiting_revive: bool = false
# Canon QUIT confirmation latch (msg #22 "DO YOU REALLY WANT TO
# QUIT NOW?"). Set when QUIT is typed; the next yes/no answer
# either exits the game or cancels.
var _quit_pending: bool = false

# 5-character-truncated verb-synonym lookup. Derived from
# verb_synonyms at _ready() so canon's "first five letters" parser
# rule (Don Woods 1977 startup banner) lands correctly on
# multi-character verbs like INVENTORY → "inven", EXTINGUISH →
# "extin", etc.
var _verb_synonyms_5: Dictionary = {}

# ============================================================
func _ready() -> void:
    fsm = CcaFSM.new()
    fsm.setup_default_aspects()
    fsm.wake_dwarves()
    _build_verb_synonyms_5()
    _build_ui()
    _print_welcome()
    _print_room()

func _build_verb_synonyms_5() -> void:
    # Pre-truncate verb_synonyms keys to 5 chars so the canon
    # "first five letters" parser rule lands correctly on long
    # verbs (INVENTORY, EXTINGUISH, RESTORE, SUSPEND).
    for key in verb_synonyms.keys():
        _verb_synonyms_5[_truncate5(key)] = verb_synonyms[key]
    # Identity mappings for canonical FSM verbs > 5 chars whose
    # truncated form would otherwise miss the dispatch table.
    # Canonical form preserved so the FSM checks like
    # `if verb == "extinguish"` keep matching.
    for canon_verb in ["extinguish", "release", "attack", "examine",
                       "unlock", "insert", "plover", "inventory"]:
        _verb_synonyms_5[_truncate5(canon_verb)] = canon_verb

func _build_ui() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    # The root Control should never claim focus. Tab cycles
    # focus through focusable controls; with the root non-
    # focusable and the output panel non-focusable, Tab has
    # nowhere to go but the LineEdit.
    focus_mode = Control.FOCUS_NONE

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
    # Don't let the log panel steal keyboard focus when clicked.
    # The LineEdit owns input; the log is read-only display.
    output.focus_mode = Control.FOCUS_NONE
    output.selection_enabled = true            # mouse-drag still selects text
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
    # Godot 4.4+ added `keep_editing_on_text_submit`, defaulting
    # to false — every Enter press kicks the LineEdit out of
    # editing mode even though it stays focused. Without this
    # the player has to press Enter (or click) again before
    # each new command.
    # https://github.com/godotengine/godot/issues/101434
    input.keep_editing_on_text_submit = true
    prompt_row.add_child(input)

    input.grab_focus()

# ============================================================
func _on_text_submitted(text: String) -> void:
    var trimmed: String = text.strip_edges().to_lower()
    input.clear()
    if trimmed.is_empty():
        # Defer so the regrab fires after the current input frame
        # finishes — calling grab_focus() synchronously inside the
        # text_submitted signal doesn't stick on every Godot version.
        input.call_deferred("grab_focus")
        return
    _print_player_input(text)
    _process_input(trimmed)
    input.call_deferred("grab_focus")

func _process_input(text: String) -> void:
    var parsed := _parse(text)
    var verb: String = parsed[0]
    var noun: String = parsed[1]

    if verb == "":
        _println("I don't understand.")
        return

    # Resurrection prompt has top priority — the only input we
    # accept while the player is dead is yes/no. (We don't go
    # through the normal verb dispatcher because the dragon
    # also uses yes/no and we don't want a state collision.)
    if _quit_pending:
        if verb == "yes":
            _quit_pending = false
            _println("Goodbye.")
            await get_tree().create_timer(0.5).timeout
            get_tree().quit()
            return
        if verb == "no":
            _quit_pending = false
            _println("OK.")
            return
        _quit_pending = false
        # Fall through to normal processing — canon: any non-yes
        # answer cancels the quit prompt.

    if _awaiting_revive:
        if verb == "yes":
            fsm.player.revive()
            _awaiting_revive = false
            _println("[color=#88dd88]You stagger to your feet, alive again. The cave entrance is before you.[/color]")
            _last_room = -1   # force room re-print
            _print_room()
            return
        if verb == "no":
            _awaiting_revive = false
            _println("[color=#cc4444]Then this is the end of you. Goodbye.[/color]")
            await get_tree().create_timer(2.0).timeout
            get_tree().quit()
            return
        _println("Please answer yes or no.")
        return

    # UI-only verbs (driver-handled, never reach the FSM).
    match verb:
        "help":
            _print_help()
            return
        "info":
            _print_info()
            return
        "quit":
            # Canon msg #22 verbatim — confirm before exit.
            _quit_pending = true
            _println("Do you really want to quit now?")
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

    # Canon "always-blocked" bumper gates — JUMP at the fissure
    # / troll bridge / volcano, SLIT at the streambed slits, the
    # dragon's east passage at canon 119/121. The verb itself
    # isn't a direction, but canon emits a specific bumper text;
    # gate the (room, verb) pair before the direction handler so
    # the player gets canon prose rather than the FSM fallback.
    var bumper_key: String = "%d:%s" % [fsm.player_room(), verb]
    if bumper_key in gated_exits and gated_exits[bumper_key].check == "always":
        _println(gated_exits[bumper_key].msg)
        return

    # Canon dark-room pit-fall hazard. Any motion attempt from a
    # dark cave room (lamp out) risks death. The first attempt in
    # the room emits the canon warning; subsequent attempts roll
    # the 35% pit-fall. Lighting the lamp clears the hazard. Lit
    # rooms (1..8, 100) and lit-lamp turns short-circuit harmlessly.
    if verb in MOTION_VERBS and _check_dark_pit_hazard():
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
    # warnings, endgame phase changes, dwarf axe hits, player
    # death. We surface text the FSM can't know how to render.
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_dwarf_axe()
    _check_player_death()
    _maybe_print_room_after_move()

# ============================================================
# Parsing
# ============================================================
func _parse(text: String) -> Array:
    # Canon: the parser examines only the first 5 characters of
    # each verb (Don Woods 1977 startup banner: "I LOOK AT ONLY
    # THE FIRST FIVE LETTERS OF EACH WORD, SO YOU'LL HAVE TO ENTER
    # 'NORTHEAST' AS 'NE' TO DISTINGUISH IT FROM 'NORTH'."). We
    # mirror that for the verb token by truncating to 5 chars and
    # looking up against a pre-truncated synonym table, so the
    # canonical form dispatched downstream is still the full word.
    # Noun-side 5-char truncation is a separate sub-pass (the FSM
    # checks against full-word noun strings throughout, so adding
    # noun truncation safely requires a dedicated noun-canonical
    # expansion map — wired in 7v alongside object-name verbs).
    var parts: PackedStringArray = text.split(" ", false)
    if parts.is_empty():
        return ["", ""]
    var raw_verb: String = _truncate5(parts[0])
    var canonical: String = _verb_synonyms_5.get(raw_verb, raw_verb)
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

func _truncate5(s: String) -> String:
    if s.length() > 5:
        return s.substr(0, 5)
    return s

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

    # Gated exits — snake at room 7 east, troll at room 10 east,
    # crystal-bridge at the fissure (room 24 east).
    var gate_key: String = "%d:%s" % [current, direction]
    if gate_key in gated_exits:
        var gate: Dictionary = gated_exits[gate_key]
        if gate.check == "snake" and fsm.snake.is_blocking():
            _println(gate.msg)
            return
        if gate.check == "troll" and fsm.troll.is_blocking_bridge():
            _println(gate.msg)
            return
        if gate.check == "bridge" and not fsm.bridge_built():
            _println(gate.msg)
            return
        if gate.check == "grate" and fsm.grate_locked():
            _println(gate.msg)
            return
        if gate.check == "plant_tall" and not fsm.plant_is_tall():
            _println(gate.msg)
            return
        if gate.check == "plant_huge" and not fsm.plant_is_huge():
            _println(gate.msg)
            return
        if gate.check == "plover_squeeze" and fsm.plover_squeeze_blocked():
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
# Dark-room pit-fall hazard (canon CCA)
# ============================================================
# Returns true if the hazard fired (warning emitted *or* player
# died), in which case the caller should short-circuit the rest
# of command handling. The "warn first, kill on the next attempt"
# pattern matches Crowther/Woods canon: the player gets exactly
# one free turn after entering a dark room before the 35% pit-
# fall roll starts.
#
# State machine:
#   lamp lit / room sunlit → reset _dark_warned_room, fall through
#   dark + first turn here → emit canon warning, set marker, return true
#   dark + same room as warning → roll pct(35); on hit, die
func _check_dark_pit_hazard() -> bool:
    var current: int = fsm.player_room()
    if not fsm._room_is_dark(current):
        # Either it's a sunlit room or the lamp is on — no hazard.
        # _room_is_dark already accounts for both. Reset the marker
        # so the warning fires fresh next time the player enters dark.
        if _dark_warned_room != -1:
            _dark_warned_room = -1
        return false
    if current != _dark_warned_room:
        # First attempted move while in this dark room. Canon msg #16
        # verbatim. Returning true blocks the move so the warning
        # stands alone — the player can retreat by lighting the lamp
        # or moving back the way they came on the *next* turn.
        _println("It is now pitch dark. If you proceed you will likely fall into a pit.")
        _dark_warned_room = current
        return true
    # Already warned in this room — pit-fall roll.
    if (randi() % 100) < DARK_PIT_PCT:
        _println("You fell into a pit and broke every bone in your body!")
        fsm.player.die()
        return true
    return false

# ============================================================
# Per-turn consequences
# ============================================================
func _check_pirate_steal() -> void:
    if _pirate_already_stole:
        return
    if fsm.pirate_state() != "stalking":
        return
    # The FSM does the cross-cutting work: rolls the steal, picks
    # a treasure deterministically, and reappears it in the chest
    # room (room 18). Driver just renders.
    var msg: String = fsm.pirate_attempt_steal()
    if msg != "":
        _pirate_already_stole = true
        _println("[color=#cc8855][i]%s[/color][/i]" % msg)

func _check_lamp_warnings() -> void:
    var msg: String = fsm.get_lamp_message()
    if msg != "":
        _println("[color=#ddaa66]%s[/color]" % msg)

func _check_dwarf_axe() -> void:
    if fsm.dwarf_threw_axe():
        _println("[color=#cc7777][i]A dwarf throws an axe at you — and connects! The axe finds your back.[/i][/color]")

func _check_player_death() -> void:
    if _awaiting_revive:
        return
    var s: String = fsm.player_state()
    if s == "dead":
        _awaiting_revive = true
        var deaths: int = fsm.player.get_deaths()
        var prompt: String = "[color=#cc4444][b]You have died. (Death %d of %d.)[/b][/color]\n[i]Do you want to be resurrected?[/i] (YES/NO)" % [
            deaths, 4]
        _println(prompt)
    elif s == "permadead":
        _println("[color=#cc4444][b]You have used up your three resurrections. This is the end.[/b][/color]")
        await get_tree().create_timer(2.0).timeout
        get_tree().quit()

var _last_endgame_state: String = "active"
# Track which closing-warning thresholds have already fired so
# we emit each one exactly once. Canon CCA escalates the warning
# text three times during the closing phase rather than printing
# a single message at the start.
var _closing_warned_25: bool = false
var _closing_warned_15: bool = false
var _closing_warned_5:  bool = false

func _check_endgame_phase_change() -> void:
    var s: String = fsm.endgame_state()
    if s != _last_endgame_state:
        _last_endgame_state = s
        if s == "closing":
            _println("[color=#cc7777][b]A sepulchral voice intones: 'The cave is closing now. Your final chance to deposit treasures has begun.'[/b][/color]")
        elif s == "in_repository":
            _println("[color=#cc7777][b]The cave closes shut. You are teleported to the repository — all your treasures lie at your feet, plus a single stick of dynamite. Try DETONATE.[/b][/color]")
        elif s == "won":
            _println("[color=#88dd88][b]You have escaped! Final score: %d. Thank you for playing.[/b][/color]" % fsm.total_score())

    # Closing-phase crescendo. While in $Closing, the timer
    # decrements each turn from CLOSING_DURATION (30) down to 0.
    # We surface escalating prose at three thresholds — once each
    # — so the player feels the cave winding shut around them
    # rather than getting one alert and silence.
    if s == "closing":
        var t: float = fsm.endgame_timer()
        if t <= 25.0 and not _closing_warned_25:
            _closing_warned_25 = true
            _println("[color=#cc7777][i]A second sepulchral voice booms: 'Cave closing soon. All adventurers exit immediately through main office.'[/i][/color]")
        if t <= 15.0 and not _closing_warned_15:
            _closing_warned_15 = true
            _println("[color=#cc7777][i]The walls of the cave seem to be trembling. A brilliant white light suddenly fills the cave.[/i][/color]")
        if t <= 5.0 and not _closing_warned_5:
            _closing_warned_5 = true
            _println("[color=#cc7777][b]The voice intones once more: 'The cave is closing — exit through the main office NOW.' The ground shudders beneath your feet.[/b][/color]")

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
    # Canon-aligned inventory, mirroring the arcade driver's
    # Don Woods 1977 short-name strings. One item per line under
    # the canon msg #99 "You are currently holding the following:"
    # header. Bird + cage compound to canon msg #8 "Little bird
    # in cage" when both are held.
    var items: Array = []
    var has_bird: bool = fsm.player.carrying(BIRD_ID)
    var has_cage: bool = fsm.player.carrying(CAGE_ID)
    if has_bird and has_cage:
        items.append("  Little bird in cage")
    elif has_bird:
        items.append("  Little bird")
    elif has_cage:
        items.append("  Wicker cage")

    if fsm.player.carrying(ROD_ID):
        items.append("  Black rod with a rusty star on the end")
    if fsm.player.carrying(MARK_ROD_ID):
        items.append("  Black rod with a rusty mark on the end")
    if fsm.player.carrying(KEYS_ID):     items.append("  Set of keys")
    if fsm.player.carrying(BOTTLE_ID):   items.append("  Small bottle")
    if fsm.player.carrying(FOOD_ID):     items.append("  Tasty food")
    if fsm.player.carrying(PILLOW_ID):   items.append("  Velvet pillow")
    if fsm.player.carrying(AXE_ID):      items.append("  Dwarf's axe")
    if fsm.player.carrying(CLAM_ID):     items.append("  Giant clam")
    if fsm.player.carrying(OYSTER_ID):   items.append("  Giant oyster")
    if fsm.player.carrying(MAGAZINE_ID): items.append("  \"Spelunker Today\" magazine")
    if fsm.player.carrying(BATTERIES_ID): items.append("  Fresh batteries")

    if fsm.player.carrying(GOLD_ID):     items.append("  Large gold nugget")
    if fsm.player.carrying(SILVER_ID):   items.append("  Bars of silver")
    if fsm.player.carrying(DIAMONDS_ID): items.append("  Several diamonds")
    if fsm.player.carrying(JEWELRY_ID):  items.append("  Precious jewelry")
    if fsm.player.carrying(PEARL_ID):    items.append("  Glistening pearl")
    if fsm.player.carrying(VASE_ID):
        if fsm.vase.is_broken():
            items.append("  Worthless shards of pottery")
        else:
            items.append("  Ming vase")
    if fsm.player.carrying(EGGS_ID):     items.append("  Nest of golden eggs")
    if fsm.player.carrying(TRIDENT_ID):  items.append("  Jeweled trident")
    if fsm.player.carrying(EMERALD_ID):  items.append("  Egg-sized emerald")
    if fsm.player.carrying(SPICES_ID):   items.append("  Rare spices")
    if fsm.player.carrying(CHEST_ID):    items.append("  Treasure chest")
    if fsm.player.carrying(PYRAMID_ID):  items.append("  Platinum pyramid")
    if fsm.player.carrying(RUG_ID):      items.append("  Persian rug")
    if fsm.player.carrying(COINS_ID):    items.append("  Rare coins")
    if fsm.player.carrying(CHAIN_ID):    items.append("  Golden chain")

    if items.is_empty():
        return "You're not carrying anything."
    return "You are currently holding the following:\n" + "\n".join(items)

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
    # Canon msg #51 verbatim — Don Woods 1977 HELP output.
    _println("I know of places, actions, and things. Most of my vocabulary describes places and is used to move you there. To move, try words like FOREST, BUILDING, DOWNSTREAM, ENTER, EAST, WEST, NORTH, SOUTH, UP, or DOWN. I know about a few special objects, like a black rod hidden in the cave. These objects can be manipulated using some of the action words that I know. Usually you will need to give both the object and action words (in either order), but sometimes I can infer the object from the verb alone. Some objects also imply verbs; in particular, \"INVENTORY\" implies \"TAKE INVENTORY\", which causes me to give you a list of what you're carrying. The objects have side effects; for instance, the rod scares the bird. Usually people having trouble moving just need to try a few more words. Usually people trying unsuccessfully to manipulate an object are attempting something beyond their (or my!) capabilities and should try a completely different tack. To speed the game you can sometimes move long distances with a single word. For example, \"BUILDING\" usually gets you to the building from anywhere above ground except when lost in the forest. Also, note that cave passages turn a lot, and that leaving a room to the north does not guarantee entering the next from the south. Good luck!")

func _print_info() -> void:
    # Canon msg #142 verbatim — Don Woods 1977 INFO output.
    _println("If you want to end your adventure early, say \"QUIT\". To suspend your adventure such that you can continue later, say \"SUSPEND\" (or \"PAUSE\" or \"SAVE\"). To see what hours the cave is normally open, say \"HOURS\". To see how well you're doing, say \"SCORE\". To get full credit for a treasure, you must have left it safely in the building, though you get partial credit just for locating it. You lose points for getting killed, or for quitting, though the former costs you more. There are also points based on how much (if any) of the cave you've managed to explore; in particular, there is a large bonus just for getting in (to distinguish the beginners from the rest of the pack), and there are other ways to determine whether you've been through some of the more harrowing sections. If you think you've found all the treasures, just keep exploring for a while. If nothing interesting happens, you haven't found them all yet. If something interesting *does* happen, it means you're getting a bonus and have an opportunity to garner many more points in the master's section. I may occasionally offer hints if you seem to be having trouble. If I do, I'll warn you in advance how much it will affect your score to accept the hints. Finally, to save paper, you may specify \"BRIEF\", which tells me never to repeat the full description of a place unless you explicitly ask me to.")

# When the application window regains focus (alt-tab back, click
# on a different app and return, etc.), Godot doesn't restore
# which Control had keyboard focus before — so the LineEdit
# stops accepting keystrokes until the player clicks it again.
# We listen for the focus-in notification and re-grab.
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN:
        if input != null:
            input.grab_focus()
