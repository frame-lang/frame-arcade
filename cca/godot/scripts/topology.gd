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
    # Below grate (canon 9). Plain rows from canon section 3:
    # `9 10 17 18 19 44` (CRAWL/COBBLES/IN/W → 10),
    # `9 14 31` (PIT → 14), `9 11 51` (DEBRIS → 11). Plus
    # conditional `9 303008 11 29` (OUT/UP → 8 when grate
    # unlocked) — symmetric mirror of the 8:down/in entries.
    # Without this the player can descend and use XYZZY but
    # can't symmetrically climb the grate's ladder back up.
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
    # Debris room — canon 11. Plain rows W/UP/IN→12, E/CRAWL/
    # COBBLES/PASSAGE/LOW→10, PIT→14, ENTRANCE→9. Canon
    # conditional `11 303008 63` adds the DEPRESSION verb as a
    # convenience-teleport back to room 8 (the surface
    # depression) when prop(3) ≠ 0 — i.e. grate has been
    # unlocked. Same shortcut at 12/13/14. The grate gate
    # below emits the canon "grate is locked" prose when the
    # condition fails.
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
    #   `117 118 49`           SW→118 (descent into sloping corridor)
    #   `117 233660/303/596 …` troll-gated OVER/ACROSS/CROSS/NE
    #                          → R_TROLL → R_NESIDE (122)
    # Per Quuxplusone Advent (ODWY0350/advent.c, R_SWSIDE entry):
    #   make_cond_ins(OVER, only_if_here(TROLL), remark(11));
    #     ditto(ACROSS); ditto(CROSS); ditto(NE);
    #   make_ins(OVER, R_TROLL);   // -> R_NESIDE when troll absent
    # The OVER/ACROSS/CROSS/NE crossings are gated on the troll
    # being absent; see GATES.
    117: {"sw": 118, "over": 122, "across": 122, "cross": 122, "ne": 122},
    # Canon 118 (R_SLOPING — long winding corridor under bridge):
    # `118 72 30` (DOWN→72), `118 117 29` (UP→117).
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
    # → 27 gated by crystal bridge). The crossing aliases are
    # gated; EAST and HALL go back to Hall of Mists ungated.
    17:  {"east": 15, "hall": 15,
          "over": 27, "across": 27, "west": 27, "cross": 27},
    # Low room w/ "won't get it up the steps" sign — canon 18.
    # Canon row `18 15 38 11 45` (HALL/OUT/N→15). Pirate's
    # stash spawns here (CHEST_ROOM = 18).
    18:  {"north": 15, "out": 15, "hall": 15},
    # West bank of fissure — canon 27. `27 17 41` (OVER→17),
    # `27 40 45` (N→40), `27 41 44` (W→41). The special-handler
    # row `27 412597 41 42 43 69` adds OVER/ACROSS/E/CROSS as
    # bridge-gated crossing aliases (mirror of 17). Canon line
    # 27:east means "across the fissure" since 27 is the west
    # bank; the gate keeps that consistent.
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
    # Hall of Mists (canon 15). Plain rows: LEFT/SOUTH→18,
    # FORWARD/HALL/WEST→17, STAIRS/DOWN/NORTH→19, UP→14, Y2→34.
    # Canon row `15 150022 …` (UP/PIT/STEPS/DOME/PASSAGE/EAST →
    # room 22 if carrying obj #50 = GOLD) is the canonical
    # "you can't get the gold up the steps" puzzle. Encoded
    # below via the GATES dict with check="carrying" + obj_id
    # = GOLD_ID. Canon room 22's description ("THE DOME IS
    # UNCLIMBABLE.") is the bumper text — the player stays at
    # 15 and must take gold out via the canon long-way (down
    # through the snake-cleared Hall of Mountain King 19 →
    # silver passage 28 → Y2 33 → PLUGH home).
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
    # `19 74 66` (SECRET→74 different secret canyon),
    # `19 35074 49` (SW→74 with 35% probability — dragon-side
    # canyon shortcut). GATES handles the snake-blocking
    # condition; we encode the destinations directly so canon-
    # aligned walking works once the bird has driven the snake
    # off. The SW alias is unconditional in the port (we don't
    # model the 35% probability) — same destination, slightly
    # easier to find than the canon original.
    19:  {"east": 15, "stairs": 15, "up": 15,
          "north": 28, "left": 28,
          "south": 29, "right": 29,
          "west": 30, "forward": 30,
          "secret": 74, "sw": 74},
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
    # Canon 34 (jumble of rocks): `34 33 30 55` (DOWN/Y2→33),
    # `34 15 29` (UP→15). Y2 verb is the canon convenience-
    # teleport shortcut back to the Y2 marker room.
    34:  {"down": 33, "y2": 33, "up": 15},
    # Canon 35 = sloping corridor with cracks. Canon `35 33 43 55`
    # (E/Y2→33), `35 20 39` (JUMP→20 death pit).
    # Canon 35 (window over pit, west view): `35 33 43 55`
    # (E/Y2→33), `35 20 39` (JUMP→20 — death pit).
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
    # Canon 61 (high N/S + low E/W crossover): `61 60 43`
    # (E→60), `61 62 45` (N→62), `61 100107 46` (S→107 always
    # but forbidden to dwarves). Adding 61:south → 107 closes
    # the canon-only entry into the second maze ("twisty
    # passages, all DIFFERENT") from outside the maze cluster.
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
    # PASSAGE→92), `94 611 45` (msg #111 — rusty refuses, fallback
    # for N when door still rusty), `94 309095 45 3 73` (N/CAVERN/
    # ENTER→95 once the rusty door is oiled). All three N/CAVERN/
    # ENTER aliases route to the same gate (`rusty`) which checks
    # rusty_door_oiled() — pour oil from the bottle here to open.
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
    # Canon 108 (Witt's End): canon section 3 has three rows —
    #   `108 95556 43 45 46 47 48 49 50 29 30`
    #     all of E/N/S/NE/SE/SW/NW/UP/DOWN: 95% chance to print
    #     msg #56 ("you have crawled around in some little holes
    #     and wound up back in the main passage") and stay put.
    #   `108 106 43`     5% E falls through: walk to 106.
    #   `108 626 44`     W: always msg #126 ("...found your way
    #                    blocked by a recent cave-in...").
    # Only EAST is in ROOMS; the other 9 directions are gated by
    # a `probability` GATES entry. See GATES below.
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
    # Per ODWY0350 R_NESIDE entry, OVER/ACROSS/CROSS/SW
    # crosses back to R_SWSIDE (117) via the R_TROLL handler;
    # gated on troll being absent (see GATES).
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
    # Troll bridge crossings (canon 117 ↔ 122). The troll
    # blocks every cross-the-chasm verb until it pays toll
    # (treasure thrown) or vanishes (chain dropped + bear).
    "117:over":   {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:across": {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:cross":  {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "117:ne":     {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:over":   {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:across": {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:cross":  {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    "122:sw":     {"check": "troll", "msg": "The troll bars your way until you pay tribute."},
    # Crystal bridge across the fissure. The gate lives on the
    # crossing verbs (OVER/WEST/CROSS at 17, OVER/EAST/CROSS at
    # 27) rather than 17:east — going east from the east bank is
    # the way *back* to hall of mists, not across. Wave the rod
    # at the fissure to materialise the bridge.
    "17:over":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:across": {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:west":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "17:cross":  {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:over":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:across": {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:east":   {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    "27:cross":  {"check": "bridge", "msg": "The fissure is too wide to leap. You'll have to find another way across."},
    # Canon JUMP-into-fissure: msg #38 "the fissure is too wide
    # to jump". Adding so a player typing JUMP gets the canon
    # text rather than a generic "no exit".
    "17:jump":  {"check": "always",  "msg": "The fissure is too wide."},
    "27:jump":  {"check": "always",  "msg": "The fissure is too wide."},
    # Canon JUMP-off-troll-bridge: msg #96 "I respectfully
    # suggest you go across the bridge instead of jumping."
    "117:jump": {"check": "always",  "msg": "I respectfully suggest you go across the bridge instead of jumping."},
    "122:jump": {"check": "always",  "msg": "I respectfully suggest you go across the bridge instead of jumping."},
    # Canon SLIT/STREAM at rooms 7 (slit-in-streambed) and 38
    # (deep cave streambed): msg #95 "You don't fit through a
    # two-inch slit!"
    "7:slit":    {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "7:stream":  {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:slit":   {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:stream": {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    # Canon dragon-side secret canyon: msg #153 "The dragon
    # looks rather nasty. You'd best not try to get by."
    "119:east":    {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "119:forward": {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "121:north":   {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    "121:forward": {"check": "always", "msg": "The dragon looks rather nasty. You'd best not try to get by."},
    # Canon volcano dive (canon 126, breath-taking view): msg
    # implies "you'd best not try to jump into a volcano". The
    # canon special-handler is `126 610 30 39` (DOWN/JUMP).
    "126:jump":  {"check": "always",  "msg": "Don't be ridiculous!"},
    "126:down":  {"check": "always",  "msg": "Don't be ridiculous!"},
    # Canon SLIT/STREAM/DOWN at room 7 (slit in streambed): all
    # three verbs route to msg #95 "two-inch slit". Adding 7:down
    # and 38:down + the upstream/downstream aliases for 38 so
    # canon prose lands.
    "7:down":          {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:down":         {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:upstream":     {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    "38:downstream":   {"check": "always", "msg": "You don't fit through a two-inch slit!"},
    # Canon 23:hole — `23 648 52`: the hole is too small to
    # crawl through (canon msg #148 "It is too far up for you to
    # reach"). Same vibe at the only-canon-tested verb.
    "23:hole":   {"check": "always", "msg": "It is too far up for you to reach."},
    # Canon 99/100 plover squeeze (canon msg #59 / #60 wording):
    # "something you're carrying won't fit through the tunnel."
    # The tight squeeze is already enforced for compass moves
    # via plover_squeeze; the PASSAGE/OUT verbs at 100 emit a
    # different bumper variant ("you can't fit").
    "99:passage":  {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    "100:passage": {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    "100:out":     {"check": "always", "msg": "Something you're carrying won't fit through the tunnel with you. You'd best take inventory and drop something."},
    # Canon 94:north — `94 611 45` is msg #111 "the door is
    # extremely rusty and refuses to open." (Treasury access in
    # canon is via the rusty-door puzzle, not modelled here.)
    # Rusty iron door at canon 94 → 95. Canon section 2 has two
    # rows for the verb cluster N/ENTER/CAVERN: a conditional row
    # `94 309095 45 3 73` (when door oiled, walk through to 95)
    # and a fallback `94 611 45` (msg #111, "rusty refuses"). The
    # `rusty` check defers to Adventure.rusty_door_oiled() — pour
    # oil from the bottle at canon 94 to lubricate.
    "94:north":  {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    "94:enter":  {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    "94:cavern": {"check": "rusty",  "msg": "The door is extremely rusty and refuses to open."},
    # Canon 116:down — `116 593 30` is msg #93 "the grate is
    # locked" variant (office grate near the repository).
    "116:down":  {"check": "always", "msg": "The grate is locked."},
    # Witt's End probabilistic bounce-back (canon row
    # `108 95556 43 45 46 47 48 49 50 29 30`). 95% chance any of
    # E/N/S/NE/SE/SW/NW/UP/DOWN prints canon msg #56 and the
    # player stays put — the message *narrates* moving back to
    # the main passage but the game state doesn't change. On the
    # 5% fall-through, EAST proceeds to ROOMS[108]→106 (the only
    # actual canon exit); the other directions get a "no exit"
    # bumper since they have no plain row in canon section 3.
    # WEST is the special-case `108 626 44` row — always msg #126.
    "108:east":  {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:north": {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:south": {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:ne":    {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:se":    {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:sw":    {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:nw":    {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:up":    {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:down":  {"check": "probability", "pct": 95,
                  "msg": "You have crawled around in some little holes and wound up back in the main passage."},
    "108:west":  {"check": "always",
                  "msg": "You have crawled around in some little holes and found your way blocked by a recent cave-in. You are now back in the main passage."},
    # Grate at depression (canon 8 → 9). Canon `8 303009 3 19 30`
    # gates ENTER, IN, and DOWN on grate-unlocked; the port had
    # 8:in/8:down gated but 8:enter ungated, letting players bypass
    # the gate by typing ENTER. All three verbs now route through
    # the same grate check.
    "8:down":    {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:in":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "8:enter":   {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # Symmetric mirror at canon 9 (below grate). Canon section 3
    # rows `9 303008 11 29` (OUT/UP → 8 when grate unlocked) and
    # `9 593 11` (OUT → msg #93 "the grate is locked"); both
    # rows collapse to a single grate-gated exit on the port side.
    "9:up":      {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    "9:out":     {"check": "grate",  "msg": "The grate is locked. You'd need keys to open it."},
    # DEPRESSION verb at debris/awkward/bird/pit-top — canon
    # rows `11 303008 63` / `12 303008 63` / `13 303008 63` /
    # `14 303008 63` are convenience teleports back to canon 8
    # (the depression with the grate above), gated on
    # prop(3) ≠ 0 = grate unlocked. The grate gate emits the
    # canon "grate is locked" prose when the condition fails;
    # otherwise the topology entry walks to 8 unblocked.
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
    # bouncer back to 15. The new "carrying" gate type takes
    # an `obj` field naming a port-side ID accessor; the driver
    # resolves it and fires when the player has the item in
    # inventory. The canonical solution is to drop gold,
    # navigate up via the cave, return via 19 → 28 → 33 with
    # the snake gone — but the trapped gold forces the player
    # to use the rod / bridge / Bedquilt long-way around.
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
