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
# Phase 6 mechanism items (cage / food / pillow / clam / oyster /
# axe / mark-rod / batteries / magazine). These IDs match the
# values declared on Adventure's domain (cca.fgd lines 4540-4590).
# Keeping them in lock-step lets Player.carrying(<id>) lookups
# work from the driver side.
const CAGE_ID := 133
const FOOD_ID := 134
const PILLOW_ID := 135
const AXE_ID := 136
const CLAM_ID := 137
const OYSTER_ID := 138
const BATTERIES_ID := 139
const MAGAZINE_ID := 140
const MARK_ROD_ID := 141
const LAMP_ID := 142
# Non-treasure carriables (mirror Adventure.ROD_ID / KEYS_ID /
# BOTTLE_ID in cca/frame/cca.fgd).
const ROD_ID := 130
const KEYS_ID := 131
const BOTTLE_ID := 132

# ------------------------------------------------------------
# Maze topology
# ------------------------------------------------------------
# Canonical Crowther+Woods 1977 room numbering, including the
# probability/conditional gate-bumper tables. The data lives in
# scripts/topology.gd (kept in sync with cca/godot/scripts/
# topology.gd via the build script). Two aliases below let the
# driver code address the maze as `room_exits` / `gated_exits`
# without caring where the canon data is stored.
# ------------------------------------------------------------
const Topology = preload("res://scripts/topology.gd")

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
    "quit": "quit",
    # NOTE: `exit` is NOT mapped to `quit`. Modern IF players type
    # "exit" expecting "leave this room"; making it kill-the-game
    # is a player-UX surprise. `quit` / `q` remain the canonical
    # quit handles.
    "save": "save", "restore": "load", "load": "load",
    # SUSPEND / PAUSE route to a canon-flavored handler that
    # narrates the original 1977 PDP-10 latency warning and
    # then saves instantly anyway. Plain SAVE stays silent for
    # modern UX; players who type SUSPEND specifically get the
    # easter egg. See the "suspend" handler in _process_input.
    "suspend": "suspend", "pause": "suspend",
    "score": "score",
    "help": "help", "?": "help",
    "info": "info",
    "hint": "hint",
    "hours": "hours",
    # Canon WIZARD/MAINT/MAGIC verbs — flavor easter eggs that
    # narrate the 1977 PDP-10 timesharing dialogue. See the
    # _process_input handlers for the full canon prose.
    "wizard": "wizard",
    "maint": "maint", "maintenance": "maint", "magic": "maint",
    "blast": "blast", "detonate": "blast",
    "wake": "wake",
    "find": "find", "where": "find",
    "brief": "brief",
    "rub": "rub",
    "say": "say",
    "back": "back", "retreat": "back",
    "look": "look",
    # Canon CAVE (advent.for STMT 40) — purely informational verb:
    # outdoors → msg #57, indoors → msg #58.
    "cave": "cave",
    # Port-only easter egg — Crowther's hand-drawn Bedquilt map.
    "map": "map",
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
# Crowther/Woods 35% chance — see Quux ODWY0350/advent.c).
const DARK_PIT_PCT := 35

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var fsm
# Driver-side RNG for probabilistic events (Witt's End 95/5,
# Bedquilt random-walk bumpers, dark-pit-fall, Y2 hollow-voice,
# unknown-verb msg distribution). Production calls randomize();
# tests inject a known seed for reproducibility. See RFC-0001.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var output: RichTextLabel
var input: LineEdit
var _last_room: int = -1
# (V1.2 Phase 0.5) _dark_warned_room moved onto DarknessGate.
# Driver accesses via fsm.dark_warned_room() /
# fsm.set_dark_warned_room(room) / fsm.clear_dark_warning().
var _save_path: String = "user://cca.save"     # cabinet convention: matches Arcade.save_path("cca")
# 5-character-truncated verb-synonym lookup, populated in _ready()
# from verb_synonyms. Mirrors canon's "first five letters" parser
# rule (Don Woods 1977 startup banner).
var _verb_synonyms_5: Dictionary = {}

# V1.2 Phase 0.10 — _pirate_already_stole driver var deleted.
# Equivalent state lives on the Pirate FSM (a successful steal
# transitions $Stalking → $Vanished).

# Resurrection-prompt state. When the player dies (bear
# Modal Y/N prompt coordinator (V1.2 Phase 0.2). Replaces four
# driver booleans (_awaiting_revive / _suspend_pending /
# _oyster_prompt_active / _hint_pending) with a single FSM.
# Standalone has a 5th latch (_quit_pending); arcade routes QUIT
# through the ExitDialog overlay instead so that latch is absent
# here (deliberate divergence — see check_cca_drift.py).
# Initialized at declaration time so headless tests work without
# _ready; fresh every session, nothing about its state survives
# save/restore.
var prompts = CcaFSM.PromptDispatcher.new()

# Canon BRIEF / IWEST / DETAIL / OLDLOC / OLDLC2 used to live
# here as driver vars; V1.2 Phase 0.1 moved them onto the
# Adventure FSM domain. Driver reads/writes via
# fsm.is_brief_mode() / fsm.enable_brief_mode(),
# fsm.get_iwest_count() / fsm.bump_iwest(),
# fsm.get_look_detail_count() / fsm.bump_look_detail() /
# fsm.reset_look_detail(), and fsm.get_old_loc() /
# fsm.set_old_loc() / fsm.get_old_loc2() / fsm.set_old_loc2().
var _visited_rooms: Dictionary = {}

# Typed-input recall (Up/Down at the prompt) and scrollback
# paging (PgUp/PgDn). Session-only ergonomic state — not part
# of save/restore. See cca/godot/scripts/driver.gd for full
# inline doc.
var _input_history: Array = []
var _input_history_idx: int = -1

# Canon msg #3 first-dwarf-encounter latch moved onto Adventure's
# domain in V1.2 Phase 0.9 (fsm.is_dwarf_first_encounter_done() /
# fsm.mark_dwarf_first_encounter_done()).

# Canon chest-only-outstanding hint latch (msg #186, fires once)
# moved onto Adventure's domain in V1.2 Phase 0.4
# (fsm.is_chest_hint_done() / fsm.mark_chest_hint_done()).

# Canon SUSPEND / OYSTER prompt latches moved onto PromptDispatcher
# in V1.2 Phase 0.2 (see `prompts` declaration above). The
# already-revealed latch moved onto Adventure in V1.2 Phase 0.11
# (fsm.is_oyster_revealed() / fsm.mark_oyster_revealed()).

# Canon hint Y/N flow. See cca/godot/scripts/driver.gd for full
# inline doc.
const HINT_PROMPT_MSGS: Dictionary = {
    "cave":   "Are you trying to get into the cave?",
    "bird":   "Are you trying to catch the bird?",
    "snake":  "Are you trying to somehow deal with the snake?",
    "maze":   "Do you need help getting out of the maze?",
    "plover": "Are you trying to explore beyond the Plover Room?",
    "witts":  "Do you need help getting out of here?",
}
const HINT_NAMES: Array = ["cave", "bird", "snake", "maze", "plover", "witts"]
# (V1.2 Phase 0.4) the "hint already auto-offered?" tracking
# moved onto each Hint FSM (as Hint.offered) and is dispatched
# via Adventure's mark_hint_offered(name) / hint_has_been_offered(name).
# (V1.2 Phase 0.2) the "hint awaiting yes/no" latch moved onto
# PromptDispatcher's $AwaitingHint state. Driver queries
# prompts.current_hint_name() to retrieve the active name.
const FORCED_ROOMS := [16, 22, 26, 32, 40, 59, 79, 89, 90, 113]

# --- Exit dialog (Save / Quit) ---
# Frame state machine that owns the dialog's modal logic.
# Defined in arcade/frame/dialog.fgd → arcade/godot/scripts/
# dialog.gd. The driver opens it on Esc, calls one of
# confirm_quit / confirm_save_quit / cancel based on the key
# pressed, then reads last_action() to decide what to do.
const ExitDialogScript = preload("res://scripts/dialog.gd")
var exit_dialog                       # ExitDialog FSM instance
var label_exit_dialog: Label

# ============================================================
func _ready() -> void:
    fsm = CcaFSM.new()
    fsm.setup_default_aspects()
    fsm.wake_dwarves()
    # `prompts` is initialized at var-declaration time (see top).
    # Seed the driver-side RNG from system time for production play.
    rng.randomize()
    exit_dialog = ExitDialogScript.new()
    _build_verb_synonyms_5()
    _build_ui()
    # If a save file is on disk, the cabinet menu's Continue/New
    # prompt has already routed us here with the player's choice
    # baked in (New game deletes the save before launching, so
    # the file's existence here means "Continue"). Auto-load and
    # skip the welcome/intro text.
    if FileAccess.file_exists(_save_path):
        _load_game()
    else:
        _print_welcome()
        _print_room()

