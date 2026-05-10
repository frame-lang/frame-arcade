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

# Canon msg #3 first-dwarf-encounter latch (advent.for STMT
# 6000). Canon narrates msg #3 on the DFLAG 1→2 transition: "A
# little dwarf just walked around a corner, saw you, threw a
# little axe at you which missed, cursed, and ran away." The port
# wakes the dwarves once at `_ready`, so we fire msg #3 the first
# time the player enters a room where a stalking dwarf is — same
# narrative beat, simpler trigger.
var _dwarf_first_encounter_done: bool = false

# Canon OYSTER hint chain (advent.dat msgs #192/193/194). READ
# OYSTER on the in-place oyster (post-clam-break) costs 10 points
# but reveals the magic-words hint. Canon flow:
#   READ OYSTER (first time)  → msg #192 prompt (Y/N, 10-pt cost)
#   YES                        → msg #193 reveal + 10-pt deduction
#   NO                         → cancel, no penalty
#   READ OYSTER (after reveal) → msg #194 ("same thing")
var _oyster_prompt_active: bool = false
var _oyster_revealed: bool = false

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
                _println("[color=#88dd88]>POOF!< (somehow.)[/color]")
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
        "suspend":
            # Canon SUSPEND (advent.for STMT 8300, around line 1791).
            # In 1977 this printed the "wait at least N minutes" warning
            # (formatted from `LATNCY`, default 45), asked YES/NO via
            # canon msg #200, and on yes called CIAO to write the
            # core image and exit. The latency was an anti-save-scum
            # measure on the multi-user PDP-10 — without it, players
            # would SAVE before every dragon fight and reload on
            # death.
            #
            # On a desktop port that whole assumption is gone: saves
            # are owned by the player. We honor the verb with the
            # canon prose and a wink, then save instantly. SAVE
            # stays silent for modern UX.
            _println("I can suspend your adventure for you so that you can resume later, but")
            _println("you will have to wait at least 45 minutes before continuing.")
            _println("")
            _println("... or not.")
            _save_game()
            return
        "hint":
            var hint_name: String = noun if noun != "" else "bird"
            _println(fsm.request_hint(hint_name))
            return
        "hours":
            # Canon HOURS (advent.for line 8310 → SUBROUTINE HOURS at
            # 2639). On the 1977 PDP-10 this printed the timesharing
            # window during which the cave was open to non-wizards
            # (`WKDAY`/`WKEND`/`HOLID` bitmasks of prime-time hours).
            # In a single-user desktop port that whole machinery is
            # vestigial — the cave is always available — so we honor
            # the verb with the canonical translation: a brief banner
            # that says exactly that and points at the canon
            # provenance for anyone curious about the history.
            _println("Colossal Cave is open all day, every day.")
            _println("(In the original 1977 PDP-10 release this verb")
            _println("printed the timesharing schedule during which")
            _println("non-wizards could play. On a desktop port the")
            _println("cave has no off-hours.)")
            return
        "wizard":
            # Canon WIZARD (advent.for SUBROUTINE WIZARD at line 2578).
            # In 1977 this was a real authentication dialogue: msg #16
            # "ARE YOU A WIZARD?" → msg #17 "PROVE IT! SAY THE MAGIC
            # WORD!" → a hashed challenge from DATIME → either msg #19
            # "OH DEAR, YOU REALLY *ARE* A WIZARD!" or msg #20 "FOO,
            # YOU ARE NOTHING BUT A CHARLATAN!". Wizards could then
            # bypass prime-time gating, edit cave hours, and resume
            # saved games early.
            #
            # The challenge response is computed from the system clock
            # plus a hashed magic-number known only to whoever set up
            # the timesharing instance — there is no fixed answer to
            # type. We narrate the canon dialogue verbatim in a single
            # turn (no Y/N prompt), end on canon msg #20. Players who
            # remember Don Woods's original dare will recognise it.
            _println("\"Are you a wizard?\"")
            _println("\"Prove it!  Say the magic word!\"")
            _println("\"That is not what I thought it was.  Do you know what I thought it was?\"")
            _println("\"Foo, you are nothing but a charlatan!\"")
            return
        "maint", "magic":
            # Canon MAINT (advent.for SUBROUTINE MAINT at line 2521).
            # Triggered in 1977 by typing "MAGIC MODE" as the very
            # first command of a session: ran WIZARD authentication,
            # then let the wizard edit cave hours, the magic word, the
            # message of the day, the demo length, and the suspend
            # latency. Wrote a new core image on exit so the next
            # session would pick up the changes.
            #
            # On a desktop port the cave needs no maintenance — there
            # are no hours to edit, no demo cap to set, no MOTD to
            # post. We honor the verb with a wink: canon msg #1 (the
            # tall wizard in grey), gently rewritten to fit the
            # situation, followed by canon msg #20 for completeness.
            _println("A large cloud of green smoke appears in front of you. It clears")
            _println("away to reveal a tall wizard, clothed in grey. He fixes you with")
            _println("a steely glare and declares, \"Maintenance mode requires a real")
            _println("PDP-10 and a sysadmin who knew Don Woods. This is neither.\"")
            _println("With that he makes a single pass over you with his hands, and")
            _println("you find yourself right back where you started.")
            _println("")
            _println("\"Foo, you are nothing but a charlatan!\"")
            return
        "blast":
            # Canon BLAST (advent.for STMT 9230). Three outcomes
            # gated on (CLOSED, LOC, HERE(ROD2)):
            #   pre-CLOSED              → msg #67 ("BLASTING REQUIRES DYNAMITE.")
            #   CLOSED, rod2 here       → blast_klutz, msg #135 (+25)
            #   CLOSED, LOC=115, no rod → blast_wrong_way, msg #134 (+30)
            #   CLOSED, otherwise       → blast_mastery, msg #133 (+45)
            #
            # Each in-repository case awards the canon score bonus
            # via the matching Adventure FSM method, then transitions
            # the Endgame FSM to $Won. The "klutz" and "wrong-way"
            # narrations describe the player dying to the explosion;
            # the "mastery" narration is the canonical victory text.
            # All three end the game.
            if fsm.endgame_state() != "in_repository":
                _println("Blasting requires dynamite.")
                return
            if fsm.mark_rod_here():
                _println("There is a loud explosion, and you are suddenly splashed across the")
                _println("walls of the room.")
                fsm.blast_klutz()
                _check_endgame_phase_change()
                return
            if fsm.player_room() == 115:
                _println("There is a loud explosion, and a twenty-foot hole appears in the far")
                _println("wall, burying the snakes in the rubble. A river of molten lava pours")
                _println("in through the hole, destroying everything in its path, including you!")
                fsm.blast_wrong_way()
                _check_endgame_phase_change()
                return
            _println("There is a loud explosion, and a twenty-foot hole appears in the far")
            _println("wall, burying the dwarves in the rubble. You march through the hole")
            _println("and find yourself in the main office, where a cheering band of")
            _println("friendly elves carry the conquering adventurer off into the sunset.")
            fsm.blast_mastery()
            _check_endgame_phase_change()
            return
        "wake":
            # Canon WAKE (advent.for STMT 9290). Pre-CLOSED: msg
            # #13 default. CLOSED + DWARF as object: msg #199 +
            # msg #136 (the disturbed-dwarves death). The port
            # collapses the WAKE-DWARF pair into the bare verb
            # since the only meaningful target at endgame is a
            # dwarf and noun-parsing is loose.
            if fsm.endgame_state() != "in_repository":
                _println("I don't understand that.")
                return
            _println("You prod the nearest dwarf, who wakes up grumpily, takes one look at")
            _println("you, curses, and grabs for his axe.")
            _println("")
            _println("The resulting ruckus has awakened the dwarves. There are now several")
            _println("threatening little dwarves in the room with you! Most of them throw")
            _println("knives at you! All of them get you!")
            fsm.player.die()
            _check_player_death()
            return
        "find":
            # Canon FIND (advent.for STMT 9190). Possible
            # responses, in canon priority order:
            #   TOTING(OBJ)            → msg #24 ("You are already
            #                              carrying it!")
            #   AT(OBJ) (here visible) → msg #94 ("I believe what
            #                              you want is right here
            #                              with you.")
            #   CLOSED                 → msg #138 ("I daresay
            #                              whatever you want is
            #                              around here somewhere.")
            #   otherwise              → msg #59 (cave-finding hint)
            # The port checks player.carrying() for the toting
            # branch; "AT(OBJ) here visible" requires per-object
            # is_in_room accessors that we don't all expose, so
            # we conservatively fall through to the canon default
            # for non-carried objects. This matches canon's "the
            # game won't help you find things" design.
            var find_obj_id: int = _resolve_object_id(noun)
            if find_obj_id > 0 and fsm.player.carrying(find_obj_id):
                _println("You are already carrying it!")
                return
            # Canon AT(OBJ) — visible in current room → msg #94.
            if find_obj_id > 0 and _object_in_room(find_obj_id, fsm.player_room()):
                _println("I believe what you want is right here with you.")
                return
            if fsm.endgame_state() == "in_repository":
                _println("I daresay whatever you want is around here somewhere.")
                return
            _println("I can only tell you what you see as you move about and manipulate things. I cannot tell you where remote things are.")
            return
        "brief":
            # Canon BRIEF (advent.for STMT 8260). Sets ABBNUM=10000
            # so room descriptions after the first visit are short.
            # Port toggles _brief_mode; `_print_room` consults it
            # before deciding long vs short form.
            _brief_mode = true
            _println("Okay, from now on I'll only describe a place in full the first time")
            _println("you come to it. To get the full description, say LOOK.")
            return
        "rub":
            # Canon RUB (advent.for STMT 9160). LAMP → msg #75
            # ("rubbing the electric lamp is not particularly
            # rewarding"). Anything else → msg #76 ("Peculiar.
            # Nothing unexpected happens.")
            if noun == "lamp":
                _println("Rubbing the electric lamp is not particularly rewarding. Anyway, nothing exciting happens.")
            else:
                _println("Peculiar. Nothing unexpected happens.")
            return
        "say":
            # Canon SAY (advent.for STMT 9030). If noun is a
            # canon magic word, re-dispatch as that verb (so
            # SAY XYZZY teleports). Otherwise echo: "Okay, X".
            if noun == "":
                _println("Say what?")
                return
            if noun in ["xyzzy", "plugh", "plover", "fee", "fie", "foe", "foo"]:
                _process_input(noun)
                return
            _println("Okay, \"%s\"." % noun)
            return
        "cave":
            # Canon CAVE (advent.for STMT 40). Outdoors (canon rooms
            # 1–8) → msg #57; indoors → msg #58. Pure flavor — no
            # state change.
            if fsm.player_room() <= 8:
                _println("I don't know where the cave is, but hereabouts no stream can run on the surface for long. I would try the stream.")
            else:
                _println("I need more detailed instructions to do that.")
            return
        "look":
            # Canon LOOK (advent.for STMT 30). Print msg #15 up to
            # 3 times to discourage spam; subsequent LOOKs silently
            # re-display the room. Reset _visited_rooms tracking
            # for BRIEF so the next room print is long-form.
            if _look_detail_count < 3:
                _println("Sorry, but I am not allowed to give more detail. I will repeat the long description of your location.")
                _look_detail_count = _look_detail_count + 1
            _last_room = -1                    # force re-print
            _visited_rooms.erase(fsm.player_room())
            _print_room()
            return
        "back":
            # Canon BACK (advent.for STMT 20-25). Find an exit
            # from the current room to OLDLOC; if OLDLOC is
            # forced-motion, use OLDLC2 instead. If no path
            # exists, msg #140. If "back" is an explicit topology
            # exit (forced-room escape verbs added per the
            # canon-march), use that directly.
            var bk_current: int = fsm.player_room()
            var bk_exits: Dictionary = room_exits.get(bk_current, {})
            if "back" in bk_exits:
                _handle_movement("back")
                return
            var k: int = _old_loc
            if k in FORCED_ROOMS:
                k = _old_loc2
            if k < 0:
                _println("Sorry, but I no longer seem to remember how it was you got here.")
                return
            if k == bk_current:
                _println("Where?")
                return
            for bk_dir in bk_exits:
                if bk_exits[bk_dir] == k:
                    _handle_movement(bk_dir)
                    return
            _println("Sorry, but I no longer seem to remember how it was you got here.")
            return

    # Canon "always-blocked" bumper gates and conditional rows.
    # The (room, verb) key may map to either a single rule
    # (Dictionary) or an ordered chain of rules (Array). Canon
    # section 3 has *multiple rows* per (from, verb) for
    # conditional dispatch — e.g. `19 35074 49` (35% → 74)
    # followed by `19 211032 49` (snake-here → 32). The chain
    # walks rules in order; the first that fires wins, the rest
    # are skipped. A rule that "doesn't apply" (probability
    # missed, condition false) falls through to the next rule.
    # Rules whose conditions all fail leave control to
    # _handle_movement / topology / no-exit fallback.
    var bumper_key: String = "%d:%s" % [fsm.player_room(), verb]
    if bumper_key in gated_exits:
        var entry = gated_exits[bumper_key]
        var rules: Array = entry if entry is Array else [entry]
        for rule in rules:
            if _try_bumper_rule(rule):
                return

    # Canon dark-room pit-fall hazard. Any motion attempt from a
    # dark cave room (lamp out) risks death. The first attempt in
    # the room emits the canon warning; subsequent attempts roll
    # the 35% pit-fall. Lighting the lamp clears the hazard. Lit
    # rooms (1..8, 100) and lit-lamp turns short-circuit harmlessly.
    if verb in MOTION_VERBS and _check_dark_pit_hazard():
        return

    # Canon ENTER STREAM / ENTER WATER (advent.for line 894-895).
    # Special-case BEFORE the DIRECTIONS check so canon msg #70
    # ("feet are now wet") fires instead of treating ENTER as a
    # generic direction verb.
    if verb == "enter" and (noun == "stream" or noun == "water"):
        _println("Your feet are now wet.")
        return

    # Direction verbs become MOVE with a resolved room ID.
    if verb in DIRECTIONS:
        _handle_movement(verb)
        return

    # Canon BREAK MIRROR (advent.for STMT 9280) — closed-only
    # death. Pre-CLOSED, BREAK MIRROR returns the action default
    # msg #146 ("It is beyond your power to do that."); the
    # FSM's _verb_break doesn't know about MIRROR and would
    # otherwise emit "I don't know how to break that." Match
    # canon by intercepting here.
    if verb == "break" and noun == "mirror":
        if fsm.endgame_state() == "in_repository":
            _println("You strike the mirror a resounding blow, whereupon it shatters into a")
            _println("myriad tiny fragments.")
            _println("")
            _println("The resulting ruckus has awakened the dwarves. There are now several")
            _println("threatening little dwarves in the room with you! Most of them throw")
            _println("knives at you! All of them get you!")
            fsm.player.die()
            _check_player_death()
            return
        _println("It is beyond your power to do that.")
        return

    # Canon DROP BIRD (advent.for STMT 9020 inline branches at
    # snake/dragon rooms). The port's _verb_drop doesn't know
    # the bird; the equivalent gameplay lives in _verb_release
    # which already handles snake (msg #30) and dragon (msg #154)
    # via the Bird FSM's $Released vs $Dead transitions. Re-
    # route DROP BIRD here so canon syntax works.
    if verb == "drop" and noun == "bird":
        _process_input("release bird")
        return

    # Canon ATTACK/KILL BIRD (advent.for STMT 9120) — msg #137:
    # "Oh, leave the poor unhappy bird alone." Bypasses the FSM's
    # default attack handling for the bird specifically.
    if verb == "attack" and noun == "bird":
        _println("Oh, leave the poor unhappy bird alone.")
        return

    # Canon ATTACK BEAR (advent.for STMT 9120 + msgs #165/#166).
    # Outcome varies by bear state:
    #   hungry           → msg #165 ("bare hands... bear hands??")
    #   tame/following   → msg #166 ("only wants to be your friend")
    #   released         → msg #167 ("poor thing is already dead")
    #     (released = post-bridge, bear off the chain; canon's
    #      "dead" prop variant doesn't exist in the port since
    #      the bear FSM has no $Dead state, but msg #167 fits.)
    if verb == "attack" and noun == "bear":
        var bs: String = fsm.bear.get_state()
        if bs == "hungry":
            _println("With what? Your bare hands? Against *his* bear hands??")
        elif bs == "tame" or bs == "following":
            _println("The bear is confused; he only wants to be your friend.")
        elif bs == "released":
            _println("For crying out loud, the poor thing is already dead!")
        else:
            _println("There is no bear here to attack.")
        return

    # Canon TAKE KNIFE (advent.for STMT 9010 + msg #116). The
    # player can never pick up a dwarf-thrown knife — they
    # canonically vanish on impact. KNFLOC tracking is moot when
    # the knife isn't a real item; we just emit the canon rebuff
    # for any TAKE/GET KNIFE attempt.
    if verb == "take" and noun == "knife":
        _println("The dwarves' knives vanish as they strike the walls of the cave.")
        return

    # Canon TAKE BEAR (advent.for STMT 9010 + msg #169). The bear
    # can be "taken" only after taming AND unlocking the chain —
    # the FSM's _verb_take("chain") handles the canonical chain-
    # transfer path. Direct TAKE BEAR while the bear is still
    # chained gets the canon rebuff.
    if verb == "take" and noun == "bear":
        var bs_take: String = fsm.bear.get_state()
        if bs_take == "hungry":
            _println("The bear is still chained to the wall.")
            return
        if bs_take == "tame":
            # Canon: must take chain first (which triggers the
            # bear-follows-you transition). TAKE BEAR alone
            # doesn't transfer the bear.
            _println("The bear is still chained to the wall.")
            return
        if bs_take == "following":
            _println("You are already leading the bear by the chain.")
            return
        _println("There is no bear here to take.")
        return

    # Canon UNLOCK CHAIN (advent.for + msg #170). UNLOCK CHAIN
    # without keys → msg #170 ("The chain is still locked.").
    # UNLOCK CHAIN with keys + bear-not-tame → msg #41 (FSM
    # default). With keys + tame bear → bear's chain unlocks.
    # Routes through the FSM's bear/chain handling for the
    # mechanical path; we just intercept the no-keys case.
    if verb == "unlock" and noun == "chain":
        if not fsm.player.carrying(KEYS_ID):
            _println("The chain is still locked.")
            return
        # Fall through — FSM _verb_unlock handles the rest.

    # Canon TAKE on fixed scenery (advent.dat msg #25) — these
    # canon objects are scenery only and never carryable. Fires
    # "You can't be serious!" verbatim. Gated on the same noun
    # set as the EXAMINE/READ scenery handlers (TABLET, MIRROR,
    # FIGURE/SHADOW, STALACTITE, DRAWINGS, VOLCANO/GEYSER,
    # CARPET/MOSS, PHONY PLANT). The MESSAGE in the second maze
    # is also scenery.
    if verb == "take" and noun in [
            "tablet", "mirror", "figure", "shadow", "stalactite",
            "drawings", "drawing", "volcano", "geyser",
            "carpet", "moss", "message"]:
        _println("You can't be serious!")
        return

    # Canon THROW AXE (advent.for STMT 9170). The port's
    # _verb_throw handles axe-at-dwarves and treasure-at-troll
    # but not the canon "axe glances off dragon / troll catches
    # axe / bear catches axe" outcomes. Intercept here for the
    # canon prose; the existing _verb_throw still handles the
    # dwarf-attack and treasure-toll cases via fall-through.
    if verb == "throw" and noun == "axe":
        var here_room: int = fsm.player_room()
        if here_room == 119 and fsm.dragon_alive():
            # Canon msg #152 — axe doesn't even break the skin.
            _println("The axe bounces harmlessly off the dragon's thick scales.")
            return
        if here_room == 117 and fsm.troll.is_blocking_bridge():
            # Canon msg #158 — troll deftly catches the axe.
            _println("The troll deftly catches the axe, examines it carefully, and tosses")
            _println("it back, declaring, \"Good workmanship, but it's not valuable enough.\"")
            return
        if here_room == 130 and fsm.bear_state() == "hungry":
            # Canon msg #164 — bear catches and is unimpressed.
            _println("The axe misses and lands near the bear where you can't get at it.")
            return
        # Fall through to the FSM's existing _verb_throw which
        # handles the dwarf-attack (and missing-axe) path.

    # Canon routine 302 — Plover-emerald drop (advent.for STMT
    # 30200). At canon Y2 (33) or Plover Room (100), invoking
    # PLOVER while carrying the emerald drops it at the current
    # room before teleporting. Net effect: the player has to
    # use the squeeze (routine 301) to retrieve the emerald
    # afterwards. The base PLOVER teleport runs immediately
    # after via fsm.do_command, so this block only handles the
    # emerald-drop side-effect.
    if verb == "plover":
        var here_pl: int = fsm.player_room()
        if (here_pl == 33 or here_pl == 100) and fsm.player.carrying(EMERALD_ID):
            fsm.emerald.try_drop(here_pl)
            fsm.player.drop(EMERALD_ID)
            _println("As you start to chant, the emerald slips from your grasp and falls to the floor.")
        # fall through — fsm.do_command runs the regular PLOVER
        # teleport via MagicWordTeleport.

    # Canon CALM/TAME verb (advent.for verb 10, default msg #7
    # "one of them gets you"). Canon's CALM is a no-op
    # placeholder verb — typing it just gets you stabbed by a
    # dwarf. The port uses msg #14 ("would you care to explain")
    # since msg #7 only makes sense in the dwarf-attack context.
    if verb == "calm" or verb == "tame":
        _println("I'm game. Would you care to explain how?")
        return

    # Canon EAT variants (advent.for STMT 9140). EAT FOOD is
    # handled by the FSM (consumes, returns canon msg). NPC
    # targets get the canon "Don't be ridiculous!" rebuff (msg
    # #71's flavor variant for animate targets). All other non-
    # food nouns get canon msg #71 verbatim.
    if verb == "eat":
        if noun in ["bird", "snake", "clam", "oyster", "dwarf", "dragon", "troll", "bear"]:
            _println("Don't be ridiculous!")
            return
        if noun != "" and noun != "food":
            _println("I think I just lost my appetite.")
            return

    # Canon FEED variants (advent.for STMT 9210/9212/9213). The
    # FSM's _verb_feed only knows about the bear; canon has a
    # ladder for other targets. Match canon prose for each.
    if verb == "feed":
        if noun == "bird":
            # canon msg #100
            _println("It's not hungry (it's merely pinin' for the fjords). Besides, you have no bird seed.")
            return
        if noun == "dwarf":
            # canon msg #103 + DFLAG bump (advent.for STMT 9213).
            # bump_dwarf_anger raises the knife-throw hit pct via
            # the canon `95*(DFLAG-2)/1000` ramp.
            fsm.bump_dwarf_anger()
            _println("You fool, dwarves eat only coal! Now you've made him *really* mad!!")
            return
        if noun == "troll":
            # canon msg #182
            _println("Gluttony is not one of the troll's vices. Avarice, however, is.")
            return
        if noun == "snake" or noun == "dragon":
            # canon msg #102 / #110 (dragon dead variant)
            if noun == "dragon" and not fsm.dragon_alive():
                _println("Don't be ridiculous!")
            else:
                _println("There's nothing here it wants to eat (except perhaps you).")
            return
        # noun == "bear" or any other → fall through to FSM,
        # which knows the bear case and emits a sensible
        # default for unknown nouns.

    # Canon scenery EXAMINE/READ flavor (advent.dat section 5
    # objects 13/23/25/26/27/29/36/37/40 — the in-scene-only
    # flavor objects that don't have inventory items but do have
    # canonical examine prose). Each handler is gated on the
    # player's current room so the noun only resolves in the
    # canonical room.
    if verb == "read" or verb == "examine":
        var er: int = fsm.player_room()
        # Canon ROD2 prop change (advent.dat object 6 prop ladder).
        # Pre-CLOSED: ROD2 examines as "a black rod with a rusty
        # mark on the end" — same flavor as the mundane ROD.
        # Post-CLOSED ($InRepository): the rod's prop reveals as
        # dynamite; this is the canonical "you've got the BLAST
        # ingredient now" moment. Drivers EXAMINE ROD here, so
        # we branch by endgame_state(); the mark_rod_here check
        # disambiguates the marked rod from the regular rod.
        if noun == "rod" and fsm.mark_rod_here():
            if fsm.endgame_state() == "in_repository":
                _println("It looks suspiciously like a stick of dynamite. Better not let it get near a flame.")
            else:
                _println("A small black rod with a rusty mark on the end.")
            return
        # Object 13 — STONE TABLET at canon 101 (Dark-Room).
        # Canon msg #196 = the long-form table-readout.
        if noun == "tablet" and er == 101:
            _println("A massive stone tablet imbedded in the wall reads:")
            _println("\"Congratulations on bringing light into the dark-room!\"")
            return
        # Object 36 — MESSAGE in second maze, placed at canon
        # CHLOC2=140 (the second-maze mirror of the pirate stash).
        # READ MESSAGE → canon msg #191.
        if noun == "message" and er == 140:
            _println("There is a message scrawled in the dust in a flowery script, reading:")
            _println("\"This is not the maze where the pirate leaves his treasure chest.\"")
            return
        # Object 15 — OYSTER hint chain (advent.dat msgs
        # #192/193/194). The oyster is post-clam-break scenery in
        # the room; reading the underside reveals the magic-words
        # hint at a 10-point cost.
        if noun == "oyster" and fsm.oyster_item.is_in_room(er):
            if _oyster_revealed:
                _println("It says the same thing it did before.")
                return
            # First read: prompt for the cost.
            _oyster_prompt_active = true
            _println("Hmmm, this looks like a clue, which means it'll cost you 10 points to")
            _println("read it. Should I go ahead and read it anyway?")
            return
        # Object 23 — MIRROR at canon 109 (Mirror Canyon).
        # Pre-endgame the canon prose is the long-form room desc;
        # we surface a one-line examine to acknowledge the verb.
        if noun == "mirror" and er == 109:
            _println("It's a two-sided mirror suspended high above the canyon floor.")
            _println("Provided for the dwarves, who as you know are extremely vain.")
            return
        # Object 27 — SHADOWY FIGURE at canon 35 (West Pit) and
        # canon 110 (Mirror Canyon's other side window).
        if (noun == "figure" or noun == "shadow") and (er == 35 or er == 110):
            _println("The shadowy figure seems to be trying to attract your attention.")
            return
        # Object 26 — STALACTITE at canon 111 (Top of Stalactite).
        if noun == "stalactite" and er == 111:
            _println("It's a large stalactite extending from the roof and almost reaching the floor below.")
            return
        # Object 29 — CAVE DRAWINGS at canon 97 (Oriental Room).
        if (noun == "drawings" or noun == "drawing") and er == 97:
            _println("The cave drawings are ancient and Oriental in style.")
            return
        # Object 37 — VOLCANO/GEYSER at canon 126 (Breath-taking
        # View). Also accept "geyser" as canon synonym.
        if (noun == "volcano" or noun == "geyser") and er == 126:
            _println("Great gouts of molten lava come surging out of an active volcano,")
            _println("cascading back down into the depths.")
            return
        # Object 40 — CARPET/MOSS at canon 96 (Soft Room).
        if (noun == "carpet" or noun == "moss") and er == 96:
            _println("The carpet is soft and the moss-covered ceiling muffles every sound.")
            return
        # Object 25 — PHONY PLANT (PLANT2) at the Twopit Room
        # (canon 23, west pit visible at 35). Canon prop reflects
        # the real plant's growth state in another pit; without
        # tracking PLANT2 props we emit the unconditional flavor.
        if (noun == "plant" or noun == "plant2") and (er == 23 or er == 35):
            _println("It's the top of a tall beanstalk poking out of the west pit.")
            return

    # All other verbs: pass to the FSM. Adventure's bus
    # dispatches through the aspects (DarknessGate may
    # consume look/examine in dark rooms, MagicWordTeleport
    # transforms xyzzy/plugh/plover into MOVE, etc.) and
    # returns the response string.
    var response: String = fsm.do_command(verb, noun)
    # Canon "unknown verb" randomization (advent.for STMT 3000):
    #     SPK = 60
    #     IF (PCT(20)) SPK = 61
    #     IF (PCT(20)) SPK = 13
    # Two chained PCT(20) calls produce a 64% / 16% / 20% mix:
    # 80%×80%=64% stays at #60; 80%×20%=16% lands on #61; 20%
    # always overrides to #13 regardless of the first check.
    # FSM emits "I don't know how to '<verb>'." for unknown verbs;
    # we substitute the canon msg matching one of these three
    # rolls.
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
    _check_chest_hint()
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
    # walk to canon 21 death). Port models chasm state via the
    # troll FSM's "vanished" terminal state (set by Adventure._
    # verb_drop when the bear is dropped at troll). The check
    # passes through the troll FSM accessor.
    if bg.check == "chasm_collapsed":
        if fsm.troll_state() == "vanished":
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
    if fsm.dwarf_threw_axe():
        _println("[color=#cc7777][i]A dwarf throws an axe at you — and connects! The axe finds your back.[/i][/color]")

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
    # Crowther/Woods credit splash — every CCA session opens
    # with explicit attribution to the original 1976/77 work
    # before any game prose. Era-appropriate plain text, no
    # emoji or modern iconography. Routed through `_println`
    # (rather than direct `output.append_text` calls) so the
    # captured-driver test can observe the welcome output.
    var rule: String = "[color=#a89878]─────────────────────────────[/color]"
    var msg: String = ""
    msg += "[color=#e0c890][b]COLOSSAL CAVE ADVENTURE[/b][/color]\n"
    msg += rule + "\n\n"
    msg += "  Originally written by [b]Will Crowther[/b] (1976)\n"
    msg += "  and expanded to the canonical 350-point version\n"
    msg += "  by [b]Don Woods[/b] at the Stanford AI Lab (1977).\n\n"
    msg += "[color=#a89878]"
    msg += "  This Frame state-machine implementation re-ports\n"
    msg += "  the original PDP-10 FORTRAN-IV source preserved at\n"
    msg += "  the Interactive Fiction Archive. Public domain;\n"
    msg += "  redistributed for historical record.\n"
    msg += "[/color]\n"
    msg += rule
    _println(msg)
    _println("Type [b]HELP[/b] for a list of commands.")

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
