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
# Non-treasure carriables (mirror Adventure.ROD_ID / KEYS_ID /
# BOTTLE_ID in cca/frame/cca.fgd).
const ROD_ID := 130
const KEYS_ID := 131
const BOTTLE_ID := 132

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
    # End of road — canon row `1 2 2 44 29` (HILL/W/UP→2),
    # `1 3 3 12 19 43` (ENTER/BUILDING/IN/E→3), `1 4 5 13 14 46 30`
    # (DOWNS/GULLY/STREAM/S/DOWN→4), `1 5 6 45 ...` (FOREST/N→5).
    1:   {"north": 5, "south": 4, "east": 3, "west": 2,
          "up": 2, "down": 4, "in": 3, "enter": 3,
          "hill": 2, "forest": 5, "stream": 4, "gully": 4,
          "building": 3, "downstream": 4, "depression": 8},
    # Hill in road — canon row `2 1 2 12 7 43 45 30` (HILL/BUILD/
    # FORWARD/E/N/DOWN→1), `2 5 6 45 46` (FOREST/N/S→5).
    2:   {"north": 1, "south": 5, "east": 1, "down": 1,
          "hill": 1, "building": 1, "forward": 1, "forest": 5},
    # Well house — canon row `3 1 3 11 32 44` (ENTER/OUT/SURFACE/W
    # → 1), `3 79 5 14` (DOWNSTREAM/STREAM → 79). Magic words
    # XYZZY (62) → 11 and PLUGH (65) → 33 are handled by the
    # MagicWordTeleport aspect, not these tables.
    3:   {"west": 1, "out": 1, "enter": 1, "stream": 79, "downstream": 79, "outdoors": 1},
    # Valley — canon row `4 1 4 12 45` (UPSTR/BUILD/N→1),
    # `4 5 6 43 44 29` (FOREST/E/W/UP→5), `4 7 5 46 30` (DOWNS/S/DOWN→7).
    4:   {"north": 1, "south": 7, "east": 5, "west": 5, "up": 5, "down": 7,
          "upstream": 1, "building": 1, "forest": 5, "downstream": 7, "depression": 8},
    # Forest 1 — canon row `5 4 9 43 30` (VALLEY/E/DOWN→4),
    # `5 6 6` (FOREST→6), `5 5 44 46` (W/S→5; "lost in forest"
    # self-loop). Port-only "north → 96" shortcut to Soft Room
    # removed for canon faithfulness.
    5:   {"south": 5, "east": 4, "west": 5, "down": 4, "forest": 6, "valley": 4},
    # Forest 2 — canon row `6 1 2 45` (HILL/N→1), `6 4 9 43 44 30`
    # (VALLEY/E/W/DOWN→4), `6 5 6 46` (FOREST/S→5).
    6:   {"north": 1, "south": 5, "east": 4, "west": 4, "down": 4,
          "hill": 1, "forest": 5, "valley": 4},
    # Slit in streambed — canon row `7 1 12` (BUILDING→1),
    # `7 4 4 45` (UPSTR/N→4), `7 5 6 43 44` (FOREST/E/W→5),
    # `7 8 5 15 16 46` (DOWNS/ROCK/BED/S→8). The slit itself
    # is "too small to enter" (canon msg #60 special handler);
    # the regular exits remain.
    7:   {"north": 4, "south": 8, "east": 5, "west": 5,
          "forest": 5, "building": 1, "upstream": 4,
          "downstream": 8, "rock": 8, "bed": 8},
    # Depression / outside grate — canon row `8 5 6 43 44 46`
    # (FOREST/E/W/S→5), `8 1 12` (BUILDING→1), `8 7 4 13 45`
    # (UPSTR/GULLY/N→7). Plus canon special-handler row
    # `8 303009 3 19 30` for ENTER/IN/DOWN→9 gated by the grate
    # (encoded in our GATES dict, with the destination=9 added
    # explicitly here so the unconditional path resolves to 9
    # when the grate is unlocked).
    8:   {"north": 7, "south": 5, "east": 5, "west": 5,
          "forest": 5, "gully": 7, "building": 1, "upstream": 7,
          "down": 9, "in": 9, "enter": 9},
    # Below grate — canon row `9 10 11 17 18 19 44`
    # (W/IN/CRAWL/COBBLES→10). Canon has no UP/OUT path back to
    # the surface — once you're under the grate you commit to
    # the cave entry crawl. Port-only "up": 8 / "out": 8 removed
    # for canon faithfulness; the player can still type UP and
    # get a "you can't go that way" deflection from the parser.
    # Below grate (canon 9): plain rows for W/IN/CRAWL/COBBLES → 10,
    # PIT → 14, DEBRIS → 11. Plus conditional `9 303008 11 29` for
    # OUT/UP → 8 when grate unlocked — symmetric to 8:down/in.
    9:   {"west": 10, "in": 10, "crawl": 10, "cobbles": 10,
          "pit": 14, "debris": 11,
          "up": 8, "out": 8},
    # Cobbles — canon row `10 9 11 17 18 20 43`
    # (E/OUT/CRAWL/COBBL/SURFA→9), `10 11 17 18 19 23 44`
    # (W/IN/CRAWL/COBBL/PASSA→11). Note "crawl" and "cobbles"
    # appear on both sides; canon's first-row-wins picks the
    # west/in destination for those words.
    10:  {"east": 9, "west": 11, "in": 11, "out": 9, "surface": 9,
          "dark": 11, "debris": 11, "pit": 14},
    # Debris room — canon row `11 9 64` (ENTRANCE→9),
    # `11 10 17 18 23 24 43` (CRAWL/COBBL/PASSAGE/LOW/E→10),
    # `11 12 25 19 29 44` (CANYON/IN/UP/W→12), `11 14 31`
    # (PIT→14). XYZZY (62) → 3 is handled by MagicWordTeleport.
    # Debris room (canon 11). Plain rows + canon `11 303008 63`
    # adds DEPRESSION verb as a teleport back to canon 8 when
    # the grate is unlocked. Same shortcut at 12/13/14.
    11:  {"east": 10, "west": 12, "up": 12, "in": 12,
          "crawl": 10, "cobbles": 10, "passage": 10, "low": 10,
          "canyon": 12, "pit": 14, "entrance": 9,
          "depression": 8},
    # Awkward sloping E/W canyon — canon row `12 9 64`
    # (ENTRANCE→9), `12 11 30 43 51` (DOWN/E/DEBRIS→11),
    # `12 13 19 29 44` (IN/UP/W→13), `12 14 31` (PIT→14).
    # Removed port-only N→33, S→11; canon has neither.
    12:  {"east": 11, "west": 13, "up": 13, "down": 11, "in": 13,
          "pit": 14, "entrance": 9, "debris": 11,
          "depression": 8},
    # Y2 marker — canon 33. Canon `33 28 46` (S→28), `33 34 43 53 54`
    # (E/WALL/BROKEN→34), `33 35 44` (W→35). PLUGH(65)→3 and
    # PLOVER(71)→100 are magic words handled by MagicWordTeleport.
    33:  {"south": 28, "east": 34, "west": 35,
          "wall": 34, "broken": 34},
    # Low n/s passage at hole — canon 28 (silver home). Canon
    # `28 19 38 11 46` (HALL/OUT/S→19), `28 33 45 55` (N/Y2→33),
    # `28 36 30 52` (DOWN/HOLE→36).
    28:  {"south": 19, "out": 19, "hall": 19, "north": 33, "y2": 33,
          "down": 36, "hole": 36},
    # Bird chamber — canon row `13 9 64` (ENTRANCE→9),
    # `13 11 51` (DEBRIS→11), `13 12 25 43` (CANYON/E→12),
    # `13 14 23 31 44` (PASSAGE/PIT/W→14). XYZZY/PLUGH/PLOVER
    # access is via magic word, not a direct exit. Port-only
    # UP/OUT→33 removed for canon faithfulness.
    13:  {"east": 12, "west": 14, "passage": 14, "pit": 14,
          "canyon": 12, "entrance": 9, "debris": 11,
          "depression": 8},
    # Plover Room — canon 100. West to alcove (99) via tight
    # tunnel (gated on emerald-only inventory); north to Dark-room
    # (port-direction; canon NE). PLOVER chant teleports to 33.
    # Plover Room — canon 100. Canon `100 99 44` (W→99 via tight
    # tunnel, gated by squeeze), `100 33 71` (PLOVER→33), and
    # `100 101 47 22` (NE→101 the Dark-room, gated by emerald).
    # Special-handler row 159302 is the PLOVER teleport variant.
    100: {"west": 99, "ne": 101, "dark": 101, "plover": 33},
    # Canon 41 = West End of Hall of Mists. Canon `41 42 46 29 23 56`
    # (S/UP/PASSAGE/CLIMB→42), `41 27 43` (E→27), `41 59 45`
    # (N→59), `41 60 44 17` (W/CRAWL→60).
    41:  {"south": 42, "up": 42, "passage": 42, "climb": 42,
          "east": 27, "north": 59, "west": 60, "crawl": 60},
    # Canon 42 = "ALIKE" maze room. Canon `42 41 29` (UP→41),
    # `42 42 45` (N→42 self loop), `42 43 43` (E→43),
    # `42 45 46` (S→45), `42 80 44` (W→80).
    42:  {"up": 41, "north": 42, "east": 43, "south": 45, "west": 80},
    # Canon 43 = "ALIKE" maze room. `43 42 44` (W→42),
    # `43 44 46` (S→44), `43 45 43` (E→45).
    43:  {"west": 42, "south": 44, "east": 45},
    # Canon 44 = "ALIKE" maze room. `44 43 43` (E→43),
    # `44 48 30` (DOWN→48), `44 50 46` (S→50), `44 82 45` (N→82).
    44:  {"east": 43, "down": 48, "south": 50, "north": 82},
    # Canon 45 = "ALIKE" maze room. `45 42 44` (W→42),
    # `45 43 45` (N→43), `45 46 43` (E→46), `45 47 46` (S→47),
    # `45 87 29 30` (UP/DOWN→87).
    45:  {"west": 42, "north": 43, "east": 46, "south": 47,
          "up": 87, "down": 87},
    # Canon 46 = DEAD END. `46 45 44 11` (W/OUT→45).
    46:  {"west": 45, "out": 45},
    # Canon 47 = DEAD END. `47 45 43 11` (E/OUT→45).
    47:  {"east": 45, "out": 45},
    # Canon 48 = DEAD END. `48 44 29 11` (UP/OUT→44).
    48:  {"up": 44, "out": 44},
    # Canon 49 = "ALIKE" maze room. `49 50 43` (E→50),
    # `49 51 44` (W→51).
    49:  {"east": 50, "west": 51},
    # Canon 50 = "ALIKE" maze room. `50 44 43` (E→44),
    # `50 49 44` (W→49), `50 51 30` (DOWN→51), `50 52 46` (S→52).
    50:  {"east": 44, "west": 49, "down": 51, "south": 52},
    # Canon 71 (secret canyon at three-canyon junction): canon
    # `71 65 48` (SE→65), `71 70 46` (S→70), `71 110 45` (N→110).
    71:  {"se": 65, "south": 70, "north": 110},
    # Bedquilt — canon 65. Canon `65 64 43` (E→64), `65 66 44`
    # (W→66), `65 68 61` (SLAB→68), `65 39 29` (UP→39),
    # `65 71 45` (N→71), `65 106 30` (DOWN→106). Plus several
    # canon special-handler rows (80556 etc.) for randomized
    # branches we don't fully model.
    65:  {"east": 64, "west": 66, "slab": 68, "up": 39,
          "north": 71, "down": 106},
    # Canon 117 (R_SWSIDE — SW side of chasm; troll bridge):
    # `117 118 49` SW→118 (descent into sloping corridor); the
    # 233660/303/596 specials are the gated OVER/ACROSS/CROSS/NE
    # crossing → R_TROLL → R_NESIDE (122). Per Quuxplusone Advent
    # ODWY0350 R_SWSIDE entry. Gated on troll absent (see GATES).
    117: {"sw": 118, "over": 122, "across": 122, "cross": 122, "ne": 122},
    # Canon 118 (other side of chasm): `118 72 30` (DOWN→72),
    # `118 117 29` (UP→117).
    118: {"down": 72, "up": 117},
    # Deep cave loop — accessible after crossing troll bridge.
    # Linear chain east-west with each room hosting a treasure.
    # Canon 120 (secret canyon, exits N and E): `120 69 45` (N→69),
    # `120 74 43` (E→74). Port-only W→118 / E→97 removed.
    120: {"north": 69, "east": 74},
    # Canon 97 (Oriental Room, vase home): `97 66 48` (SE→66),
    # `97 72 44 17` (W/CRAWL→72), `97 98 29 45 73` (UP/N/CAVERN→98).
    97:  {"se": 66, "west": 72, "crawl": 72, "up": 98, "north": 98,
          "cavern": 98},
    # Canon 92 (Giant Room, eggs home): `92 88 46` (S→88),
    # `92 93 43` (E→93), `92 94 45` (N→94).
    92:  {"south": 88, "east": 93, "north": 94},
    # Canon 95 (Magnificent Cavern, trident): `95 94 46 11`
    # (S/OUT→94), `95 92 27` (GIANT→92), `95 91 44` (W→91).
    95:  {"south": 94, "out": 94, "giant": 92, "west": 91},
    # Canon 2nd maze (131-139): "twisty maze, all DIFFERENT". Canon
    # gives each room 10 exits to siblings + entry points 107 / 112,
    # with directions deliberately scrambled so a player can't tell
    # one room from another. We use a simplified linear-chain
    # topology (the canonical maze prose still reads correct on
    # `look`) — full canon-exit encoding is a future polish step.
    # Canon 2nd maze (131-139) — "TWISTY MAZE OF LITTLE PASSAGES,
    # ALL DIFFERENT" — 9 rooms whose only difference from the
    # player's view is word-order in the prose. Canon assigns 10
    # verbs per room (N/S/E/W + 4 diagonals + UP/DOWN) to a
    # carefully scrambled set of destinations so that compass
    # rules don't help at all. Every dict below is canon-verbatim
    # from advent.dat section 2.
    131: {"north": 138, "south": 139, "east": 112, "west": 107,
          "ne": 135, "se": 132, "sw": 134, "nw": 133,
          "up": 136, "down": 137},
    # Canon 40 = "VERY LOW WIDE PASSAGE PARALLEL TO HALL OF
    # MISTS." Canon row `40 41 1` is a one-way bounce: any
    # verb routes to 41 (West End of Hall of Mists). We add an
    # explicit OUT/EAST/WEST/BACK→41 escape.
    40:  {"out": 41, "east": 41, "west": 41, "back": 41},
    132: {"north": 133, "south": 134, "east": 138, "west": 135,
          "ne": 137, "se": 112, "sw": 136, "nw": 107,
          "up": 131, "down": 139},
    133: {"north": 137, "south": 112, "east": 136, "west": 132,
          "ne": 134, "se": 139, "sw": 135, "nw": 138,
          "up": 107, "down": 131},
    134: {"north": 131, "south": 137, "east": 135, "west": 139,
          "ne": 107, "se": 133, "sw": 112, "nw": 132,
          "up": 138, "down": 136},
    135: {"north": 107, "south": 133, "east": 134, "west": 136,
          "ne": 138, "se": 131, "sw": 137, "nw": 139,
          "up": 112, "down": 132},
    136: {"north": 112, "south": 135, "east": 107, "west": 131,
          "ne": 139, "se": 138, "sw": 133, "nw": 137,
          "up": 132, "down": 134},
    137: {"north": 136, "south": 132, "east": 139, "west": 112,
          "ne": 131, "se": 107, "sw": 138, "nw": 135,
          "up": 134, "down": 133},
    138: {"north": 135, "south": 136, "east": 131, "west": 134,
          "ne": 132, "se": 137, "sw": 139, "nw": 112,
          "up": 133, "down": 107},
    139: {"north": 134, "south": 138, "east": 132, "west": 133,
          "ne": 112, "se": 136, "sw": 107, "nw": 131,
          "up": 137, "down": 135},
    # Barren Room — canon 130 (BEAR_HOME_ROOM, chain). Canon
    # `130 129 44 11` (W/OUT→129), `130 124 77` (FORK→124),
    # `130 126 28` (VIEW→126).
    130: {"west": 129, "out": 129, "fork": 124, "view": 126},
    # Rod-puzzle branch: hangs off Y2 (33) to the north. The
    # fissure (17) is the gate; crossing east requires the
    # crystal bridge (waved up by the rod).
    # Top of small pit — canon row `14 9 64` (ENTRANCE→9),
    # `14 11 51` (DEBRIS→11), `14 13 23 43` (PASSAGE/E→13),
    # `14 15 30` (DOWN→15), `14 16 33 44` (CRACK/W→16). The
    # canon special-handler row `14 150020 ...` is the
    # fall-into-pit branch handled by gameplay logic, not these
    # tables. Port-only S→33 / N→17 removed.
    14:  {"east": 13, "west": 16, "down": 15,
          "passage": 13, "entrance": 9, "debris": 11, "crack": 16,
          "depression": 8},
    # East bank of fissure — canon row `17 15 38 43`
    # (HALL/E→15), `17 412597 41 42 44 69` (OVER/ACROSS/W/CROSS
    # → 27 gated by crystal bridge). EAST and HALL go back to
    # Hall of Mists ungated.
    17:  {"east": 15, "hall": 15,
          "over": 27, "across": 27, "west": 27, "cross": 27},
    # Low room w/ "won't get it up the steps" sign — canon 18.
    # Canon row `18 15 38 11 45` (HALL/OUT/N→15). Pirate's
    # stash spawns here (CHEST_ROOM = 18).
    18:  {"north": 15, "out": 15, "hall": 15},
    # West bank of fissure — canon 27. Canon `27 17 41` (OVER→17
    # gated by bridge), `27 40 45` (N→40), `27 41 44` (W→41).
    # Special-handler rows 27 312596/412021/412597 are the
    # fall-into-pit conditional cases handled engine-side.
    27:  {"north": 40, "west": 41,
          "over": 17, "across": 17, "east": 17, "cross": 17},
    # Canon 69 = secret N/S canyon above a large room. Canon
    # `69 68 30 61` (DOWN/SLAB→68), `69 119 46` (S→119),
    # `69 109 45` (N→109), `69 113 75` (RESERVOIR→113). The
    # special-handler row 331120 is a randomized branch.
    # Port-only "west: 17" hall-of-mirrors removed.
    69:  {"down": 68, "slab": 68, "south": 119, "north": 109,
          "reservoir": 113},
    # Mist + King hall + two-pit + plant + slab area. Hangs off
    # the top of small pit (14) via a stone staircase down. The
    # Hall of Mists (15) is the regional hub; King Hall (19) is
    # the western centerpoint. The slab area (34-37) hangs off
    # the rock-jumble junction (30) and is largely a dead-end
    # for atmosphere.
    # Hall of Mists east end — canon 15. Canon row `15 18 36 46`
    # (LEFT/S→18), `15 17 7 38 44` (FORWARD/HALL/W→17),
    # `15 19 10 30 45` (STAIRS/DOWN/N→19), `15 14 29` (UP→14),
    # `15 34 55` (Y2 magic word→34 — handled by MagicWordTeleport).
    # Special-handler row `15 150022 ...` is the rod-puzzle pit
    # check; encoded via gameplay logic.
    15:  {"up": 14, "west": 17, "south": 18, "north": 19, "down": 19,
          "left": 18, "forward": 17, "hall": 17, "stairs": 19,
          "y2": 34},
    # Crack — canon 16. Canon row `16 14 1` is the engine
    # "any-verb-falls-back-to-14" handler that prints the
    # transition message ("the crack is far too small to
    # follow") then bounces the player back to 14. Without
    # canon's NULL-verb handling, we add a single explicit
    # OUT/EAST/BACK route to 14 so the player can escape.
    16:  {"east": 14, "out": 14, "back": 14},
    # Hall of the Mountain King — canon 19. Canon row
    # `19 15 10 29 43` (STAIRS/UP/E→15), `19 32 45` (N→32 is the
    # snake-block message room, fired when condition fails),
    # `19 311028 45 36` (N/LEFT→28 silver passage when snake gone),
    # `19 311029 46 37` (S/RIGHT→29 jewelry when snake gone),
    # `19 311030 44 7` (W/FORWARD→30 coins when snake gone),
    # `19 74 66` (SECRET→74 different secret canyon).
    # GATES handles the snake-blocking condition; we encode the
    # destinations directly so canon-aligned walking works once
    # the bird has driven the snake off.
    # SW removed from topology (canon `19 35074 49` is 35%
    # probability + `19 211032 49` snake-here); both rows wired
    # at GATES `19:sw` as a chain.
    19:  {"east": 15, "stairs": 15, "up": 15,
          "north": 28, "left": 28,
          "south": 29, "right": 29,
          "west": 30, "forward": 30,
          "secret": 74},
    # Canon 20 is the "YOU ARE AT THE BOTTOM OF THE PIT WITH A
    # BROKEN NECK." death message room — canon row `20 0 1` is
    # the engine's "kill the player and skip" handler. No walking
    # exits in canon. Port-only `north: 19` removed.
    20:  {},
    # South side chamber — canon 29 (jewelry home). Canon
    # `29 19 38 11 45` (HALL/OUT/N→19).
    29:  {"north": 19, "out": 19, "hall": 19},
    # West side chamber Hall of Mt King — canon 30 (coins home).
    # Canon `30 19 38 11 43` (HALL/OUT/E→19), `30 62 44 29`
    # (W/UP→62 secret canyon).
    30:  {"east": 19, "out": 19, "hall": 19, "west": 62, "up": 62},
    # Canon 21 = "YOU DIDN'T MAKE IT." death message; canon row
    # `21 0 1` is the engine kill handler. No walking exits.
    21:  {},
    # Canon 22 = "THE DOME IS UNCLIMBABLE." transition message;
    # canon row `22 15 1` bounces back to 15.
    22:  {"out": 15, "back": 15},
    # West pit (plant home) — canon 25. Canon `25 23 29 11`
    # (UP→23 gated by plant tall), `25 26 56` (CLIMB→26 the
    # transition "scurry through the hole" message).
    25:  {"up": 23, "out": 23, "climb": 26},
    # East pit — canon 24. Canon `24 67 29 11` (UP/OUT→67 east
    # end of two-pit room).
    24:  {"up": 67, "out": 67},
    # West end of two-pit room — canon 23. Canon
    # `23 67 43 42` (E/ACROSS→67), `23 68 44 61` (W/SLAB→68),
    # `23 25 30 31` (DOWN/PIT→25).
    23:  {"east": 67, "across": 67, "west": 68, "slab": 68,
          "down": 25, "pit": 25},
    # Canon 26 = "YOU CLAMBER UP THE PLANT AND SCURRY THROUGH
    # THE HOLE AT THE TOP." transition; canon `26 88 1` bounces
    # to canon 88 (decorated chamber). Single explicit east
    # exit covers the player's escape.
    26:  {"east": 88, "out": 88, "back": 88},
    # Canon 31 (PIT — bottomless pit, fall-to-death). Canon
    # rows `31 524089 1` and `31 90 1` are death encodings; no
    # walking exits.
    31:  {},
    # Canon 32 = "YOU CAN'T GET BY THE SNAKE." transition msg.
    # Canon `32 19 1` bounces back to 19. Explicit OUT/BACK→19.
    32:  {"out": 19, "back": 19, "south": 19},
    # Canon 34 = jumble of rock with cracks. Canon `34 33 30 55`
    # (DOWN/Y2→33), `34 15 29` (UP→15).
    34:  {"down": 33, "y2": 33, "up": 15},
    # Canon 35 = sloping corridor with cracks. Canon `35 33 43 55`
    # (E/Y2→33), `35 20 39` (JUMP→20 death pit).
    35:  {"east": 33, "y2": 33, "jump": 20},
    # Canon 36 = dirty broken passage. Canon `36 37 43 17`
    # (E/CRAWL→37), `36 28 29 52` (UP/HOLE→28), `36 39 44` (W→39),
    # `36 65 70` (BEDQUILT→65).
    36:  {"east": 37, "crawl": 37, "up": 28, "hole": 28,
          "west": 39, "bedquilt": 65},
    # Canon 37 = brink of pit. Canon `37 36 44 17` (W/CRAWL→36),
    # `37 38 30 31 56` (DOWN/PIT/CLIMB→38).
    37:  {"west": 36, "crawl": 36, "down": 38, "pit": 38, "climb": 38},
    # --- Side passages (39, 101 + 43-49) ---
    # 39 hangs off the Oriental Room (97) to the north. 101 is the
    # canon Dark-room — reachable from Plover (100) via
    # north (a one-way exit; you can't go back through Plover
    # without the magic word). 43-49 form a side branch off the
    # snake passage (47).
    # Canon 38 = bottom of small pit. Canon `38 37 56 29 11`
    # (CLIMB/UP→37 with condition).
    38:  {"up": 37, "climb": 37, "out": 37},
    # Canon 39 = large room with dusty rocks. Canon `39 36 43 23`
    # (E/PASSAGE→36), `39 64 30 52 58` (DOWN/HOLE/FLOOR→64),
    # `39 65 70` (BEDQUILT→65).
    39:  {"east": 36, "passage": 36, "down": 64, "hole": 64,
          "floor": 64, "bedquilt": 65},
    # Dark-room — canon 101 (pyramid home). Canon `101 100 46 71 11`
    # (S/PLOVER/OUT→100). PLOVER chant handled by MagicWordTeleport.
    101: {"south": 100, "out": 100},
    # Rooms 43-50 already canon-aligned above as part of the
    # "secret canyon / first maze" cluster.
    # --- Maze of twisty little passages, all alike (50-57) ---
    # All
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
    # Room 50 already canon-aligned above. Rooms 51-57 will be
    # rewritten in the next batch (canon `^5N\t` rows).
    # --- Rooms 58-64: assorted passages (canon 58 = DEAD END,
    # 59 = parallel low passage, 60-61 = long featureless hall,
    # 62 = crossover, 63 = DEAD END, 64 = complex junction). ---
    # Canon 51 (alike maze): `51 49 44` (W→49), `51 50 29` (UP→50),
    # `51 52 43` (E→52), `51 53 46` (S→53).
    51:  {"west": 49, "up": 50, "east": 52, "south": 53},
    # Canon 52 (alike maze): `52 50 44` (W→50), `52 51 43` (E→51),
    # `52 52 46` (S→52 self-loop), `52 53 29` (UP→53),
    # `52 55 45` (N→55), `52 86 30` (DOWN→86).
    52:  {"west": 50, "east": 51, "south": 52, "up": 53,
          "north": 55, "down": 86},
    # Canon 53 (alike maze): `53 51 44` (W→51), `53 52 45` (N→52),
    # `53 54 46` (S→54).
    53:  {"west": 51, "north": 52, "south": 54},
    # Canon 54 (DEAD END): `54 53 44 11` (W/OUT→53).
    54:  {"west": 53, "out": 53},
    # Canon 55 (alike maze): `55 52 44` (W→52), `55 55 45` (N→55
    # self-loop), `55 56 30` (DOWN→56), `55 57 43` (E→57).
    55:  {"west": 52, "north": 55, "down": 56, "east": 57},
    # Canon 56 (DEAD END): `56 55 29 11` (UP/OUT→55).
    56:  {"up": 55, "out": 55},
    # Canon 57 (orange-column pit / brink): `57 13 30 56`
    # (DOWN/CLIMB→13), `57 55 44` (W→55), `57 58 46` (S→58),
    # `57 83 45` (N→83), `57 84 43` (E→84).
    57:  {"down": 13, "climb": 13, "west": 55, "south": 58,
          "north": 83, "east": 84},
    # Canon 58 (DEAD END): `58 57 43 11` (E/OUT→57).
    58:  {"east": 57, "out": 57},
    # Canon 59 (parallel low passage): `59 27 1` is any-verb→27;
    # explicit OUT/EAST/SOUTH/BACK→27.
    59:  {"out": 27, "east": 27, "south": 27, "back": 27},
    # Canon 60 (long featureless hall east end): `60 41 43 29 17`
    # (E/UP/CRAWL→41), `60 61 44` (W→61), `60 62 45 30 52`
    # (N/DOWN/HOLE→62).
    60:  {"east": 41, "up": 41, "crawl": 41, "west": 61,
          "north": 62, "down": 62, "hole": 62},
    # Canon 61 (long featureless hall west end): `61 60 43`
    # (E→60), `61 62 45` (N→62). Special-handler 100107 is
    # the randomized "lost in maze" branch.
    61:  {"east": 60, "north": 62, "south": 107},
    # Canon 62 (high N/S + low E/W crossover): `62 60 44`
    # (W→60), `62 63 45` (N→63), `62 30 43` (E→30 west side
    # chamber Mt King), `62 61 46` (S→61).
    62:  {"west": 60, "north": 63, "east": 30, "south": 61},
    # Canon 63 (DEAD END): `63 62 46 11` (S/OUT→62).
    63:  {"south": 62, "out": 62},
    # Canon 64 (complex junction): `64 39 29 56 59` (UP/CLIMB/
    # ROOM→39), `64 65 44 70` (W/BEDQUILT→65), `64 103 45 74`
    # (N/SHELL→103), `64 106 43` (E→106).
    64:  {"up": 39, "climb": 39, "room": 39, "west": 65,
          "bedquilt": 65, "north": 103, "shell": 103, "east": 106},
    # --- Witt's End trio (66-68) ---
    # Canon 66 (swiss cheese room): `66 65 47` (NE→65), `66 67 44`
    # (W→67), `66 77 25` (CANYON→77), `66 96 43` (E→96),
    # `66 97 72` (ORIENTAL→97). Special 50556/80556 are
    # randomized branches.
    66:  {"ne": 65, "west": 67, "canyon": 77, "east": 96, "oriental": 97},
    # Canon 67 (east end of TwoPit room): `67 66 43` (E→66),
    # `67 23 44 42` (W/ACROSS→23), `67 24 30 31` (DOWN/PIT→24).
    67:  {"east": 66, "west": 23, "across": 23, "down": 24, "pit": 24},
    # Canon 68 (large low circular slab room): `68 23 46`
    # (S→23), `68 69 29 56` (UP/CLIMB→69), `68 65 45` (N→65).
    68:  {"south": 23, "up": 69, "climb": 69, "north": 65},
    # Canon 70 (secret canyon above sizable passage): `70 71 45`
    # (N→71), `70 65 30 23` (DOWN/PASSAGE→65), `70 111 46`
    # (S→111).
    70:  {"north": 71, "down": 65, "passage": 65, "south": 111},
    # --- Phase E: Bedquilt extensions, reservoir, treasury,
    # cliff-and-ladder descent, post-cave outdoors, forest grid ---
    # 72-86: deeper passages, soft room, reservoir, barren room.
    # Most chain off Bedquilt (65) or each other.
    # Canon 72 (sloping corridor): `72 65 70` (BEDQUILT→65),
    # `72 118 49` (SW→118), `72 73 45` (N→73), `72 97 48 72`
    # (SE/ORIENTAL→97).
    72:  {"bedquilt": 65, "sw": 118, "north": 73, "se": 97, "oriental": 97},
    # Canon 73 (DEAD END CRAWL): `73 72 46 17 11` (S/CRAWL/OUT→72).
    73:  {"south": 72, "crawl": 72, "out": 72},
    # Canon 74 (secret canyon E/W): `74 19 43` (E→19), `74 121 44`
    # (W→121), `74 75 30` (DOWN→75). Special-handler 331120 is
    # randomized.
    74:  {"east": 19, "west": 121, "down": 75},
    # Canon 75 (wide place in tight canyon): `75 76 46` (S→76),
    # `75 77 45` (N→77).
    75:  {"south": 76, "north": 77},
    # Canon 76 (canyon too tight south): `76 75 45` (N→75).
    76:  {"north": 75},
    # Canon 77 (tall E/W canyon): `77 75 43` (E→75), `77 78 44`
    # (W→78), `77 66 45 17` (N/CRAWL→66).
    77:  {"east": 75, "west": 78, "north": 66, "crawl": 66},
    # Canon 78 (canyon dead-end at boulders): `78 77 46` (S→77).
    78:  {"south": 77},
    # Canon 79 (sewer-pipe death): `79 3 1` is engine "any-verb→3"
    # bounce. Explicit OUT/UP/BACK→3.
    79:  {"out": 3, "up": 3, "back": 3},
    # Canon 80 (alike maze): `80 42 45` (N→42), `80 80 44` (W
    # self), `80 80 46` (S self), `80 81 43` (E→81).
    80:  {"north": 42, "west": 80, "south": 80, "east": 81},
    # Canon 81 (DEAD END): `81 80 44 11` (W/OUT→80).
    81:  {"west": 80, "out": 80},
    # Canon 82 (DEAD END): `82 44 46 11` (S/OUT→44? wait verb 44=W).
    # Reading: `82 44 46 11` → dest 44 via verbs 46(S) and 11(OUT).
    # So canon 82 S/OUT → 44.
    82:  {"south": 44, "out": 44},
    # Canon 83 (alike maze): `83 57 46` (S→57), `83 84 43` (E→84),
    # `83 85 44` (W→85).
    83:  {"south": 57, "east": 84, "west": 85},
    # Canon 84 (alike maze): `84 57 45` (N→57), `84 83 44` (W→83),
    # `84 114 50` (NW→114).
    84:  {"north": 57, "west": 83, "nw": 114},
    # Canon 85 (DEAD END): `85 83 43 11` (E/OUT→83).
    85:  {"east": 83, "out": 83},
    # Canon 86 (DEAD END): `86 52 29 11` (UP/OUT→52).
    86:  {"up": 52, "out": 52},
    # 87-94: cliff brink, cylindrical canyon, treasury area.
    # Brought together off the secret canyons (78/93) and the
    # cliff-with-ladder (119) chain.
    # Canon 87 (Brink of thirty-foot cliff). Canon `87 45 29 30`
    # (UP/DOWN→45). The cliff descent is handled by the
    # condition-based "fall into pit" branches engine-side.
    87:  {"up": 45, "down": 45},
    # Canon 89 (transition msg "nothing to climb"): `89 25 1`
    # bounces to 25; explicit OUT/UP/BACK→25.
    89:  {"out": 25, "up": 25, "back": 25},
    # Canon 90 (transition msg "climb up plant out"): `90 23 1`
    # bounces to 23; explicit OUT/UP/BACK→23.
    90:  {"out": 23, "up": 23, "back": 23},
    # Canon 91 (Steep incline above large room): `91 95 45 73 23`
    # (N/CAVERN/PASSAGE→95), `91 72 30 56` (DOWN/CLIMB→72).
    91:  {"north": 95, "cavern": 95, "passage": 95,
          "down": 72, "climb": 72},
    # Canon 93 (Cave-in, blocking N from Giant Room): `93 92 46 27 11`
    # (S/GIANT/OUT→92).
    93:  {"south": 92, "giant": 92, "out": 92},
    # Canon 94 (Immense N/S passage): `94 92 46 27 23` (S/GIANT/
    # PASSAGE→92), `94 611 45` (special), `94 309095 45 3 73`
    # (N/CAVERN/ENTER→canon 95 with conditional).
    94:  {"south": 92, "giant": 92, "passage": 92,
          "north": 95, "enter": 95, "cavern": 95},
    # 96-99: canon forest grid surrounding the road/valley.
    # All four are canonical (advent.dat "different forest, NE/SW/SE/NW").
    # Canon 96 (Soft Room): `96 66 44 11` (W/OUT→66).
    96:  {"west": 66, "out": 66},
    # Canon 98 (Wide path around large cavern): `98 97 46 72`
    # (S/ORIENTAL→97), `98 99 44` (W→99).
    98:  {"south": 97, "oriental": 97, "west": 99},
    # Canon: 99 (alcove) is connected EAST to 100 (Plover Room)
    # via a tight crawl gated on inventory. The forest connection
    # to 98 moves to the canon "down" direction so both routes can
    # coexist in a single-direction-key topology.
    # Alcove — canon 99. Canon `99 98 50 73` (NW/CAVERN→98),
    # `99 100 43` (E→100 via tight tunnel, gated by squeeze).
    # Special-handler row 301 is the squeeze "drop everything"
    # branch handled by GATES.
    99: {"east": 100, "nw": 98, "cavern": 98},
    # 108, 115, 116: pre-repository corridor.
    # Threads from snake passage / rear of dragon area into the
    # endgame approach.
    # Witt's End — canon 108. Canon `108 106 43` (E→106) plus
    # the special-handler row `108 95556 ...` which scrambles
    # 8 compass directions to a randomized "you are at Witt's
    # End" maze of self-loops. The port keeps a non-canon
    # `north → 67` shortcut to Bedquilt cluster (whitelisted in
    # the audit) so testing scaffolding can reach 108 from a
    # known checkpoint.
    # Canon 108 (Witt's End): canon's three section-3 rows say
    # 95% chance any of E/N/S/NE/SE/SW/NW/UP/DOWN prints msg #56
    # and stays put; 5% E falls through to room 106; W is always
    # the cave-in bumper msg #126. ROOMS holds only the canon
    # `108 106 43` plain row; everything else is gated below.
    108: {"east": 106},
    # Canon 115/116 = NE/SW Repository — reachable ONLY via the
    # cave-closing teleport that fires in Adventure.tick() when
    # endgame transitions to $InRepository. Walking corridor from
    # 108 was a port holdover removed in Phase 7i.
    # Canon 115 (NE end of Repository): `115 116 49` (SW→116).
    115: {"sw": 116, "east": 116},
    # Canon 116 (SW end of Repository, terminal endgame): canon
    # `116 115 47` (NE→115). Special-handler 593 is the cave-
    # closing teleport-from-anywhere encoding.
    116: {"ne": 115, "west": 115},
    # 119, 121-129: cliff-and-ladder descent + sub-anteroom area.
    # Canon 119 (secret canyon at dragon's lair): `119 69 45 11`
    # (N/OUT→69). Special 653 is dragon-related.
    119: {"north": 69, "out": 69},
    # Canon 121 (DEAD END at the cave's south end): canon
    # `121 74 43 11` (E/OUT→74). Special 653 = dragon.
    121: {"east": 74, "out": 74},
    # Canon 123 (anteroom, pictographs): canon `123 122 44`
    # (W→122), `123 124 43 77` (E/FORK→124), `123 126 28`
    # (VIEW→126), `123 129 40` (BARREN→129).
    123: {"west": 122, "east": 124, "fork": 124,
          "view": 126, "barren": 129},
    # Canon 125 (anteroom with niches): canon `125 124 46 77`
    # (S/FORK→124), `125 126 45 28` (N/VIEW→126),
    # `125 127 43 17` (E/CRAWL→127).
    125: {"south": 124, "fork": 124, "north": 126, "view": 126,
          "east": 127, "crawl": 127},
    # --- Phase F: iconic remainder ---
    # Decorated chamber (88), Vending Machine Room (canon 140 —
    # vending mechanic itself is a port-synth holdover from
    # Adventure 2 / 550-point edition, scheduled for Phase 7e
    # cleanup). Plus the canon Shell Room (103) and forest
    # variant (102).
    # Canon 88 (decorated chamber, dragon's room? actually
    # canon's "narrow east-stretching corridor"). Canon
    # `88 25 30 56 43` (DOWN/CLIMB/E→25), `88 20 39` (JUMP→20
    # death), `88 92 44 27` (W/GIANT→92).
    88:  {"down": 25, "climb": 25, "east": 25,
          "jump": 20, "west": 92, "giant": 92},
    # Canon 140 = "DEAD END" room (vending machine in our port).
    # Canon `140 112 45 11` (N/OUT→112).
    140: {"north": 112, "out": 112},
    # Canon 102 (Arched Hall): `102 103 30 74 11` (DOWN/SHELL/OUT→103).
    102: {"down": 103, "shell": 103, "out": 103},
    # Canon 103 (Shell Room, clam home): `103 102 29 38` (UP/HALL→102),
    # `103 104 30` (DOWN→104), `103 64 46` (S→64). Specials skipped.
    103: {"up": 102, "hall": 102, "down": 104, "south": 64},
    # Canon 109 (north/south canyon ~25 ft across): `109 69 46`
    # (S→69), `109 113 45 75` (N/RESERVOIR→113).
    109: {"south": 69, "north": 113, "reservoir": 113},
    # Canon 113 (edge of large reservoir): `113 109 46 11 109`
    # (S/OUT/RESERVOIR→109).
    113: {"south": 109, "out": 109, "reservoir": 109},
    # Canon 122 (R_NESIDE — far/NE side of chasm). Canon
    # `122 123 47` (NE→123), `122 124 77` (FORK→124),
    # `122 126 28` (VIEW→126), `122 129 40` (BARREN→129).
    # OVER/ACROSS/CROSS/SW crosses back to R_SWSIDE (117) via
    # R_TROLL; gated on troll being absent (see GATES).
    122: {"ne": 123, "fork": 124, "view": 126, "barren": 129,
          "over": 117, "across": 117, "cross": 117, "sw": 117},
    # Canon 124 (path forks): canon `124 123 44` (W→123),
    # `124 125 47 36` (NE/LEFT→125), `124 128 48 37 30`
    # (SE/RIGHT/DOWN→128), `124 126 28` (VIEW→126),
    # `124 129 40` (BARREN→129).
    124: {"west": 123, "ne": 125, "left": 125,
          "se": 128, "right": 128, "down": 128,
          "view": 126, "barren": 129},
    # Canon 126 (breath-taking view of volcano): canon
    # `126 125 46 23 11` (S/PASSAGE/OUT→125), `126 124 77`
    # (FORK→124). Special 610 is the volcano-jump.
    126: {"south": 125, "passage": 125, "out": 125, "fork": 124},
    # --- Round 10: canon-completion fillers (104-107, 110-114, 127-129) ---
    # Forest grid completion + inner-anteroom cluster.
    # Canon 104 (sloping corridor, ragged sharp walls): `104 103 29 74`
    # (UP/SHELL→103), `104 105 30` (DOWN→105).
    104: {"up": 103, "shell": 103, "down": 105},
    # Canon 105 (cul-de-sac eight feet across): `105 104 29 11`
    # (UP/OUT→104), `105 103 74` (SHELL→103).
    105: {"up": 104, "out": 104, "shell": 103},
    # Canon 106 (anteroom leading to large E passage): `106 64 29`
    # (UP→64), `106 65 44` (W→65), `106 108 43` (E→108).
    106: {"up": 64, "west": 65, "east": 108},
    # Canon 107 = "MAZE OF TWISTY LITTLE PASSAGES, ALL DIFFERENT" —
    # the second maze entry. Canon row sets all eight compass + UP +
    # DOWN to scrambled destinations 131-139, plus DOWN→61.
    # `107 131 46` (S→131), `107 132 49` (SW→132), `107 133 47` (NW→133),
    # `107 134 48` (SE→134), `107 135 29` (UP→135), `107 136 50` (NW→136),
    # `107 137 43` (E→137), `107 138 44` (W→138), `107 139 45` (N→139),
    # `107 61 30` (DOWN→61).
    # First-write wins so my generator captures one verb per (verb→dest)
    # pair. The audit accepts canon rows in declaration order.
    107: {"south": 131, "sw": 132, "ne": 133, "se": 134,
          "up": 135, "nw": 136, "east": 137, "west": 138,
          "north": 139, "down": 61},
    # Canon 110 (low window overlooking pit): `110 71 44` (W→71),
    # `110 20 39` (JUMP→20 death pit).
    110: {"west": 71, "jump": 20},
    # Canon 111 (large stalactite extends from roof): `111 70 45`
    # (N→70), `111 45 30` (DOWN→45). Special 40050/50053 are
    # the stalactite-jump conditional branches.
    111: {"north": 70, "down": 45},
    # Canon 112 ("LITTLE MAZE OF TWISTING PASSAGES, ALL DIFFERENT") —
    # second-maze entry from the deep cave. Canon `112 131 49`
    # (SW→131), `112 132 45` (N→132), `112 133 43` (E→133),
    # `112 134 50` (NW→134), `112 135 48` (SE→135), `112 136 47`
    # (NW→136 — first-write wins; canon files have NW twice),
    # `112 137 44` (W→137), `112 138 30` (DOWN→138),
    # `112 139 29` (UP→139), `112 140 46` (S→140).
    112: {"sw": 131, "north": 132, "east": 133, "nw": 134,
          "se": 135, "ne": 136, "west": 137, "down": 138, "up": 139,
          "south": 140},
    # Canon 114 (DEAD END): `114 84 48` (SE→84).
    114: {"se": 84, "out": 84},
    # Canon 127 (Chamber of Boulders, spices home): canon
    # `127 125 44 11 17` (W/OUT/CRAWL→125), `127 124 77`
    # (FORK→124), `127 126 28` (VIEW→126).
    127: {"west": 125, "out": 125, "crawl": 125, "fork": 124, "view": 126},
    # Canon 128 (sloping passage with limestone formations):
    # canon `128 124 45 29 77` (N/UP/FORK→124),
    # `128 129 46 30 40` (S/DOWN/BARREN→129), `128 126 28`
    # (VIEW→126).
    128: {"north": 124, "up": 124, "fork": 124,
          "south": 129, "down": 129, "barren": 129,
          "view": 126},
    # Canon 129 (entrance to Barren Room): canon
    # `129 128 44 29` (W/UP→128), `129 124 77` (FORK→124),
    # `129 130 43 19 40 3` (E/IN/BARREN/ENTER→130),
    # `129 126 28` (VIEW→126).
    129: {"west": 128, "up": 128, "fork": 124,
          "east": 130, "in": 130, "barren": 130, "enter": 130,
          "view": 126},
}