func _build_ui() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    # The root Control should never claim focus. Tab cycles
    # focus through focusable controls; with the root non-
    # focusable and the output panel non-focusable (set below),
    # Tab has nowhere to go but the LineEdit.
    focus_mode = Control.FOCUS_NONE

    var bg := ColorRect.new()
    bg.color = Color(0.05, 0.06, 0.09)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    # MarginContainer keeps the output log and input row away
    # from the viewport edges. Without this, the prompt text
    # sits hard against the bottom-left corner and the whole
    # screen reads like an untrimmed terminal dump.
    var margins := MarginContainer.new()
    margins.set_anchors_preset(Control.PRESET_FULL_RECT)
    margins.add_theme_constant_override("margin_left", 24)
    margins.add_theme_constant_override("margin_right", 24)
    margins.add_theme_constant_override("margin_top", 16)
    margins.add_theme_constant_override("margin_bottom", 16)
    add_child(margins)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 4)
    margins.add_child(vbox)

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
    # [url=...]...[/url] BBCode just emits meta_clicked; opening
    # a browser is on us. The welcome panel embeds the IF Archive
    # link as the one canonical thing players might click.
    output.meta_clicked.connect(_on_meta_clicked)
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
    # Strip the default boxy LineEdit chrome so the prompt
    # reads as a single terminal line — `> ` label flowing
    # straight into the typed text. Without these overrides
    # the LineEdit carries a grey form-style border that looks
    # out of place against the dark terminal background.
    var transparent_box := StyleBoxEmpty.new()
    input.add_theme_stylebox_override("normal",   transparent_box)
    input.add_theme_stylebox_override("focus",    transparent_box)
    input.add_theme_stylebox_override("read_only", transparent_box)
    input.add_theme_color_override("font_color", Color(0.92, 0.95, 0.6))
    input.add_theme_color_override("font_placeholder_color", Color(0.55, 0.55, 0.55))
    input.add_theme_color_override("caret_color", Color(0.92, 0.95, 0.6))
    # Godot 4.4+ added `keep_editing_on_text_submit`, defaulting
    # to false — every Enter press kicks the LineEdit out of
    # editing mode even though it stays focused. Without this
    # the player has to press Enter (or click) again before each
    # new command. See:
    #   https://github.com/godotengine/godot/issues/101434
    input.keep_editing_on_text_submit = true
    # Up/Down recall typed history; PgUp/PgDn page the scroll
    # log. LineEdit ignores these keys for single-line editing,
    # so we intercept via gui_input before they bubble out.
    input.gui_input.connect(_on_input_gui_input)
    prompt_row.add_child(input)

    input.grab_focus()

    # Centered Save/Quit dialog overlay. Hidden until Esc.
    label_exit_dialog = Label.new()
    label_exit_dialog.add_theme_font_size_override("font_size", 24)
    label_exit_dialog.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
    label_exit_dialog.set_anchors_preset(Control.PRESET_CENTER)
    label_exit_dialog.position = Vector2(-220, -60)
    label_exit_dialog.size = Vector2(440, 120)
    label_exit_dialog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_exit_dialog.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label_exit_dialog.text = "Leaving the cave?\n\n[Enter] Save and quit (default)    [Q] Quit without saving\n[Esc] Cancel"
    label_exit_dialog.visible = false
    add_child(label_exit_dialog)

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
    var cooked: String = text.strip_edges()
    if _input_history.is_empty() or _input_history.back() != cooked:
        _input_history.append(cooked)
    _input_history_idx = -1
    _process_input(trimmed)
    input.call_deferred("grab_focus")

# Up/Down recall typed history; PgUp/PgDn page the scroll log.
# Mirror of cca/godot/scripts/driver.gd._on_input_gui_input —
# see that file for full inline doc.
func _on_input_gui_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed:
        return
    match event.keycode:
        KEY_UP:
            _history_recall(-1)
            input.accept_event()
        KEY_DOWN:
            _history_recall(1)
            input.accept_event()
        KEY_PAGEUP:
            _scroll_output(-1)
            input.accept_event()
        KEY_PAGEDOWN:
            _scroll_output(1)
            input.accept_event()
        KEY_F5:
            # Quick-save (Half-Life / Skyrim convention). The
            # arcade chapter binds the same key via its own
            # _input handler — see arcade/godot/scripts/cca_main.gd.
            # The standalone uses gui_input because the LineEdit
            # owns focus permanently here.
            _save_game()
            input.accept_event()
        KEY_F9:
            # Quick-load — companion to F5.
            _load_game()
            input.accept_event()

func _history_recall(direction: int) -> void:
    if _input_history.is_empty():
        return
    if _input_history_idx == -1:
        if direction > 0:
            return
        _input_history_idx = _input_history.size() - 1
    else:
        var new_idx: int = _input_history_idx + direction
        if new_idx < 0:
            new_idx = 0
        elif new_idx >= _input_history.size():
            _input_history_idx = -1
            input.text = ""
            input.caret_column = 0
            return
        _input_history_idx = new_idx
    input.text = _input_history[_input_history_idx]
    input.caret_column = input.text.length()

func _scroll_output(direction: int) -> void:
    var sb: ScrollBar = output.get_v_scroll_bar()
    if sb == null:
        return
    var page: float = max(sb.page, 100.0)
    sb.value = sb.value + direction * page

func _process_input(text: String) -> void:
    # Canon WEST counter (advent.for line 901). On the 10th
    # typed "WEST", fire msg #17 once. "w" doesn't trigger.
    var raw_first: String = text.strip_edges().split(" ", false)[0] if not text.strip_edges().is_empty() else ""
    if raw_first == "west":
        fsm.bump_iwest()
        if fsm.get_iwest_count() == 10:
            _println("If you prefer, simply type W rather than WEST.")

    var parsed := _parse(text)
    var verb: String = parsed[0]
    var noun: String = parsed[1]

    if verb == "":
        # Canon msg #195 — parser fallback for whitespace-only input.
        _println("I'm afraid I don't understand.")
        return

    # ----- Modal Y/N prompt dispatcher (V1.2 Phase 0.2) -----
    # PromptDispatcher FSM holds "which prompt is open" as state.
    # Arcade has four prompts (revive / suspend / oyster / hint) —
    # no inline quit prompt since QUIT routes through ExitDialog.
    # See cca/godot/scripts/driver.gd for the standalone equivalent
    # (which adds a "quit" branch).
    if prompts.is_active():
        var prompt_name: String = prompts.current_prompt()
        var hint_name: String = prompts.current_hint_name()
        if verb == "yes":
            prompts.confirm()
            match prompt_name:
                "suspend":
                    _println("OK")
                    _save_game()
                    return
                "oyster":
                    fsm.mark_oyster_revealed()
                    _println("It says, \"There is something strange about this place, such that one")
                    _println("of the words I've always known now has a new effect.\"")
                    fsm.score_hints = fsm.score_hints - 10
                    fsm.real_score = fsm.real_score - 10
                    return
                "revive":
                    # Canon advent.for STMT 16100 — revive prose owned
                    # by Player FSM (V1.2 Phase 0.8).
                    var revive_prose: String = fsm.player.get_revive_response()
                    fsm.player.revive()
                    _println("[color=#88dd88]%s[/color]" % revive_prose)
                    _last_room = -1
                    _print_room()
                    return
                "hint":
                    _println(fsm.request_hint(hint_name))
                    return
        elif verb == "no":
            prompts.decline()
            match prompt_name:
                "suspend":
                    _println("OK")
                    return
                "oyster":
                    _println("OK.")
                    return
                "hint":
                    # Canon msg #54.
                    _println("OK")
                    return
                "revive":
                    # Canon msg #86 — Player owns the prose (V1.2 Phase 0.8).
                    _println("[color=#cc4444]%s[/color]" % fsm.player.get_permadeath_msg())
                    await get_tree().create_timer(2.0).timeout
                    # Game-over: return to the cabinet menu rather
                    # than killing the whole cabinet. The dead-player
                    # state isn't worth saving, so skip the exit
                    # dialog and leave straight away.
                    Arcade.return_to_menu()
                    return
        else:
            # Non-yes/no input. $AwaitingRevive re-prompts; the
            # others cancel and fall through to normal verb
            # processing.
            if prompts.accepts_only_yes_no():
                # advent.for FORMAT(/' Please answer the question.')
                _println("Please answer the question.")
                return
            prompts.cancel()
            # Fall through.

    # ----- UI-only verbs (driver-handled, never reach the FSM) -----
    # Mirror cca/godot/scripts/driver.gd — every turn-taking
    # intercept routes through _post_intercept_tick so the canon
    # per-turn checks (dwarf movement, lamp, hints, pirate steal)
    # fire on every turn.
    if _handle_ui_verb(verb, noun): _post_intercept_tick(); return

    # ----- Canon bear-on-bridge cross (msg #162) -----
    if _intercept_bridge_cross(verb): _post_intercept_tick(); return

    # ----- Bumper rules + dark-pit hazard -----
    if _dispatch_bumper(verb): _post_intercept_tick(); return
    if verb in MOTION_VERBS and _check_dark_pit_hazard(): _post_intercept_tick(); return

    # ENTER STREAM/WATER must precede DIRECTIONS.
    if _intercept_enter_stream(verb, noun): _post_intercept_tick(); return
    if verb in DIRECTIONS:
        _handle_movement(verb)
        return
    # ----- Canon verb intercepts (order is canon-significant) -----
    if _intercept_break_mirror(verb, noun): _post_intercept_tick(); return
    if _intercept_drop_bird(verb, noun): _post_intercept_tick(); return
    if _intercept_attack_bird(verb, noun): _post_intercept_tick(); return
    if _intercept_attack_bear(verb, noun): _post_intercept_tick(); return
    if _intercept_take_knife(verb, noun): _post_intercept_tick(); return
    if _intercept_take_bear(verb, noun): _post_intercept_tick(); return
    if _intercept_unlock_chain(verb, noun): _post_intercept_tick(); return
    if _intercept_take_scenery(verb, noun): _post_intercept_tick(); return
    if _intercept_throw_axe(verb, noun): _post_intercept_tick(); return
    _intercept_plover_emerald(verb, noun)              # side-effect; falls through to FSM
    if _intercept_calm(verb, noun): _post_intercept_tick(); return
    if _intercept_eat(verb, noun): _post_intercept_tick(); return
    if _intercept_feed(verb, noun): _post_intercept_tick(); return
    if _intercept_scenery_read(verb, noun): _post_intercept_tick(); return

    # Custom motion aliases. Placed AFTER intercepts so verbs with
    # side effects (e.g. plover dropping the emerald) fire first —
    # otherwise a verb that's also a magic-word-exit would be
    # eaten by movement before the side-effect handler ran.
    if verb in room_exits.get(fsm.player_room(), {}):
        _handle_movement(verb)
        return

    # ----- FSM dispatch + unknown-verb prose mix -----
    _dispatch_to_fsm(verb, noun)

    # ----- Per-turn check chain -----
    _run_per_turn_checks()

func _post_intercept_tick() -> void:
    _run_per_turn_checks()

