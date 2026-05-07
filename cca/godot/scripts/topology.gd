# ============================================================
# topology.gd — CCA world geometry as pure data
# ============================================================
# Extracted from driver.gd so that non-driver consumers (the
# monkey fuzzer, the state explorer test, future visualisers)
# can reason about the room graph without instantiating a UI
# Control. The driver imports these tables; nothing else
# changes.
#
# ROOMS:    canonical room number → {direction → dest_room}
# GATES:    "from_room:direction" → {check, msg} for blockers
#           that must be cleared by FSM aspects (snake, troll,
#           crystal bridge, grate, plant) before the move
#           resolves.
#
# Numbering follows Crowther+Woods 1977 canon where possible;
# 130-139 are interpolated treasure side-rooms, 136 is the
# endgame Repository, 96-107 fill out the surface forest grid,
# 137-139 the final pre-Repository corridor.
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
#    18 Low room w/ "won't get it up the steps" sign  (dark; gold home — canon 18)
#    27 West bank fissure                  (dark) — canon 27
#    92 Giant Room                        (dark; eggs)
#    33 Y2 marker                         (dark; silver; magic-word hub)
#    97 Oriental Room                     (dark; vase)
#    40 Alcove                            (dark; spices)
#   100 Plover Room                       (lit; pearl; magic-word access only)
#    47 Snake passage (secret E-W canyon) (dark; snake blocking east)
#    69 Hall of Mirrors                   (dark; far side of fissure)
#    65 Bedquilt / bear chamber           (dark; bear, chain) — canon 65 (port keeps bear here pending Barren-Room move to canon 130)
#    71 Scorched cavern                   (dark; dragon, diamonds, rug)
#   117 Troll bridge                      (dark; troll blocking east)
#   118 Cliff with ledge (beyond bridge)  (dark; jewelry)
#    95 Magnificent Cavern (waterfall)    (dark; trident) — canon 95
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
#   PLOVER pairs 33 ↔ 100
# ============================================================
class_name CcaTopology
extends RefCounted

