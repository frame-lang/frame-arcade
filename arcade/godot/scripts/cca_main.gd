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
# Canonical Crowther+Woods 1977 room numbering. Where a room
# has a canonical analog, we use that number; interpolated
# rooms (treasure side-rooms not in canon) take numbers in
# the 130-139 gap zone above the canon repository (140).
#
# Mapping intent:
#     1 End of road / outside building   (lit, surface)
#     2 Hill in road                      (lit, surface)
#     3 Inside well house                 (lit; DEPOSIT_ROOM)
#     4 Valley                            (lit, surface)
#     5 Forest 1                          (lit, surface)
#     6 Forest 2                          (lit, surface)
#     7 Slit in streambed                 (lit, surface)
#     8 Outside grate / depression        (lit, surface)
#     9 Below the grate                   (dark; cave entry)
#    10 Cobbles (canon surface entry)     (dark; transit)
#    11 Debris room                       (dark; gold; rod)
#    12 Awkward sloping E/W canyon        (dark; transit)
#    13 Bird chamber                      (dark; bird)
#    14 Top of small pit                  (dark; rod-puzzle approach)
#    17 East of fissure                   (dark; gated by crystal bridge)
#    28 Giant Room                        (dark; eggs)
#    33 Y2 marker                         (dark; silver; magic-word hub)
#    38 Oriental Room                     (dark; vase)
#    40 Alcove                            (dark; spices)
#    41 Plover Room                       (lit; pearl; magic-word access only)
#    47 Snake passage (secret E-W canyon) (dark; snake blocking east)
#    69 Hall of Mirrors                   (dark; far side of fissure)
#    70 Bedquilt / bear chamber           (dark; bear, chain)
#    71 Scorched cavern                   (dark; dragon, diamonds, rug)
#   117 Troll bridge                      (dark; troll blocking east)
#   118 Cliff with ledge (beyond bridge)  (dark; jewelry)
#   130 Sapphire Hallway      (interpolated, dark; trident)
#   131 Vast Hall             (interpolated, dark; emerald)
#   132 Pirate's chest cavern (interpolated, dark; chest)
#   133 Pyramid Chamber       (interpolated, dark; pyramid)
#   134 Coin Niche            (interpolated, dark; coins)
#   135 Sloping Passage       (interpolated, dark; statuette)
#   136 Repository                        (endgame destination)
#
# Magic-word teleports (handled by the FSM's MagicWordTeleport
# aspect, not these tables):
#   XYZZY  pairs 1 ↔ 11
#   PLUGH  pairs 1 ↔ 33
#   PLOVER pairs 33 ↔ 41
# ------------------------------------------------------------
var room_exits: Dictionary = {
    # Surface block — canon descent: road → slit/depression → grate.
    # The grate is described but not currently gated (would need a
    # Grate FSM + keys handling — same shape as CrystalBridge, so
    # we don't add it just to demonstrate the same pattern again).
    1:   {"north": 2, "up": 2, "south": 4, "down": 4, "east": 8,
          "west": 5, "in": 3, "enter": 3},
    2:   {"down": 1, "south": 1},                   # Hill in road
    3:   {"south": 1, "out": 1, "down": 12},        # Well house
    4:   {"north": 1, "up": 1, "south": 7, "down": 7, "east": 5, "west": 6},  # Valley
    5:   {"east": 1, "west": 6, "north": 96},       # Forest 1
    6:   {"east": 5, "west": 1, "north": 100},      # Forest 2
    7:   {"north": 4, "up": 4},                     # Slit (too small to enter)
    8:   {"north": 1, "up": 1, "down": 9, "in": 9}, # Depression / outside grate
    9:   {"up": 8, "out": 8, "west": 10, "in": 10}, # Below grate
    10:  {"east": 9, "west": 11},                   # Cobbles (canon surface entry)
    11:  {"out": 1, "up": 1, "north": 12, "east": 12}, # Debris room
    12:  {"up": 1, "down": 33, "north": 33, "south": 11, "west": 11}, # Awkward canyon
    33:  {"up": 12, "south": 12, "down": 13, "east": 47, "west": 70, "north": 14},
    13:  {"up": 33, "out": 33},
    41:  {"north": 42},                      # Plover Room — magic exits + north to dark room
    47:  {"west": 33, "east": 71, "up": 44}, # snake-east gated; up to secret canyon side branch
    71:  {"west": 47, "north": 70},
    70:  {"south": 71, "east": 117, "west": 33, "north": 72},
    117: {"west": 70, "east": 118},          # troll-east gated below
    118: {"west": 117, "east": 120},
    # Deep cave loop — accessible after crossing troll bridge.
    # Linear chain east-west with each room hosting a treasure.
    120: {"west": 118, "east": 38},
    38:  {"west": 120, "east": 28, "north": 39},
    28:  {"west": 38, "east": 130},
    130: {"west": 28, "east": 131},
    131: {"west": 130, "east": 40},
    40:  {"west": 131, "east": 132},
    132: {"west": 40, "east": 133},
    133: {"west": 132, "east": 134},
    134: {"west": 133, "east": 135},
    135: {"west": 134},
    136: {},                                 # Repository — terminal endgame room
    # Rod-puzzle branch: hangs off Y2 (33) to the north. The
    # fissure (17) is the gate; crossing east requires the
    # crystal bridge (waved up by the rod).
    14:  {"south": 33, "north": 17, "down": 15},  # top of small pit
    17:  {"south": 14, "east": 69, "west": 18},   # fissure — east gated; west to other side
    18:  {"east": 17, "west": 19},                # west side of fissure
    69:  {"west": 17},                            # hall of mirrors (across)
    # Mist + King hall + two-pit + plant + slab area. Hangs off
    # the top of small pit (14) via a stone staircase down. The
    # Hall of Mists (15) is the regional hub; King Hall (19) is
    # the western centerpoint. The slab area (34-37) hangs off
    # the rock-jumble junction (30) and is largely a dead-end
    # for atmosphere.
    15:  {"up": 14, "east": 16, "west": 19, "south": 18, "north": 21},   # Hall of Mists
    16:  {"west": 15, "north": 30, "up": 17},                            # East end of mists
    19:  {"east": 15, "north": 26, "south": 20},                         # Hall of Mt King
    20:  {"north": 19},                                                  # South entry
    21:  {"south": 15, "east": 22, "west": 23},                          # Two-pit room
    22:  {"out": 21, "up": 21},                                          # East pit (dead-end)
    23:  {"out": 21, "up": 24, "climb": 24},                             # West pit
    24:  {"down": 23, "up": 25, "climb": 25},                            # Plant — middle
    25:  {"down": 24},                                                   # Plant — top
    26:  {"south": 19, "north": 27},                                     # Narrow corridor
    27:  {"south": 26, "north": 29, "west": 50},                         # Above immense passage
    29:  {"south": 27, "east": 30},                                      # Immense passage
    30:  {"south": 16, "west": 29, "north": 31, "down": 34, "east": 58}, # Jumble of rock
    31:  {"south": 30, "north": 32},                                     # Window on pit (low)
    32:  {"south": 31},                                                  # Window on pit (high)
    34:  {"up": 30, "north": 35},                                        # Low dust chamber
    35:  {"south": 34, "north": 36},                                     # Sloping corridor
    36:  {"south": 35, "west": 37},                                      # Above slab
    37:  {"east": 36},                                                   # Slab room (dead-end)
    # --- Side passages (39, 42-49) ---
    # 39 hangs off the Oriental Room (38) to the north. 42 is the
    # "dark room after Plover" — reachable from Plover (41) via
    # north (a one-way exit; you can't go back through Plover
    # without the magic word). 43-49 form a side branch off the
    # snake passage (47).
    39:  {"south": 38},                                                  # Misty cavern
    42:  {"south": 41, "out": 41, "north": 43},                          # Dark room after Plover
    43:  {"south": 42, "north": 44},                                     # Wide place
    44:  {"south": 43, "north": 45, "down": 47},                         # Secret canyon
    45:  {"south": 44, "east": 46},                                      # Tight place
    46:  {"west": 45, "east": 48},                                       # Tall E/W passage
    48:  {"west": 46, "east": 49},                                       # Boulders cluster
    49:  {"west": 48},                                                   # Limestone passage (dead-end)
    # --- Maze of twisty little passages, all alike (50-57) ---
    # Entry from "Above the immense passage" (27) via west. All
    # 8 rooms share the same description ("a maze of twisty
    # little passages, all alike"), so the player can't tell
    # them apart from look. Exit topology is deliberately non-
    # uniform — going "north" from one room and "north" from
    # the next-identical-looking room lands you in different
    # places. The canon CCA puzzle is to mark visited rooms by
    # dropping items, then map the maze. Only room 50's east
    # exit returns to room 27 (the way back out). Some
    # directions are missing to create dead-end "you can't go
    # that way" branches.
    50:  {"east": 27, "north": 51, "south": 52, "west": 53},
    51:  {"north": 54, "south": 55, "west": 50},
    52:  {"east": 56, "north": 57, "south": 50},
    53:  {"east": 51, "south": 54},
    54:  {"north": 50, "east": 56},
    55:  {"east": 51, "south": 57},
    56:  {"west": 52, "north": 54},
    57:  {"north": 55, "south": 53, "east": 50},
    # --- Maze of twisty passages, all different (58-65) ---
    # Entry from rock-jumble junction (30) via east.
    58:  {"west": 30, "east": 59, "south": 60},
    59:  {"west": 58, "east": 61, "north": 62},
    60:  {"north": 58, "east": 63},
    61:  {"west": 59, "east": 64},
    62:  {"south": 59, "east": 65},
    63:  {"west": 60, "east": 64},
    64:  {"west": 63, "north": 65, "east": 66},
    65:  {"south": 64, "west": 62},
    # --- Witt's End trio (66-68) ---
    66:  {"west": 64, "east": 67, "down": 68},
    67:  {"west": 66},                                                   # Witt's End — apparent dead-end
    68:  {"up": 66},                                                     # Bottom of polished cone
    # --- Phase E: Bedquilt extensions, reservoir, treasury,
    # cliff-and-ladder descent, post-cave outdoors, forest grid ---
    # 72-86: deeper passages, soft room, reservoir, barren room.
    # Most chain off Bedquilt (70) or each other.
    72:  {"south": 70, "north": 73},                                     # Sloping corridor
    73:  {"south": 72, "down": 74},                                      # Sloping room above large round chamber
    74:  {"up": 73, "north": 75, "south": 80},                           # Large low room
    75:  {"south": 74, "north": 76},                                     # Sloping corridor
    76:  {"south": 75, "north": 77},                                     # Soft Room
    77:  {"south": 76, "east": 78, "down": 79},                          # Steep canyon
    78:  {"west": 77, "east": 81, "north": 87},                          # Different secret canyon
    79:  {"up": 77, "east": 82},                                         # Steep passage
    80:  {"north": 74, "east": 81},                                      # Dirty passage
    81:  {"west": 80, "north": 78, "down": 83},                          # Wet room
    82:  {"west": 79, "east": 83},                                       # Different cobble crawl
    83:  {"up": 81, "west": 82, "east": 84},                             # Reservoir
    84:  {"west": 83, "down": 85},                                       # Underground stream
    85:  {"up": 84, "east": 86},                                         # Front of barren room
    86:  {"west": 85},                                                   # Barren room (dead-end)
    # 87-94: cliff brink, cylindrical canyon, treasury area.
    # Brought together off the secret canyons (78/93) and the
    # cliff-with-ladder (119) chain.
    87:  {"east": 89, "down": 119, "south": 78},                         # Brink of cliff
    89:  {"west": 87, "north": 90},                                      # Cylindrical canyon
    90:  {"south": 89, "east": 91},                                      # Smooth passage
    91:  {"west": 90, "north": 93},                                      # Different soft passage
    93:  {"south": 91, "east": 94},                                      # Different fissure
    94:  {"west": 93},                                                   # Treasury (dead-end)
    # 96-100: forest grid on the surface — these chain off the
    # existing forest rooms (5, 6) and the road/valley.
    96:  {"south": 5, "east": 97},                                       # Forest NE-of-road
    97:  {"west": 96, "south": 98},                                      # Forest SE-of-road
    98:  {"north": 97, "west": 99},                                      # Forest SE/SW
    99:  {"east": 98, "north": 100},                                     # Forest SW-of-road
    100: {"south": 99, "east": 6},                                       # Forest NW (back to known forest)
    # 108, 115, 116: pre-repository corridor.
    # Threads from snake passage / rear of dragon area into the
    # endgame approach.
    108: {"east": 115, "north": 67},                                     # Fork
    115: {"west": 108, "east": 116},                                     # End of corridor
    116: {"west": 115, "down": 136},                                     # Pre-Repository
    # 119, 121-129: cliff-and-ladder descent + sub-anteroom area.
    119: {"up": 87, "down": 121},                                        # Cliff face with ladder
    121: {"up": 119, "north": 123, "east": 125, "south": 122, "west": 124}, # Bottom of ladder
    123: {"south": 121, "north": 126},                                   # Anteroom with pictographs
    125: {"west": 121},                                                  # Anteroom with niches
    # --- Phase F: iconic remainder ---
    # Decorated chamber (88), different soft passage (92), Vending
    # Machine Room (95) — canon CCA's pre-endgame Easter egg with
    # the "BATTERIES — 25 CENTS" sign. Plus more forest variants
    # (101-103) and miscellaneous passages.
    88:  {"east": 76, "south": 90},                                      # Decorated chamber
    92:  {"south": 91, "east": 95},                                      # Different soft passage
    95:  {"west": 92, "down": 116},                                      # Vending Machine Room
    101: {"west": 96},                                                   # Forest far east
    102: {"north": 97},                                                  # Forest far south
    103: {"east": 99},                                                   # Forest far west
    109: {"east": 113},                                                  # Low passage (curving west)
    113: {"west": 109, "down": 121},                                     # Wide chamber
    122: {"north": 121},                                                 # Anteroom — basalt
    124: {"east": 121},                                                  # Anteroom — red stone
    126: {"south": 123},                                                 # Anteroom — fireplace
    # --- Round 10: canon-completion fillers (104-107, 110-114, 127-129, 137-139) ---
    # Forest grid completion + inner-anteroom cluster + the
    # final pre-Repository corridor. These bring the room
    # total to ~140 (canon scope).
    104: {"south": 96, "east": 105},                                     # Dense forest
    105: {"west": 104, "south": 97, "east": 106},                        # Scrub forest
    106: {"west": 105, "north": 107},                                    # Forest clearing (water source flavor)
    107: {"south": 106, "west": 100},                                    # Forest path
    110: {"east": 109, "north": 111},                                    # Low passage with claw-marks
    111: {"south": 110, "east": 112, "down": 114},                       # Different secret canyon
    112: {"west": 111, "north": 113},                                    # Tall canyon
    114: {"up": 111},                                                    # Crystal grotto (dead-end)
    127: {"south": 126, "east": 128},                                    # Inner anteroom
    128: {"west": 127, "down": 129},                                     # Different inner anteroom
    129: {"up": 128},                                                    # Polished slab chamber (dead-end)
    137: {"north": 116, "down": 138},                                    # Antechamber outside Repository
    138: {"up": 137, "east": 139, "south": 136},                         # Final corridor
    139: {"west": 138},                                                  # EXIT plaque chamber (dead-end)
}

