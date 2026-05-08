extends SceneTree

# Stage-DAG canonical playthrough — the "if this passes, the
# game works" test. The architectural commitment that
# distinguishes this from test_cca_full.gd:
#
#   1. NO `adv.player.move_to(...)` SETTER TELEPORTS. Every
#      navigation is a real `do_command("move", str(dest))`
#      that resolves a direction against the topology table.
#      If the canonical playthrough can't be walked from
#      `init` end-to-end with player commands, it doesn't
#      pass.
#   2. Stages are checkpointed via Frame `@@[persist]` and
#      restored to fast-forward between them. Same primitive
#      the state explorer uses, but here we use it to
#      eliminate redundant walking — every stage's `from`
#      must already exist as a checkpoint built by an
#      earlier stage that exercised real commands.
#   3. Each stage asserts post-conditions. Failure names the
#      stage and the assertion, so a regression points
#      directly at the broken transition.
#
# Branches: two stages can share a `from` checkpoint to
# explore alternate paths from the same world state. This
# scaffolding is here from day one even though the MVP is
# linear (init → dragon-killed). Failure-mode forks
# (resurrection cycle, vase shatter, dragon decline) come
# in a later commit.
#
# Status: this commit reaches dragon-killed via real
# commands only. The full win (deposit-all + endgame) is
# the next layer.

const Cca = preload("res://scripts/cca.gd")
const Topology = preload("res://scripts/topology.gd")

# ------------------------------------------------------------
# Stage shape
# ------------------------------------------------------------
# Each stage is a Dictionary with:
#   name        — String, identifies stage in failure reports
#   from        — String checkpoint to restore before running.
#                 "init" means a fresh Adventure.
#   actions     — Array of [verb_or_directive, arg]:
#                   ["go", "north"]   resolves direction → move
#                   ["move", "11"]    direct move (only for
#                                     non-direction shortcuts
#                                     like magic words; should
#                                     be rare)
#                   ["take", "keys"]  passthrough do_command
#                   etc.
#   asserts     — Callable(adv) → Array of [label, actual, expected]
#   checkpoint  — String, optional save name for descendants
# ------------------------------------------------------------

var checkpoints: Dictionary = {}    # name → save_state bytes
var failures: int = 0
var current_stage: String = ""

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("    ok   %-40s = %s" % [label, str(actual)])
    else:
        print("    FAIL [%s] %-40s = %s (expected %s)" % [
            current_stage, label, str(actual), str(expected)])
        failures += 1

# ------------------------------------------------------------
# Stage execution
# ------------------------------------------------------------
func _run_stage(stage: Dictionary) -> void:
    current_stage = stage.name
    print("--- stage: %s (from %s) ---" % [stage.name, stage.from])

    var adv = Cca.new()
    adv.setup_default_aspects()
    # Test-only: bump CLOSING_DURATION so the cave-closing teleport
    # doesn't fire mid-stage. Canon CLOSING_DURATION is 30 ticks,
    # which our long playthrough exceeds while still walking around
    # depositing treasures. We defer the teleport with a high value,
    # then explicitly drain the timer at the in_repository stage.
    adv.endgame.CLOSING_DURATION = 1000
    # Defer canon's deep-cave-turn dwarf auto-wake so the long
    # walk-driven playthrough doesn't get axed mid-batch. Tests
    # that specifically need stalking dwarves call wake_dwarves()
    # explicitly.
    adv.DWARF_WAKE_THRESHOLD = 9999
    # NB: wake_dwarves() deliberately not called. Dwarves are
    # canonically activated by deep-cave entry; on this test
    # path their random axe-throwing would inject seed-dependent
    # deaths that aren't what we're testing. A dedicated dwarves
    # stage (forking off a late checkpoint) covers that system.
    if stage.from != "init":
        if not checkpoints.has(stage.from):
            print("  FAIL no checkpoint named '%s' — stage authoring bug" % stage.from)
            failures += 1
            return
        adv.restore_state(checkpoints[stage.from])

    for entry in stage.get("actions", []):
        var verb: String = entry[0]
        var arg: String = entry[1] if entry.size() > 1 else ""

        if verb == "go":
            # Direction resolution — the test's analog of the
            # driver's _handle_movement. Look up the exit in
            # Topology.ROOMS for the player's current room
            # and emit a real do_command("move", str(dest)).
            # If the direction isn't in the exit table, we
            # treat that as a stage authoring bug — every
            # canonical step should be traversing a real exit.
            var room: int = adv.player_room()
            var exits: Dictionary = Topology.ROOMS.get(room, {})
            if not exits.has(arg):
                print("  FAIL [%s] no exit '%s' from room %d" % [
                    stage.name, arg, room])
                failures += 1
                return
            adv.do_command("move", str(exits[arg]))
            adv.tick()
        elif verb == "tick":
            # Bare tick — drives endgame timer, lamp drain,
            # hint observation. No command dispatch.
            adv.tick()
        elif verb == "spawn_chest":
            # Test rig: force the canonical chest to materialise
            # at CHEST_ROOM. Canon CCA spawns it when the pirate
            # makes its first steal; that roll is RNG and isn't
            # guaranteed to fire by the time this stage runs.
            # Mirrors what the pirate would do — keeps the rest
            # of the playthrough on its canon timeline.
            adv.chest.reappear(adv.CHEST_ROOM)
        elif verb == "force_in_repository":
            # Test rig: drain the closing timer until endgame
            # transitions to $InRepository. Mirrors the canonical
            # 30 ticks of cave-closing — we deferred them earlier
            # by setting CLOSING_DURATION = 1000 so the teleport
            # wouldn't fire mid-batch. Each adv.tick() also fires
            # the rising-edge teleport once endgame flips.
            var safety = 2000
            while not adv.endgame.in_repository() and safety > 0:
                adv.tick()
                safety -= 1
        elif verb == "detonate":
            # detonate_marker is a top-level Adventure event,
            # not a verb the parser routes through. Mirrors
            # test_cca_full.gd's direct call.
            adv.detonate_marker()
        elif verb == "die":
            # FSM event called by various in-game causes
            # (dwarf axe, bear maul, dark-room pit-fall).
            # Used in resurrection-cycle stages to exercise
            # the state machine directly without setting up
            # a fresh trigger each time.
            adv.player.die()
        elif verb == "revive":
            # FSM event the driver calls when the user types
            # "yes" at the resurrection prompt. Resets player
            # to START_ROOM with empty inventory.
            adv.player.revive()
        elif verb == "wake_dwarves":
            # Top-level Adventure event. Activates the five
            # dwarf instances from $Hidden to $Stalking. Used
            # in dwarf-specific stages that fork late and
            # exercise the axe-throw / kill-with-axe paths.
            adv.wake_dwarves()
        else:
            adv.do_command(verb, arg)
            adv.tick()

    if stage.has("asserts"):
        stage.asserts.call(adv, self)

    if stage.has("checkpoint"):
        checkpoints[stage.checkpoint] = adv.save_state()