# ============================================================
# UI-only verbs (driver-handled, never reach the FSM)
# ============================================================
# Returns true if `verb` was a UI verb the driver fully handled.
# Arcade differs from cca/driver in two places:
#   - QUIT routes through the exit_dialog (cabinet shell handles
#     save+quit / quit / cancel) instead of canon msg #22.
#   - Otherwise identical to the cca/driver mirror.
func _handle_ui_verb(verb: String, noun: String) -> bool:
    match verb:
        "help":
            _print_help()
            return true
        "info":
            _print_info()
            return true
        "quit":
            # Typed QUIT mirrors the Esc keypress: open the
            # save+quit / quit / cancel dialog rather than firing
            # canon msg #22 + killing the cabinet.
            if not exit_dialog.is_open():
                exit_dialog.open()
                _show_exit_dialog()
            return true
        "score":
            _println("[b]Score: %d[/b] — treasures %d (%d/15 deposited), visits %d, hints %d, endgame %d" % [
                fsm.score(),
                fsm.treasure_score(), fsm.treasures_deposited(),
                fsm.visit_score(),
                fsm.hint_penalty(),
                fsm.endgame_score()])
            return true
        "inventory":
            _println(_format_inventory())
            return true
        "save":
            _save_game()
            return true
        "load":
            _load_game()
            return true
        "suspend":
            # Canon SUSPEND (advent.for STMT 8300) — prompts msg
            # #200 confirmation; YES saves + ends, NO cancels.
            _println("I can suspend your adventure for you so that you can resume later, but")
            _println("you will have to wait at least 45 minutes before continuing.")
            _println("Is this acceptable?")
            prompts.offer_suspend()
            return true
        "hint":
            var hint_name: String = noun if noun != "" else "bird"
            _println(fsm.request_hint(hint_name))
            return true
        "hours":
            # Canon HOURS — desktop port has no off-hours.
            _println("Colossal Cave is open all day, every day.")
            _println("(In the original 1977 PDP-10 release this verb")
            _println("printed the timesharing schedule during which")
            _println("non-wizards could play. On a desktop port the")
            _println("cave has no off-hours.)")
            return true
        "wizard":
            # Canon WIZARD — canon-msg-#16/#17/#19/#20 dialogue.
            _println("\"Are you a wizard?\"")
            _println("\"Prove it!  Say the magic word!\"")
            _println("\"That is not what I thought it was.  Do you know what I thought it was?\"")
            _println("\"Foo, you are nothing but a charlatan!\"")
            return true
        "maint", "magic":
            # Canon MAINT — wizard-in-grey flavor.
            _println("A large cloud of green smoke appears in front of you. It clears")
            _println("away to reveal a tall wizard, clothed in grey. He fixes you with")
            _println("a steely glare and declares, \"Maintenance mode requires a real")
            _println("PDP-10 and a sysadmin who knew Don Woods. This is neither.\"")
            _println("With that he makes a single pass over you with his hands, and")
            _println("you find yourself right back where you started.")
            _println("")
            _println("\"Foo, you are nothing but a charlatan!\"")
            return true
        "blast":
            # Canon BLAST (advent.for STMT 9230). See cca/driver
            # for full inline canon-spec docs.
            if fsm.endgame_state() != "in_repository":
                _println("Blasting requires dynamite.")
                return true
            if fsm.mark_rod_here():
                _println("There is a loud explosion, and you are suddenly splashed across the")
                _println("walls of the room.")
                fsm.blast_klutz()
                _check_endgame_phase_change()
                return true
            if fsm.player_room() == 115:
                _println("There is a loud explosion, and a twenty-foot hole appears in the far")
                _println("wall, burying the snakes in the rubble. A river of molten lava pours")
                _println("in through the hole, destroying everything in its path, including you!")
                fsm.blast_wrong_way()
                _check_endgame_phase_change()
                return true
            _println("There is a loud explosion, and a twenty-foot hole appears in the far")
            _println("wall, burying the dwarves in the rubble. You march through the hole")
            _println("and find yourself in the main office, where a cheering band of")
            _println("friendly elves carry the conquering adventurer off into the sunset.")
            fsm.blast_mastery()
            _check_endgame_phase_change()
            return true
        "wake":
            if fsm.endgame_state() != "in_repository":
                _println("I don't understand that.")
                return true
            _println("You prod the nearest dwarf, who wakes up grumpily, takes one look at")
            _println("you, curses, and grabs for his axe.")
            _println("")
            _println("The resulting ruckus has awakened the dwarves. There are now several")
            _println("threatening little dwarves in the room with you! Most of them throw")
            _println("knives at you! All of them get you!")
            fsm.player.die()
            _check_player_death()
            return true
        "find":
            var find_obj_id: int = _resolve_object_id(noun)
            if find_obj_id > 0 and fsm.player.carrying(find_obj_id):
                _println("You are already carrying it!")
                return true
            if find_obj_id > 0 and _object_in_room(find_obj_id, fsm.player_room()):
                _println("I believe what you want is right here with you.")
                return true
            if fsm.endgame_state() == "in_repository":
                _println("I daresay whatever you want is around here somewhere.")
                return true
            _println("I can only tell you what you see as you move about and manipulate things. I cannot tell you where remote things are.")
            return true
        "brief":
            fsm.enable_brief_mode()
            _println("Okay, from now on I'll only describe a place in full the first time")
            _println("you come to it. To get the full description, say LOOK.")
            return true
        "rub":
            if noun == "lamp":
                _println("Rubbing the electric lamp is not particularly rewarding. Anyway, nothing exciting happens.")
            else:
                _println("Peculiar. Nothing unexpected happens.")
            return true
        "say":
            if noun == "":
                _println("Say what?")
                return true
            if noun in ["xyzzy", "plugh", "plover", "fee", "fie", "foe", "foo"]:
                _process_input(noun)
                return true
            _println("Okay, \"%s\"." % noun)
            return true
        "cave":
            if fsm.player_room() <= 8:
                _println("I don't know where the cave is, but hereabouts no stream can run on the surface for long. I would try the stream.")
            else:
                _println("I need more detailed instructions to do that.")
            return true
        "map":
            # Port-only easter egg — Crowther's Bedquilt map.
            # Available at the well-house (canon 3) or in the deep
            # cave (LOC ≥ 15); surface forest gets canon msg #60.
            var here_r: int = fsm.player_room()
            if here_r != 3 and here_r < 15:
                _println("I don't know that word.")
                return true
            _print_crowther_map()
            return true
        "look":
            if fsm.get_look_detail_count() < 3:
                _println("Sorry, but I am not allowed to give more detail. I will repeat the long description of your location.")
                fsm.bump_look_detail()
            _last_room = -1
            _visited_rooms.erase(fsm.player_room())
            _print_room()
            return true
        "back":
            # Canon BACK (advent.for STMT 20-25) — msg #91 if no
            # history, msg #140 if history valid but unreachable.
            var bk_current: int = fsm.player_room()
            var bk_exits: Dictionary = room_exits.get(bk_current, {})
            if "back" in bk_exits:
                _handle_movement("back")
                return true
            var k: int = fsm.get_old_loc()
            if k in FORCED_ROOMS:
                k = fsm.get_old_loc2()
            if k < 0 or k == bk_current:
                _println("Sorry, but I no longer seem to remember how it was you got here.")
                return true
            for bk_dir in bk_exits:
                if bk_exits[bk_dir] == k:
                    _handle_movement(bk_dir)
                    return true
            _println("You can't get there from here.")
            return true
    return false

# ============================================================
# Dispatch helpers
# ============================================================

# Canon "always-blocked" bumper gates and conditional rows. The
# (room, verb) key may map to either a single rule (Dictionary)
# or an ordered chain of rules (Array). The chain walks rules in
# order; the first that fires wins. Returns true if any rule
# fired (caller should `return`).
func _dispatch_bumper(verb: String) -> bool:
    var bumper_key: String = "%d:%s" % [fsm.player_room(), verb]
    if not bumper_key in gated_exits:
        return false
    var entry = gated_exits[bumper_key]
    var rules: Array = entry if entry is Array else [entry]
    for rule in rules:
        if _try_bumper_rule(rule):
            return true
    return false

# FSM dispatch + unknown-verb canon randomization (msg #60/#61/
# #13 in 64/16/20 distribution per advent.for STMT 3000).
func _dispatch_to_fsm(verb: String, noun: String) -> void:
    var response: String = fsm.do_command(verb, noun)
    if response.begins_with("I don't know how to '"):
        var roll1: int = rng.randi() % 100
        var roll2: int = rng.randi() % 100
        if roll2 < 20:
            response = "I don't understand that!"   # canon msg #13
        elif roll1 < 20:
            response = "What?"                       # canon msg #61
        else:
            response = "I don't know that word."     # canon msg #60
    _println(response)

# Per-turn check chain.
func _run_per_turn_checks() -> void:
    _step_dwarves()
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_dwarf_axe()
    _check_chest_hint()
    _check_hint_prompts()
    _check_player_death()
    _maybe_print_room_after_move()

# Canon STMT 6010 dwarf-movement loop. Mirrors the cca/godot
# driver implementation. The per-turn walker picks each
# stalking dwarf a non-backtrack non-surface destination from
# the canon section-3 travel graph; if the dwarf has SEEN the
# player and the player is still in the deep cave, it snaps
# to the player's room.
# V1.3 Phase 0.9 follow-on — the shared `_dwarf_walk_rng` was
# replaced by each Dwarf / Pirate FSM's own seeded PRNG
# (deterministic per save_state). See Dwarf.pick_destination
# in cca/frame/cca.fgd. Driver now only supplies the candidate
# exits from canon section-3; the FSM filters + picks.