# Movements that require a clear NPC to traverse. Each entry:
# (from_room, direction) → (npc query name, blocked-message).
# Adventure exposes snake/troll blocking via accessor; we
# check them before letting the player through.
var gated_exits: Dictionary = {
    "47:east":   {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "117:east":  {"check": "troll",  "msg": "The troll bars your way until you pay tribute."},
    "17:east":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "8:down":    {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:in":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # Beanstalk climb gates: 23→24 needs at least $Tall; 24→25
    # needs $Huge. Without water the plant is just a tiny shoot
    # murmuring "water, water" — no climbing.
    "23:up":     {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "23:climb":  {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "24:up":     {"check": "plant_huge", "msg": "The plant is too feeble to support your weight any higher."},
    "24:climb":  {"check": "plant_huge", "msg": "The plant is too feeble to support your weight any higher."},
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
var _save_path: String = "user://cca.save"     # cabinet convention: matches Arcade.save_path("cca")

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
    exit_dialog = ExitDialogScript.new()
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

func _process(_delta: float) -> void:
    # Bolt focus to the input box. Anything in CCA except the
    # exit dialog should leave keyboard focus in the LineEdit.
    # Per-frame re-grab catches Tab, clicks, focus signals
    # during text submission, and any other drift.
    if input != null and not exit_dialog.is_open() and not input.has_focus():
        input.grab_focus()

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
    label_exit_dialog.text = "Save before quitting?\n\n[Enter] Quit (default)    [S] Save and quit\n[Esc] Cancel"
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
[b]Special:[/b] LIGHT (lamp), EXTINGUISH, FEED BEAR, RELEASE BIRD, WAVE ROD, UNLOCK GRATE, INSERT COINS.
[b]Bottle:[/b]  TAKE BOTTLE, FILL BOTTLE (at water), POUR / WATER PLANT, DRINK.
[b]Magic:[/b]   XYZZY, PLUGH, PLOVER (in the right places).
[b]Chants:[/b]  FEE / FIE / FOE / FOO (in sequence).
[b]Meta:[/b]    SAVE, LOAD, SCORE, HINT [name], QUIT.
""")

# ============================================================
# Cabinet integration: Esc opens the Save/Quit dialog FSM.
#
# The dialog FSM (ExitDialog in arcade/frame/dialog.fgd) owns
# the modal logic. The driver:
#   - opens it on Esc when no dialog is active
#   - feeds key events as confirm_quit / confirm_save_quit /
#     cancel based on which key was pressed
#   - reads last_action() after each event and acts on it
# Key bindings:
#   Enter / Space  → confirm_quit (default)
#   S              → confirm_save_quit
#   Esc            → cancel back to game
# ============================================================
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed):
        return

    if exit_dialog.is_open():
        get_viewport().set_input_as_handled()
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
            exit_dialog.confirm_quit()
        elif event.keycode == KEY_S:
            exit_dialog.confirm_save_quit()
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

func _show_exit_dialog() -> void:
    label_exit_dialog.visible = true
    # Take focus off the LineEdit so its keystrokes don't fight
    # the dialog handler. We restore on cancel.
    if input != null:
        input.release_focus()

func _hide_exit_dialog() -> void:
    label_exit_dialog.visible = false
    if input != null:
        input.grab_focus()

# When the application window regains focus (alt-tab back, click
# on a different app and return, etc.), Godot doesn't restore
# which Control had keyboard focus before — so the LineEdit
# stops accepting keystrokes until the player clicks it again.
# We listen for the focus-in notification and re-grab.
func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_IN:
        if input != null:
            input.grab_focus()