# ------------------------------------------------------------
# Stage list
# ------------------------------------------------------------
# Authored as functions returning Dictionary so the asserts
# Callable can capture `self` cleanly (GDScript lambdas don't
# play well with Dictionary-literal closures across calls).
# ------------------------------------------------------------
func _stages() -> Array:
    return [
        # ----- Surface entry -----
        {
            "name":       "init_outside_road",
            "from":       "init",
            "actions":    [],
            "asserts":    _assert_at_road,
            "checkpoint": "outside_road",
        },
        {
            "name":       "in_well_house",
            "from":       "outside_road",
            "actions":    [["go", "in"]],
            "asserts":    _assert_in_well_house,
            "checkpoint": "well_house",
        },
        {
            "name":       "keys_and_bottle_taken",
            "from":       "well_house",
            "actions":    [["take", "keys"], ["take", "bottle"]],
            "asserts":    _assert_keys_and_bottle_carried,
            "checkpoint": "carrying_keys_bottle",
        },
        # Light the lamp before descending. Canon: moving in
        # the dark can pit-kill the player. Without this stage
        # the run dies between rooms 12 and 33.
        {
            "name":       "lamp_lit",
            "from":       "carrying_keys_bottle",
            "actions":    [["light", "lamp"]],
            "asserts":    _assert_lamp_lit,
            "checkpoint": "lamp_lit",
        },
        {
            "name":       "outside_grate",
            "from":       "lamp_lit",
            # Canon walking from well-house (3) to depression (8):
            # 3 → out → 1 (end of road), 1 → S → 4 (valley),
            # 4 → S → 7 (slit), 7 → S → 8 (depression). Canon
            # has no surface shortcut from end-of-road to the
            # depression — that's the four-step descent the
            # player must do to reach the grate.
            "actions":    [["go", "out"], ["go", "south"], ["go", "south"], ["go", "south"]],
            "asserts":    _assert_at_depression,
            "checkpoint": "at_depression",
        },
        {
            "name":       "grate_unlocked",
            "from":       "at_depression",
            "actions":    [["unlock", "grate"]],
            "asserts":    _assert_grate_unlocked,
            "checkpoint": "grate_unlocked",
        },
        # ----- Cave entry -----
        {
            "name":       "below_grate",
            "from":       "grate_unlocked",
            "actions":    [["go", "down"]],
            "asserts":    _assert_room(9),
            "checkpoint": "below_grate",
        },
        # Cobble Crawl (canon 10) carries the wicker cage. Canon
        # bird-take fails without it, so the take here is on the
        # critical path — feeds every later bird-using stage.
        {
            "name":       "cobbles_with_cage",
            "from":       "below_grate",
            "actions":    [["go", "west"], ["take", "cage"]],
            "asserts":    _assert_cage_carried_at_cobbles,
            "checkpoint": "carrying_cage",
        },
        {
            "name":       "debris_room",
            "from":       "carrying_cage",
            "actions":    [["go", "west"]],          # 10 → 11
            "asserts":    _assert_room(11),
            "checkpoint": "debris_room",
        },
        {
            "name":       "rod_taken",
            "from":       "debris_room",
            "actions":    [["take", "rod"]],
            "asserts":    _assert_rod_carried,
            "checkpoint": "carrying_rod",
        },
        # Canon: gold lives at room 18 ("low room with crude
        # note, you won't get it up the steps"), reached only
        # from Hall of Mists east end (15) → south. Path from
        # debris (11): 11 west → 12 → up → 13 → west → 14 →
        # down → 15 → south → 18. Take gold, then return to Y2
        # (33) via the canonical XYZZY/PLUGH magic-word route
        # since canon has no walking shortcut from 14 to 33.
        {
            "name":       "gold_taken_back_at_y2",
            "from":       "carrying_rod",
            "actions":    [
                ["go", "west"],            # 11 → 12 (canon)
                ["go", "up"],              # 12 → 13 (canon)
                ["go", "west"],            # 13 → 14 (canon)
                ["go", "down"],            # 14 → 15 (canon)
                ["go", "south"],           # 15 → 18 (canon, gold-nugget room)
                ["take", "gold"],
                ["go", "north"],           # 18 → 15 (canon)
                ["go", "up"],              # 15 → 14 (canon)
                ["go", "east"],            # 14 → 13 (canon)
                ["go", "east"],            # 13 → 12 (canon)
                ["go", "east"],            # 12 → 11 (canon)
                ["xyzzy", ""],             # 11 → 3 (well house)
                ["plugh", ""],             # 3 → 33 (Y2 marker)
            ],
            "asserts":    _assert_rod_and_gold_carried,
            "checkpoint": "carrying_rod_gold",
        },
        # carrying_rod_gold checkpoint is now AT Y2 (33).
        # at_y2 stage is a no-op assert; downstream stages
        # already chain off carrying_rod_gold via Y2.
        {
            "name":       "at_y2",
            "from":       "carrying_rod_gold",
            "actions":    [],
            "asserts":    _assert_room(33),
            "checkpoint": "at_y2",
        },
        {
            "name":       "bird_chamber",
            "from":       "at_y2",
            # Canon path Y2 (33) → bird chamber (13):
            #   33 east → 34 (jumble of rock)
            #   34 up   → 15 (Hall of Mists east end)
            #   15 up   → 14 (top of small pit)
            #   14 east → 13 (bird chamber)
            "actions":    [
                ["go", "east"],            # 33 → 34
                ["go", "up"],              # 34 → 15
                ["go", "up"],              # 15 → 14
                ["go", "east"],            # 14 → 13
            ],
            "asserts":    _assert_room(13),
            "checkpoint": "bird_chamber",
        },
        # Bird is carryable only because we don't have the rod
        # in inventory yet. Wait — we DO have the rod. Canon
        # CCA: bird won't approach if you carry the rod.
        # We need to drop the rod first, take bird, pick rod
        # back up. Test that real constraint.
        {
            "name":       "bird_taken_drop_rod_first",
            "from":       "bird_chamber",
            "actions":    [["drop", "rod"], ["take", "bird"], ["take", "rod"]],
            "asserts":    _assert_bird_and_rod_carried,
            "checkpoint": "carrying_bird_rod",
        },
        # ----- Snake at canon 19 (Hall of Mountain King) -----
        # Canon path bird chamber (13) → 19: 13 west → 14, 14
        # down → 15, 15 north → 19. Snake blocks the canyon
        # exits north (to canon 28 / silver passage), south (to
        # canon 29 / jewelry), and west (to canon 30 / coins).
        {
            "name":       "at_snake_passage",
            "from":       "carrying_bird_rod",
            "actions":    [
                ["go", "west"],            # 13 → 14 (canon)
                ["go", "down"],            # 14 → 15 (canon)
                ["go", "north"],           # 15 → 19 (canon: north/stairs/down → 19)
            ],
            "asserts":    _assert_at_snake_passage,
            "checkpoint": "snake_blocking",
        },
        {
            "name":       "snake_cleared",
            "from":       "snake_blocking",
            "actions":    [["release", "bird"]],
            "asserts":    _assert_snake_cleared,
            "checkpoint": "snake_cleared",
        },
        # ----- Dragon at canon 119 (Secret canyon) -----
        # Canon path Hall of Mt King (19, snake gone) → dragon
        # canyon (119):
        #   19 → north → 28 (silver passage; snake-gated)
        #   28 → down  → 36 (dirty broken passage)
        #   36 → bedquilt → 65 (Bedquilt, long-distance verb)
        #   65 → slab  → 68 (slab room)
        #   68 → up    → 69 (secret N/S canyon above large room)
        #   69 → south → 119 (DRAGON)
        {
            "name":       "at_dragon",
            "from":       "snake_cleared",
            "actions":    [
                ["go", "north"],           # 19 → 28 (silver passage)
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "slab"],            # 65 → 68
                ["go", "up"],              # 68 → 69
                ["go", "south"],           # 69 → 119 (DRAGON)
            ],
            "asserts":    _assert_at_dragon,
            "checkpoint": "facing_dragon",
        },
        {
            "name":       "dragon_killed",
            "from":       "facing_dragon",
            "actions":    [["attack", "dragon"], ["yes", ""]],
            "asserts":    _assert_dragon_dead,
            "checkpoint": "dragon_dead",
        },
        # ----- Treasure haul: rug at 119, diamonds at canon 27 -----
        # Canon: rug is under dragon at 119; diamonds at room 27
        # (west bank fissure in Hall of Mists), entirely separate
        # from dragon. After the kill, take the rug at 119, walk
        # the canon route back to Y2 (33) through Bedquilt-cluster
        # — 119 → N → 69 → D → 68 → N → 65 → UP → 39 → E → 36 →
        # UP → 28 → N → 33 — then cross the fissure (33 → E → 34
        # → UP → 15 → W → 17, wave rod to materialize the crystal
        # bridge, OVER → 27).
        {
            "name":       "rug_taken",
            "from":       "dragon_dead",
            "actions":    [["take", "rug"]],
            "asserts":    _assert_rug_carried_at_119,
            "checkpoint": "carrying_rug",
        },
        {
            "name":       "diamonds_taken_at_west_bank",
            "from":       "carrying_rug",
            "actions":    [
                # 119 → 33 via canon Bedquilt-cluster ascent.
                ["go", "north"],           # 119 → 69
                ["go", "down"],            # 69 → 68
                ["go", "north"],           # 68 → 65 (Bedquilt)
                ["go", "up"],               # 65 → 39 (cliff)
                ["go", "east"],            # 39 → 36
                ["go", "up"],               # 36 → 28 (silver passage)
                ["go", "north"],           # 28 → 33 (Y2)
                # 33 → 17 via Hall of Mists west.
                ["go", "east"],            # 33 → 34 (jumble of rock)
                ["go", "up"],               # 34 → 15 (Hall of Mists)
                ["go", "west"],            # 15 → 17 (east bank fissure)
                # Build the crystal bridge so the fissure is
                # crossable (and stays crossable on the way back).
                ["wave", "rod"],
                ["go", "over"],            # 17 → 27 (west bank — diamonds)
                ["take", "diamonds"],
            ],
            "asserts":    _assert_diamonds_rug_carried,
            "checkpoint": "carrying_first_haul",
        },
        {
            "name":       "deposit_first_haul",
            "from":       "carrying_first_haul",
            "actions":    [
                # 27 → 17 over the (still-built) crystal bridge,
                # then back through Hall of Mt King via 19 (snake
                # gone) to 28 → 33, and PLUGH home to drop.
                ["go", "over"],            # 27 → 17
                ["go", "east"],            # 17 → 15 (bridge built)
                ["go", "down"],            # 15 → 19 (Hall of Mt King)
                ["go", "north"],           # 19 → 28 (silver passage; snake gone)
                ["go", "north"],           # 28 → 33 (Y2)
                ["plugh", ""],             # 33 → 3 (well house)
                ["drop", "diamonds"],
                ["drop", "rug"],
                ["drop", "gold"],
            ],
            "asserts":    _assert_three_treasures_deposited,
            "checkpoint": "after_first_deposit",
        },
        # ----- Silver from low-n/s passage (canon 28) -----
        # Canon: silver at room 28, reached from Y2 (33) south.
        # Walk: PLUGH (3 → 33) → south (33 → 28) → take silver
        # → north (28 → 33) for return PLUGH.
        {
            "name":       "take_silver",
            "from":       "after_first_deposit",
            "actions":    [
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28
                ["take", "silver"],
            ],
            "asserts":    _assert_silver_carried,
            "checkpoint": "carrying_silver",
        },
        {
            "name":       "deposit_silver",
            "from":       "carrying_silver",
            "actions":    [
                ["go", "north"],           # 28 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "silver"],
            ],
            "asserts":    _assert_treasures_deposited(4),
            "checkpoint": "after_silver",
        },
        # ----- Pearl + Emerald from Plover Room -----
        # Canon: emerald lives in the Plover Room (canon 100),
        # but pearl is dynamic — extracted by BREAKing the clam
        # at the Shell Room (canon 103). _verb_break makes the
        # pearl reappear at the player's room, so we crack it
        # right at 103 to avoid hauling it back through Bedquilt.
        # Then walk 103 → 33 and PLOVER round-trip for the emerald.
        {
            "name":       "take_pearl_emerald",
            "from":       "after_silver",
            "actions":    [
                # 3 → 103 via Y2 → silver passage → Bedquilt cluster.
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28 (silver passage)
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "east"],            # 65 → 64 (complex junction)
                ["go", "north"],           # 64 → 103 (Shell Room)
                ["take", "clam"],
                ["break", "clam"],         # pearl appears at 103
                ["take", "pearl"],
                # 103 → 33 via cliff (39).
                ["go", "south"],           # 103 → 64
                ["go", "west"],            # 64 → 65 (Bedquilt)
                ["go", "up"],               # 65 → 39 (cliff)
                ["go", "east"],            # 39 → 36
                ["go", "up"],               # 36 → 28
                ["go", "north"],           # 28 → 33
                # Emerald via PLOVER round trip.
                ["plover", ""],            # 33 → 100
                ["take", "emerald"],
                ["plover", ""],            # 100 → 33
            ],
            "asserts":    _assert_pearl_emerald_carried,
            "checkpoint": "carrying_pearl_emerald",
        },
        {
            "name":       "deposit_pearl_emerald",
            "from":       "carrying_pearl_emerald",
            "actions":    [
                ["plugh", ""],             # 33 → 3
                ["drop", "pearl"],
                ["drop", "emerald"],
            ],
            "asserts":    _assert_treasures_deposited(6),
            "checkpoint": "after_pearl",
        },
        # ----- Plant beanstalk + giant chamber + troll bridge -----
        # Canon: bear at 130 (Barren Room) is reached only by
        # crossing the troll bridge (117 → 122 → 129 → 130). The
        # troll demands tribute; canon's solution is to throw the
        # eggs (recallable later via FEE FIE FOE FOO). To reach
        # the eggs in the giant chamber (92) the player needs the
        # huge plant — climb 25 → 26 → 88 → west 92. The huge
        # plant requires two waterings (Tiny → Tall → Huge),
        # which means two round trips between West Pit and the
        # well house spring.
        {
            "name":       "plant_watered_to_huge",
            "from":       "after_pearl",
            "actions":    [
                # Pick up canon FOOD at the well house — needed
                # to tame the bear later. Inventory pressure is
                # gone now (treasures all deposited) so we can
                # carry it through the plant + bridge sequence.
                ["take", "food"],
                # First trip: fill at well house, walk down to
                # West Pit, pour. Plant Tiny → Tall.
                ["fill", "bottle"],
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "slab"],            # 65 → 68
                ["go", "south"],           # 68 → 23
                ["go", "down"],            # 23 → 25 (West Pit)
                ["water", "plant"],        # plant Tiny → Tall
                # Walk back to 33 via the now-tall plant route:
                # 25 → up → 23 → west → 68 → north → 65 → up → 39
                # → east → 36 → up → 28 → north → 33. PLUGH home.
                ["go", "up"],              # 25 → 23 (plant tall lifts)
                ["go", "west"],            # 23 → 68
                ["go", "north"],           # 68 → 65
                ["go", "up"],              # 65 → 39
                ["go", "east"],            # 39 → 36
                ["go", "up"],              # 36 → 28
                ["go", "north"],           # 28 → 33
                ["plugh", ""],             # 33 → 3
                # Second trip: refill, walk back, pour again.
                # Plant Tall → Huge.
                ["fill", "bottle"],
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "slab"],            # 65 → 68
                ["go", "south"],           # 68 → 23
                ["go", "down"],            # 23 → 25
                ["water", "plant"],        # plant Tall → Huge
            ],
            "asserts":    _assert_plant_huge_at_west_pit,
            "checkpoint": "plant_huge",
        },
        # Canon: with the plant huge, CLIMB at West Pit goes
        # 25 → 26 (transition message) → 88 (cliff above giant)
        # → west → 92 (giant chamber, eggs).
        {
            "name":       "eggs_taken_at_giant",
            "from":       "plant_huge",
            "actions":    [
                ["go", "climb"],           # 25 → 26 (huge plant)
                ["go", "east"],            # 26 → 88 (transition bounce)
                ["go", "west"],            # 88 → 92 (giant chamber)
                ["take", "eggs"],
            ],
            "asserts":    _assert_eggs_carried_at_giant,
            "checkpoint": "carrying_eggs",
        },
        # Canon: troll bridge (117) is reached from the giant
        # chamber via the magnificent cavern + steep incline:
        # 92 → north → 94 → north → 95 → west → 91 → down → 72
        # → sw → 118 → up → 117. Throw eggs at the troll; troll
        # pays toll and ceases to block the bridge. Cross to
        # 122 (R_NESIDE), then take the bear-chamber path
        # 122 → barren → 129 → enter → 130. Pick up food at
        # the well house in the prep round (we did so at
        # `at_bear_chamber` originally; here we already have it
        # — see `after_pearl` carries food via the `take_food`
        # added back at the carrying_pearl_emerald checkpoint).
        {
            "name":       "at_bear_chamber",
            "from":       "carrying_eggs",
            "actions":    [
                ["take", "food"],          # canon FOOD at well house — but we're at 92.
                                           # No-op if not present; the action
                                           # is harmless and keeps the original
                                           # invariant intact.
                ["go", "north"],           # 92 → 94
                ["go", "north"],           # 94 → 95
                ["go", "west"],            # 95 → 91
                ["go", "down"],            # 91 → 72
                ["go", "sw"],              # 72 → 118
                ["go", "up"],              # 118 → 117 (troll bridge)
                ["throw", "eggs"],         # troll catches eggs → toll paid
                ["go", "over"],            # 117 → 122 (R_NESIDE, troll cleared)
                ["go", "barren"],          # 122 → 129 (front of barren room)
                ["go", "enter"],           # 129 → 130 (bear inside)
            ],
            "asserts":    _assert_room_and_bear(130, "hungry"),
            "checkpoint": "at_bear_chamber",
        },
        {
            "name":       "bear_tame_chained",
            "from":       "at_bear_chamber",
            "actions":    [["feed", "bear"], ["take", "chain"]],
            "asserts":    _assert_bear_following,
            "checkpoint": "bear_following",
        },
        # Walk back to the troll bridge with the bear in tow,
        # drop the chain — bear stays at 117 and the troll is
        # permanently vanished.
        {
            "name":       "troll_vanished",
            "from":       "bear_following",
            "actions":    [
                ["go", "out"],             # 130 → 129
                ["go", "west"],            # 129 → 128
                ["go", "north"],           # 128 → 124
                ["go", "west"],            # 124 → 123
                ["go", "west"],            # 123 → 122
                ["go", "over"],            # 122 → 117 (troll already paid)
                ["drop", "chain"],
            ],
            "asserts":    _assert_troll_vanished,
            "checkpoint": "troll_vanished",
        },
        # Recall the thrown eggs back to the giant chamber via
        # canon's incantation. Important for the deep-cave batch
        # (eggs are one of the 14 treasures).
        {
            "name":       "eggs_recalled_after_toll",
            "from":       "troll_vanished",
            "actions":    [
                ["fee", ""], ["fie", ""], ["foe", ""], ["foo", ""],
            ],
            "asserts":    _assert_eggs_back_at_giant,
            "checkpoint": "eggs_recalled",
        },
        # Jewelry is at canon 29 (south side chamber). Walk
        # 117 → SW → 118 → down → 72 → bedquilt → 65 → up → 39
        # → east → 36 → up → 28 → north → 33 → east → 34 → up
        # → 15 → north → 19 → south → 29.
        {
            "name":       "take_jewelry",
            "from":       "eggs_recalled",
            "actions":    [
                ["go", "sw"],              # 117 → 118
                ["go", "down"],            # 118 → 72
                ["go", "bedquilt"],        # 72 → 65
                ["go", "up"],              # 65 → 39
                ["go", "east"],            # 39 → 36
                ["go", "up"],              # 36 → 28
                ["go", "north"],           # 28 → 33 (Y2)
                ["go", "east"],            # 33 → 34
                ["go", "up"],              # 34 → 15
                ["go", "north"],           # 15 → 19 (Hall of Mt King; snake gone)
                ["go", "south"],           # 19 → 29 (south side chamber)
                ["take", "jewelry"],
            ],
            "asserts":    _assert_jewelry_carried,
            "checkpoint": "carrying_jewelry",
        },
        # ----- Deep cave loop: vase, eggs, trident -----
        # 118 → 120 → 97(vase) → 92(eggs) → 130(trident).
        # Emerald moved to canon Plover Room (taken with pearl
        # in the earlier trip), so deep-cave batch_a is now 3
        # treasures. We drop jewelry at well house first
        # (separate trip) so the deep-cave run starts with
        # only keys/bottle/rod in inventory.
        {
            "name":       "deposit_jewelry",
            "from":       "carrying_jewelry",
            "actions":    [
                # 29 → 19 (snake gone) → 28 (silver passage; snake
                # gone) → 33 (Y2). Canon doesn't connect 14 → 33,
                # so the return goes via 19 → 28 instead of via
                # 14 → 15 → 19 → 28 — same destination, two fewer
                # rooms.
                ["go", "north"],           # 29 → 19 (Hall of Mt King)
                ["go", "north"],           # 19 → 28 (silver passage)
                ["go", "north"],           # 28 → 33 (Y2)
                ["plugh", ""],             # 33 → 3 (well house)
                ["drop", "jewelry"],
            ],
            "asserts":    _assert_treasures_deposited(7),
            "checkpoint": "after_jewelry",
        },
        # Vase is fragile — dropping it without a pillow at the
        # destination shatters it. Canon solution: drop the
        # velvet pillow (at canon 96, Soft Room) at the well
        # house first, then later drops onto pillow are soft
        # landings. Path 3 → 96 → 3:
        #   3 → plugh → 33 → S → 28 → D → 36 → bedquilt → 65 →
        #   W → 66 → E → 96. Take pillow. Reverse via the
        #   cliff (39): 96 → W → 66 → NE → 65 → UP → 39 → E →
        #   36 → UP → 28 → N → 33 → plugh → 3. Drop pillow.
        {
            "name":       "pillow_to_well_house",
            "from":       "after_jewelry",
            "actions":    [
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "west"],            # 65 → 66
                ["go", "east"],            # 66 → 96 (Soft Room)
                ["take", "pillow"],
                ["go", "west"],            # 96 → 66
                ["go", "ne"],              # 66 → 65
                ["go", "up"],              # 65 → 39 (cliff)
                ["go", "east"],            # 39 → 36
                ["go", "up"],              # 36 → 28
                ["go", "north"],           # 28 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "pillow"],
            ],
            "asserts":    _assert_pillow_at_well_house,
            "checkpoint": "after_pillow",
        },
        # Deep cave batch_a — vase (canon 97), eggs (canon 92,
        # recalled), trident (canon 95). Canon path 3 → vase →
        # eggs → trident:
        #   3 → plugh → 33 → S → 28 → D → 36 → bedquilt → 65 →
        #   W → 66 → oriental → 97 (Oriental Room). Take vase.
        # Then walk to West Pit and climb the still-huge plant
        # to get into the giant chamber:
        #   97 → W → 72 → bedquilt → 65 → slab → 68 → S → 23 →
        #   D → 25 → climb → 26 → E → 88 → W → 92. Take eggs.
        # Magnificent Cavern is north of the giant chamber:
        #   92 → N → 94 → N → 95. Take trident.
        {
            "name":       "deep_cave_batch_a_takes",
            "from":       "after_pillow",
            "actions":    [
                ["plugh", ""],             # 3 → 33
                ["go", "south"],           # 33 → 28
                ["go", "down"],            # 28 → 36
                ["go", "bedquilt"],        # 36 → 65
                ["go", "west"],            # 65 → 66
                ["go", "oriental"],        # 66 → 97
                ["take", "vase"],
                ["go", "west"],            # 97 → 72
                ["go", "bedquilt"],        # 72 → 65
                ["go", "slab"],            # 65 → 68
                ["go", "south"],           # 68 → 23
                ["go", "down"],            # 23 → 25 (West Pit, plant huge)
                ["go", "climb"],           # 25 → 26 (huge plant)
                ["go", "east"],            # 26 → 88
                ["go", "west"],            # 88 → 92 (Giant Room)
                ["take", "eggs"],
                ["go", "north"],           # 92 → 94
                ["go", "north"],           # 94 → 95 (Magnificent Cavern)
                ["take", "trident"],
            ],
            "asserts":    _assert_batch_a_carried,
            "checkpoint": "carrying_batch_a",
        },
        # Walk 95 → 3, dropping eggs/trident first then vase
        # last so the vase lands on the pillow:
        #   95 → S → 94 → S → 92 → S → 88 → D → 25 → UP → 23 →
        #   W → 68 → N → 65 → UP → 39 → E → 36 → UP → 28 → N →
        #   33 → plugh → 3.
        {
            "name":       "deposit_batch_a",
            "from":       "carrying_batch_a",
            "actions":    [
                ["go", "south"],           # 95 → 94
                ["go", "south"],           # 94 → 92
                ["go", "south"],           # 92 → 88
                ["go", "down"],            # 88 → 25
                ["go", "up"],              # 25 → 23 (plant tall lifts)
                ["go", "west"],            # 23 → 68
                ["go", "north"],           # 68 → 65
                ["go", "up"],              # 65 → 39
                ["go", "east"],            # 39 → 36
                ["go", "up"],              # 36 → 28
                ["go", "north"],           # 28 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "eggs"],
                ["drop", "trident"],
                ["drop", "vase"],          # lands on pillow → preserved
            ],
            "asserts":    _assert_treasures_deposited(10),
            "checkpoint": "after_batch_a",
        },
        # ----- Batch B: chest (deep cave) + spices (canon 127) + pyramid (canon 101) -----
        # Three separate excursions on canonical homes:
        #   - chest: pirate's stash at canon 18 (low room w/ steps note)
        #   - spices: anteroom-to-volcano-to-boulders chain → 127
        #   - pyramid: PLOVER round-trip → 100 → north → 101
        # Chest excursion path: 3 → plugh → 33 → north 14 → down 15
        # → south 18. Take chest. End at 18.
        {
            "name":       "deep_cave_batch_b_takes",
            "from":       "after_batch_a",
            "actions":    [
                # Canon: chest is dynamic — spawned by the
                # pirate. The pirate's first roll isn't seeded
                # to fire by this point in the test, so use the
                # spawn_chest test rig to materialise it now.
                ["spawn_chest", ""],
                ["plugh", ""],          # 3 → 33 (Y2)
                ["go", "north"],        # 33 → 14 (top of small pit)
                ["go", "down"],         # 14 → 15 (Hall of Mists east end)
                ["go", "south"],        # 15 → 18 (low room, canon stash)
                ["take", "chest"],
            ],
            "asserts":    _assert_batch_b_partial_carried,
            "checkpoint": "carrying_batch_b",
        },
        # End of batch_b takes: at 18 with chest only. Reverse to
        # well house, drop chest, then two more excursions for
        # spices (canon 127) and pyramid (canon 101).
        # Spices excursion path: 3 → plugh → 33 → west 65 → north
        # 72 → north 73 → down 74 → north 75 → north 76 → north 77
        # → east 78 → north 87 → down 119 → down 121 → north 123
        # → north 126 → north 127. Take spices, then reverse the
        # 14 commands back to 33, plugh → 3.
        {
            "name":       "deposit_batch_b",
            "from":       "carrying_batch_b",
            "actions":    [
                # Walk back from 18 → 3 (north 18 → 15, up 15 → 14,
                # south 14 → 33, plugh 33 → 3).
                ["go", "north"],           # 18 → 15
                ["go", "up"],              # 15 → 14
                ["go", "south"],           # 14 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "chest"],
                # Spices excursion: 3 → 33 → 65 → 72 → 73 → 74 →
                # 75 → 76 → 77 → 78 → 87 → 119 → 121 → 123 → 126
                # → 127.
                ["plugh", ""],             # 3 → 33
                ["go", "west"],            # 33 → 65
                ["go", "north"],           # 65 → 72
                ["go", "north"],           # 72 → 73
                ["go", "down"],            # 73 → 74
                ["go", "north"],           # 74 → 75
                ["go", "north"],           # 75 → 76
                ["go", "north"],           # 76 → 77
                ["go", "east"],            # 77 → 78
                ["go", "north"],           # 78 → 87
                ["go", "down"],            # 87 → 119
                ["go", "down"],            # 119 → 121
                ["go", "north"],           # 121 → 123
                ["go", "north"],           # 123 → 126
                ["go", "north"],           # 126 → 127 (Chamber of Boulders)
                ["take", "spices"],
                # Reverse to 3.
                ["go", "south"],           # 127 → 126
                ["go", "south"],           # 126 → 123
                ["go", "south"],           # 123 → 121
                ["go", "up"],              # 121 → 119
                ["go", "up"],              # 119 → 87
                ["go", "south"],           # 87 → 78
                ["go", "west"],            # 78 → 77
                ["go", "south"],           # 77 → 76
                ["go", "south"],           # 76 → 75
                ["go", "south"],           # 75 → 74
                ["go", "up"],              # 74 → 73
                ["go", "south"],           # 73 → 72
                ["go", "south"],           # 72 → 65
                ["go", "west"],            # 65 → 33 (asymmetric "west": both
                                           # 33 west → 65 and 65 west → 33)
                ["plugh", ""],             # 33 → 3
                ["drop", "spices"],
                # Pyramid via PLOVER: 3 → plugh → 33 → plover →
                # 100 → north → 101 (Dark-room). Take pyramid,
                # back south → 100 → plover → 33 → plugh → 3.
                ["plugh", ""],             # 3 → 33
                ["plover", ""],            # 33 → 100
                ["go", "north"],           # 100 → 101 (Dark-room)
                ["take", "pyramid"],
                ["go", "south"],           # 101 → 100
                ["plover", ""],            # 100 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "pyramid"],
            ],
            "asserts":    _assert_treasures_deposited(13),
            "checkpoint": "after_batch_b",
        },
        # ----- Batch C: coins (canon 30) + chain (canon 130) -----
        # Coins live at canon 30 (West side chamber Hall of Mt
        # King) per advent.dat. Then pick up the chain at the
        # troll bridge (130 was the bear's room; the chain is
        # left behind once the bear is fed and lumbers off).
        # Coins trip: 3 → plugh → 33 → north 14 → down 15 →
        # west 19 → north 30, take, back via south → east → up
        # → south → 33.
        # Chain trip: from 33 → west 65 → east 117 (troll bridge).
        {
            "name":       "deep_cave_batch_c_takes",
            "from":       "after_batch_b",
            "actions":    [
                # --- Coins via Hall of Mt King ---
                ["plugh", ""],             # 3 → 33
                ["go", "north"],           # 33 → 14
                ["go", "down"],            # 14 → 15
                ["go", "west"],            # 15 → 19
                ["go", "north"],           # 19 → 30 (West side chamber)
                ["take", "coins"],
                ["go", "south"],           # 30 → 19
                ["go", "east"],            # 19 → 15
                ["go", "up"],              # 15 → 14
                ["go", "south"],           # 14 → 33
                # --- Chain pick-up at troll bridge (canon 15th
                # treasure). Bear has long since lumbered off, so
                # the chain is just a free treasure on the bridge.
                ["go", "west"],            # 33 → 65
                ["go", "east"],            # 65 → 117 troll bridge
                ["take", "chain"],
            ],
            "asserts":    _assert_batch_c_carried,
            "checkpoint": "carrying_batch_c",
        },
        # End of batch_c takes: at 117. Reverse: west 117→65,
        # west 65→33, plugh → 3 — drop coins + chain.
        {
            "name":       "deposit_batch_c",
            "from":       "carrying_batch_c",
            "actions":    [
                ["go", "west"],            # 117 → 65
                ["go", "west"],            # 65 → 33 (asymmetric)
                ["plugh", ""],             # 33 → 3
                ["drop", "coins"],
                ["drop", "chain"],
            ],
            "asserts":    _assert_all_15_deposited,
            "checkpoint": "all_deposited",
        },
        # ----- Endgame -----
        # We bumped CLOSING_DURATION = 1000 at test setup so the
        # cave-closing teleport wouldn't fire while we walked the
        # canon paths to deposit treasures 11-15. Now drain the
        # timer explicitly via the force_in_repository test rig,
        # which ticks until $Closing → $InRepository transitions.
        # The Adventure tick handler then teleports the player to
        # REPOSITORY_ROOM (canon 116) on the rising edge.
        {
            "name":       "in_repository",
            "from":       "all_deposited",
            "actions":    [["force_in_repository", ""]],
            "asserts":    _assert_in_repository,
            "checkpoint": "in_repository",
        },
        {
            "name":       "won",
            "from":       "in_repository",
            "actions":    [["detonate", ""]],
            "asserts":    _assert_won,
            "checkpoint": "won",
        },
        # ============================================================
        # Failure-mode forks
        # ============================================================
        # These stages don't continue the canonical path — they fork
        # off existing checkpoints to exercise alternate branches the
        # winning playthrough can't cover. Each one ends in an
        # asserted state (broken / dead / declined) and doesn't feed
        # into a downstream stage.
        # ============================================================

        # Dragon decline: at facing_dragon, attack but say no.
        # Dragon returns to $Sleeping; player can re-attack later.
        {
            "name":       "dragon_declined",
            "from":       "facing_dragon",
            "actions":    [["attack", "dragon"], ["no", ""]],
            "asserts":    _assert_dragon_sleeping,
            "checkpoint": "dragon_declined",
        },
        {
            "name":       "dragon_killed_after_decline",
            "from":       "dragon_declined",
            "actions":    [["attack", "dragon"], ["yes", ""]],
            "asserts":    _assert_dragon_dead,
        },
        # Fragile vase shatter: at carrying_batch_a we have the
        # vase. Drop it anywhere except the well house (deposit
        # room) → $Broken. Tested in isolation by
        # test_cca_fragile_vase.gd; here we verify it from the
        # canonical mid-game state, not a synthetic setup.
        {
            "name":       "vase_shattered_mid_game",
            "from":       "carrying_batch_a",
            "actions":    [["drop", "vase"]],
            "asserts":    _assert_vase_broken,
            "checkpoint": "vase_shattered",
        },
        # Bear-mauling: at at_bear_chamber, take chain WITHOUT
        # feeding the bear → bear goes $Attacking and player
        # dies. The "feed first" rule encoded as state.
        {
            "name":       "bear_maul",
            "from":       "at_bear_chamber",
            "actions":    [["take", "chain"]],
            "asserts":    _assert_player_dead_bear_attacking,
            "checkpoint": "after_first_bear_death",
        },
        # Resurrection cycle: from after_first_bear_death we
        # have death #1. Direct die/revive from there — the
        # FSM is the system under test, not the trigger
        # mechanism. Three more deaths → $Permadead.
        {
            "name":       "second_death",
            "from":       "after_first_bear_death",
            "actions":    [["revive", ""], ["die", ""]],
            "asserts":    _assert_dead_count(2),
        },
        {
            "name":       "third_death",
            "from":       "after_first_bear_death",
            "actions":    [["revive", ""], ["die", ""], ["revive", ""], ["die", ""]],
            "asserts":    _assert_dead_count(3),
        },
        {
            "name":       "permadead_after_fourth",
            "from":       "after_first_bear_death",
            "actions":    [
                ["revive", ""], ["die", ""],
                ["revive", ""], ["die", ""],
                ["revive", ""], ["die", ""],
            ],
            "asserts":    _assert_permadead,
        },

        # ============================================================
        # Cross-system regressions
        # ============================================================
        # Behaviours that span more than one FSM. Single-system
        # tests don't catch these because the bug only surfaces
        # when two FSMs coordinate via Adventure's brokering.
        # ============================================================

        # Eggs incantation: FEE FIE FOE FOO chant resets the eggs
        # back to the Giant Room (92) regardless of where they
        # were — including from $Deposited. test_cca_full doesn't
        # exercise this; the Treasure $Deposited.reappear branch
        # is canon-bug intentional ("you can re-deposit and
        # double-score").
        {
            "name":       "eggs_summoned_back",
            "from":       "after_batch_a",
            "actions":    [
                ["fee", ""], ["fie", ""], ["foe", ""], ["foo", ""],
            ],
            "asserts":    _assert_eggs_back_at_giant,
        },

        # Plant beanstalk: bottle + plant cross-FSM. From an
        # already-grate-unlocked checkpoint, fill the bottle at
        # the well house water source, walk down through the
        # cave to the West Pit (room 23), pour. plant.water()
        # transitions $Tiny → $Tall; bottle.pour() empties the
        # bottle. Both side-effects must land for the canonical
        # plant puzzle to work.
        {
            "name":       "plant_watered_to_tall",
            "from":       "after_first_deposit",
            "actions":    [
                ["fill", "bottle"],         # at room 3 — water source
                ["go", "out"],              # 3 → 1 (canon: out)
                ["go", "south"],            # 1 → 4 (canon: S)
                ["go", "south"],            # 4 → 7 (canon: S)
                ["go", "south"],            # 7 → 8 (canon: S)
                ["go", "down"],             # 8 → 9 (grate already unlocked)
                ["go", "west"],             # 9 → 10
                ["go", "west"],             # 10 → 11
                ["go", "east"],             # 11 → 12
                ["go", "north"],            # 12 → 33
                ["go", "north"],            # 33 → 14
                ["go", "down"],             # 14 → 15
                ["go", "north"],            # 15 → 21
                ["go", "west"],             # 21 → 25 (canon West Pit, plant home)
                ["water", "plant"],
            ],
            "asserts":    _assert_plant_tall,
        },

        # ============================================================
        # Dwarves
        # ============================================================
        # The canonical playthrough deliberately doesn't call
        # wake_dwarves() so axe-throwing doesn't inject seed-
        # dependent deaths into the win path. This stage forks
        # late, wakes them, and exercises the activation logic.
        # ============================================================
        {
            "name":       "dwarves_woken",
            "from":       "after_first_deposit",
            "actions":    [["wake_dwarves", ""]],
            "asserts":    _assert_dwarves_living,
        },
    ]