# Movements that require a clear NPC to traverse. Each entry:
# (from_room, direction) → (npc query name, blocked-message).
# Adventure exposes snake/troll blocking via accessor; we
# check them before letting the player through.
var gated_exits: Dictionary = {
    # Snake at canon 19 (Hall of Mountain King) blocks the
    # canyon exits north (to canon 30, coins) and south (to
    # canon 29, jewelry). East back to 15 is unguarded — that's
    # how the player retreats. Bird-release at 19 sends snake
    # away.
    "19:north":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:south":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:west":   {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:left":   {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:right":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:forward":{"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    # Canon SW chain (rows `19 35074 49` + `19 211032 49`):
    # 35% probability shortcut to canon 74 (dragon-side secret
    # canyon); on miss, snake-here bumper. Snake gone + miss =
    # no exit (topology has no `sw` at 19).
    "19:sw": [
        {"check": "probability", "pct": 35, "dest": 74},
        {"check": "snake",       "msg":  "You can't get by the snake."},
    ],
    # Troll bridge crossings (canon 117 ↔ 122). Every cross-the-
    # chasm verb is gated on troll absence; the bear-and-chain
    # combination at 117 vanishes the troll permanently.
    "117:over":   {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:across": {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:cross":  {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:ne":     {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:over":   {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:across": {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:cross":  {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:sw":     {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    # Crystal bridge across the fissure — gate lives on the
    # crossing verbs (OVER/ACROSS/W/CROSS at 17, OVER/ACROSS/E/
    # CROSS at 27). Going east from 17 (back to Hall of Mists)
    # is ungated; that was a long-standing port bug.
    "17:over":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:across": {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:west":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:cross":  {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:over":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:across": {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:east":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:cross":  {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    # Canon "always-blocked" bumper gates — JUMP at fissure / troll
    # bridge / volcano, SLIT/STREAM at the streambed slits, the
    # dragon's east passage at canon 119/121, locked grates and
    # plover squeezes. Driver dispatches before DIRECTIONS so the
    # canon prose lands rather than the FSM fallback.
    "17:jump":  {"check": "always", "msg": "The fissure is too wide."},
    "27:jump":  {"check": "always", "msg": "The fissure is too wide."},
    # Canon `17/27 412021 7` — FORWARD across fissure with no
    # bridge walks to canon 21 (death). Bridge-built case falls
    # through; topology has no `forward` so no-exit fires.
    "17:forward": {"check": "bridge", "dest": 21},
    "27:forward": {"check": "bridge", "dest": 21},
    # Canon `117 332021 39` / `122 332021 39` — JUMP after bear-
    # bridge collapse walks to canon 21 (death). Pre-collapse
    # falls through to the unconditional msg #96 ("use the
    # bridge"). Encoded as a chain.
    "117:jump": [
        {"check": "chasm_collapsed", "dest": 21},
        {"check": "always",          "msg":  "I respectfully suggest you go across the bridge instead of jumping."},
    ],
    "122:jump": [
        {"check": "chasm_collapsed", "dest": 21},
        {"check": "always",          "msg":  "I respectfully suggest you go across the bridge instead of jumping."},
    ],
    # Canon `69 331120 46` / `74 331120 44` — post-dragon-kill
    # shortcut to canon 120 (the connecting canyon). Pre-kill
    # falls through; topology has unconditional 69:south=119
    # and 74:west=121 for the regular pre-kill route.
    "69:south": {"check": "dragon_killed", "dest": 120},
    "74:west":  {"check": "dragon_killed", "dest": 120},
    # Probabilistic-maze decoration (canon's twisty-maze rooms).
    # See cca/godot/scripts/topology.gd for full per-room canon
    # row mapping; this block is a byte-equivalent mirror.
    "5:forest":  [{"check": "probability", "pct": 50, "dest": 5}],
    "5:forward": [{"check": "probability", "pct": 50, "dest": 5}],
    "5:north":   [{"check": "probability", "pct": 50, "dest": 5}],
    "65:south": [{"check": "probability", "pct": 80, "msg": "You have crawled around in some little holes and wound up back in the main passage."}],
    "65:up": [
        {"check": "probability", "pct": 80, "msg":  "You have crawled around in some little holes and wound up back in the main passage."},
        {"check": "probability", "pct": 50, "dest": 70},
    ],
    "65:north": [
        {"check": "probability", "pct": 60, "msg":  "You have crawled around in some little holes and wound up back in the main passage."},
        {"check": "probability", "pct": 75, "dest": 72},
    ],
    "65:down":  [{"check": "probability", "pct": 80, "msg": "You have crawled around in some little holes and wound up back in the main passage."}],
    "66:south": [{"check": "probability", "pct": 80, "msg": "You have crawled around in some little holes and wound up back in the main passage."}],
    "66:nw":    [{"check": "probability", "pct": 50, "msg": "You have crawled around in some little holes and wound up back in the main passage."}],
    "111:down": [
        {"check": "probability", "pct": 40, "dest": 50},
        {"check": "probability", "pct": 50, "dest": 53},
    ],
    "111:jump":  [{"check": "probability", "pct": 40, "dest": 50}],
    "111:climb": [{"check": "probability", "pct": 40, "dest": 50}],
    "7:slit":          {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "7:stream":        {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "7:down":          {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:slit":         {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:stream":       {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:down":         {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:upstream":     {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:downstream":   {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "119:east":    {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "119:forward": {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "121:north":   {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "121:forward": {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "126:jump":  {"check": "always", "msg": "Don't be ridiculous!"},
    "126:down":  {"check": "always", "msg": "Don't be ridiculous!"},
    "23:hole":   {"check": "always", "msg": "It is too far up for you to reach."},
    "99:passage":  {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    "100:passage": {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    "100:out":     {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    # Rusty iron door at canon 94 → 95. Pour oil from the bottle
    # at room 94 to lubricate the hinges; the gate then passes
    # and N/ENTER/CAVERN walk through to the Magnificent Cavern.
    "94:north":  {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    "94:enter":  {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    "94:cavern": {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    "116:down":  {"check": "always", "msg": "The grate is locked."},
    # Witt's End probabilistic bounce-back. Per advent.dat row
    # `108 95556 ...` and the FORTRAN spec, 95% of E/N/S/NE/SE/
    # SW/NW/UP/DOWN attempts print msg #56 and stay put. Only
    # the 5% E case actually walks to room 106; W is the always-
    # bumper "cave-in" prose (canon msg #126).
    "108:east":  {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:north": {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:south": {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:ne":    {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:se":    {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:sw":    {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:nw":    {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:up":    {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:down":  {"check": "probability", "pct": 95, "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:west":  {"check": "always", "msg": "You have crawled around in some little holes and found your way blocked by a recent cave-in. You are now back in the main passage."},
    # Grate at depression (canon 8 → 9). Canon `8 303009 3 19 30`
    # gates ENTER, IN, and DOWN — all three on the same condition.
    "8:down":    {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:in":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:enter":   {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # Symmetric mirror at canon 9 (below grate) per canon section
    # 3 row `9 303008 11 29` — UP/OUT route back to 8 when grate
    # is unlocked, otherwise the canon "grate is locked" bumper.
    "9:up":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "9:out":     {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # DEPRESSION verb at debris/awkward/bird/pit-top — canon
    # `11/12/13/14 303008 63` teleports back to canon 8 when
    # the grate is unlocked.
    "11:depression": {"check": "grate", "msg": "The grate is locked. You'd need keys to open it."},
    "12:depression": {"check": "grate", "msg": "The grate is locked. You'd need keys to open it."},
    "13:depression": {"check": "grate", "msg": "The grate is locked. You'd need keys to open it."},
    "14:depression": {"check": "grate", "msg": "The grate is locked. You'd need keys to open it."},
    # "You can't get the gold up the steps." Canon row
    # `15 150022 29 31 34 35 23 43` blocks UP/PIT/STEPS/DOME/
    # PASSAGE/EAST at the Hall of Mists when the player is
    # carrying obj #50 (gold). The canon dest is room 22, whose
    # description IS the bumper message ("THE DOME IS
    # UNCLIMBABLE.") and which itself is a forced-motion
    # bouncer back to 15. The "carrying" gate type takes an
    # `obj` field naming a port-side ID accessor; the driver
    # resolves it and fires when the player has the item in
    # inventory. The canonical solution is to navigate up via
    # the cave long-way (rod / bridge / Bedquilt) once the gold
    # has been retrieved.
    "15:up":      {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    "15:east":    {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    "15:pit":     {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    "15:steps":   {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    "15:dome":    {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    "15:passage": {"check": "carrying", "obj": "GOLD_ID", "msg": "The dome is unclimbable."},
    # Companion canon row `14 150020 30 31 34` — DOWN/PIT/STEPS
    # at canon 14 (Top of Small Pit) when carrying the gold:
    # the player falls into canon 20 ("AT THE BOTTOM OF THE PIT
    # WITH A BROKEN NECK"), where the room-entry death handler
    # in cca.fgd's _verb_move fires player.die(). The non-gold
    # case keeps the unconditional `14 15 30` fall-through
    # (down → 15) — verified by topology row 14:down=15.
    # PIT and STEPS aren't in the unconditional row, so without
    # gold those verbs fall through to the FSM's "I don't know
    # how to X" response — same as canon, where the verbs only
    # exist on the carrying-conditional row.
    "14:down":  {"check": "carrying", "obj": "GOLD_ID", "dest": 20},
    "14:pit":   {"check": "carrying", "obj": "GOLD_ID", "dest": 20},
    "14:steps": {"check": "carrying", "obj": "GOLD_ID", "dest": 20},
    # Canon plant — single-jump model:
    #   25 UP/OUT → 23 gated by plant tall (canon row
    #   `25 23 29 11`, condition 11 = plant tall).
    #   25 CLIMB → 26 gated by plant huge (canon row
    #   `25 724031 56`, condition encodes plant huge).
    "25:up":     {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "25:out":    {"check": "plant_tall", "msg": "There is nothing here to climb. The plant is a tiny shoot, struggling for water."},
    "25:climb":  {"check": "plant_huge", "msg": "The plant is too feeble to support your weight that high."},
    # Plover Room narrow tunnel — canon CCA permits only the
    # emerald (small enough) or empty hands through the squeeze.
    # Anything else and the player can't fit.
    "99:east":   {"check": "plover_squeeze", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    "100:west":  {"check": "plover_squeeze", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
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
var output: RichTextLabel
var input: LineEdit
var _last_room: int = -1
# Tracks whether the player has already been warned about the
# darkness in their current room. Canon CCA gives one free turn —
# the warning fires, and only on the *next* move attempt does the
# pit-fall roll happen.
var _dark_warned_room: int = -1
var _save_path: String = "user://cca.save"     # cabinet convention: matches Arcade.save_path("cca")
# 5-character-truncated verb-synonym lookup, populated in _ready()
# from verb_synonyms. Mirrors canon's "first five letters" parser
# rule (Don Woods 1977 startup banner).
var _verb_synonyms_5: Dictionary = {}

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

# Canon BRIEF flag (advent.for STMT 8260) — when set, revisits
# to already-seen rooms skip the full description.
var _brief_mode: bool = false
var _visited_rooms: Dictionary = {}

# Canon IWEST counter (advent.for line 901) — 10th typed
# "WEST" fires msg #17 once.
var _iwest_count: int = 0

# Canon LOOK detail counter (advent.for STMT 30).
var _look_detail_count: int = 0

# Canon BACK history (advent.for STMT 20-25). See cca/godot
# mirror for full inline doc on the OLDLOC/OLDLC2 mechanic.
var _old_loc: int = -1
var _old_loc2: int = -1

# Typed-input recall (Up/Down at the prompt) and scrollback
# paging (PgUp/PgDn). Session-only ergonomic state — not part
# of save/restore. See cca/godot/scripts/driver.gd for full
# inline doc.
var _input_history: Array = []
var _input_history_idx: int = -1

# Canon msg #3 first-dwarf-encounter latch (advent.for STMT 6000).
var _dwarf_first_encounter_done: bool = false

# Canon chest-only-outstanding hint latch (msg #186, fires once).
var _chest_hint_done: bool = false

# Canon OYSTER hint chain (advent.dat msgs #192/193/194).
var _oyster_prompt_active: bool = false
var _oyster_revealed: bool = false
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
    if _awaiting_revive:
        if verb == "yes":
            # Canon advent.for STMT 16100: revive-text varies by
            # death count via msg #82/#84.
            var prior_deaths: int = fsm.player.get_deaths()
            fsm.player.revive()
            _awaiting_revive = false
            if prior_deaths == 1:
                _println("[color=#88dd88]All right. But don't blame me if something goes wr......")
                _println("                --- POOF!! ---")
                _println("You are engulfed in a cloud of orange smoke. Coughing and gasping,")
                _println("you emerge from the smoke and find....[/color]")
            elif prior_deaths == 2:
                _println("[color=#88dd88]Okay, now where did I put my orange smoke?....   >POOF!<")
                _println("Everything disappears in a dense cloud of orange smoke.[/color]")
            else:
                _println("[color=#88dd88]>POOF!< (somehow.)[/color]")
            _last_room = -1   # force room re-print
            _print_room()
            return
        if verb == "no":
            _awaiting_revive = false
            # Canon msg #86.
            _println("[color=#cc4444]Okay, if you're so smart, do it yourself! I'm leaving![/color]")
            await get_tree().create_timer(2.0).timeout
            # Game-over: return to the cabinet menu rather than
            # killing the whole cabinet. The dead-player state
            # isn't worth saving, so skip the exit dialog and
            # leave straight away.
            Arcade.return_to_menu()
            return
        _println("Please answer yes or no.")
        return

    # Canon oyster-clue Y/N prompt (advent.dat msg #192). YES
    # costs 10 points and reveals msg #193, NO cancels.
    if _oyster_prompt_active:
        if verb == "yes":
            _oyster_prompt_active = false
            _oyster_revealed = true
            _println("It says, \"There is something strange about this place, such that one")
            _println("of the words I've always known now has a new effect.\"")
            fsm.score_hints = fsm.score_hints - 10
            fsm.real_score = fsm.real_score - 10
            return
        if verb == "no":
            _oyster_prompt_active = false
            _println("OK.")
            return
        _oyster_prompt_active = false

    # ----- UI-only verbs (driver-handled, never reach the FSM) -----
    if _handle_ui_verb(verb, noun): return

    # ----- Bumper rules + dark-pit hazard -----
    if _dispatch_bumper(verb): return
    if verb in MOTION_VERBS and _check_dark_pit_hazard(): return

    # ENTER STREAM/WATER must precede DIRECTIONS — "enter" is in
    # DIRECTIONS, so the intercept has to win first.
    if _intercept_enter_stream(verb, noun): return
    if verb in DIRECTIONS:
        _handle_movement(verb)
        return

    # ----- Canon verb intercepts (order is canon-significant) -----
    if _intercept_break_mirror(verb, noun): return
    if _intercept_drop_bird(verb, noun): return
    if _intercept_attack_bird(verb, noun): return
    if _intercept_attack_bear(verb, noun): return
    if _intercept_take_knife(verb, noun): return
    if _intercept_take_bear(verb, noun): return
    if _intercept_unlock_chain(verb, noun): return
    if _intercept_take_scenery(verb, noun): return
    if _intercept_throw_axe(verb, noun): return
    _intercept_plover_emerald(verb, noun)              # side-effect; falls through to FSM
    if _intercept_calm(verb, noun): return
    if _intercept_eat(verb, noun): return
    if _intercept_feed(verb, noun): return
    if _intercept_scenery_read(verb, noun): return

    # ----- FSM dispatch + unknown-verb prose mix -----
    _dispatch_to_fsm(verb, noun)

    # ----- Per-turn check chain -----
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
            # Canon SUSPEND (advent.for STMT 8300). Honor the
            # canon prose + a wink, then save instantly.
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
            _brief_mode = true
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
        "look":
            if _look_detail_count < 3:
                _println("Sorry, but I am not allowed to give more detail. I will repeat the long description of your location.")
                _look_detail_count = _look_detail_count + 1
            _last_room = -1
            _visited_rooms.erase(fsm.player_room())
            _print_room()
            return true
        "back":
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
        var roll1: int = randi() % 100
        var roll2: int = randi() % 100
        if roll2 < 20:
            response = "I don't understand that!"   # canon msg #13
        elif roll1 < 20:
            response = "What?"                       # canon msg #61
        else:
            response = "I don't know that word."     # canon msg #60
    _println(response)

# Per-turn check chain.
func _run_per_turn_checks() -> void:
    fsm.tick()
    _check_pirate_steal()
    _check_lamp_warnings()
    _check_endgame_phase_change()
    _check_dwarf_axe()
    _check_chest_hint()
    _check_player_death()
    _maybe_print_room_after_move()

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

func _intercept_drop_bird(verb: String, noun: String) -> bool:
    if verb != "drop" or noun != "bird":
        return false
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
        _println("There is no bear here to attack.")
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
        _println("You are already leading the bear by the chain.")
        return true
    _println("There is no bear here to take.")
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
    if noun in [
            "tablet", "mirror", "figure", "shadow", "stalactite",
            "drawings", "drawing", "volcano", "geyser",
            "carpet", "moss", "message"]:
        _println("You can't be serious!")
        return true
    return false

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
        _println("As you start to chant, the emerald slips from your grasp and falls to the floor.")

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
            _println("It looks suspiciously like a stick of dynamite. Better not let it get near a flame.")
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
        if _oyster_revealed:
            _println("It says the same thing it did before.")
            return true
        _oyster_prompt_active = true
        _println("Hmmm, this looks like a clue, which means it'll cost you 10 points to")
        _println("read it. Should I go ahead and read it anyway?")
        return true
    if noun == "mirror" and er == 109:
        _println("It's a two-sided mirror suspended high above the canyon floor.")
        _println("Provided for the dwarves, who as you know are extremely vain.")
        return true
    if (noun == "figure" or noun == "shadow") and (er == 35 or er == 110):
        _println("The shadowy figure seems to be trying to attract your attention.")
        return true
    if noun == "stalactite" and er == 111:
        _println("It's a large stalactite extending from the roof and almost reaching the floor below.")
        return true
    if (noun == "drawings" or noun == "drawing") and er == 97:
        _println("The cave drawings are ancient and Oriental in style.")
        return true
    if (noun == "volcano" or noun == "geyser") and er == 126:
        _println("Great gouts of molten lava come surging out of an active volcano,")
        _println("cascading back down into the depths.")
        return true
    if (noun == "carpet" or noun == "moss") and er == 96:
        _println("The carpet is soft and the moss-covered ceiling muffles every sound.")
        return true
    if (noun == "plant" or noun == "plant2") and (er == 23 or er == 35):
        _println("It's the top of a tall beanstalk poking out of the west pit.")
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
        if (randi() % 100) < bg.pct:
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
    # sequence (troll FSM in $Vanished). Used for canon
    # `117 332661 41` (OVER → msg #161) and `117 332021 39`
    # (JUMP → walk to canon 21 death).
    if bg.check == "chasm_collapsed":
        if fsm.troll_state() == "vanished":
            if "dest" in bg:
                _walk_to_dest(int(bg.dest))
            else:
                _println(bg.msg)
            return true
        return false
    return false

func _walk_to_dest(dest_room: int) -> void:
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
# died), in which case the caller short-circuits the rest of
# command handling. The "warn first, kill on the next attempt"
# pattern matches Crowther/Woods canon: the player gets exactly
# one free turn after entering a dark room before the 35% pit-
# fall roll starts.
func _check_dark_pit_hazard() -> bool:
    var current: int = fsm.player_room()
    if not fsm._room_is_dark(current):
        if _dark_warned_room != -1:
            _dark_warned_room = -1
        return false
    if current != _dark_warned_room:
        _println("It is now pitch dark. If you proceed you will likely fall into a pit.")
        _dark_warned_room = current
        return true
    if (randi() % 100) < DARK_PIT_PCT:
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
        _println("[color=#cc8855][i]%s[/i][/color]" % msg)
        return
    _check_pirate_rustle()

# Canon msg #127 (advent.for STMT 6080-ish): ~20% per-turn
# rustling-noise hint while pirate is active in deep cave.
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
    # Canon msg #185 forced quit — lamp out + above-ground.
    if fsm.lamp.get_state() == "out" and fsm.player_room() <= 8:
        _println("[color=#cc7777][b]There's not much point in wandering around out here, and you can't explore the cave without a lamp. So let's just call it a day.[/b][/color]")
        if is_inside_tree():
            await get_tree().create_timer(2.0).timeout
            get_tree().quit()

func _check_dwarf_axe() -> void:
    if fsm.dwarf_threw_axe():
        _println("[color=#cc7777][i]A dwarf throws an axe at you — and connects! The axe finds your back.[/i][/color]")

# Canon chest-only-outstanding hint (advent.for STMT 6020, msg
# #186). Fires once when 14 of 15 treasures are deposited and
# the chest is still missing.
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
        # Canon advent.for STMT 16000: prompt text varies by
        # death count via msg #81/#83/#85.
        var deaths: int = fsm.player.get_deaths()
        if deaths == 1:
            _println("[color=#cc4444]Oh dear, you seem to have gotten yourself killed. I might be able to")
            _println("help you out, but I've never really done this before. Do you want me")
            _println("to try to reincarnate you?[/color]")
        elif deaths == 2:
            _println("[color=#cc4444]You clumsy oaf, you've done it again! I don't know how long I can")
            _println("keep this up. Do you want me to try reincarnating you again?[/color]")
        else:
            _println("[color=#cc4444]Now you've really done it! I'm out of orange smoke! You don't expect")
            _println("me to do a decent reincarnation without any orange smoke, do you?[/color]")
    elif s == "permadead":
        # Canon msg #86.
        _println("[color=#cc4444][b]Okay, if you're so smart, do it yourself! I'm leaving![/b][/color]")
        await get_tree().create_timer(2.0).timeout
        Arcade.return_to_menu()

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
    # Canon Y2 whisper (advent.for line 808): 25% chance per
    # visit to room 33 prints msg #8.
    if _last_room == 33 and not fsm.endgame_closing() and (randi() % 100) < 25:
        _println("A hollow voice says \"PLUGH\".")
    # Canon msg #3 first-dwarf-encounter (advent.for STMT 6000).
    if not _dwarf_first_encounter_done and _dwarf_at_room(_last_room):
        _dwarf_first_encounter_done = true
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
    if fsm.player.carrying(BOTTLE_ID):   items.append("  Small bottle")
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
    # emoji or modern iconography. Synced from cca/godot/
    # scripts/driver.gd; keep the two welcome panels identical.
    var rule: String = "[color=#a89878]─────────────────────────────[/color]"
    # Small brick-building silhouette, period line-printer style.
    # Echoes the canon opening room ("a small brick building").
    var art: String = (
        "[color=#a89878]"
        + "             ____\n"
        + "            /    \\\n"
        + "           /______\\\n"
        + "           |[]  []|\n"
        + "           |______|\n"
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
    _println("Type [b]HELP[/b] for a list of commands.")

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
