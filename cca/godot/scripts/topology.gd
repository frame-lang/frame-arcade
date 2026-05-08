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
# Numbering follows Crowther+Woods 1977 canon. After Phase 7 the
# room IDs match advent.dat's section 1 layout: 1-130 are canon
# rooms with verbatim ALL-CAPS prose, 131-139 host the canonical
# "twisty maze, all DIFFERENT", 115/116 are the cave-closing
# Repository (teleport-only after Phase 7i), and the port-synth
# 200-series + statuette + port endgame chain were removed in
# Phases 7d-7e.
#
# Deferred — known port-vs-canon topology drift (~594 deltas
# enumerated by /tmp/topology_audit.py against canon's section 2
# room-exit table):
#   - The plant beanstalk is modeled as a 3-room climb (25→24→23)
#     instead of canon's 1-jump (25→23 with plant gating).
#   - Most rooms use only cardinal compass directions; canon
#     supports NE/SE/NW/SW via verbs 45-48 plus IN/OUT/UP/DOWN
#     as object-named alternatives.
#   - Both mazes (50-57 first, 131-139 second) use simplified
#     linear-chain exits; canon scrambles 10 exits per maze room
#     into a deliberately disorienting layout.
#   - Canon section 2 occasionally has multiple verbs to the same
#     destination (e.g., HILL + W + N from end-of-road); we keep
#     just the canonical compass direction.
# These are intentional simplifications that preserve gameplay
# without sacrificing the canon prose. Closing them is a future
# polish item; the canon conformance dashboard tracks story-
# affecting mechanics rather than per-direction exit equivalence.
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
    9:   {"west": 10, "in": 10, "crawl": 10, "cobbles": 10, "pit": 14, "debris": 11},
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
    11:  {"east": 10, "west": 12, "up": 12, "in": 12,
          "crawl": 10, "cobbles": 10, "passage": 10, "low": 10,
          "canyon": 12, "pit": 14, "entrance": 9},
    # Awkward sloping E/W canyon — canon row `12 9 64`
    # (ENTRANCE→9), `12 11 30 43 51` (DOWN/E/DEBRIS→11),
    # `12 13 19 29 44` (IN/UP/W→13), `12 14 31` (PIT→14).
    # Removed port-only N→33, S→11; canon has neither.
    12:  {"east": 11, "west": 13, "up": 13, "down": 11, "in": 13,
          "pit": 14, "entrance": 9, "debris": 11},
    # Y2 marker — canon 33. Canon `33 28 46` (S→28), `33 34 43 53 54`
    # (E/WALL/BROKEN→34), `33 35 44` (W→35). PLUGH(65)→3 and
    # PLOVER(71)→100 are magic words handled by MagicWordTeleport.
    33:  {"south": 28, "east": 34, "west": 35,
          "wall": 34, "broken": 34},
    # Low n/s passage at hole — canon 28 (silver home). Canon
    # `28 19 38 11 46` (HALL/OUT/S→19), `28 33 45 55` (N/Y2→33),
    # `28 36 30 52` (DOWN/HOLE→36).
    28:  {"south": 19, "out": 19, "hall": 19, "north": 33,
          "down": 36, "hole": 36},
    # Bird chamber — canon row `13 9 64` (ENTRANCE→9),
    # `13 11 51` (DEBRIS→11), `13 12 25 43` (CANYON/E→12),
    # `13 14 23 31 44` (PASSAGE/PIT/W→14). XYZZY/PLUGH/PLOVER
    # access is via magic word, not a direct exit. Port-only
    # UP/OUT→33 removed for canon faithfulness.
    13:  {"east": 12, "west": 14, "passage": 14, "pit": 14,
          "canyon": 12, "entrance": 9, "debris": 11},
    # Plover Room — canon 100. West to alcove (99) via tight
    # tunnel (gated on emerald-only inventory); north to Dark-room
    # (port-direction; canon NE). PLOVER chant teleports to 33.
    100: {"north": 101, "west": 99},
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
    # Canon 2nd maze (131-139): "twisty maze, all DIFFERENT". Canon
    # gives each room 10 exits to siblings + entry points 107 / 112,
    # with directions deliberately scrambled so a player can't tell
    # one room from another. We use a simplified linear-chain
    # topology (the canonical maze prose still reads correct on
    # `look`) — full canon-exit encoding is a future polish step.
    131: {"west": 95, "east": 40, "north": 132, "south": 137},
    # Canon 40 = "VERY LOW WIDE PASSAGE PARALLEL TO HALL OF
    # MISTS." Canon row `40 41 1` is a one-way bounce: any
    # verb routes to 41 (West End of Hall of Mists). We add an
    # explicit OUT/EAST/WEST/BACK→41 escape.
    40:  {"out": 41, "east": 41, "west": 41, "back": 41},
    132: {"west": 40, "east": 133, "south": 131, "north": 138},
    133: {"west": 132, "east": 134, "south": 139},
    134: {"west": 133, "east": 135, "north": 136},
    135: {"west": 134, "east": 136},
    136: {"west": 135, "south": 134, "east": 138},
    137: {"north": 131, "east": 139},
    138: {"south": 132, "west": 136, "east": 139},
    139: {"west": 138, "north": 133, "south": 137},
    130: {"up": 65, "out": 65},              # Barren Room — canon 130 (BEAR_HOME_ROOM); up/out back to Bedquilt
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
          "passage": 13, "entrance": 9, "debris": 11, "crack": 16},
    # East bank of fissure — canon row `17 15 38 43`
    # (HALL/E→15), `17 27 41` (OVER→27 gated by bridge). Canon
    # has no W or S exit; port-only `west: 27` and `south: 14`
    # removed for canon faithfulness.
    17:  {"east": 15, "hall": 15, "over": 27},
    # Low room w/ "won't get it up the steps" sign — canon 18.
    # Canon row `18 15 38 11 45` (HALL/OUT/N→15). Pirate's
    # stash spawns here (CHEST_ROOM = 18).
    18:  {"north": 15, "out": 15, "hall": 15},
    # West bank of fissure — canon 27. Canon `27 17 41` (OVER→17
    # gated by bridge), `27 40 45` (N→40), `27 41 44` (W→41).
    # Special-handler rows 27 312596/412021/412597 are the
    # fall-into-pit conditional cases handled engine-side.
    27:  {"north": 40, "west": 41, "over": 17},
    69:  {"west": 17},                            # hall of mirrors (across)
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
          "left": 18, "forward": 17, "hall": 17, "stairs": 19},
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
    34:  {"down": 33, "up": 15},
    # Canon 35 = sloping corridor with cracks. Canon `35 33 43 55`
    # (E/Y2→33), `35 20 39` (JUMP→20 death pit).
    35:  {"east": 33, "jump": 20},
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
    58: {"east": 59, "south": 60},
    59:  {"west": 58, "east": 61, "north": 62},
    60:  {"north": 58, "east": 63},
    61:  {"west": 59, "east": 64},
    62: {"south": 59},
    63:  {"west": 60, "east": 64},
    64: {"west": 63, "east": 66},
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
    # 96-99: canon forest grid surrounding the road/valley.
    # All four are canonical (advent.dat "different forest, NE/SW/SE/NW").
    96: {"south": 5},                                      # Forest NE-of-road
    98: {"west": 99},                                     # Forest SE/SW
    # Canon: 99 (alcove) is connected EAST to 100 (Plover Room)
    # via a tight crawl gated on inventory. The forest connection
    # to 98 moves to the canon "down" direction so both routes can
    # coexist in a single-direction-key topology.
    99: {"east": 100, "down": 98},                                       # Alcove — east to Plover via tight tunnel
    # 108, 115, 116: pre-repository corridor.
    # Threads from snake passage / rear of dragon area into the
    # endgame approach.
    108: {"north": 67},                                                  # Witt's End fork — north back to Bedquilt cluster
    # Canon 115/116 = NE/SW Repository — reachable ONLY via the
    # cave-closing teleport that fires in Adventure.tick() when
    # endgame transitions to $InRepository. Walking corridor from
    # 108 was a port holdover removed in Phase 7i.
    115: {"east": 116},                                                  # NE Repository
    116: {"west": 115},                                                  # SW Repository — terminal endgame room
    # 119, 121-129: cliff-and-ladder descent + sub-anteroom area.
    119: {"up": 87, "down": 121},                                        # Cliff face with ladder
    121: {"up": 119, "north": 123, "east": 125, "south": 122, "west": 124}, # Bottom of ladder
    123: {"south": 121, "north": 126},                                   # Anteroom with pictographs
    125: {"west": 121},                                                  # Anteroom with niches
    # --- Phase F: iconic remainder ---
    # Decorated chamber (88), Vending Machine Room (canon 140 —
    # vending mechanic itself is a port-synth holdover from
    # Adventure 2 / 550-point edition, scheduled for Phase 7e
    # cleanup). Plus the canon Shell Room (103) and forest
    # variant (102).
    88:  {"east": 76, "south": 90},                                      # Decorated chamber
    140: {},                                                  # Vending Machine Room (port-synth at canon 140 — handled in Phase 7e)
    102: {},                                                 # Forest far south
    103: {"west": 16},                                                   # Shell Room — canon 103 (clam home)
    109: {"east": 113},                                                  # Low passage (curving west)
    113: {"west": 109, "down": 121},                                     # Wide chamber
    122: {"north": 121},                                                 # Anteroom — basalt
    124: {"east": 121},                                                  # Anteroom — red stone
    126: {"south": 123, "north": 127},                                  # Breath-taking view (canon 126; north to canon 127 Chamber of Boulders)
    # --- Round 10: canon-completion fillers (104-107, 110-114, 127-129) ---
    # Forest grid completion + inner-anteroom cluster.
    104: {"south": 96, "east": 105},                                     # Dense forest
    105: {"west": 104, "east": 106},                       # Scrub forest
    106: {"west": 105, "north": 107},                                    # Forest clearing (water source flavor)
    107: {"south": 106},                                    # Forest path
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
    "19:west":   {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:left":   {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:right":  {"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "19:forward":{"check": "snake",  "msg": "The snake glares at you and refuses to move."},
    "117:east":  {"check": "troll",  "msg": "The troll bars your way until you pay tribute."},
    "17:east":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "8:down":    {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:in":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
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