# A "tick" pseudo-action: emit ["tick", ""] N times. The
# stage runner translates this to adv.tick() calls below.
func _ticks(n: int) -> Array:
    var out: Array = []
    for _i in range(n):
        out.append(["tick", ""])
    return out

# ------------------------------------------------------------
# Asserts (each takes adv + the test SceneTree for _expect access)
# ------------------------------------------------------------
func _assert_at_road(adv, t) -> void:
    t._expect("player_room", adv.player_room(), 1)
    t._expect("player_state", adv.player_state(), "alive")

func _assert_in_well_house(adv, t) -> void:
    t._expect("player_room", adv.player_room(), 3)

func _assert_keys_and_bottle_carried(adv, t) -> void:
    t._expect("keys carried",   adv.keys_in_inventory(),   true)
    t._expect("bottle carried", adv.bottle_in_inventory(), true)

func _assert_lamp_lit(adv, t) -> void:
    t._expect("lamp lit",     adv.is_lit(),         true)
    t._expect("lamp state",   adv.get_lamp_state(), "bright")

func _assert_at_depression(adv, t) -> void:
    t._expect("player_room",  adv.player_room(),    8)
    t._expect("grate locked", adv.grate_locked(),   true)

func _assert_grate_unlocked(adv, t) -> void:
    t._expect("grate unlocked", adv.grate_locked(), false)
    t._expect("at depression",  adv.player_room(),  8)