const ROOMS: Dictionary = {
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
    6:   {"east": 5, "west": 1, "north": 200},      # Forest 2
    7:   {"north": 4, "up": 4},                     # Slit (too small to enter)
    8:   {"north": 1, "up": 1, "down": 9, "in": 9}, # Depression / outside grate
    9:   {"up": 8, "out": 8, "west": 10, "in": 10}, # Below grate
    10:  {"east": 9, "west": 11},                   # Cobbles (canon surface entry)
    11:  {"out": 1, "up": 1, "north": 12, "east": 12}, # Debris room
    12:  {"up": 1, "down": 33, "north": 33, "south": 11, "west": 11}, # Awkward canyon
    33:  {"up": 12, "south": 28, "down": 13, "east": 47, "west": 65, "north": 14},
    28:  {"north": 33},                                                  # Low n/s passage at hole — canon 28 (silver home)
    13:  {"up": 33, "out": 33},
    100: {"north": 101},                     # Plover Room (canon 100) — north to canon Dark-room (101)
    47:  {"west": 33, "east": 71, "up": 44}, # snake-east gated; up to secret canyon side branch
    71:  {"west": 47, "north": 65},
    65:  {"south": 71, "east": 117, "west": 33, "north": 72, "down": 130}, # Bedquilt (canon 65) — down to canon 130 (Barren Room, bear)
    117: {"west": 65, "east": 118},          # troll-east gated below
    118: {"west": 117, "east": 120},
    # Deep cave loop — accessible after crossing troll bridge.
    # Linear chain east-west with each room hosting a treasure.
    120: {"west": 118, "east": 97},
    97:  {"west": 120, "east": 92, "north": 39},                         # Oriental Room (canon 97) — vase
    92:  {"west": 97, "east": 95},                                       # Giant Room (canon 92) — eggs
    95:  {"west": 92, "east": 131},                                      # Magnificent Cavern (canon 95) — trident, waterfall
    131: {"west": 95, "east": 40},
    40:  {"west": 131, "east": 132},
    132: {"west": 40, "east": 133},
    133: {"west": 132, "east": 134},
    134: {"west": 133, "east": 135},
    135: {"west": 134},
    130: {"up": 65, "out": 65},              # Barren Room — canon 130 (BEAR_HOME_ROOM); up/out back to Bedquilt
    # Rod-puzzle branch: hangs off Y2 (33) to the north. The
    # fissure (17) is the gate; crossing east requires the
    # crystal bridge (waved up by the rod).
    14:  {"south": 33, "north": 17, "down": 15},  # top of small pit
    17:  {"south": 14, "east": 69, "west": 27},   # fissure — east gated; west to other side
    18:  {"north": 15},                            # Low room w/ "won't get it up the steps" sign — canon 18 (gold home)
    27:  {"east": 17, "west": 19},                # West bank of fissure — canon 27
    69:  {"west": 17},                            # hall of mirrors (across)
    # Mist + King hall + two-pit + plant + slab area. Hangs off
    # the top of small pit (14) via a stone staircase down. The
    # Hall of Mists (15) is the regional hub; King Hall (19) is
    # the western centerpoint. The slab area (34-37) hangs off
    # the rock-jumble junction (30) and is largely a dead-end
    # for atmosphere.
    15:  {"up": 14, "east": 16, "west": 19, "south": 18, "north": 21},   # Hall of Mists
    16:  {"west": 15, "north": 206, "up": 17, "east": 103},              # East end of mists; east to canon 103 Shell Room
    19:  {"east": 15, "north": 30, "south": 29},                        # Hall of Mt King — north canon-30, south canon-29
    20:  {"north": 19},                                                  # South entry (port-orphan; canon 20 is broken-neck death msg)
    29:  {"north": 19},                                                  # South side chamber — canon 29 (jewelry home)
    30:  {"south": 19},                                                  # West side chamber Hall of Mt King — canon 30 (coins home)
    21:  {"south": 15, "east": 22, "west": 25},                          # Two-pit room — canon-aligned: west to canon 25 (Bottom of west pit, plant)
    22:  {"out": 21, "up": 21},                                          # East pit (dead-end)
    25:  {"out": 21, "up": 24, "climb": 24},                             # Bottom of west pit — canon 25 (plant home)
    24:  {"down": 25, "up": 23, "climb": 23},                            # Mid-beanstalk
    23:  {"down": 24},                                                   # Top of vast crack (port-synth name; reachable up the beanstalk)
    26:  {"south": 19, "north": 204},                                    # Narrow corridor
    204: {"south": 26, "north": 205, "west": 50},                       # Above immense passage (port-synth; canon 27 = west fissure)
    205: {"south": 204, "east": 206},                                   # Immense passage (port-synth; canon 29 is south side chamber)
    206: {"south": 16, "west": 205, "north": 31, "down": 34, "east": 58},# Jumble of rock (port-synth; canon 30 = west side chamber)
    31:  {"south": 206, "north": 32},                                    # Window on pit (low)
    32:  {"south": 31},                                                  # Window on pit (high)
    34:  {"up": 206, "north": 35},                                       # Low dust chamber
    35:  {"south": 34, "north": 36},                                     # Sloping corridor
    36:  {"south": 35, "west": 37},                                      # Above slab
    37:  {"east": 36},                                                   # Slab room (dead-end)
    # --- Side passages (39, 101 + 43-49) ---
    # 39 hangs off the Oriental Room (97) to the north. 101 is the
    # canon Dark-room — reachable from Plover (100) via
    # north (a one-way exit; you can't go back through Plover
    # without the magic word). 43-49 form a side branch off the
    # snake passage (47).
    39:  {"south": 97},                                                  # Misty cavern
    101: {"south": 100, "out": 100, "north": 43},                       # Dark-room — canon 101 (pyramid home)
    43:  {"south": 101, "north": 44},                                    # Wide place
    44:  {"south": 43, "north": 45, "down": 47},                         # Secret canyon
    45:  {"south": 44, "east": 46},                                      # Tight place
    46:  {"west": 45, "east": 48},                                       # Tall E/W passage
    48:  {"west": 46, "east": 49},                                       # Boulders cluster
    49:  {"west": 48},                                                   # Limestone passage (dead-end)
    # --- Maze of twisty little passages, all alike (50-57) ---
    # Entry from "Above the immense passage" (204) via west. All
    # 8 rooms share the same description ("a maze of twisty
    # little passages, all alike"), so the player can't tell
    # them apart from look. Exit topology is deliberately non-
    # uniform — going "north" from one room and "north" from
    # the next-identical-looking room lands you in different
    # places. The canon CCA puzzle is to mark visited rooms by
    # dropping items, then map the maze. Only room 50's east
    # exit returns to room 204 (the way back out). Some
    # directions are missing to create dead-end "you can't go
    # that way" branches.
    50:  {"east": 204, "north": 51, "south": 52, "west": 53},
    51:  {"north": 54, "south": 55, "west": 50},
    52:  {"east": 56, "north": 57, "south": 50},
    53:  {"east": 51, "south": 54},
    54:  {"north": 50, "east": 56},
    55:  {"east": 51, "south": 57},
    56:  {"west": 52, "north": 54},
    57:  {"north": 55, "south": 53, "east": 50},
    # --- Maze of twisty passages, all different (58-64 + 203) ---
    # Entry from rock-jumble junction (30) via east.
    # Synthesized terminal room moved 65 → 203 to free canon
    # room 65 (Bedquilt).
    58:  {"west": 206, "east": 59, "south": 60},
    59:  {"west": 58, "east": 61, "north": 62},
    60:  {"north": 58, "east": 63},
    61:  {"west": 59, "east": 64},
    62:  {"south": 59, "east": 203},
    63:  {"west": 60, "east": 64},
    64:  {"west": 63, "north": 203, "east": 66},
    203: {"south": 64, "west": 62},                                      # port-synth maze terminal (canon 65 = Bedquilt)
    # --- Witt's End trio (66-68) ---
    66:  {"west": 64, "east": 67, "down": 68},
    67:  {"west": 66},                                                   # Witt's End — apparent dead-end
    68:  {"up": 66},                                                     # Bottom of polished cone
    # --- Phase E: Bedquilt extensions, reservoir, treasury,
    # cliff-and-ladder descent, post-cave outdoors, forest grid ---
    # 72-86: deeper passages, soft room, reservoir, barren room.
    # Most chain off Bedquilt (65) or each other.
    72:  {"south": 65, "north": 73},                                     # Sloping corridor
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
    # 96-99 + 200: forest grid on the surface — these chain off
    # the existing forest rooms (5, 6) and the road/valley.
    # Port-synthesized: canon has only forest rooms 5 and 6.
    # The "Forest NW" room moved from 100 → 200 to free room
    # 100 for canonical Plover Room.
    96:  {"south": 5, "east": 201},                                      # Forest NE-of-road
    201: {"west": 96, "south": 98},                                      # Forest SE-of-road (port-synth; canon 97 is Oriental Room)
    98:  {"north": 201, "west": 99},                                     # Forest SE/SW
    99:  {"east": 98, "north": 200},                                     # Forest SW-of-road
    200: {"south": 99, "east": 6},                                       # Forest NW (port-synthesized; canon 100 is Plover Room — moved out of canon range)
    # 108, 115, 116: pre-repository corridor.
    # Threads from snake passage / rear of dragon area into the
    # endgame approach.
    108: {"east": 115, "north": 67},                                     # Fork
    # Canon 115/116 = NE/SW Repository — the cave-closing teleport
    # destination. Reached non-canon via the 108→115→116 corridor for
    # walking access; the canonical route is the Adventure.tick()
    # teleport that fires when endgame transitions to $InRepository.
    115: {"west": 108, "east": 116},                                     # NE Repository
    116: {"west": 115},                                                  # SW Repository — terminal endgame room
    # 119, 121-129: cliff-and-ladder descent + sub-anteroom area.
    119: {"up": 87, "down": 121},                                        # Cliff face with ladder
    121: {"up": 119, "north": 123, "east": 125, "south": 122, "west": 124}, # Bottom of ladder
    123: {"south": 121, "north": 126},                                   # Anteroom with pictographs
    125: {"west": 121},                                                  # Anteroom with niches
    # --- Phase F: iconic remainder ---
    # Decorated chamber (88), different soft passage (202), Vending
    # Machine Room (canon 140) — canon CCA's pre-endgame Easter egg with
    # the "BATTERIES — 25 CENTS" sign. Plus a couple of forest
    # variants (102-103) and miscellaneous passages. (Port-101
    # was a forest filler; it has been removed because canon 101
    # is the Dark-room — see canon-101 entry above.)
    88:  {"east": 76, "south": 90},                                      # Decorated chamber
    202: {"south": 91, "east": 140},                                    # Different soft passage (port-synth; canon 92 is Giant Room)
    140: {"west": 202},                                                  # Vending Machine Room (port-synth at canon 140 — handled in Phase 7e)
    102: {"north": 201},                                                 # Forest far south
    103: {"west": 16},                                                   # Shell Room — canon 103 (clam home)
    109: {"east": 113},                                                  # Low passage (curving west)
    113: {"west": 109, "down": 121},                                     # Wide chamber
    122: {"north": 121},                                                 # Anteroom — basalt
    124: {"east": 121},                                                  # Anteroom — red stone
    126: {"south": 123, "north": 127},                                  # Breath-taking view (canon 126; north to canon 127 Chamber of Boulders)
    # --- Round 10: canon-completion fillers (104-107, 110-114, 127-129) ---
    # Forest grid completion + inner-anteroom cluster.
    104: {"south": 96, "east": 105},                                     # Dense forest
    105: {"west": 104, "south": 201, "east": 106},                       # Scrub forest
    106: {"west": 105, "north": 107},                                    # Forest clearing (water source flavor)
    107: {"south": 106, "west": 200},                                    # Forest path
    110: {"east": 109, "north": 111},                                    # Low passage with claw-marks
    111: {"south": 110, "east": 112, "down": 114},                       # Different secret canyon
    112: {"west": 111, "north": 113},                                    # Tall canyon
    114: {"up": 111},                                                    # Crystal grotto (dead-end)
    127: {"south": 126, "east": 128},                                    # Chamber of Boulders — canon 127 (spices home)
    128: {"west": 127, "down": 129},                                     # Different inner anteroom
    129: {"up": 128},                                                    # Polished slab chamber (dead-end)
}

# Movements that require a clear NPC to traverse. Each entry:
# (from_room, direction) → (npc query name, blocked-message).
# Adventure exposes snake/troll blocking via accessor; the
# driver checks them before letting the player through.
const GATES: Dictionary = {
    # Snake at canon 19 (Hall of Mountain King) blocks the
    # canyon exits north (to canon 30, coins) and south (to
    # canon 29, jewelry). East back to 15 is unguarded — that's
    # how the player retreats. Bird-release at 19 sends snake
    # away.
    "19:north":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:south":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "117:east":  {"check": "troll",  "msg": "The troll bars your way until you pay tribute."},
    "17:east":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "8:down":    {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:in":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # Beanstalk climb gates: 25→24 (canon West Pit → mid-beanstalk)
    # needs at least $Tall; 24→23 (mid → top of crack) needs $Huge.
    # Without water the plant is just a tiny shoot murmuring
    # "water, water" — no climbing.
    "25:up":     {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "25:climb":  {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "24:up":     {"check": "plant_huge", "msg": "The plant is too feeble to support your weight any higher."},
    "24:climb":  {"check": "plant_huge", "msg": "The plant is too feeble to support your weight any higher."},
}
