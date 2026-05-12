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
    # Canon endgame verbs (advent.for STMT 9230 / 9280 / 9290).
    # BLAST is the canon win-path: in the repository, fires a
    # BONUS-bearing detonation. WAKE and BREAK MIRROR are
    # closed-only deaths. Each routes through a driver handler
    # that consults endgame state + rod2 location and dispatches
    # to the matching FSM method.
    "blast": "blast", "detonate": "blast",
    "wake": "wake",
    # Canon flavor verbs that the FSM doesn't know about. Each
    # is a small driver-side handler producing canon-aligned
    # prose; some (FIND, SAY) consult FSM state but most are
    # purely textual.
    "find": "find", "where": "find",
    "brief": "brief",
    "rub": "rub",
    "say": "say",
    # Canon BACK / RETREAT — driver-handled retreat to OLDLOC.
    "back": "back", "retreat": "back",
    "look": "look",
    # Canon CAVE (advent.for STMT 40) — purely informational verb:
    # outdoors → msg #57, indoors → msg #58.
    "cave": "cave",
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

# Canon BRIEF flag (advent.for STMT 8260 sets ABBNUM=10000 to
# suppress long-form descriptions after the first visit).
# Port interpretation: when brief_mode is true, revisits to
# rooms already in _visited_rooms skip the full description
# (the player just sees the next prompt). Typing LOOK still
# works to re-display.
var _brief_mode: bool = false
var _visited_rooms: Dictionary = {}

# Canon IWEST counter (advent.for line 901). When the player
# types "WEST" instead of "W" ten times, msg #17 fires once
# ("If you prefer, simply type W rather than WEST.").
var _iwest_count: int = 0

# Canon LOOK detail counter (advent.for STMT 30, var DETAIL).
# Canon prints msg #15 ("Sorry, but I am not allowed to give
# more detail.") on each of the first 3 LOOKs; subsequent
# LOOKs silently re-display the long-form room description.
var _look_detail_count: int = 0

# Canon BACK history (advent.for STMT 20-25, vars OLDLOC and
# OLDLC2). On a successful move, _old_loc2 ← _old_loc, then
# _old_loc ← previous-room. BACK uses _old_loc unless that
# room is forced-motion, in which case it falls back to
# _old_loc2 — matches canon's "if you BACK from a forced room,
# you go two rooms back."
var _old_loc: int = -1
var _old_loc2: int = -1

# Typed-input recall (Up/Down arrow keys at the prompt) and
# scrollback paging (PgUp/PgDn). Session-only ergonomic state —
# not part of save/restore, since it's about the player's typing
# rhythm, not the game world.
#
# `_input_history_idx == -1` means "sitting at a fresh edit
# buffer below the end of history"; Up moves back into history,
# Down from -1 is a no-op.
var _input_history: Array = []
var _input_history_idx: int = -1

# Canon msg #3 first-dwarf-encounter latch (advent.for STMT
# 6000). Canon narrates msg #3 on the DFLAG 1→2 transition: "A
# little dwarf just walked around a corner, saw you, threw a
# little axe at you which missed, cursed, and ran away." The port
# wakes the dwarves once at `_ready`, so we fire msg #3 the first
# time the player enters a room where a stalking dwarf is — same
# narrative beat, simpler trigger.
var _dwarf_first_encounter_done: bool = false