func _assert_room(want: int) -> Callable:
    return func(adv, t): t._expect("player_room", adv.player_room(), want)

func _assert_cage_carried_at_cobbles(adv, t) -> void:
    t._expect("cage carried", adv.player.carrying(adv.CAGE_ID), true)
    t._expect("at cobbles",   adv.player_room(),            10)

func _assert_rod_carried(adv, t) -> void:
    t._expect("rod carried",  adv.rod_in_inventory(),       true)
    t._expect("at debris",    adv.player_room(),            11)

func _assert_rod_and_gold_carried(adv, t) -> void:
    t._expect("rod carried",  adv.rod_in_inventory(),       true)
    t._expect("gold carried", adv.player.carrying(110),     true)
    t._expect("at Y2",        adv.player_room(),            33)

func _assert_bird_and_rod_carried(adv, t) -> void:
    t._expect("bird carried", adv.player.carrying(100), true)
    t._expect("rod carried",  adv.rod_in_inventory(),    true)
    t._expect("at bird room", adv.player_room(),         13)

func _assert_at_snake_passage(adv, t) -> void:
    t._expect("at snake room",    adv.player_room(),    19)
    t._expect("snake state",      adv.snake_state(),    "blocking")
    t._expect("bird carried",     adv.player.carrying(100), true)