func _step_dwarves() -> void:
    var player_room: int = fsm.player_room()
    for i in [1, 2, 3, 4, 5]:
        var d_state: String = _dwarf_state(i)
        if d_state != "stalking":
            continue
        var cur: int = fsm.dwarf_room_of(i)
        var was_seen: bool = fsm.dwarf_is_seen(i)
        var new_room: int = fsm.dwarf_pick_destination(
            i, _candidate_exits(cur), FORCED_ROOMS)
        fsm.dwarf_step_to(i, new_room)
        var now_at: int = fsm.dwarf_room_of(i)
        var now_prev: int = fsm.dwarf_prev_room_of(i)
        var saw_player: bool = (now_at == player_room) or (now_prev == player_room)
        var new_seen: bool = saw_player or (was_seen and player_room >= 15)
        if new_seen:
            fsm.dwarf_snap_to_player(i)
        elif player_room < 15:
            fsm.dwarf_unsee(i)
    # Canon dwarf #6 — the pirate. Same movement loop once active.
    if fsm.pirate.is_stalking():
        var p_cur: int = fsm.pirate_room()
        var p_was_seen: bool = fsm.pirate_is_seen()
        var p_forbidden: Array = FORCED_ROOMS + FORBIDDEN_PIRATE_ROOMS
        var p_new: int = fsm.pirate_pick_destination(_candidate_exits(p_cur), p_forbidden)
        fsm.pirate_step_to(p_new)
        var p_at: int = fsm.pirate_room()
        var p_pat: int = fsm.pirate_prev_room()
        var p_saw: bool = (p_at == player_room) or (p_pat == player_room)
        var p_new_seen: bool = p_saw or (p_was_seen and player_room >= 15)
        if p_new_seen:
            fsm.pirate_snap_to_player()
        elif player_room < 15:
            fsm.pirate_unsee()

func _candidate_exits(cur: int) -> Array:
    var out: Array = []
    for dest in room_exits.get(cur, {}).values():
        if not out.has(dest):
            out.append(dest)
    return out

const FORBIDDEN_PIRATE_ROOMS: Array = [101, 117, 122]

func _dwarf_state(idx: int) -> String:
    if idx == 1: return fsm.dwarf1.get_state()
    if idx == 2: return fsm.dwarf2.get_state()
    if idx == 3: return fsm.dwarf3.get_state()
    if idx == 4: return fsm.dwarf4.get_state()
    if idx == 5: return fsm.dwarf5.get_state()
    return "hidden"

# Canon hint Y/N auto-prompt. See cca/godot/scripts/driver.gd.
func _check_hint_prompts() -> void:
    if prompts.is_active():
        return
    for n in HINT_NAMES:
        if fsm.hint_has_been_offered(n):
            continue
        if fsm.hint_state(n) != "eligible":
            continue
        fsm.mark_hint_offered(n)
        prompts.offer_hint(n)
        _println(HINT_PROMPT_MSGS[n])
        return

# ============================================================
# Verb intercepts
# ============================================================
# Each `_intercept_*` returns true if the verb was handled
# (caller should `return`) and false to fall through. Dispatch
# order in `_process_input` is canon-significant.

func _intercept_break_mirror(verb: String, noun: String) -> bool:
    if verb != "break" or noun != "mirror":
        return false
    if fsm.endgame_state() == "in_repository":
        _println("You strike the mirror a resounding blow, whereupon it shatters into a")
        _println("myriad tiny fragments.")
        _println("")
        _println("The resulting ruckus has awakened the dwarves. There are now several")
        _println("threatening little dwarves in the room with you! Most of them throw")
        _println("knives at you! All of them get you!")
        fsm.player.die()
        _check_player_death()
        return true
    _println("It is beyond your power to do that.")
    return true

# Canon DROP BIRD (advent.for STMT 9020). DROP at snake →
# snake eats caged bird (msg #101); elsewhere routes to release.
# See cca/godot/scripts/driver.gd for full inline doc.
func _intercept_drop_bird(verb: String, noun: String) -> bool:
    if verb != "drop" or noun != "bird":
        return false
    if not fsm.player.carrying(BIRD_ID):
        _process_input("release bird")
        return true
    if fsm.player_room() == fsm.SNAKE_ROOM and fsm.snake.is_blocking():
        fsm.bird.vanish()
        fsm.player.drop(BIRD_ID)
        _println("The snake has now devoured your bird.")
        return true
    _process_input("release bird")
    return true

func _intercept_attack_bird(verb: String, noun: String) -> bool:
    if verb != "attack" or noun != "bird":
        return false
    _println("Oh, leave the poor unhappy bird alone.")
    return true

func _intercept_attack_bear(verb: String, noun: String) -> bool:
    if verb != "attack" or noun != "bear":
        return false
    var bs: String = fsm.bear.get_state()
    if bs == "hungry":
        _println("With what? Your bare hands? Against *his* bear hands??")
    elif bs == "tame" or bs == "following":
        _println("The bear is confused; he only wants to be your friend.")
    elif bs == "released":
        _println("For crying out loud, the poor thing is already dead!")
    else:
        _println("You can't be serious!")
    return true

func _intercept_take_knife(verb: String, noun: String) -> bool:
    if verb != "take" or noun != "knife":
        return false
    _println("The dwarves' knives vanish as they strike the walls of the cave.")
    return true

func _intercept_take_bear(verb: String, noun: String) -> bool:
    if verb != "take" or noun != "bear":
        return false
    var bs: String = fsm.bear.get_state()
    if bs == "hungry" or bs == "tame":
        _println("The bear is still chained to the wall.")
        return true
    if bs == "following":
        _println("OK")
        return true
    _println("You can't be serious!")
    return true

func _intercept_unlock_chain(verb: String, noun: String) -> bool:
    if verb != "unlock" or noun != "chain":
        return false
    if not fsm.player.carrying(KEYS_ID):
        _println("The chain is still locked.")
        return true
    return false

func _intercept_take_scenery(verb: String, noun: String) -> bool:
    if verb != "take":
        return false
    if noun == "stalactite":
        # Canon msg #148.
        _println("It is too far up for you to reach.")
        return true
    if noun in [
            "tablet", "mirror", "figure", "shadow",
            "drawings", "drawing", "volcano", "geyser",
            "carpet", "moss", "message"]:
        _println("You can't be serious!")
        return true
    return false

# Canon msg #162 — bear-bridge collapse on cross with bear
# following. See cca/godot/scripts/driver.gd for full inline doc.
const _BRIDGE_CROSS_VERBS: Array = ["over", "across", "cross", "ne", "sw"]
func _intercept_bridge_cross(verb: String) -> bool:
    if not verb in _BRIDGE_CROSS_VERBS:
        return false
    var here: int = fsm.player_room()
    if here != 117 and here != 122:
        return false
    if fsm.troll_bridge_collapsed():
        return false   # let topology gate emit msg #161
    if fsm.bear_state() != "following":
        return false
    # Canon msg #162 verbatim.
    _println("Just as you reach the other side, the bridge buckles beneath the weight of the bear, which was still following you around. You scrabble desperately for support, but as the bridge collapses you stumble back and fall into the chasm.")
    fsm.collapse_troll_bridge()
    fsm.player.die()
    _check_player_death()
    return true

# Canon ENTER STREAM / ENTER WATER (msg #70). Must precede the
# DIRECTIONS check.
func _intercept_enter_stream(verb: String, noun: String) -> bool:
    if verb != "enter":
        return false
    if noun != "stream" and noun != "water":
        return false
    _println("Your feet are now wet.")
    return true

# Canon THROW AXE (advent.for STMT 9170). Returns false (falls
# through to FSM _verb_throw) for the dwarf-attack path.
func _intercept_throw_axe(verb: String, noun: String) -> bool:
    if verb != "throw" or noun != "axe":
        return false
    var here_room: int = fsm.player_room()
    if here_room == 119 and fsm.dragon_alive():
        _println("The axe bounces harmlessly off the dragon's thick scales.")
        return true
    if here_room == 117 and fsm.troll.is_blocking_bridge():
        _println("The troll deftly catches the axe, examines it carefully, and tosses")
        _println("it back, declaring, \"Good workmanship, but it's not valuable enough.\"")
        return true
    if here_room == 130 and fsm.bear_state() == "hungry":
        _println("The axe misses and lands near the bear where you can't get at it.")
        return true
    return false

# Canon routine 302 — Plover-emerald drop. Side-effect only;
# falls through so the regular PLOVER teleport runs after via
# fsm.do_command.
func _intercept_plover_emerald(verb: String, noun: String) -> void:
    if verb != "plover":
        return
    var here_pl: int = fsm.player_room()
    if (here_pl == 33 or here_pl == 100) and fsm.player.carrying(EMERALD_ID):
        fsm.emerald.try_drop(here_pl)
        fsm.player.drop(EMERALD_ID)
        _println("OK")

func _intercept_calm(verb: String, noun: String) -> bool:
    if verb != "calm" and verb != "tame":
        return false
    _println("I'm game. Would you care to explain how?")
    return true

func _intercept_eat(verb: String, noun: String) -> bool:
    if verb != "eat":
        return false
    if noun in ["bird", "snake", "clam", "oyster", "dwarf", "dragon", "troll", "bear"]:
        _println("Don't be ridiculous!")
        return true
    if noun != "" and noun != "food":
        _println("I think I just lost my appetite.")
        return true
    return false

func _intercept_feed(verb: String, noun: String) -> bool:
    if verb != "feed":
        return false
    if noun == "bird":
        _println("It's not hungry (it's merely pinin' for the fjords). Besides, you have no bird seed.")
        return true
    if noun == "dwarf":
        # canon msg #103 + DFLAG bump.
        fsm.bump_dwarf_anger()
        _println("You fool, dwarves eat only coal! Now you've made him *really* mad!!")
        return true
    if noun == "troll":
        _println("Gluttony is not one of the troll's vices. Avarice, however, is.")
        return true
    if noun == "snake" or noun == "dragon":
        if noun == "dragon" and not fsm.dragon_alive():
            _println("Don't be ridiculous!")
        else:
            _println("There's nothing here it wants to eat (except perhaps you).")
        return true
    return false