# Canon dwarf movement RNG. Each turn, every stalking dwarf
# walks one step along the canon section-3 travel graph. We
# pick a random non-backtrack non-surface destination per
# canon STMT 6010-6030. The seed is set in _ready() so playthroughs
# replay byte-identical from a saved game.
var _dwarf_walk_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Canon OYSTER hint chain (advent.dat msgs #192/193/194). READ
# OYSTER on the in-place oyster (post-clam-break) costs 10 points
# but reveals the magic-words hint. Canon flow:
#   READ OYSTER (first time)  → msg #192 prompt (Y/N, 10-pt cost)
#   YES                        → msg #193 reveal + 10-pt deduction
#   NO                         → cancel, no penalty
#   READ OYSTER (after reveal) → msg #194 ("same thing")
var _oyster_prompt_active: bool = false
var _oyster_revealed: bool = false

# Canon hint Y/N flow (advent.for STMT 6020 + msgs #18/#20/#62/
# #176/#178/#180). When a hint becomes eligible (player has been
# in the trigger condition for the threshold turns), the game
# canonically asks Y/N before revealing the payload. On YES the
# payload fires + points deduct; on NO no penalty. Each hint is
# only auto-prompted once per session (the `_hint_prompted` set
# latches the first prompt regardless of the answer).
#
# Names match the Hint FSM's keys: cave / bird / snake / maze /
# plover / witts. The prompt msg # / payload msg # mapping:
#   cave   → prompt #62  / payload #63
#   bird   → prompt #18  / payload #19
#   snake  → prompt #20  / payload #21
#   maze   → prompt #176 / payload #177
#   plover → prompt #178 / payload #179
#   witts  → prompt #180 / payload #181
const HINT_PROMPT_MSGS: Dictionary = {
    "cave":   "Are you trying to get into the cave?",
    "bird":   "Are you trying to catch the bird?",
    "snake":  "Are you trying to somehow deal with the snake?",
    "maze":   "Do you need help getting out of the maze?",
    "plover": "Are you trying to explore beyond the Plover Room?",
    "witts":  "Do you need help getting out of here?",
}
const HINT_NAMES: Array = ["cave", "bird", "snake", "maze", "plover", "witts"]
var _hint_prompted: Dictionary = {}    # name -> true once auto-offered
var _hint_pending: String = ""         # name of hint awaiting YES/NO, "" if none

# Canon chest-only-outstanding hint latch (advent.for STMT 6020,
# canon msg #186). When the player has 14 of 15 treasures
# deposited and the chest is the only one missing — and the
# chest is still in the pirate's stash, not yet in inventory —
# the canon "spotted pirate" message fires once, pointing the
# player toward the maze.
var _chest_hint_done: bool = false

# Canon forced-motion rooms (cond=2 per advent.for line 393).
# These rooms auto-bounce on entry; BACK from a non-forced
# room into one of these would re-fire the bounce, so canon
# skips them and uses _old_loc2 instead.
const FORCED_ROOMS := [16, 22, 26, 32, 40, 59, 79, 89, 90, 113]

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
    # `if verb == "extinguish"` keep matching, and so that gate
    # keys like "15:passage" (gold-blocks-steps) match against
    # the full canonical form rather than the truncated stub.
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
    # [url=...]...[/url] BBCode just emits meta_clicked; opening a
    # browser is on us. The welcome panel embeds the IF Archive
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
    # Godot 4.4+ added `keep_editing_on_text_submit`, defaulting
    # to false — every Enter press kicks the LineEdit out of
    # editing mode even though it stays focused. Without this
    # the player has to press Enter (or click) again before
    # each new command.
    # https://github.com/godotengine/godot/issues/101434
    input.keep_editing_on_text_submit = true
    # Up/Down recall typed history; PgUp/PgDn page the scroll
    # log. LineEdit ignores these keys for single-line editing,
    # so we intercept via gui_input before they bubble out.
    input.gui_input.connect(_on_input_gui_input)
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
    # Push the player's exact text into recall history (preserving
    # case), deduping immediate repeats.
    var cooked: String = text.strip_edges()
    if _input_history.is_empty() or _input_history.back() != cooked:
        _input_history.append(cooked)
    _input_history_idx = -1
    _process_input(trimmed)
    input.call_deferred("grab_focus")

# Up/Down/PgUp/PgDn at the LineEdit. Single-line LineEdit treats
# the arrow keys as no-ops — we repurpose them for shell-style
# command-history recall. PgUp/PgDn page the scroll log behind
# the prompt; the player's caret stays in the input.
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

# Walk the recall pointer by `direction` (-1 = older, +1 = newer)
# and replace the LineEdit text with the recalled command. Going
# past the newest entry restores a blank edit buffer.
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

# Page the scroll log up/down by one viewport. RichTextLabel
# would do this natively if it had focus, but the LineEdit owns
# focus permanently, so we drive the v-scrollbar directly.
func _scroll_output(direction: int) -> void:
    var sb: ScrollBar = output.get_v_scroll_bar()
    if sb == null:
        return
    var page: float = max(sb.page, 100.0)
    sb.value = sb.value + direction * page

func _process_input(text: String) -> void:
    # Canon WEST counter (advent.for line 901). Counts raw
    # "WEST" tokens before they get normalized to "west" by
    # the synonym table. On the 10th WEST, fire canon msg #17
    # one-shot. The word "w" doesn't trigger.
    var raw_first: String = text.strip_edges().split(" ", false)[0] if not text.strip_edges().is_empty() else ""
    if raw_first == "west":
        _iwest_count = _iwest_count + 1
        if _iwest_count == 10:
            _println("If you prefer, simply type W rather than WEST.")

    var parsed := _parse(text)
    var verb: String = parsed[0]
    var noun: String = parsed[1]

    if verb == "":
        # Canon msg #195 — parser fallback for whitespace-only input.
        _println("I'm afraid I don't understand.")
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

    # Canon hint Y/N flow. YES emits the payload + deducts the
    # per-hint cost (handled inside fsm.request_hint); NO emits
    # canon msg #54 ("OK"). Any other verb cancels the prompt and
    # falls through to normal processing.
    if _hint_pending != "":
        var hint_name: String = _hint_pending
        _hint_pending = ""
        if verb == "yes":
            _println(fsm.request_hint(hint_name))
            return
        if verb == "no":
            # Canon msg #54.
            _println("OK")
            return
        # Fall through to normal verb processing.

    # Canon oyster-clue Y/N prompt (advent.dat msg #192). Player
    # has READ OYSTER on the in-place oyster; answering YES costs
    # 10 points and reveals msg #193, NO cancels with no penalty.
    if _oyster_prompt_active:
        if verb == "yes":
            _oyster_prompt_active = false
            _oyster_revealed = true
            _println("It says, \"There is something strange about this place, such that one")
            _println("of the words I've always known now has a new effect.\"")
            # Canon 10-point cost for the oyster clue (advent.for
            # SPK=192/193 chain). Hits both the per-component
            # ledger and the aggregate score so the score line
            # remains consistent.
            fsm.score_hints = fsm.score_hints - 10
            fsm.real_score = fsm.real_score - 10
            return
        if verb == "no":
            _oyster_prompt_active = false
            _println("OK.")
            return
        _oyster_prompt_active = false
        # Any other answer cancels the prompt and falls through.

    if _awaiting_revive:
        if verb == "yes":
            # Canon advent.for STMT 16100: revive-text varies by
            # death count via msg #82/#84 (msg #86 covers the
            # final out-of-magic case as the prompt itself).
            var prior_deaths: int = fsm.player.get_deaths()
            fsm.player.revive()
            _awaiting_revive = false
            if prior_deaths == 1:
                # Canon msg #82.
                _println("[color=#88dd88]All right. But don't blame me if something goes wr......")
                _println("                --- POOF!! ---")
                _println("You are engulfed in a cloud of orange smoke. Coughing and gasping,")
                _println("you emerge from the smoke and find....[/color]")
            elif prior_deaths == 2:
                # Canon msg #84.
                _println("[color=#88dd88]Okay, now where did I put my orange smoke?....   >POOF!<")
                _println("Everything disappears in a dense cloud of orange smoke.[/color]")
            else:
                # 3rd revive — out of orange smoke; canon
                # transitions to msg #86 (handled in $Permadead
                # branch). Defensive: still revive if reached.
                _println("[color=#88dd88]OK[/color]")
            _last_room = -1   # force room re-print
            _print_room()
            return
        if verb == "no":
            _awaiting_revive = false
            # Canon msg #86 — same line as the "out of smoke"
            # giving-up text from the player declining help.
            _println("[color=#cc4444]Okay, if you're so smart, do it yourself! I'm leaving![/color]")
            # is_inside_tree guard: headless tests instantiate the
            # driver bare (no scene tree); skip the dramatic pause +
            # quit there so the test can keep running.
            if is_inside_tree():
                await get_tree().create_timer(2.0).timeout
                get_tree().quit()
            return
        # advent.for FORMAT(/' Please answer the question.') — canon
        # prose for ambiguous yes/no input during the revive prompt.
        _println("Please answer the question.")
        return

    # ----- UI-only verbs (driver-handled, never reach the FSM) -----
    # Every turn-taking intercept routes through _post_intercept_tick
    # at the end so the canon per-turn checks (dwarf movement, lamp
    # battery, hint observation, pirate steal) fire regardless of
    # which verb was handled. Non-turn UI verbs (HOURS / WIZARD /
    # MAINT / SUSPEND) opt out via _handle_ui_verb's own logic.
    if _handle_ui_verb(verb, noun): _post_intercept_tick(); return

    # ----- Canon bear-on-bridge cross (msg #162) -----
    if _intercept_bridge_cross(verb): _post_intercept_tick(); return

    # ----- Bumper rules + dark-pit hazard -----
    if _dispatch_bumper(verb): _post_intercept_tick(); return
    if verb in MOTION_VERBS and _check_dark_pit_hazard(): _post_intercept_tick(); return

    # ENTER STREAM/WATER must precede DIRECTIONS — "enter" is in
    # DIRECTIONS, so the intercept has to win first.
    if _intercept_enter_stream(verb, noun): _post_intercept_tick(); return
    if verb in DIRECTIONS:
        # _handle_movement runs its own per-turn chain via _run_per_turn_checks.
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

    # ----- FSM dispatch + unknown-verb prose mix -----
    _dispatch_to_fsm(verb, noun)

    # ----- Per-turn check chain -----
    _run_per_turn_checks()

# Per-turn tick for paths where a verb intercept handled the
# input before the FSM dispatcher ran. Canon advances TURNS on
# any real action (LOOK, RUB, SAY, BLAST, TAKE, FEED, etc.), so
# dwarves walk + attack on every turn-taking verb — not just
# direction commands. The non-turn easter-egg verbs (HOURS,
# WIZARD, MAINT, SUSPEND) gate themselves out via _handle_ui_verb.
func _post_intercept_tick() -> void:
    _run_per_turn_checks()

# ============================================================
# Dispatch helpers
# ============================================================

# Canon "always-blocked" bumper gates and conditional rows.
# The (room, verb) key may map to either a single rule
# (Dictionary) or an ordered chain of rules (Array). Canon
# section 3 has multiple rows per (from, verb) for conditional
# dispatch — e.g. `19 35074 49` (35% → 74) followed by `19
# 211032 49` (snake-here → 32). The chain walks rules in order;
# the first that fires wins, the rest are skipped. Returns true
# if any rule fired (caller should `return`).
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

# FSM dispatch + unknown-verb canon randomization.
# Adventure's bus walks the aspects (DarknessGate may consume
# look/examine in dark rooms, MagicWordTeleport transforms
# xyzzy/plugh/plover into MOVE, etc.) and returns the response
# string. For unknown verbs, the FSM emits "I don't know how to
# '<verb>'." which we substitute with the canon STMT 3000 mix
# (msg #60/#61/#13 in 64/16/20 distribution).
func _dispatch_to_fsm(verb: String, noun: String) -> void:
    var response: String = fsm.do_command(verb, noun)
    if response.begins_with("I don't know how to '"):
        var roll1: int = randi() % 100
        var roll2: int = randi() % 100
        if roll2 < 20:
            response = "I don't understand that!"   # canon msg #13
        elif roll1 < 20:
            response = "What?"                       # canon msg #61
        else:
            response = "I don't know that word."     # canon msg #60
    _println(response)

# Per-turn check chain: lamp battery + endgame timer (in fsm.tick),
# pirate-steals, lamp warnings, endgame phase changes, dwarf axe
# hits, chest hint, player death, then re-print the room if the
# player has moved. Order matters — death must come last so the
# revive prompt has the latest state.
func _run_per_turn_checks() -> void:
    # Canon STMT 6010 — walk each stalking dwarf one step along the
    # canon section-3 travel graph BEFORE the FSM tick fires the
    # attack resolution. The driver owns the topology (room_exits)
    # so the walk lives here; the FSM tick reads the post-walk
    # positions to populate DTOTAL / ATTACK / STICK.
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

# Canon STMT 6010 dwarf-movement loop. Each stalking dwarf
# walks one step along the section-3 travel graph. Per canon:
#   - no backtracking to prev_room unless no other option
#   - no surface rooms (LOC < 15)
#   - no rooms outside the deep cave (LOC > 130)
#   - if the dwarf has SEEN the player and player is still in
#     the deep cave, the dwarf snaps to the player's room
#   - if player drops to the surface, the dwarf loses sight
#     and goes back to wandering
func _step_dwarves() -> void:
    var player_room: int = fsm.player_room()
    for i in [1, 2, 3, 4, 5]:
        # Skip hidden/dead dwarves. The Dwarf FSM's `get_room()`
        # returns -1 in those states, so the room lookup below
        # would fail anyway, but the state-string check is
        # cheaper and clearer.
        var d_state: String = _dwarf_state(i)
        if d_state != "stalking":
            continue
        var cur: int = fsm.dwarf_room_of(i)
        var prev: int = fsm.dwarf_prev_room_of(i)
        var was_seen: bool = fsm.dwarf_is_seen(i)
        var new_room: int = _pick_dwarf_destination(cur, prev, false)
        fsm.dwarf_step_to(i, new_room)
        # Canon DSEEN update — sticky while in deep cave; clears
        # when player surfaces.
        var now_at: int = fsm.dwarf_room_of(i)
        var now_prev: int = fsm.dwarf_prev_room_of(i)
        var saw_player: bool = (now_at == player_room) or (now_prev == player_room)
        var new_seen: bool = saw_player or (was_seen and player_room >= 15)
        if new_seen:
            fsm.dwarf_snap_to_player(i)
        elif player_room < 15:
            fsm.dwarf_unsee(i)
    # Canon dwarf #6 — the pirate. Walks the cave with the same
    # movement loop once activated (treasures_carried >= 3). The
    # pirate's room tracking lets the player encounter it
    # probabilistically along the canon section-3 graph, instead
    # of teleporting in from nowhere. The pirate-specific outcomes
    # (steal vs msg #127 rustling) resolve in _check_pirate_steal.
    if fsm.pirate.is_stalking():
        var p_cur: int = fsm.pirate_room()
        var p_prev: int = fsm.pirate_prev_room()
        var p_was_seen: bool = fsm.pirate_is_seen()
        # Pirate is canon-forbidden from additional rooms (BITSET 3)
        # but for V1 we use the same deep-cave filter as dwarves.
        var p_new: int = _pick_dwarf_destination(p_cur, p_prev, true)
        fsm.pirate_step_to(p_new)
        var p_at: int = fsm.pirate_room()
        var p_pat: int = fsm.pirate_prev_room()
        var p_saw: bool = (p_at == player_room) or (p_pat == player_room)
        var p_new_seen: bool = p_saw or (p_was_seen and player_room >= 15)
        if p_new_seen:
            fsm.pirate_snap_to_player()
        elif player_room < 15:
            fsm.pirate_unsee()

# Canon STMT 6012 destination picker. Builds the candidate list
# from the section-3 exits of `cur`, drops self-loops, prev_room
# (no backtrack), and rooms outside the deep cave (LOC < 15 or
# LOC > 130). For pirate-forbidden rooms (canon BITSET 3) we use
# the same conservative deep-cave bound for V1 — those rooms are
# the dark-room (101), dead ends, and a few flavor rooms canon
# explicitly excludes; the deep-cave bound captures most.
func _pick_dwarf_destination(cur: int, prev: int, is_pirate: bool) -> int:
    var candidates: Array = []
    for dest in room_exits.get(cur, {}).values():
        if dest == cur or dest == prev:
            continue
        if dest < 15 or dest > 130:
            continue
        if is_pirate and dest in FORBIDDEN_PIRATE_ROOMS:
            continue
        if dest in FORCED_ROOMS:
            continue
        if not candidates.has(dest):
            candidates.append(dest)
    if candidates.is_empty():
        # Canon "no alternative" fallback: backtrack to prev.
        return prev if prev != -1 else cur
    return candidates[_dwarf_walk_rng.randi() % candidates.size()]

# Canon BITSET(LOC,3) — rooms the pirate is canonically barred
# from. Mostly the dark-room and a few one-way-passage rooms.
# Conservative list for V1; expand if canon trace surfaces more.
const FORBIDDEN_PIRATE_ROOMS: Array = [101, 117, 122]

func _dwarf_state(idx: int) -> String:
    if idx == 1: return fsm.dwarf1.get_state()
    if idx == 2: return fsm.dwarf2.get_state()
    if idx == 3: return fsm.dwarf3.get_state()
    if idx == 4: return fsm.dwarf4.get_state()
    if idx == 5: return fsm.dwarf5.get_state()
    return "hidden"

# Canon hint Y/N auto-prompt. When a Hint FSM transitions to
# $Eligible (player has been in the trigger condition for N
# turns), fire the canon Y/N prompt one time. Subsequent
# eligibility on the same hint stays silent — the player still
# has the explicit HINT verb if they want to ask later.
func _check_hint_prompts() -> void:
    if _hint_pending != "":
        return
    for n in HINT_NAMES:
        if _hint_prompted.get(n, false):
            continue
        if fsm.hint_state(n) != "eligible":
            continue
        _hint_prompted[n] = true
        _hint_pending = n
        _println(HINT_PROMPT_MSGS[n])
        return  # only one prompt per turn

# ============================================================
# UI-only verbs (driver-handled, never reach the FSM)
# ============================================================
# Returns true if `verb` was a UI verb the driver fully handled
# (caller should `return`); false otherwise. Most branches emit
# canon msg + return; the BACK branch may delegate to
# `_handle_movement`. The matched verbs include canon UI primitives
# (help, info, score, inventory, save, load, quit, suspend, hint),
# canon flavor verbs that don't touch the FSM (hours, wizard,
# maint/magic, find, brief, rub, say, cave, look, back), and the
# endgame BLAST/WAKE pair.
func _handle_ui_verb(verb: String, noun: String) -> bool:
    match verb:
        "help":
            _print_help()
            return true
        "info":
            _print_info()
            return true
        "quit":
            # Canon msg #22 verbatim — standard QUIT confirmation.
            # (Canon also has msg #143 "Do you indeed wish to quit now?"
            # for the closing-cave variant; #22 fires for normal QUIT.)
            _quit_pending = true
            _println("Do you really want to quit now?")
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
            # Canon SUSPEND (advent.for STMT 8300). Original 1977
            # printed the "wait at least N minutes" warning and
            # called CIAO to write a core image; latency was an
            # anti-save-scum measure on the multi-user PDP-10.
            # Modern desktop port: honor the verb with the canon
            # prose plus a wink, then save instantly.
            _println("I can suspend your adventure for you so that you can resume later, but")
            _println("you will have to wait at least 45 minutes before continuing.")
            _println("")
            _println("... or not.")
            _save_game()
            return true
        "hint":
            var hint_name: String = noun if noun != "" else "bird"
            _println(fsm.request_hint(hint_name))
            return true
        "hours":
            # Canon HOURS (advent.for line 8310). 1977 printed the
            # PDP-10 timesharing schedule; on a desktop port the
            # cave is always available.
            _println("Colossal Cave is open all day, every day.")
            _println("(In the original 1977 PDP-10 release this verb")
            _println("printed the timesharing schedule during which")
            _println("non-wizards could play. On a desktop port the")
            _println("cave has no off-hours.)")
            return true
        "wizard":
            # Canon WIZARD (advent.for SUBROUTINE WIZARD). Original
            # 1977 ran a hashed-challenge auth dialogue (msgs
            # #16/#17/#19/#20). Port narrates the dialogue verbatim
            # and ends on canon msg #20 (the "charlatan" rebuff).
            _println("\"Are you a wizard?\"")
            _println("\"Prove it!  Say the magic word!\"")
            _println("\"That is not what I thought it was.  Do you know what I thought it was?\"")
            _println("\"Foo, you are nothing but a charlatan!\"")
            return true
        "maint", "magic":
            # Canon MAINT (advent.for SUBROUTINE MAINT). Original
            # 1977 let a wizard edit cave hours, magic word, MOTD,
            # demo length, suspend latency. On a desktop port none
            # of those exist — honor the verb with canon msg #1
            # (tall wizard in grey) gently rewritten + msg #20.
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
            # Canon BLAST (advent.for STMT 9230). Three outcomes
            # gated on (CLOSED, LOC, HERE(ROD2)):
            #   pre-CLOSED              → msg #67
            #   CLOSED, rod2 here       → blast_klutz, msg #135 (+25)
            #   CLOSED, LOC=115, no rod → blast_wrong_way, msg #134 (+30)
            #   CLOSED, otherwise       → blast_mastery, msg #133 (+45)
            # Each in-repository case awards the canon score bonus
            # via the matching FSM method, then transitions Endgame
            # to $Won.
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
            # Canon WAKE (advent.for STMT 9290). Pre-CLOSED: msg
            # #13 default. CLOSED: msg #199 + msg #136 (disturbed-
            # dwarves death).
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
            # Canon FIND (advent.for STMT 9190) priority ladder:
            #   TOTING(OBJ) → msg #24
            #   AT(OBJ)     → msg #94
            #   CLOSED      → msg #138
            #   else        → msg #59
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
            # Canon BRIEF (advent.for STMT 8260). Sets ABBNUM=10000
            # so room descriptions after the first visit are short.
            _brief_mode = true
            _println("Okay, from now on I'll only describe a place in full the first time")
            _println("you come to it. To get the full description, say LOOK.")
            return true
        "rub":
            # Canon RUB (advent.for STMT 9160). LAMP → msg #75;
            # anything else → msg #76.
            if noun == "lamp":
                _println("Rubbing the electric lamp is not particularly rewarding. Anyway, nothing exciting happens.")
            else:
                _println("Peculiar. Nothing unexpected happens.")
            return true
        "say":
            # Canon SAY (advent.for STMT 9030). Magic-word noun →
            # re-dispatch as that verb. Otherwise echo "Okay, X".
            if noun == "":
                _println("Say what?")
                return true
            if noun in ["xyzzy", "plugh", "plover", "fee", "fie", "foe", "foo"]:
                _process_input(noun)
                return true
            _println("Okay, \"%s\"." % noun)
            return true
        "cave":
            # Canon CAVE (advent.for STMT 40). Outdoors (canon ≤8)
            # → msg #57; indoors → msg #58.
            if fsm.player_room() <= 8:
                _println("I don't know where the cave is, but hereabouts no stream can run on the surface for long. I would try the stream.")
            else:
                _println("I need more detailed instructions to do that.")
            return true
        "look":
            # Canon LOOK (advent.for STMT 30). msg #15 first 3
            # times, then re-display normally.
            if _look_detail_count < 3:
                _println("Sorry, but I am not allowed to give more detail. I will repeat the long description of your location.")
                _look_detail_count = _look_detail_count + 1
            _last_room = -1                    # force re-print
            _visited_rooms.erase(fsm.player_room())
            _print_room()
            return true
        "back":
            # Canon BACK (advent.for STMT 20-25). Walk to OLDLOC
            # via an exit from current; OLDLC2 if OLDLOC is
            # forced-motion. msg #140 on no path.
            var bk_current: int = fsm.player_room()
            var bk_exits: Dictionary = room_exits.get(bk_current, {})
            if "back" in bk_exits:
                _handle_movement("back")
                return true
            var k: int = _old_loc
            if k in FORCED_ROOMS:
                k = _old_loc2
            if k < 0:
                _println("Sorry, but I no longer seem to remember how it was you got here.")
                return true
            if k == bk_current:
                _println("Where?")
                return true
            for bk_dir in bk_exits:
                if bk_exits[bk_dir] == k:
                    _handle_movement(bk_dir)
                    return true
            _println("Sorry, but I no longer seem to remember how it was you got here.")
            return true
    return false

# ============================================================
# Verb intercepts
# ============================================================
# Each `_intercept_*` returns true if the verb was handled (caller
# should `return`) and false if the input should fall through to
# the next intercept or the FSM. The dispatch order in
# `_process_input` is canon-significant — moving these around
# changes which canonical msg the player sees.

# Canon BREAK MIRROR (advent.for STMT 9280) — closed-only death.
# Pre-CLOSED, BREAK MIRROR returns the action default msg #146;
# the FSM's _verb_break doesn't know about MIRROR and would
# otherwise emit "I don't know how to break that."
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

# Canon DROP BIRD (advent.for STMT 9020). Canon distinguishes
# DROP (cage stays closed) from RELEASE (bird is freed first):
#   DROP BIRD at snake (bird still caged) → snake catches the
#     defenseless caged bird → msg #101, bird dies.
#   RELEASE BIRD at snake (bird out of cage) → bird attacks snake
#     successfully → msg #30, snake driven away.
# Both DROP and RELEASE at dragon → bird vaporized (msg #154).
# Anywhere else, drop-vs-release is functionally identical in
# the port's bird model, so we route through RELEASE.
func _intercept_drop_bird(verb: String, noun: String) -> bool:
    if verb != "drop" or noun != "bird":
        return false
    if not fsm.player.carrying(BIRD_ID):
        # Defer to release-bird's "aren't carrying" canon msg #29.
        _process_input("release bird")
        return true
    if fsm.player_room() == fsm.SNAKE_ROOM and fsm.snake.is_blocking():
        # Canon msg #101 verbatim. Bird dies in the cage; cage
        # remains (still in player inventory, but bird removed
        # via vanish()).
        fsm.bird.vanish()
        fsm.player.drop(BIRD_ID)
        _println("The snake has now devoured your bird.")
        return true
    # All other rooms: drop = release in the port's bird model.
    _process_input("release bird")
    return true

# Canon ATTACK/KILL BIRD (advent.for STMT 9120) — msg #137.
func _intercept_attack_bird(verb: String, noun: String) -> bool:
    if verb != "attack" or noun != "bird":
        return false
    _println("Oh, leave the poor unhappy bird alone.")
    return true

# Canon ATTACK BEAR (msgs #165/#166/#167). Outcome by bear state:
#   hungry           → msg #165 ("bare hands... bear hands??")
#   tame/following   → msg #166 ("only wants to be your friend")
#   released         → msg #167 ("poor thing is already dead")
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

# Canon TAKE KNIFE (msg #116) — dwarf knives vanish on impact.
func _intercept_take_knife(verb: String, noun: String) -> bool:
    if verb != "take" or noun != "knife":
        return false
    _println("The dwarves' knives vanish as they strike the walls of the cave.")
    return true

# Canon TAKE BEAR (msg #169) — bear is still chained.
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

# Canon UNLOCK CHAIN (msg #170) — without keys, chain stays
# locked. Returns false (fall-through to FSM) when keys are
# carried so the FSM's bear/chain handling runs.
func _intercept_unlock_chain(verb: String, noun: String) -> bool:
    if verb != "unlock" or noun != "chain":
        return false
    if not fsm.player.carrying(KEYS_ID):
        _println("The chain is still locked.")
        return true
    return false

# Canon msg #162 — bear-bridge collapse. If the player is at the
# troll bridge (117 or 122) and the bear is still in $Following
# (chain in inventory, never dropped at the troll), trying to
# cross sends both player and bear into the chasm. Bridge is
# permanently collapsed (one-shot terminal flag); subsequent
# JUMP attempts at 117/122 walk to canon 21 via the existing
# chasm_collapsed bumper rule. msg #161 ("There is no longer any
# way across the chasm.") fires for OVER/ACROSS/CROSS/NE/SW
# attempts at 117/122 after the bridge is gone — handled in the
# topology gate chain, not here.
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

# Canon ENTER STREAM / ENTER WATER (advent.for line 894-895) —
# msg #70. Must precede the DIRECTIONS check since "enter" is in
# DIRECTIONS and would otherwise route to _handle_movement.
func _intercept_enter_stream(verb: String, noun: String) -> bool:
    if verb != "enter":
        return false
    if noun != "stream" and noun != "water":
        return false
    _println("Your feet are now wet.")
    return true

# Canon TAKE on fixed scenery (msg #25) — "You can't be serious!"
# Stalactite gets msg #148 specifically (too far up to reach).
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

# Canon THROW AXE (advent.for STMT 9170). Intercepts dragon /
# troll / bear catches; returns false (falls through to FSM
# _verb_throw) for the dwarf-attack path.
func _intercept_throw_axe(verb: String, noun: String) -> bool:
    if verb != "throw" or noun != "axe":
        return false
    var here_room: int = fsm.player_room()
    if here_room == 119 and fsm.dragon_alive():
        # Canon msg #152.
        _println("The axe bounces harmlessly off the dragon's thick scales.")
        return true
    if here_room == 117 and fsm.troll.is_blocking_bridge():
        # Canon msg #158.
        _println("The troll deftly catches the axe, examines it carefully, and tosses")
        _println("it back, declaring, \"Good workmanship, but it's not valuable enough.\"")
        return true
    if here_room == 130 and fsm.bear_state() == "hungry":
        # Canon msg #164.
        _println("The axe misses and lands near the bear where you can't get at it.")
        return true
    return false

# Canon routine 302 — Plover-emerald drop. Side-effect only:
# falls through so the regular PLOVER teleport runs after via
# fsm.do_command. No bool return; caller doesn't gate on this.
func _intercept_plover_emerald(verb: String, noun: String) -> void:
    if verb != "plover":
        return
    var here_pl: int = fsm.player_room()
    if (here_pl == 33 or here_pl == 100) and fsm.player.carrying(EMERALD_ID):
        fsm.emerald.try_drop(here_pl)
        fsm.player.drop(EMERALD_ID)
        _println("OK")

# Canon CALM/TAME (verb 10, msg #14) — no-op flavor placeholder.
func _intercept_calm(verb: String, noun: String) -> bool:
    if verb != "calm" and verb != "tame":
        return false
    _println("I'm game. Would you care to explain how?")
    return true

# Canon EAT variants (advent.for STMT 9140). NPC nouns get the
# "ridiculous" rebuff; non-food nouns get canon msg #71. EAT
# FOOD or empty-noun falls through to the FSM.
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

# Canon FEED variants (advent.for STMT 9210/9212/9213). FEED
# DWARF bumps DFLAG and emits canon msg #103. FEED BEAR (and
# unknown nouns) falls through to FSM.
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

# Canon scenery EXAMINE/READ flavor (advent.dat section 5
# objects 6/13/15/23/25/26/27/29/36/37/40). Each noun is gated
# on the canonical room so it only resolves where canon expects.
func _intercept_scenery_read(verb: String, noun: String) -> bool:
    if verb != "read" and verb != "examine":
        return false
    var er: int = fsm.player_room()
    # ROD2 prop change (object 6) — pre-CLOSED rod / post-CLOSED dynamite.
    if noun == "rod" and fsm.mark_rod_here():
        if fsm.endgame_state() == "in_repository":
            _println("Peculiar. Nothing unexpected happens.")
        else:
            _println("A small black rod with a rusty mark on the end.")
        return true
    # STONE TABLET (object 13) at canon 101 → msg #196.
    if noun == "tablet" and er == 101:
        _println("A massive stone tablet imbedded in the wall reads:")
        _println("\"Congratulations on bringing light into the dark-room!\"")
        return true
    # MESSAGE in second maze (object 36) at canon 140 → msg #191.
    if noun == "message" and er == 140:
        _println("There is a message scrawled in the dust in a flowery script, reading:")
        _println("\"This is not the maze where the pirate leaves his treasure chest.\"")
        return true
    # OYSTER hint chain (object 15) — msgs #192/193/194 with Y/N
    # prompt + 10pt cost. Driver _oyster_prompt_active latch
    # picks up the YES/NO answer at top of _process_input.
    if noun == "oyster" and fsm.oyster_item.is_in_room(er):
        if _oyster_revealed:
            _println("It says the same thing it did before.")
            return true
        _oyster_prompt_active = true
        _println("Hmmm, this looks like a clue, which means it'll cost you 10 points to")
        _println("read it. Should I go ahead and read it anyway?")
        return true
    # MIRROR (object 23) at canon 109 (Mirror Canyon).
    if noun == "mirror" and er == 109:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    # SHADOWY FIGURE (object 27) at canon 35 / 110.
    if (noun == "figure" or noun == "shadow") and (er == 35 or er == 110):
        _println("The shadowy figure seems to be trying to attract your attention.")
        return true
    # STALACTITE (object 26) at canon 111.
    if noun == "stalactite" and er == 111:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    # CAVE DRAWINGS (object 29) at canon 97.
    if (noun == "drawings" or noun == "drawing") and er == 97:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    # VOLCANO/GEYSER (object 37) at canon 126.
    if (noun == "volcano" or noun == "geyser") and er == 126:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    # CARPET/MOSS (object 40) at canon 96.
    if (noun == "carpet" or noun == "moss") and er == 96:
        _println("Peculiar. Nothing unexpected happens.")
        return true
    # PHONY PLANT (object 25) at canon 23/35.
    if (noun == "plant" or noun == "plant2") and (er == 23 or er == 35):
        _println("There is a huge beanstalk growing out of the west pit up to the hole.")
        return true
    # Canon msg #63 — EXAMINE GRATE at the depression (canon 8).
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
    # Canon: the parser examines only the first 5 characters of
    # each verb (Don Woods 1977 startup banner: "I LOOK AT ONLY
    # THE FIRST FIVE LETTERS OF EACH WORD, SO YOU'LL HAVE TO ENTER
    # 'NORTHEAST' AS 'NE' TO DISTINGUISH IT FROM 'NORTH'."). We
    # mirror that for the verb token by truncating to 5 chars and
    # looking up against a pre-truncated synonym table, so the
    # canonical form dispatched downstream is still the full word.
    # Lazily populate the truncation table on first parse — for
    # production use _ready() runs first, but headless tests
    # construct Driver outside the scene tree, so _ready() is
    # never called and the table would be empty.
    if _verb_synonyms_5.is_empty():
        _build_verb_synonyms_5()
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
        # Canon msg #11 (advent.for): IN/OUT in rooms with no
        # canonical IN/OUT exit get the "I don't know in from out
        # here" rebuff rather than the generic no-exit msg.
        if direction == "in" or direction == "out":
            _println("I don't know in from out here. Use compass points or name something")
            _println("in the general direction you want to go.")
            return
        # Canon msg #10 (advent.for word table 7/36/37) — player-
        # relative motion verbs the parser can't resolve without
        # facing context. Fires only when the current room hasn't
        # mapped this verb to a specific direction (a handful of
        # rooms — canon 4 / 17 / 19 / 124 — do).
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
        if gate.check == "rusty" and not fsm.rusty_door_oiled():
            # Rusty iron door at canon 94 → 95. Blocks NORTH/ENTER/
            # CAVERN until POUR OIL transitions the door FSM.
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
        # Note: `probability` gates are deliberately NOT re-checked
        # here. The bumper-key dispatch above (which fires for
        # *every* verb, including DIRECTIONS) already rolled the
        # gate; if we got here, that roll missed, and the move
        # should proceed unconditionally to the topology lookup.
        # Re-rolling would compound the probability and produce a
        # 99.75% effective bounce instead of the canon 95%.

    # Plover Room special: when leaving room 6 normally without
    # PLOVER, you can't. Stuck unless you use the magic word.
    # That's handled by the room having empty exits — the player
    # just gets the "you can't go that way" branch above.

    # Canon panic (advent.for STMT 2): during $Closing, if the
    # player tries to move to a surface room (canon dest 1..8
    # excluding 0), msg #130 fires, the move is blocked, and
    # CLOCK2 caps at 15. Subsequent attempts re-emit msg #130
    # but don't re-cap (PANIC latch on the Endgame side).
    if fsm.endgame_closing() and dest >= 1 and dest <= 8:
        _println("A mysterious recorded voice groans into life and announces:")
        _println("    \"This exit is closed. Please leave via main office.\"")
        fsm.endgame_panic()
        return

    # Canon dwarf-blocks-exit (advent.for STMT 71): if a stalking
    # dwarf is at the destination room, msg #2 fires and the move
    # is blocked. Canon checks ODLOC (last-turn dwarf position +
    # DSEEN flag); the port simplifies to "any stalking dwarf at
    # dest blocks". Forced-motion rooms bypass this rule (canon
    # FORCED check), but the port's _walk_to_dest path handles
    # forced rooms separately so this is movement-only.
    if _dwarf_at_room(dest):
        _println("A little dwarf with a big knife blocks your way.")
        return

    # Tell the FSM to move; the FSM's _verb_move parses the noun
    # to_int and moves the player. The bus walks first (darkness
    # might consume "move" if dark — actually no, darkness only
    # gates look/examine; CCA-canon: you CAN move in the dark,
    # but you might fall in a pit).
    # Capture BACK history before the move fires.
    _old_loc2 = _old_loc
    _old_loc = current
    var response: String = fsm.do_command("move", str(dest))
    # We use our own room descriptions (via FSM's look) rather
    # than the FSM's move-response — it's more atmospheric.
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_chest_hint()
    _print_room()

# ============================================================
# Bumper-rule evaluator (canon section-3 single-row resolver)
# ============================================================
# Evaluates one rule from the GATES chain at (room, verb) and
# returns true if the rule fired (verb consumed; caller should
# return). Returns false if the rule's preconditions weren't met
# and the next rule in the chain (or topology fallback) should
# be tried.
#
# Each rule has a `check` field naming the test, plus optional
# `dest` (walk to room), `msg` (print and stay put), `pct`
# (probability percent), and `obj` (port-side ID accessor name).
# A rule with `dest` walks via fsm._verb_move so the destination
# room's entry handler fires (e.g. canon 20/21 deaths). A rule
# with `msg` only prints and returns. The exact fields each
# `check` understands are documented inline below.
func _try_bumper_rule(bg: Dictionary) -> bool:
    # "always" — unconditional bumper. Used for canon msg500 rows
    # like JUMP at the fissure, SLIT at the streambed, etc.
    if bg.check == "always":
        _println(bg.msg)
        return true
    # "rusty" — fires only while the rusty-door FSM is in the
    # un-oiled state. Once oiled, falls through so _handle_movement
    # walks the regular topology exit (94:enter / 94:cavern → 95).
    if bg.check == "rusty":
        if not fsm.rusty_door_oiled():
            _println(bg.msg)
            return true
        return false
    # "snake" — fires while the snake is blocking the canyon at
    # canon 19. Mirrored from _handle_movement's gate handler so
    # bumper-dispatch chains (e.g. 19:sw probability + snake) can
    # consult it. Falls through if snake gone.
    if bg.check == "snake":
        if fsm.snake.is_blocking():
            _println(bg.msg)
            return true
        return false
    # "probability" — canon's M*1000+N rows where M is in 1..99.
    # Roll once per attempt. On hit: walk to `dest` (with full
    # per-turn upkeep) if dest is set; else print `msg` and stay
    # put. On miss: fall through to the next rule. Used by
    # Witt's End (msg-only) and the 19:sw 35% dragon-canyon
    # shortcut (dest=74).
    if bg.check == "probability":
        if (randi() % 100) < bg.pct:
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # "carrying" — canon's `M*1000+N` rows where M is 100..200,
    # i.e. carrying obj M-100. Two flavours:
    #   - msg only (e.g. `15 150022 …` — gold-blocks-the-steps):
    #     print and stay put.
    #   - dest only (e.g. `14 150020 …` — gold-falls-pit-to-20):
    #     walk to dest, room's own death handler fires.
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
    # "bridge" — canon `prop(fissure) != 1` rows: fires while the
    # crystal bridge is NOT yet built. Used for the fissure-jump-
    # to-death rows (canon `17/27 412021 7` → walk to canon 21 if
    # bridge missing) and the OVER/ACROSS/W/CROSS bumper rows
    # (canon `17/27 412597 …` → emit msg #97). Both flavours
    # supported via `dest` vs `msg`. Falls through once bridge
    # built (so the player walks to 27 / 17 normally).
    if bg.check == "bridge":
        if not fsm.bridge_built():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # "dragon_killed" — canon `prop(dragon) != 0` rows: fires
    # *after* the player has slain the dragon (prop=2). Used for
    # the post-kill shortcut rows: canon `69 331120 46` (south →
    # 120) and `74 331120 44` (west → 120) open up the connecting
    # canyon once the dragon is no longer blocking it.
    if bg.check == "dragon_killed":
        if not fsm.dragon_alive():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # "chasm_collapsed" — canon `prop(chasm) != 0` rows: fires
    # *after* the bear-falls-bridge sequence has destroyed the
    # crossing. Used for canon `117 332661 41` (OVER → msg #161
    # "no longer any way across") and `117 332021 39` (JUMP →
    # walk to canon 21 death). Port models chasm state as the
    # Adventure FSM's `troll_bridge_collapsed()` flag, set when
    # the player crosses 117↔122 with the bear in $Following
    # (canon msg #162 / driver intercept in _handle_movement).
    if bg.check == "chasm_collapsed":
        if fsm.troll_bridge_collapsed():
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    # Unknown check type — defensive fall-through. Any gate type
    # only handled by _handle_movement (snake/troll/bridge/grate/
    # plant_*/plover_squeeze) at the topology stage will reach
    # here from chains and harmlessly skip; the topology lookup
    # in _handle_movement handles those gates instead.
    return false

# Walk the player to `dest_room` via fsm._verb_move and run all
# the per-turn upkeep that direction-handling does. Used by
# bumper rules whose `dest` field routes to a destination room
# (e.g. canon 14:down with gold → room 20 death).
func _walk_to_dest(dest_room: int) -> void:
    # Capture BACK history before the move fires.
    _old_loc2 = _old_loc
    _old_loc = fsm.player_room()
    var resp: String = fsm.do_command("move", str(dest_room))
    _println(resp)
    # Canon STMT 6010 — bumper-walks still advance the dwarf turn
    # counter, so dwarves walk and may attack along this path too.
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

# Returns true if any stalking dwarf is currently at `room`.
# Used by _handle_movement to block exit toward a dwarf-occupied
# room (canon msg #2). The Adventure FSM holds five named Dwarf
# instances; iterate them by name since framec doesn't expose
# Array<@@system> and there's no per-room aggregator method.
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
        return
    _check_pirate_rustle()

# Canon msg #127 (advent.for STMT 6080-ish): while the pirate is
# stalking and the player is in a deep-cave room (canon LOC>=15),
# there's a ~20% chance per turn to emit the "faint rustling
# noises" hint — the canonical heads-up that the pirate is
# somewhere nearby. Factored out of `_check_pirate_steal` so
# tests can exercise the rustle path independently from the
# steal-roll → $Vanished transition.
func _check_pirate_rustle() -> void:
    if fsm.pirate_state() != "stalking":
        return
    if _pirate_already_stole:
        return
    if fsm.player_room() < 15:
        return
    if (randi() % 100) < 20:
        _println("[color=#cc8855][i]There are faint rustling noises from the darkness behind you.[/i][/color]")

func _check_lamp_warnings() -> void:
    var msg: String = fsm.get_lamp_message()
    if msg != "":
        # Canon msg #183/#188/#189 — the lamp-dim warning varies by
        # player state (advent.for LMWARN):
        #   carrying batteries   → msg #188 (auto-replace + refresh)
        #   vending depleted, no
        #     spares carried     → msg #189 (out of spare batteries)
        #   vending still loaded → msg #183 (initial dim, find vending)
        # The Lamp FSM emits msg #183 by default; we substitute the
        # variant based on cross-FSM state. Canon msg #187 ("go
        # back for those batteries") is a subtle in-between state
        # canon tracks via PROP(BATTERIES); the port model conflates
        # it with msg #189 — same actionable advice.
        if fsm.player.carrying(BATTERIES_ID):
            # Auto-replace: refresh lamp + consume the batteries.
            # Canon msg #188 verbatim.
            fsm.refresh_lamp()
            fsm.batteries_item.consume()
            fsm.player.drop(BATTERIES_ID)
            msg = "Your lamp is getting dim. I'm taking the liberty of replacing the batteries."
        elif not fsm.vending_loaded():
            # Canon msg #189 verbatim.
            msg = "Your lamp is getting dim, and you're out of spare batteries. You'd best start wrapping this up."
        # Else: msg stays as canon msg #183 (vending loaded).
        _println("[color=#ddaa66]%s[/color]" % msg)
    # Canon msg #185 (advent.for STMT 12600): if the lamp is
    # out and the player has wandered above-ground (canon
    # `LIMIT<0 AND LOC<=8`), force the game to end. Above-ground
    # in canon = rooms 1..8; with no lamp, the player has no
    # way back into the cave to find batteries, so canon
    # mercy-quits with msg #185 + final score.
    if fsm.lamp.get_state() == "out" and fsm.player_room() <= 8:
        _println("[color=#cc7777][b]There's not much point in wandering around out here, and you can't explore the cave without a lamp. So let's just call it a day.[/b][/color]")
        # Guard the scene-tree call for headless tests where
        # the Driver node isn't actually in a tree.
        if is_inside_tree():
            await get_tree().create_timer(2.0).timeout
            get_tree().quit()

func _check_dwarf_axe() -> void:
    # Canon STMT 6010-6030 multi-dwarf prose ladder. The
    # orchestrator's resolve_dwarf_attack() has already run and
    # populated DTOTAL / ATTACK / STICK counters; we drain them
    # here, then render the canon msgs.
    #
    #   DTOTAL == 0          → silent (no dwarves here)
    #   DTOTAL == 1          → msg #4 ("There is a threatening
    #                             little dwarf in the room with
    #                             you!")
    #   DTOTAL >= 2          → canon FORMAT 67 ("There are N
    #                             threatening little dwarves...")
    #
    #   ATTACK == 0          → no throw line
    #   ATTACK == 1, STICK=0 → msg #5 + msg #52 ("It misses!")
    #   ATTACK == 1, STICK=1 → msg #5 + msg #53 ("It gets you!")
    #   ATTACK >= 2, STICK=0 → canon FORMAT 78 + msg #6
    #   ATTACK >= 2, STICK=1 → canon FORMAT 78 + msg #7
    #   ATTACK >= 2, STICK>1 → canon FORMAT 78 + canon FORMAT 68
    #
    # We still consume dwarf_threw_axe / dwarf_threw_and_missed
    # because the orchestrator sets those legacy flags for
    # save/restore compatibility — but the count-aware ladder is
    # what the player sees.
    var dtotal: int = fsm.dwarf_count_in_room()
    var attack: int = fsm.dwarf_attack_count()
    var stick:  int = fsm.dwarf_hit_count()
    # Drain the legacy single-dwarf flags so a later turn doesn't
    # see stale state. The ladder below already handled the
    # message rendering.
    fsm.dwarf_threw_axe()
    fsm.dwarf_threw_and_missed()
    if dtotal == 0:
        return
    if not _dwarf_first_encounter_done:
        # First-encounter narration (msg #3 set by observe_player_move
        # path runs only on the player's first walk-into; here we
        # latch the flag so the per-turn count msgs don't double
        # up with that intro.
        _dwarf_first_encounter_done = true
    if dtotal == 1:
        _println("[color=#cc7777][i]There is a threatening little dwarf in the room with you![/i][/color]")
    else:
        # Canon FORMAT 67 — "There are N threatening little dwarves..."
        _println("[color=#cc7777][i]There are %d threatening little dwarves in the room with you.[/i][/color]" % dtotal)
    if attack == 0:
        return
    if attack == 1:
        # Canon msg #5 — singular throw.
        _println("[color=#cc7777][i]One sharp nasty knife is thrown at you![/i][/color]")
        if stick == 0:
            # Canon msg #52 — "It misses!"
            _println("[color=#cc7777][i]It misses![/i][/color]")
        else:
            # Canon msg #53 — "It gets you!"
            _println("[color=#cc7777][i]It gets you![/i][/color]")
        return
    # ATTACK >= 2 — canon FORMAT 78 "N of them throw knives at you!"
    _println("[color=#cc7777][i]%d of them throw knives at you![/i][/color]" % attack)
    if stick == 0:
        # Canon msg #6 — "None of them hit you!"
        _println("[color=#cc7777][i]None of them hit you![/i][/color]")
    elif stick == 1:
        # Canon msg #7 — "One of them gets you!"
        _println("[color=#cc7777][i]One of them gets you![/i][/color]")
    else:
        # Canon FORMAT 68 — "N of them get you!"
        _println("[color=#cc7777][i]%d of them get you![/i][/color]" % stick)

# Canon chest-only-outstanding hint (advent.for STMT 6020, msg
# #186). Fires once when the player has deposited all 14
# non-chest treasures and the chest is still missing — pointing
# them toward the maze where the pirate has hidden it.
func _check_chest_hint() -> void:
    if _chest_hint_done:
        return
    if fsm.chest.is_deposited():
        return
    if fsm.player.carrying(CHEST_ID):
        return
    if fsm.treasures_deposited() < 14:
        return
    _chest_hint_done = true
    _println("There are faint rustling noises from the darkness behind you. As you")
    _println("turn toward them, the beam of your lamp falls across a bearded pirate.")
    _println("He is carrying a large chest. \"Shiver me timbers!\" he cries, \"I've")
    _println("been spotted! I'd best hie meself off to the maze to hide me chest!\"")
    _println("With that, he vanishes into the gloom.")

func _check_player_death() -> void:
    if _awaiting_revive:
        return
    var s: String = fsm.player_state()
    if s == "dead":
        # Canon msg #131 — death during the closing-cave phase is
        # final (no resurrection because the cave is already winding
        # down). End the game outright instead of offering revive.
        if fsm.endgame_state() == "closing":
            _println("[color=#cc4444][b]It looks as though you're dead. Well, seeing as how it's so close to closing time anyway, I think we'll just call it a day.[/b][/color]")
            if is_inside_tree():
                await get_tree().create_timer(2.0).timeout
                get_tree().quit()
            return
        _awaiting_revive = true
        # Canon advent.for STMT 16000: prompt text varies by death
        # count via the msg #81/#83/#85 ladder.
        var deaths: int = fsm.player.get_deaths()
        if deaths == 1:
            # Canon msg #81 verbatim.
            _println("[color=#cc4444]Oh dear, you seem to have gotten yourself killed. I might be able to")
            _println("help you out, but I've never really done this before. Do you want me")
            _println("to try to reincarnate you?[/color]")
        elif deaths == 2:
            # Canon msg #83 verbatim.
            _println("[color=#cc4444]You clumsy oaf, you've done it again! I don't know how long I can")
            _println("keep this up. Do you want me to try reincarnating you again?[/color]")
        else:
            # Canon msg #85 verbatim — last shot.
            _println("[color=#cc4444]Now you've really done it! I'm out of orange smoke! You don't expect")
            _println("me to do a decent reincarnation without any orange smoke, do you?[/color]")
    elif s == "permadead":
        # Canon msg #86 verbatim.
        _println("[color=#cc4444][b]Okay, if you're so smart, do it yourself! I'm leaving![/b][/color]")
        if is_inside_tree():
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
            # Canon msg #129 verbatim. Closing-phase opens with the
            # canonical sepulchral voice announcement.
            _println("[color=#cc7777][b]A sepulchral voice reverberating through the cave, says, \"Cave closing soon. All adventurers exit immediately through main office.\"[/b][/color]")
        elif s == "in_repository":
            # Canon msg #132 verbatim — the cave-closes-shut prose.
            # Port supplements with the dynamite hint since the
            # repository's stick-of-dynamite puzzle is a canon
            # feature but the prose doesn't quite spell it out.
            _println("[color=#cc7777][b]The sepulchral voice entones, \"The cave is now closed.\" As the echoes fade, there is a blinding flash of light (and a small puff of orange smoke). . . . As your eyes refocus, you look around and find...[/b][/color]")
            _println("[color=#aaaaaa][i](Try DETONATE.)[/i][/color]")
        elif s == "won":
            _println("[color=#88dd88][b]There is a loud explosion, and a twenty-foot hole appears in the far wall, burying the dwarves in the rubble. You march through the hole and find yourself in the main office, where a cheering band of friendly elves carry the conquering adventurer off into the sunset. (Final score: %d)[/b][/color]" % fsm.total_score())

    # Closing-phase crescendo. Canon msg #129 is the single
    # cave-closing warning; the t=15 and t=5 escalations below are
    # port-only flavor to keep tension building (canon has just one
    # alert and then $Closed). They use distinct prose so they
    # don't duplicate the canon opening text.
    if s == "closing":
        var t: float = fsm.endgame_timer()
        if t <= 25.0 and not _closing_warned_25:
            _closing_warned_25 = true
            _println("[color=#cc7777][i]A sepulchral voice reverberating through the cave, says, \"Cave closing soon. All adventurers exit immediately through main office.\"[/i][/color]")
        if t <= 15.0 and not _closing_warned_15:
            _closing_warned_15 = true
            _println("[color=#cc7777][i]A sepulchral voice reverberating through the cave, says, \"Cave closing soon. All adventurers exit immediately through main office.\"[/i][/color]")
        if t <= 5.0 and not _closing_warned_5:
            _closing_warned_5 = true
            _println("[color=#cc7777][b]A mysterious recorded voice groans into life and announces: \"This exit is closed. Please leave via main office.\"[/b][/color]")

func _maybe_print_room_after_move() -> void:
    var current: int = fsm.player_room()
    if current != _last_room:
        _last_room = current
        # Canon BRIEF: skip the long room display on revisit.
        # The player can always type LOOK to re-display.
        if _brief_mode and _visited_rooms.has(current):
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
    # Canon Y2 whisper (advent.for line 808): at canon room 33,
    # 25% chance per visit to print msg #8 ("a hollow voice
    # says 'PLUGH'"). Doesn't fire during closing.
    if _last_room == 33 and not fsm.endgame_closing() and (randi() % 100) < 25:
        _println("A hollow voice says \"PLUGH\".")
    # Canon msg #3 first-dwarf-encounter (advent.for STMT 6000).
    # Fires once when the player first arrives in a room with a
    # stalking dwarf — canon's DFLAG 1→2 transition narration.
    if not _dwarf_first_encounter_done and _dwarf_at_room(_last_room):
        _dwarf_first_encounter_done = true
        _println("A little dwarf just walked around a corner, saw you, threw a little")
        _println("axe at you which missed, cursed, and ran away.")

# Returns true if the object identified by `obj_id` is visible
# in the given room (canon AT(OBJ) test). Used by FIND to fire
# msg #94 ("I believe what you want is right here with you")
# when the player asks for an object that's actually here.
#
# Treasures expose `get_location(): int`. Items expose
# `is_in_room(r): bool`. The Bird is the one outlier — its
# `get_location()` returns the canonical room number.
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
# Used by FIND. Mirrors the inventory-builder's static name
# table; not a synonym engine — just the canon vocabulary
# words. Multi-word names ("gold nugget") are also accepted.
func _resolve_object_id(noun: String) -> int:
    var n: String = noun.strip_edges().to_lower()
    if n == "":
        return 0
    if n in ["bird"]:                   return BIRD_ID
    if n in ["chain"]:                  return CHAIN_ID
    if n in ["gold", "nugget", "gold nugget"]: return GOLD_ID
    if n in ["silver", "bars", "silver bars"]: return SILVER_ID
    if n in ["diamonds"]:               return DIAMONDS_ID
    if n in ["jewelry"]:                return JEWELRY_ID
    if n in ["pearl"]:                  return PEARL_ID
    if n in ["vase"]:                   return VASE_ID
    if n in ["eggs"]:                   return EGGS_ID
    if n in ["trident"]:                return TRIDENT_ID
    if n in ["emerald"]:                return EMERALD_ID
    if n in ["spices"]:                 return SPICES_ID
    if n in ["chest"]:                  return CHEST_ID
    if n in ["pyramid"]:                return PYRAMID_ID
    if n in ["rug"]:                    return RUG_ID
    if n in ["coins"]:                  return COINS_ID
    if n in ["rod"]:                    return ROD_ID
    if n in ["keys"]:                   return KEYS_ID
    if n in ["bottle"]:                 return BOTTLE_ID
    if n in ["cage"]:                   return CAGE_ID
    if n in ["food"]:                   return FOOD_ID
    if n in ["pillow"]:                 return PILLOW_ID
    if n in ["axe"]:                    return AXE_ID
    if n in ["clam"]:                   return CLAM_ID
    if n in ["oyster"]:                 return OYSTER_ID
    if n in ["magazine"]:               return MAGAZINE_ID
    if n in ["batteries"]:              return BATTERIES_ID
    return 0

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
    if fsm.player.carrying(BOTTLE_ID):
        # Canon obj#20/21/22: bottle label varies with contents.
        # Empty → "Small bottle", with water → "Water in the bottle",
        # with oil → "Oil in the bottle". Advent.dat distinguishes
        # the prop=0/2/4 forms; the port reads bottle state via the
        # FSM getters.
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
    # Canon advent.for STMT 6010 line 777: SAVED != -1 → dwarves
    # snap to DFLAG=20 on next attack. The FSM latch fires once.
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
    # Crowther/Woods credit splash — every CCA session opens
    # with explicit attribution to the original 1976/77 work
    # before any game prose. Era-appropriate plain text, no
    # emoji or modern iconography. Routed through `_println`
    # (rather than direct `output.append_text` calls) so the
    # captured-driver test can observe the welcome output.
    var rule: String = "[color=#a89878]─────────────────────────────[/color]"
    # Small brick-building silhouette, period line-printer style.
    # Echoes the canon opening room ("a small brick building").
    # Bracket pairs like `[]` would be parsed as empty BBCode
    # tags and corrupt the parser state for everything that
    # comes after, so the window squares are drawn with `( )`
    # instead — same visual rhythm, no parser hazard.
    var art: String = (
        "[color=#a89878]"
        + "             ____\n"
        + "            /    \\\n"
        + "           /______\\\n"
        + "           |() ()|\n"
        + "           |_____|\n"
        + "[/color]"
    )
    var msg: String = ""
    msg += "[color=#e0c890][b]COLOSSAL CAVE ADVENTURE[/b][/color]\n"
    msg += rule + "\n\n"
    msg += art + "\n"
    msg += "  Originally written by [b]Will Crowther[/b] (1976)\n"
    msg += "  and expanded to the canonical 350-point version\n"
    msg += "  by [b]Don Woods[/b] at the Stanford AI Lab (1977).\n\n"
    msg += "[color=#a89878]"
    msg += "  This Frame state-machine implementation re-ports\n"
    msg += "  the original PDP-10 FORTRAN-IV source preserved at\n"
    msg += "  the [url=https://www.ifarchive.org/]Interactive Fiction Archive[/url].\n"
    msg += "  Public domain; redistributed for historical record.\n"
    msg += "[/color]\n"
    msg += rule
    _println(msg)
    # Canon msg #65 — original opening prompt. Followed by the
    # port's HELP hint since the canon Y/N flow for instructions
    # is out of scope (port has a dedicated HELP verb instead).
    _println("Welcome to Adventure!! Would you like instructions?")
    _println("Type [b]HELP[/b] for a list of commands, or press Enter to begin.")

# Opens [url=...] BBCode links in the player's default browser.
# `meta` arrives as a Variant (the bare url string from BBCode).
func _on_meta_clicked(meta: Variant) -> void:
    if meta is String:
        OS.shell_open(meta)

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