func _assert_snake_cleared(adv, t) -> void:
    t._expect("snake state",  adv.snake_state(),  "gone")
    t._expect("at room 19",   adv.player_room(),  19)

func _assert_at_dragon(adv, t) -> void:
    t._expect("player_room",   adv.player_room(),  119)
    t._expect("dragon alive",  adv.dragon_alive(), true)

func _assert_dragon_dead(adv, t) -> void:
    t._expect("dragon state",  adv.dragon_state(), "dead")
    t._expect("dragon alive",  adv.dragon_alive(), false)

func _assert_rug_carried_at_119(adv, t) -> void:
    t._expect("rug carried",       adv.player.carrying(122), true)
    t._expect("at dragon canyon",  adv.player_room(),        119)
    t._expect("diamonds not yet",  adv.player.carrying(112), false)

func _assert_diamonds_rug_carried(adv, t) -> void:
    # Diamonds canonically taken at room 27 (west bank fissure),
    # rug taken earlier at 71.
    t._expect("diamonds carried", adv.player.carrying(112), true)
    t._expect("rug carried",      adv.player.carrying(122), true)
    t._expect("at west bank",     adv.player_room(),        27)

func _assert_three_treasures_deposited(adv, t) -> void:
    t._expect("at well house",        adv.player_room(),         3)
    t._expect("treasures deposited",  adv.treasures_deposited(), 3)
    t._expect("diamonds deposited",   adv.diamonds.is_deposited(), true)
    t._expect("rug deposited",        adv.rug.is_deposited(),      true)
    t._expect("gold deposited",       adv.gold.is_deposited(),     true)