# Canon scenery EXAMINE/READ flavor (advent.dat section 5).
func _intercept_scenery_read(verb: String, noun: String) -> bool:
    if verb != "read" and verb != "examine":
        return false
    var er: int = fsm.player_room()
    # ROD2 prop change — pre-CLOSED rod / post-CLOSED dynamite.
    if noun == "rod" and fsm.mark_rod_here():
        if fsm.endgame_state() == "in_repository":
            _println("Peculiar. Nothing unexpected happens.")
        else:
            _println("A small black rod with a rusty mark on the end.")
        return true
    if noun == "tablet" and er == 101:
        _println("A massive stone tablet imbedded in the wall reads:")
        _println("\"Congratulations on bringing light into the dark-room!\"")
        return true
    if noun == "message" and er == 140:
        _println("There is a message scrawled in the dust in a flowery script, reading:")
        _println("\"This is not the maze where the pirate leaves his treasure chest.\"")
        return true
    if noun == "oyster" and fsm.oyster_item.is_in_room(er):
        if fsm.is_oyster_revealed():
            _println("It says the same thing it did before.")
            return true
        prompts.offer_oyster()
        _println("Hmmm, this looks like a clue, which means it'll cost you 10 points to")
        _println("read it. Should I go ahead and read it anyway?")
        return true
    if noun == "mirror" and er == 109:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    if (noun == "figure" or noun == "shadow") and (er == 35 or er == 110):
        _println("The shadowy figure seems to be trying to attract your attention.")
        return true
    if noun == "stalactite" and er == 111:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    if (noun == "drawings" or noun == "drawing") and er == 97:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    if (noun == "volcano" or noun == "geyser") and er == 126:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    if (noun == "carpet" or noun == "moss") and er == 96:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    if (noun == "plant" or noun == "plant2") and (er == 23 or er == 35):
        _println("There is a huge beanstalk growing out of the west pit up to the hole.")
        return true
    # Canon msg #63 — EXAMINE GRATE at the depression.
    if noun == "grate" and (er == 8 or er == 9):
        _println("The grate is very solid and has a hardened steel lock. You cannot")
        _println("enter without a key, and there are no keys nearby. I would recommend")
        _println("looking elsewhere for the keys.")
        return true
    # Canon msg #64 — EXAMINE TREES/FOREST in the forest rooms.
    if (noun == "trees" or noun == "forest" or noun == "tree") and er in [4, 5, 6]:
        _println("The trees of the forest are large hardwood oak and maple, with an")
        _println("occasional grove of pine or spruce. There is quite a bit of under-")
        _println("growth, largely birch and ash saplings plus nondescript bushes of")
        _println("various sorts. This time of year visibility is quite restricted by")
        _println("all the leaves, but travel is quite easy if you detour around the")
        _println("spruce and berry bushes.")
        return true
    # Canon msg #69 — EXAMINE MIST.
    if noun == "mist":
        _println("Mist is a white vapor, usually water, seen from time to time in")
        _println("caverns. It can be found anywhere but is frequently a sign of a deep")
        _println("pit leading down to water.")
        return true
    return false

# ============================================================
# Parsing
# ============================================================
func _parse(text: String) -> Array:
    # Canon: parser examines only the first 5 chars of each verb
    # token (Don Woods 1977 startup banner). Truncate, then look
    # up in a pre-truncated synonym table that resolves back to
    # the canonical form for FSM dispatch.
    # Lazily populate the truncation table on first parse — for
    # production use _ready() runs first, but headless tests
    # construct outside the scene tree, so _ready() is never
    # called and the table would be empty.
    if _verb_synonyms_5.is_empty():
        _build_verb_synonyms_5()
    var parts: PackedStringArray = text.split(" ", false)
    if parts.is_empty():
        return ["", ""]
    var raw_verb: String = _truncate5(parts[0])
    var canonical: String = _verb_synonyms_5.get(raw_verb, raw_verb)
    var noun: String = ""
    if parts.size() > 1:
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

func _build_verb_synonyms_5() -> void:
    for key in verb_synonyms.keys():
        _verb_synonyms_5[_truncate5(key)] = verb_synonyms[key]
    for canon_verb in ["extinguish", "release", "attack", "examine",
                       "unlock", "insert", "plover", "inventory",
                       # Motion verbs > 5 chars that appear in
                       # GATES keys or topology aliases. The
                       # gate-key check uses the full canonical
                       # verb, so the 5-char truncation must
                       # restore here (e.g. "passa" → "passage"
                       # so 15:passage gold-bumper can fire).
                       "passage", "forward", "stream", "across",
                       "stairs", "depression", "building", "valley",
                       "bedquilt", "oriental", "cavern", "barren",
                       "secret", "office", "cobbles", "awkward",
                       "outdoors", "downstream", "upstream",
                       "entrance", "surface", "reservoir"]:
        _verb_synonyms_5[_truncate5(canon_verb)] = canon_verb

# ============================================================
# Movement
# ============================================================
func _handle_movement(direction: String) -> void:
    var current: int = fsm.player_room()
    var exits: Dictionary = room_exits.get(current, {})
    if not direction in exits:
        # Canon msg #11 — IN/OUT without an exit gets the
        # "I don't know in from out" rebuff.
        if direction == "in" or direction == "out":
            _println("I don't know in from out here. Use compass points or name something")
            _println("in the general direction you want to go.")
            return
        # Canon msg #10 — LEFT/RIGHT/FORWARD without facing context.
        if direction == "left" or direction == "right" or direction == "forward":
            _println("I am unsure how you are facing. Use compass points or nearby objects.")
            return
        # Canon msg #9 — uniform "no exit that way" rebuff. Canon
        # doesn't echo the direction the player tried.
        _println("There is no way to go that direction.")
        return

    var dest: int = exits[direction]

    # Gated exits — snake at room 7 east, troll at room 10 east,
    # crystal-bridge at the fissure (room 24 east).
    var gate_key: String = "%d:%s" % [current, direction]
    if gate_key in gated_exits and not (gated_exits[gate_key] is Array):
        # Single-rule gates (Dictionary). Multi-rule chains (Array)
        # were already handled by _dispatch_bumper.
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
        if gate.check == "rusty" and not fsm.rusty_door_oiled():
            # Rusty iron door at canon 94 → 95. Pour oil to open.
            _println(gate.msg)
            return
        if gate.check == "carrying":
            # Inventory-conditional bumper. Used at canon 15 for
            # the gold-blocks-the-steps puzzle (canon row
            # `15 150022 …`). The gate's `obj` field names the
            # port-side constant on Adventure (e.g. "GOLD_ID");
            # we resolve it and check player.carrying(...). On
            # match, emit the canon msg and stay put — forces
            # the player to use the canon long-way out.
            var obj_name: String = gate.get("obj", "")
            if obj_name != "" and obj_name in fsm:
                var obj_id: int = int(fsm.get(obj_name))
                if fsm.player.carrying(obj_id):
                    _println(gate.msg)
                    return
        # `probability` gates are deliberately handled only in the
        # bumper-key dispatch above, not here. Rolling again at this
        # point would compound the probability (e.g. canon 95% → an
        # effective 99.75% bounce). On a miss the move proceeds
        # unconditionally to the topology lookup.
        if gate.check == "plover_squeeze" and fsm.plover_squeeze_blocked():
            _println(gate.msg)
            return
        if gate.check == "plant_huge" and not fsm.plant_is_huge():
            _println(gate.msg)
            return

    # Plover Room special: when leaving room 6 normally without
    # PLOVER, you can't. Stuck unless you use the magic word.
    # That's handled by the room having empty exits — the player
    # just gets the "you can't go that way" branch above.

    # Canon panic (advent.for STMT 2) — msg #130 + CLOCK2 cap @15.
    if fsm.endgame_closing() and dest >= 1 and dest <= 8:
        _println("A mysterious recorded voice groans into life and announces:")
        _println("    \"This exit is closed. Please leave via main office.\"")
        fsm.endgame_panic()
        return

    # Canon dwarf-blocks-exit (advent.for STMT 71) — msg #2.
    if _dwarf_at_room(dest):
        _println("A little dwarf with a big knife blocks your way.")
        return

    # Tell the FSM to move; the FSM's _verb_move parses the noun
    # to_int and moves the player. The bus walks first (darkness
    # might consume "move" if dark — actually no, darkness only
    # gates look/examine; CCA-canon: you CAN move in the dark,
    # but you might fall in a pit).
    fsm.set_old_loc2(fsm.get_old_loc())
    fsm.set_old_loc(current)
    var response: String = fsm.do_command("move", str(dest))
    # We use our own room descriptions (via FSM's look) rather
    # than the FSM's move-response — it's more atmospheric.
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_chest_hint()
    # Canon: rooms 20 and 21 fire `player.die()` inside _verb_move
    # on landing. Run death-cleanup here so items drop and the
    # revive prompt fires.
    _check_player_death()
    _print_room()

# ============================================================
# Bumper-rule evaluator (canon section-3 single-row resolver)
# ============================================================
# Evaluates one rule from the GATES chain at (room, verb) and
# returns true if the rule fired (caller should return). Returns
# false if preconditions weren't met, so the next rule in the
# chain (or topology fallback) is tried. See the cca/godot
# version for full inline docs on each `check` type.
func _try_bumper_rule(bg: Dictionary) -> bool:
    if bg.check == "always":
        _println(bg.msg)
        return true
    if bg.check == "rusty":
        if not fsm.rusty_door_oiled():
            _println(bg.msg)
            return true
        return false
    if bg.check == "snake":
        if fsm.snake.is_blocking():
            _println(bg.msg)
            return true
        return false
    if bg.check == "probability":
        if (rng.randi() % 100) < bg.pct:
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    if bg.check == "carrying":
        var bobj: String = bg.get("obj", "")
        if bobj != "" and bobj in fsm:
            var boid: int = int(fsm.get(bobj))
            if fsm.player.carrying(boid):
                if "dest" in bg:
                    _walk_to_dest(int(bg.dest))
                else:
                    _println(bg.msg)
                return true
        return false
    # "bridge" — fires while crystal bridge is NOT built. Used
    # for fissure-jump-to-death (canon `17/27 412021 7` → walk
    # to 21) and fissure-no-cross bumpers (canon `17/27 412597`).
    if bg.check == "bridge":
        if not fsm.bridge_built():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # "dragon_killed" — fires after dragon slain. Used for the
    # post-kill shortcut rows (canon `69/74 331120` → walk to
    # canon 120, the connecting canyon).
    if bg.check == "dragon_killed":
        if not fsm.dragon_alive():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # "chasm_collapsed" — fires after the bear-falls-bridge
    # sequence sets the Adventure FSM's troll_bridge_collapsed flag
    # (driver intercept in _handle_movement when player crosses
    # 117↔122 with bear in $Following).
    if bg.check == "chasm_collapsed":
        if fsm.troll_bridge_collapsed():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    return false