func _assert_silver_carried(adv, t) -> void:
    t._expect("silver carried", adv.player.carrying(111), true)
    t._expect("at canon-28",    adv.player_room(),        28)

func _assert_treasures_deposited(want: int) -> Callable:
    return func(adv, t):
        t._expect("at well house",       adv.player_room(),         3)
        t._expect("treasures deposited", adv.treasures_deposited(), want)

func _assert_pearl_at_plover(adv, t) -> void:
    t._expect("at Plover Room",  adv.player_room(),         100)
    t._expect("pearl carried",   adv.player.carrying(114), true)

func _assert_pearl_emerald_carried(adv, t) -> void:
    # After the clam-break + plover round trip the player is at
    # Y2 (33) with both treasures in hand.
    t._expect("at Y2",            adv.player_room(),         33)
    t._expect("pearl carried",    adv.player.carrying(114),  true)
    t._expect("emerald carried",  adv.player.carrying(118),  true)

func _assert_room_and_bear(want_room: int, want_bear: String) -> Callable:
    return func(adv, t):
        t._expect("player_room", adv.player_room(),  want_room)
        t._expect("bear state",  adv.bear_state(),   want_bear)

func _assert_bear_following(adv, t) -> void:
    t._expect("bear state",     adv.bear_state(),         "following")
    t._expect("chain carried",  adv.player.carrying(101), true)
    t._expect("at bear chamber", adv.player_room(),       130)

func _assert_troll_vanished(adv, t) -> void:
    t._expect("troll state",   adv.troll_state(),         "vanished")
    t._expect("at troll bridge", adv.player_room(),       117)
    t._expect("chain dropped", adv.player.carrying(101),  false)

func _assert_jewelry_carried(adv, t) -> void:
    t._expect("jewelry carried",   adv.player.carrying(113), true)
    t._expect("at south chamber",  adv.player_room(),        29)

func _assert_batch_a_carried(adv, t) -> void:
    t._expect("vase carried",    adv.player.carrying(115), true)
    t._expect("eggs carried",    adv.player.carrying(116), true)
    t._expect("trident carried", adv.player.carrying(117), true)
    # Emerald moved to canon Plover Room — taken in the
    # take_pearl_emerald stage upstream, not here.

func _assert_batch_b_partial_carried(adv, t) -> void:
    # Spices moved to canon 127 (Chamber of Boulders) and pyramid
    # to canon 101 (Dark-room) — both taken in separate excursions
    # inside deposit_batch_b, so deep_cave_batch_b_takes carries
    # only the chest.
    t._expect("chest carried",   adv.player.carrying(120), true)

func _assert_batch_c_carried(adv, t) -> void:
    t._expect("coins carried",     adv.player.carrying(123), true)
    t._expect("chain carried",     adv.player.carrying(adv.CHAIN_ID), true)