func _walk_to_dest(dest_room: int) -> void:
    fsm.set_old_loc2(fsm.get_old_loc())
    fsm.set_old_loc(fsm.player_room())
    var resp: String = fsm.do_command("move", str(dest_room))
    _println(resp)
    # Canon STMT 6010 — bumper-walks advance the dwarf turn too.
    _step_dwarves()
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_dwarf_axe()
    _check_player_death()
    _maybe_print_room_after_move()

# ============================================================
# Dark-room pit-fall hazard (canon CCA)
# ============================================================
# Returns true if the hazard fired (warning emitted *or* player
# died), in which case the caller short-circuits the rest of
# command handling. The "warn first, kill on the next attempt"
# pattern matches Crowther/Woods canon: the player gets exactly
# one free turn after entering a dark room before the 35% pit-
# fall roll starts.
func _check_dark_pit_hazard() -> bool:
    var current: int = fsm.player_room()
    if not fsm._room_is_dark(current):
        if fsm.dark_warned_room() != -1:
            fsm.clear_dark_warning()
        return false
    if current != fsm.dark_warned_room():
        _println("It is now pitch dark. If you proceed you will likely fall into a pit.")
        fsm.set_dark_warned_room(current)
        return true
    if (rng.randi() % 100) < DARK_PIT_PCT:
        _println("You fell into a pit and broke every bone in your body!")
        fsm.player.die()
        return true
    return false

# Returns true if any stalking dwarf is currently at `room`.
# Used by _handle_movement to block exit toward a dwarf-occupied
# room (canon msg #2).
func _dwarf_at_room(room: int) -> bool:
    if fsm.dwarf1.get_state() == "stalking" and fsm.dwarf1.get_room() == room:
        return true
    if fsm.dwarf2.get_state() == "stalking" and fsm.dwarf2.get_room() == room:
        return true
    if fsm.dwarf3.get_state() == "stalking" and fsm.dwarf3.get_room() == room:
        return true
    if fsm.dwarf4.get_state() == "stalking" and fsm.dwarf4.get_room() == room:
        return true
    if fsm.dwarf5.get_state() == "stalking" and fsm.dwarf5.get_room() == room:
        return true
    return false

# ============================================================
# Per-turn consequences
# ============================================================
func _check_pirate_steal() -> void:
    # V1.2 Phase 0.10 — Pirate FSM is the source of truth for
    # "stalking vs already stole" (the latter == $Vanished).
    if fsm.pirate_state() != "stalking":
        return
    # The FSM does the cross-cutting work: rolls the steal, picks
    # a treasure deterministically, and reappears it in the chest
    # room (room 18). Driver just renders.
    var msg: String = fsm.pirate_attempt_steal()
    if msg != "":
        _println("[color=#cc8855][i]%s[/i][/color]" % msg)
        return
    _check_pirate_rustle()

# Canon msg #127 (advent.for STMT 6080-ish): ~20% per-turn
# rustling-noise hint while pirate is active in deep cave.
func _check_pirate_rustle() -> void:
    if fsm.pirate_state() != "stalking":
        return
    if fsm.player_room() < 15:
        return
    if (rng.randi() % 100) < 20:
        _println("[color=#cc8855][i]There are faint rustling noises from the darkness behind you.[/i][/color]")

func _check_lamp_warnings() -> void:
    # V1.2 Phase 0.6 — canon STMT 12000/12200 variant selection
    # moved onto Adventure. See cca/godot/scripts/driver.gd.
    var msg: String = fsm.lamp_warning_text()
    if msg != "":
        _println("[color=#ddaa66]%s[/color]" % msg)
    # Canon msg #185 forced quit — lamp out + above-ground.
    if fsm.lamp_out_aboveground():
        _println("[color=#cc7777][b]There's not much point in wandering around out here, and you can't explore the cave without a lamp. So let's just call it a day.[/b][/color]")
        if is_inside_tree():
            await get_tree().create_timer(2.0).timeout
            get_tree().quit()

func _check_dwarf_axe() -> void:
    # Canon STMT 6010-6030 multi-dwarf prose ladder. Mirrors
    # cca/godot/scripts/driver.gd:_check_dwarf_axe — see that
    # file for the full ladder commentary.
    var dtotal: int = fsm.dwarf_count_in_room()
    var attack: int = fsm.dwarf_attack_count()
    var stick:  int = fsm.dwarf_hit_count()
    fsm.dwarf_threw_axe()
    fsm.dwarf_threw_and_missed()
    if dtotal == 0:
        return
    if not fsm.is_dwarf_first_encounter_done():
        fsm.mark_dwarf_first_encounter_done()
    if dtotal == 1:
        _println("[color=#cc7777][i]There is a threatening little dwarf in the room with you![/i][/color]")
    else:
        _println("[color=#cc7777][i]There are %d threatening little dwarves in the room with you.[/i][/color]" % dtotal)
    if attack == 0:
        return
    if attack == 1:
        _println("[color=#cc7777][i]One sharp nasty knife is thrown at you![/i][/color]")
        if stick == 0:
            _println("[color=#cc7777][i]It misses![/i][/color]")
        else:
            _println("[color=#cc7777][i]It gets you![/i][/color]")
        return
    _println("[color=#cc7777][i]%d of them throw knives at you![/i][/color]" % attack)
    if stick == 0:
        _println("[color=#cc7777][i]None of them hit you![/i][/color]")
    elif stick == 1:
        _println("[color=#cc7777][i]One of them gets you![/i][/color]")
    else:
        _println("[color=#cc7777][i]%d of them get you![/i][/color]" % stick)

# Canon chest-only-outstanding hint (advent.for STMT 6020, msg
# #186). Fires once when 14 of 15 treasures are deposited and
# the chest is still missing.
func _check_chest_hint() -> void:
    if fsm.is_chest_hint_done():
        return
    if fsm.chest.is_deposited():
        return
    if fsm.player.carrying(CHEST_ID):
        return
    if fsm.treasures_deposited() < 14:
        return
    fsm.mark_chest_hint_done()
    _println("There are faint rustling noises from the darkness behind you. As you")
    _println("turn toward them, the beam of your lamp falls across a bearded pirate.")
    _println("He is carrying a large chest. \"Shiver me timbers!\" he cries, \"I've")
    _println("been spotted! I'd best hie meself off to the maze to hide me chest!\"")
    _println("With that, he vanishes into the gloom.")

func _check_player_death() -> void:
    if prompts.is_active():
        return
    var s: String = fsm.player_state()
    if s == "dead" or s == "permadead":
        # Canon: every carried item drops at the death room. The
        # Player FSM's $Dead state returns false for carrying()
        # but the individual _item / Treasure FSMs need an
        # explicit transition (the inventory-consistency
        # divergence RFC-0001's state-space search caught).
        _drop_inventory_at_death_room()
    if s == "dead":
        # Canon msg #131 — death during the closing-cave phase is
        # final. End the game instead of offering revive.
        if fsm.endgame_state() == "closing":
            _println("[color=#cc4444][b]It looks as though you're dead. Well, seeing as how it's so close to closing time anyway, I think we'll just call it a day.[/b][/color]")
            if is_inside_tree():
                await get_tree().create_timer(2.0).timeout
                Arcade.return_to_menu()
            return
        prompts.offer_revive()
        # Canon advent.for STMT 16000 — prompt prose owned by
        # Player FSM (V1.2 Phase 0.8).
        _println("[color=#cc4444]%s[/color]" % fsm.player.get_revive_prompt())
    elif s == "permadead":
        # Canon msg #86 — Player owns the prose.
        _println("[color=#cc4444][b]%s[/b][/color]" % fsm.player.get_permadeath_msg())
        await get_tree().create_timer(2.0).timeout
        Arcade.return_to_menu()

# Drop every carried Item / Treasure FSM at the player's current
# room. Called from _check_player_death; see driver.gd's matching
# function for the design rationale (RFC-0001 inventory-on-death
# fix).
func _drop_inventory_at_death_room() -> void:
    var here: int = fsm.player.get_room()
    for it in [fsm.rod_item, fsm.keys_item, fsm.bottle_item,
               fsm.cage_item, fsm.food_item, fsm.pillow_item,
               fsm.axe_item, fsm.clam_item, fsm.oyster_item,
               fsm.batteries_item, fsm.magazine_item,
               fsm.mark_rod_item, fsm.lamp_item]:
        if it.is_carried():
            it.try_drop(here)
    for t in [fsm.gold, fsm.silver, fsm.diamonds, fsm.jewelry,
              fsm.pearl, fsm.vase, fsm.eggs, fsm.trident,
              fsm.emerald, fsm.spices, fsm.chest, fsm.pyramid,
              fsm.rug, fsm.coins, fsm.chain]:
        if t.is_carried():
            t.try_drop(here)

var _last_endgame_state: String = "active"
# (V1.2 Phase 0.3) Closing-warning latches moved into Endgame
# FSM as substates $ClosingT25 / $ClosingT15 / $ClosingT5; driver
# reads fsm.pending_warning_threshold() and drains via
# fsm.clear_pending_warning(). See cca/godot/scripts/driver.gd.