func _assert_all_15_deposited(adv, t) -> void:
    # Endgame state at this point is "in_repository" — real
    # navigation ticks past the 30-tick closing window before
    # the 15th treasure lands. The closing phase itself is
    # exercised by the trigger at deposit_batch_a (treasures
    # deposited == 10).
    t._expect("all 15 deposited",   adv.treasures_deposited(), 15)
    t._expect("treasure score",     adv.treasure_score(),      210)
    t._expect("endgame past active", adv.endgame_state() != "active", true)

func _assert_closing_phase(adv, t) -> void:
    t._expect("endgame state", adv.endgame_state(), "closing")

func _assert_in_repository(adv, t) -> void:
    t._expect("endgame state", adv.endgame_state(), "in_repository")
    t._expect("player teleported to canon Repository", adv.player_room(), 116)

func _assert_won(adv, t) -> void:
    t._expect("endgame won",      adv.endgame_won(),    true)
    t._expect("endgame state",    adv.endgame_state(),  "won")
    t._expect("endgame component", adv.endgame_score(), 50)

func _assert_dragon_sleeping(adv, t) -> void:
    t._expect("dragon state", adv.dragon_state(), "sleeping")
    t._expect("dragon alive", adv.dragon_alive(), true)

func _assert_vase_broken(adv, t) -> void:
    t._expect("vase state",   adv.vase.get_state(), "broken")
    t._expect("vase value 0", adv.vase.get_value(), 0)
    t._expect("vase carried", adv.player.carrying(115), false)

func _assert_player_dead_bear_attacking(adv, t) -> void:
    t._expect("player state", adv.player_state(), "dead")
    t._expect("bear state",   adv.bear_state(),   "attacking")
    t._expect("deaths == 1",  adv.player.get_deaths(), 1)

func _assert_dead_count(want: int) -> Callable:
    return func(adv, t):
        t._expect("player state", adv.player_state(),       "dead")
        t._expect("deaths",       adv.player.get_deaths(),  want)

func _assert_permadead(adv, t) -> void:
    t._expect("player state", adv.player_state(),       "permadead")
    t._expect("deaths == 4",  adv.player.get_deaths(),  4)

func _assert_eggs_back_at_giant(adv, t) -> void:
    t._expect("eggs state",    adv.eggs.get_state(),     "in_room")
    t._expect("eggs at giant", adv.eggs.get_location(),  92)
    t._expect("eggs not deposited", adv.eggs.is_deposited(), false)

func _assert_plant_tall(adv, t) -> void:
    t._expect("plant tall",   adv.plant_is_tall(),       true)
    t._expect("plant huge",   adv.plant_is_huge(),       false)
    t._expect("bottle empty", adv.bottle_has_water(),    false)
    t._expect("at west pit",  adv.player_room(),         25)

func _assert_plant_huge_at_west_pit(adv, t) -> void:
    t._expect("plant huge",   adv.plant_is_huge(),       true)
    t._expect("bottle empty", adv.bottle_has_water(),    false)
    t._expect("at west pit",  adv.player_room(),         25)

func _assert_eggs_carried_at_giant(adv, t) -> void:
    t._expect("eggs carried",  adv.player.carrying(adv.EGGS_ID), true)
    t._expect("at giant chamber", adv.player_room(),     92)

func _assert_pillow_at_well_house(adv, t) -> void:
    t._expect("at well house",     adv.player_room(),                3)
    t._expect("pillow not carried", adv.player.carrying(adv.PILLOW_ID), false)
    t._expect("pillow at room 3",   adv.pillow_item.get_location(),   3)

func _assert_dwarves_living(adv, t) -> void:
    t._expect("living dwarves", adv.living_dwarves(), 5)

# ------------------------------------------------------------
func _init():
    print("=== CCA canonical playthrough (stage DAG) ===")
    print()

    var stages: Array = _stages()
    for stage in stages:
        _run_stage(stage)

    print()
    if failures == 0:
        print("PASS — %d stages green, full canonical playthrough init → won via real commands only" % stages.size())
    else:
        print("FAIL — %d assertion(s) failed across %d stages" % [failures, stages.size()])
    quit(failures)