func _check_endgame_phase_change() -> void:
    var s: String = fsm.endgame_state()
    if s != _last_endgame_state:
        _last_endgame_state = s
        if s == "closing":
            # Canon msg #129 verbatim. Closing-phase opens with the
            # canonical sepulchral voice announcement.
            _println("[color=#cc7777][b]A sepulchral voice reverberating through the cave, says, \"Cave closing soon. All adventurers exit immediately through main office.\"[/b][/color]")
        elif s == "in_repository":
            # Canon msg #132 verbatim — the cave-closes-shut prose.
            _println("[color=#cc7777][b]The sepulchral voice entones, \"The cave is now closed.\" As the echoes fade, there is a blinding flash of light (and a small puff of orange smoke). . . . As your eyes refocus, you look around and find...[/b][/color]")
            _println("[color=#aaaaaa][i](Try DETONATE.)[/i][/color]")
        elif s == "won":
            _println("[color=#88dd88][b]There is a loud explosion, and a twenty-foot hole appears in the far wall, burying the dwarves in the rubble. You march through the hole and find yourself in the main office, where a cheering band of friendly elves carry the conquering adventurer off into the sunset. (Final score: %d)[/b][/color]" % fsm.total_score())

    # Closing-phase crescendo via Endgame substates (V1.2 Phase 0.3).
    # T-15 and T-5 are port-only flavor (canon has just msg #129).
    var w: int = fsm.pending_warning_threshold()
    if w == 25 or w == 15:
        _println("[color=#cc7777][i]A sepulchral voice reverberating through the cave, says, \"Cave closing soon. All adventurers exit immediately through main office.\"[/i][/color]")
        fsm.clear_pending_warning()
    elif w == 5:
        _println("[color=#cc7777][b]A mysterious recorded voice groans into life and announces: \"This exit is closed. Please leave via main office.\"[/b][/color]")
        fsm.clear_pending_warning()

func _maybe_print_room_after_move() -> void:
    var current: int = fsm.player_room()
    if current != _last_room:
        _last_room = current
        if fsm.is_brief_mode() and _visited_rooms.has(current):
            return
        _visited_rooms[current] = true
        _print_room()

# ============================================================
# Room display
# ============================================================
func _print_room() -> void:
    _last_room = fsm.player_room()
    var desc: String = fsm.do_command("look", "")
    _println("[color=#aabbcc][b]%s[/b][/color]" % desc)
    # Canon Y2 whisper (advent.for line 808): 25% chance per
    # visit to room 33 prints msg #8.
    if _last_room == 33 and not fsm.endgame_closing() and (rng.randi() % 100) < 25:
        _println("A hollow voice says \"PLUGH\".")
    # Canon msg #3 first-dwarf-encounter (advent.for STMT 6000).
    if not fsm.is_dwarf_first_encounter_done() and _dwarf_at_room(_last_room):
        fsm.mark_dwarf_first_encounter_done()
        _println("A little dwarf just walked around a corner, saw you, threw a little")
        _println("axe at you which missed, cursed, and ran away.")

# Returns true if `obj_id` is visible in `room` — canon AT(OBJ).
# Used by FIND to fire msg #94 when the player asks for an
# object that's actually here.
func _object_in_room(obj_id: int, room: int) -> bool:
    match obj_id:
        BIRD_ID:        return fsm.bird.get_location() == room
        GOLD_ID:        return fsm.gold.get_location() == room
        SILVER_ID:      return fsm.silver.get_location() == room
        DIAMONDS_ID:    return fsm.diamonds.get_location() == room
        JEWELRY_ID:     return fsm.jewelry.get_location() == room
        PEARL_ID:       return fsm.pearl.get_location() == room
        VASE_ID:        return fsm.vase.get_location() == room
        EGGS_ID:        return fsm.eggs.get_location() == room
        TRIDENT_ID:     return fsm.trident.get_location() == room
        EMERALD_ID:     return fsm.emerald.get_location() == room
        SPICES_ID:      return fsm.spices.get_location() == room
        CHEST_ID:       return fsm.chest.get_location() == room
        PYRAMID_ID:     return fsm.pyramid.get_location() == room
        RUG_ID:         return fsm.rug.get_location() == room
        COINS_ID:       return fsm.coins.get_location() == room
        CHAIN_ID:       return fsm.chain.get_location() == room
        ROD_ID:         return fsm.rod_item.is_in_room(room)
        MARK_ROD_ID:    return fsm.mark_rod_item.is_in_room(room)
        KEYS_ID:        return fsm.keys_item.is_in_room(room)
        LAMP_ID:        return fsm.lamp_item.is_in_room(room)
        BOTTLE_ID:      return fsm.bottle_item.is_in_room(room)
        CAGE_ID:        return fsm.cage_item.is_in_room(room)
        FOOD_ID:        return fsm.food_item.is_in_room(room)
        PILLOW_ID:      return fsm.pillow_item.is_in_room(room)
        AXE_ID:         return fsm.axe_item.is_in_room(room)
        CLAM_ID:        return fsm.clam_item.is_in_room(room)
        OYSTER_ID:      return fsm.oyster_item.is_in_room(room)
        BATTERIES_ID:   return fsm.batteries_item.is_in_room(room)
        MAGAZINE_ID:    return fsm.magazine_item.is_in_room(room)
    return false

# Resolve a noun token to a port object ID, or 0 if no match.
func _resolve_object_id(noun: String) -> int:
    var n: String = noun.strip_edges().to_lower()
    if n == "":                                  return 0
    if n in ["bird"]:                            return BIRD_ID
    if n in ["chain"]:                           return CHAIN_ID
    if n in ["gold", "nugget", "gold nugget"]:   return GOLD_ID
    if n in ["silver", "bars", "silver bars"]:   return SILVER_ID
    if n in ["diamonds"]:                        return DIAMONDS_ID
    if n in ["jewelry"]:                         return JEWELRY_ID
    if n in ["pearl"]:                           return PEARL_ID
    if n in ["vase"]:                            return VASE_ID
    if n in ["eggs"]:                            return EGGS_ID
    if n in ["trident"]:                         return TRIDENT_ID
    if n in ["emerald"]:                         return EMERALD_ID
    if n in ["spices"]:                          return SPICES_ID
    if n in ["chest"]:                           return CHEST_ID
    if n in ["pyramid"]:                         return PYRAMID_ID
    if n in ["rug"]:                             return RUG_ID
    if n in ["coins"]:                           return COINS_ID
    if n in ["rod"]:                             return ROD_ID
    if n in ["keys"]:                            return KEYS_ID
    if n in ["lamp", "lantern"]:                 return LAMP_ID
    if n in ["bottle"]:                          return BOTTLE_ID
    if n in ["cage"]:                            return CAGE_ID
    if n in ["food"]:                            return FOOD_ID
    if n in ["pillow"]:                          return PILLOW_ID
    if n in ["axe"]:                             return AXE_ID
    if n in ["clam"]:                            return CLAM_ID
    if n in ["oyster"]:                          return OYSTER_ID
    if n in ["magazine"]:                        return MAGAZINE_ID
    if n in ["batteries"]:                       return BATTERIES_ID
    return 0

# ============================================================
# Inventory
# ============================================================
func _format_inventory() -> String:
    # Canon-aligned inventory (Don Woods 1977 short-name strings,
    # one item per line, "You are currently holding the following:"
    # header). Item-name strings are taken verbatim from the
    # canonical INVENTORY output where they exist; the few items
    # without a canon counterpart (statuette is port-only) keep
    # the port label.
    var items: Array = []

    # Bird + cage compound: canon shows "Little bird in cage" as
    # one entry when both are held, instead of listing the bare
    # cage and the bird separately. The cage stays in the
    # player's inventory after a release, so once the bird is
    # gone the player still carries the wicker cage.
    var has_bird: bool = fsm.player.carrying(BIRD_ID)
    var has_cage: bool = fsm.player.carrying(CAGE_ID)
    if has_bird and has_cage:
        items.append("  Little bird in cage")
    elif has_bird:
        items.append("  Little bird")
    elif has_cage:
        items.append("  Wicker cage")

    # The two black rods. Canon shows them with the same short
    # name on purpose (the player has to WAVE to tell them apart);
    # we keep the distinguishing tail so saves stay legible
    # without forcing the player to remember which they took.
    if fsm.player.carrying(ROD_ID):
        items.append("  Black rod with a rusty star on the end")
    if fsm.player.carrying(MARK_ROD_ID):
        items.append("  Black rod with a rusty mark on the end")

    if fsm.player.carrying(KEYS_ID):     items.append("  Set of keys")
    if fsm.player.carrying(LAMP_ID):     items.append("  Brass lantern")
    if fsm.player.carrying(BOTTLE_ID):
        # Canon obj#20/21/22: bottle label varies with contents.
        if fsm.bottle.has_water():
            items.append("  Water in the bottle")
        elif fsm.bottle.has_oil():
            items.append("  Oil in the bottle")
        else:
            items.append("  Small bottle")
    if fsm.player.carrying(FOOD_ID):     items.append("  Tasty food")
    if fsm.player.carrying(PILLOW_ID):   items.append("  Velvet pillow")
    if fsm.player.carrying(AXE_ID):      items.append("  Dwarf's axe")
    if fsm.player.carrying(CLAM_ID):     items.append("  Giant clam")
    if fsm.player.carrying(MAGAZINE_ID): items.append("  \"Spelunker Today\" magazine")
    if fsm.player.carrying(BATTERIES_ID): items.append("  Fresh batteries")

    # Treasures (canon names exactly).
    if fsm.player.carrying(GOLD_ID):     items.append("  Large gold nugget")
    if fsm.player.carrying(SILVER_ID):   items.append("  Bars of silver")
    if fsm.player.carrying(DIAMONDS_ID): items.append("  Several diamonds")
    if fsm.player.carrying(JEWELRY_ID):  items.append("  Precious jewelry")
    if fsm.player.carrying(PEARL_ID):    items.append("  Glistening pearl")
    # Vase has a $Broken state — show the canon "Worthless shards
    # of pottery" line in that case rather than the intact label.
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
## Save-file magic — see cca/godot/scripts/driver.gd for full doc.
static var _SAVE_MAGIC: PackedByteArray = PackedByteArray([67, 67, 65, 51])  # "CCA3"

func _save_game() -> void:
    var bytes: PackedByteArray = fsm.save_state()
    var f := FileAccess.open(_save_path, FileAccess.WRITE)
    if f == null:
        _println("Save failed.")
        return
    f.store_buffer(_SAVE_MAGIC)
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
    var raw := f.get_buffer(f.get_length())
    f.close()
    # Save-file format magic — see cca/godot/scripts/driver.gd
    # for full inline doc. Drops incompatible saves cleanly.
    if raw.size() < 4 or raw.slice(0, 4) != _SAVE_MAGIC:
        _println("Saved game is from an older version and is no longer compatible. Starting fresh.")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
        _print_welcome()
        _print_room()
        return
    var bytes := raw.slice(4)
    fsm.restore_state(bytes)
    # Canon SAVED latch (advent.for STMT 6010 line 777) — dwarves
    # snap to DFLAG=20 on next attack tick.
    fsm.mark_loaded_from_save()
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
    # Canon msg #1 verbatim — the 1977 Don Woods intro with the
    # Crowther/Woods attribution already baked in at the bottom.
    # Mirrors cca/godot/scripts/driver.gd:_print_welcome.
    var art: String = (
        "[color=#a89878]"
        + "                       __\n"
        + "                      /  \\\n"
        + "                     /    \\\n"
        + "                    /      \\\n"
        + "                   /________\\\n"
        + "                   |  __ __  |\n"
        + "                   | |..|..| |\n"
        + "                   | |..|..| |\n"
        + "                   |_|..|..|_|\n"
        + "                   |         |\n"
        + "                   |   ___   |\n"
        + "                   |  |...|  |\n"
        + "                   |  |...|  |\n"
        + "                   |__|...|__|\n"
        + " ^  ^  ^  ^  ^  ^  ===========  ^  ^  ^  ^  ^  ^\n"
        + " | | | | | | | | |             | | | | | | | | |\n"
        + "                                ~~~~~~~~~~~~~~~~\n"
        + "  ~~~  forest  ~~~              ~~  stream  ~~~~\n"
        + "[/color]"
    )
    _println(art)
    _println("Somewhere nearby is Colossal Cave, where others have found fortunes in treasure and gold, though it is rumored that some who enter are never seen again. Magic is said to work in the cave. I will be your eyes and hands. Direct me with commands of 1 or 2 words. I should warn you that I look at only the first five letters of each word, so you'll have to enter \"NORTHEAST\" as \"NE\" to distinguish it from \"NORTH\". (Should you get stuck, type \"HELP\" for some general hints. For information on how to end your adventure, etc., type \"INFO\".)")
    _println("                      - - -")
    _println("This program was originally developed by Willie Crowther. Most of the features of the current program were added by Don Woods (DON @ SU-AI). Contact Don if you have any questions, comments, etc.")
    # Canon msg #65 — opening prompt.
    _println("Welcome to Adventure!! Would you like instructions?")
    _println("Type HELP for a list of commands, or press Enter to begin.")
    _println("[b]Cabinet keys:[/b] [b]F5[/b] quick-save, [b]F9[/b] quick-load, [b]Esc[/b] save/quit dialog.")

# Port-only easter egg — Will Crowther's Bedquilt cave map (1972).
# Mirrors cca/godot/scripts/driver.gd:_print_crowther_map. Triggered
# by the MAP verb at the well-house or in the deep cave.
func _print_crowther_map() -> void:
    var map: String = (
        "[color=#a89878]"
        + "                                                       \n"
        + "      W. CROWTHER -- BEDQUILT  MAP -- 1972 (RECONSTRUCTED)\n"
        + "      ====================================================\n"
        + "                                                       \n"
        + "                          .-- Hall of Mists --.        \n"
        + "                          |                   |        \n"
        + "                          v                   v        \n"
        + "                       Slab Rm           Mist Hall     \n"
        + "                          |                   |        \n"
        + "                          '---->  BEDQUILT  <-'        \n"
        + "                                  (canon 65)           \n"
        + "                                     |                 \n"
        + "                  .------------------+-------------.   \n"
        + "                  |              |                 |   \n"
        + "                  v              v                 v   \n"
        + "             Y2 marker     Mt King Hall      Anteroom  \n"
        + "                  |              |                 |   \n"
        + "                  |              v                 v   \n"
        + "                  |        Snake Passage    Shell Room \n"
        + "                  |                                |   \n"
        + "                  v                                v   \n"
        + "             Twopit Rm                      The Oyster \n"
        + "                  |                                    \n"
        + "        .---------+---------.                          \n"
        + "        |                   |                          \n"
        + "        v                   v                          \n"
        + "    East Pit             West Pit -- plant ascends     \n"
        + "    (oil pool)           (canon 25)        |           \n"
        + "                                           v           \n"
        + "                                       Giant Room      \n"
        + "                                           |           \n"
        + "                                           v           \n"
        + "                                      Repository       \n"
        + "                                                       \n"
        + "      ----------------------------------------------   \n"
        + "      \"Most of the passages turn, and leaving a room   \n"
        + "       to the north does not guarantee entering the    \n"
        + "       next from the south.\"  -- W. Crowther, 1976     \n"
        + "      ----------------------------------------------   \n"
        + "[/color]"
    )
    _println(map)

# Opens [url=...] BBCode links in the player's default browser.
# `meta` arrives as a Variant (the bare url string from BBCode).
func _on_meta_clicked(meta: Variant) -> void:
    if meta is String:
        OS.shell_open(meta)

func _print_help() -> void:
    # Canon msg #51 verbatim — Don Woods 1977 HELP output. The
    # cabinet keys footer is appended below as port-only flavor
    # since arcade-mode players need to know about F5/F9/Esc.
    _println("I know of places, actions, and things. Most of my vocabulary describes places and is used to move you there. To move, try words like FOREST, BUILDING, DOWNSTREAM, ENTER, EAST, WEST, NORTH, SOUTH, UP, or DOWN. I know about a few special objects, like a black rod hidden in the cave. These objects can be manipulated using some of the action words that I know. Usually you will need to give both the object and action words (in either order), but sometimes I can infer the object from the verb alone. Some objects also imply verbs; in particular, \"INVENTORY\" implies \"TAKE INVENTORY\", which causes me to give you a list of what you're carrying. The objects have side effects; for instance, the rod scares the bird. Usually people having trouble moving just need to try a few more words. Usually people trying unsuccessfully to manipulate an object are attempting something beyond their (or my!) capabilities and should try a completely different tack. To speed the game you can sometimes move long distances with a single word. For example, \"BUILDING\" usually gets you to the building from anywhere above ground except when lost in the forest. Also, note that cave passages turn a lot, and that leaving a room to the north does not guarantee entering the next from the south. Good luck!")
    _println("[b]Cabinet keys:[/b] [b]F5[/b] quick-save, [b]F9[/b] quick-load, [b]Esc[/b] save/quit dialog.")

func _print_info() -> void:
    # Canon msg #142 verbatim — Don Woods 1977 INFO output.
    _println("If you want to end your adventure early, say \"QUIT\". To suspend your adventure such that you can continue later, say \"SUSPEND\" (or \"PAUSE\" or \"SAVE\"). To see what hours the cave is normally open, say \"HOURS\". To see how well you're doing, say \"SCORE\". To get full credit for a treasure, you must have left it safely in the building, though you get partial credit just for locating it. You lose points for getting killed, or for quitting, though the former costs you more. There are also points based on how much (if any) of the cave you've managed to explore; in particular, there is a large bonus just for getting in (to distinguish the beginners from the rest of the pack), and there are other ways to determine whether you've been through some of the more harrowing sections. If you think you've found all the treasures, just keep exploring for a while. If nothing interesting happens, you haven't found them all yet. If something interesting *does* happen, it means you're getting a bonus and have an opportunity to garner many more points in the master's section. I may occasionally offer hints if you seem to be having trouble. If I do, I'll warn you in advance how much it will affect your score to accept the hints. Finally, to save paper, you may specify \"BRIEF\", which tells me never to repeat the full description of a place unless you explicitly ask me to.")

# ============================================================
# Cabinet integration: Esc opens the Save/Quit dialog FSM.
#
# The dialog FSM (ExitDialog in arcade/frame/dialog.fgd) owns
# the modal logic. The driver:
#   - opens it on Esc when no dialog is active
#   - feeds key events as confirm_quit / confirm_save_quit /
#     cancel based on which key was pressed
#   - reads last_action() after each event and acts on it
# Key bindings (cabinet-wide convention — Enter is the SAFE
# default everywhere):
#   Enter / Space  → confirm_save_quit (default — preserve work)
#   Q              → confirm_quit (discard, return to menu)
#   Esc            → cancel back to game
#
# Outside the dialog, F5 / F9 are the standard quick-save /
# quick-load shortcuts (Half-Life / Skyrim convention). They
# call the same _save_game() / _load_game() handlers the typed
# SAVE / LOAD verbs do, so all three paths converge.
# ============================================================
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed):
        return

    if exit_dialog.is_open():
        get_viewport().set_input_as_handled()
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
            exit_dialog.confirm_save_quit()
        elif event.keycode == KEY_Q:
            exit_dialog.confirm_quit()
        elif event.keycode == KEY_ESCAPE:
            exit_dialog.cancel()
        else:
            return     # other keys: stay in dialog
        # Resolve whichever action just landed.
        match exit_dialog.last_action():
            "quit":
                Arcade.return_to_menu()
            "save_quit":
                _save_game()
                Arcade.return_to_menu()
            "cancel":
                _hide_exit_dialog()
        return

    if event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        exit_dialog.open()
        _show_exit_dialog()
        return

    if event.keycode == KEY_F5:
        get_viewport().set_input_as_handled()
        _save_game()
        return

    if event.keycode == KEY_F9:
        get_viewport().set_input_as_handled()
        _load_game()
        return

func _show_exit_dialog() -> void:
    label_exit_dialog.visible = true
    # Take focus off the LineEdit so its keystrokes don't fight
    # the dialog handler. We restore on cancel.
    if input != null:
        input.release_focus()

func _hide_exit_dialog() -> void:
    label_exit_dialog.visible = false
    if input != null:
        # Defer the regrab — synchronous grab_focus() inside the
        # _input signal handler doesn't stick on every Godot 4.x
        # version (same pattern as _on_text_submitted at line ~387).
        input.call_deferred("grab_focus")

# When the application window regains focus (alt-tab back, click
# on a different app and return, etc.), Godot doesn't restore
# which Control had keyboard focus before — so the LineEdit
# stops accepting keystrokes until the player clicks it again.
# We listen for the focus-in notification and re-grab.
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN:
        if input != null:
            input.call_deferred("grab_focus")
