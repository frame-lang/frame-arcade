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
            "actions":    [["go", "out"], ["go", "east"]],
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
        {
            "name":       "cobbles",
            "from":       "below_grate",
            "actions":    [["go", "west"]],
            "asserts":    _assert_room(10),
        },
        {
            "name":       "debris_room",
            "from":       "below_grate",
            "actions":    [["go", "west"], ["go", "west"]],
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
        # note, you won't get it up the steps"), reached from
        # Hall of Mists (15) → south. Path from debris (11):
        # 11 east → 12 → north → 33 → north → 14 → down → 15
        # → south → 18. Take gold, then walk back to 33 via
        # 18 → north (15) → up (14) → south (33) — leaving the
        # player at Y2 ready for the bird-chamber descent.
        {
            "name":       "gold_taken_back_at_y2",
            "from":       "carrying_rod",
            "actions":    [
                ["go", "east"],            # 11 → 12
                ["go", "north"],           # 12 → 33
                ["go", "north"],           # 33 → 14
                ["go", "down"],            # 14 → 15
                ["go", "south"],           # 15 → 18 (gold-nugget room)
                ["take", "gold"],
                ["go", "north"],           # 18 → 15
                ["go", "up"],              # 15 → 14
                ["go", "south"],           # 14 → 33 (Y2)
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
            "actions":    [["go", "down"]],
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
        # ----- Snake passage -----
        # Y2 (33) east → snake passage (47).
        {
            "name":       "at_snake_passage",
            "from":       "carrying_bird_rod",
            "actions":    [["go", "up"], ["go", "east"]],
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
        # ----- Dragon -----
        {
            "name":       "at_dragon",
            "from":       "snake_cleared",
            "actions":    [["go", "east"]],
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
        # ----- Treasure haul: diamonds + rug -----
        # Dragon dead → diamonds and rug both visible at 71.
        # Walk back via 47 (snake gone) → 33 → plugh (magic
        # word that pairs 1 ↔ 33) → in to well house → drop.
        {
            "name":       "diamonds_rug_taken",
            "from":       "dragon_dead",
            "actions":    [["take", "diamonds"], ["take", "rug"]],
            "asserts":    _assert_diamonds_rug_taken,
            "checkpoint": "carrying_first_haul",
        },
        {
            "name":       "deposit_first_haul",
            "from":       "carrying_first_haul",
            "actions":    [
                ["go", "west"],            # 71 → 47
                ["go", "west"],            # 47 → 33
                ["plugh", ""],              # 1 → 3 well house
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
        # PLOVER pairs 33 ↔ 100. The Plover Room is otherwise
        # unreachable (its map exits don't lead back through
        # 33). Canon: BOTH pearl and emerald live in the Plover
        # Room (advent.dat section 7 places emerald at 100 and
        # pearl is dynamic — picked up from the oyster — but
        # the port still treats pearl as a static placement at
        # the Plover Room until the clam/oyster mechanic lands).
        {
            "name":       "take_pearl_emerald",
            "from":       "after_silver",
            "actions":    [
                ["plugh", ""],             # 3 → 33
                ["plover", ""],            # 33 → 100
                ["take", "pearl"],
                ["take", "emerald"],
            ],
            "asserts":    _assert_pearl_emerald_at_plover,
            "checkpoint": "carrying_pearl_emerald",
        },
        {
            "name":       "deposit_pearl_emerald",
            "from":       "carrying_pearl_emerald",
            "actions":    [
                ["plover", ""],            # 100 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "pearl"],
                ["drop", "emerald"],
            ],
            "asserts":    _assert_treasures_deposited(6),
            "checkpoint": "after_pearl",
        },
        # ----- Bear → troll bridge → jewelry -----
        # Y2 (33) west → Bedquilt (65). Bear lives there with
        # chain attached. Feed to tame, take chain to lure,
        # walk to troll bridge, drop chain. Bear stays at 117
        # and scares the troll.
        {
            "name":       "at_bear_chamber",
            "from":       "after_pearl",
            "actions":    [
                ["plugh", ""],             # 1 → 33
                ["go", "west"],            # 33 → 65
            ],
            "asserts":    _assert_room_and_bear(65, "hungry"),
            "checkpoint": "at_bear_chamber",
        },
        {
            "name":       "bear_tame_chained",
            "from":       "at_bear_chamber",
            "actions":    [["feed", "bear"], ["take", "chain"]],
            "asserts":    _assert_bear_following,
            "checkpoint": "bear_following",
        },
        {
            "name":       "troll_vanished",
            "from":       "bear_following",
            "actions":    [
                ["go", "east"],            # 65 → 117 troll bridge
                ["drop", "chain"],
            ],
            "asserts":    _assert_troll_vanished,
            "checkpoint": "troll_vanished",
        },
        {
            "name":       "take_jewelry",
            "from":       "troll_vanished",
            "actions":    [
                ["go", "east"],            # 117 → 118
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
                ["go", "west"],            # 118 → 117
                ["go", "west"],            # 117 → 65
                ["go", "west"],            # 65 → 33
                ["plugh", ""],              # 33 → 3
                ["drop", "jewelry"],
            ],
            "asserts":    _assert_treasures_deposited(7),
            "checkpoint": "after_jewelry",
        },
        # Walk back to the deep cave: 3 → 1 (plugh) → 33 → 65
        # → 117 (bear+troll already cleared, bridge passable)
        # → 118 → 120 → 97 (Oriental, vase). Long traversal;
        # keep as one stage since each transition is just "go".
        {
            "name":       "deep_cave_batch_a_takes",
            "from":       "after_jewelry",
            "actions":    [
                ["plugh", ""],             # 3 → 33
                ["go", "west"],            # 33 → 65
                ["go", "east"],            # 65 → 117
                ["go", "east"],            # 117 → 118
                ["go", "east"],            # 118 → 120
                ["go", "east"],            # 120 → 97
                ["take", "vase"],
                ["go", "east"],            # 97 → 92
                ["take", "eggs"],
                ["go", "east"],            # 92 → 95
                ["take", "trident"],
            ],
            "asserts":    _assert_batch_a_carried,
            "checkpoint": "carrying_batch_a",
        },
        {
            "name":       "deposit_batch_a",
            "from":       "carrying_batch_a",
            "actions":    [
                ["go", "west"],            # 95 → 92
                ["go", "west"],            # 92 → 97
                ["go", "west"],            # 97 → 120
                ["go", "west"],            # 120 → 118
                ["go", "west"],            # 118 → 117
                ["go", "west"],            # 117 → 65
                ["go", "west"],            # 65 → 33
                ["plugh", ""],             # 33 → 3
                ["drop", "vase"],
                ["drop", "eggs"],
                ["drop", "trident"],
            ],
            "asserts":    _assert_treasures_deposited(10),
            "checkpoint": "after_batch_a",
        },
        # ----- Batch B: spices, chest, pyramid -----
        # Path 3 → 1 → 33 → 65 → 117 → 118 → 120 → 97 → 92 →
        # 95 → 131 → 40 (Alcove). 1 west + 8 east = 9 nav.
        {
            "name":       "deep_cave_batch_b_takes",
            "from":       "after_batch_a",
            "actions":    [
                ["plugh", ""],
                ["go", "west"],
                ["go", "east"], ["go", "east"], ["go", "east"],
                ["go", "east"], ["go", "east"], ["go", "east"],
                ["go", "east"], ["go", "east"],   # 8 easts → at 40
                ["take", "spices"],
                ["go", "east"],            # 40 → 132
                ["take", "chest"],
                ["go", "east"],            # 132 → 133
                ["take", "pyramid"],
            ],
            "asserts":    _assert_batch_b_carried,
            "checkpoint": "carrying_batch_b",
        },
        # End of batch_b takes: at 133. Reverse: 11 wests +
        # plugh + in.
        {
            "name":       "deposit_batch_b",
            "from":       "carrying_batch_b",
            "actions":    [
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"],
                ["plugh", ""],
                ["drop", "spices"],
                ["drop", "chest"],
                ["drop", "pyramid"],
            ],
            "asserts":    _assert_treasures_deposited(13),
            "checkpoint": "after_batch_b",
        },
        # ----- Batch C: coins, statuette -----
        # Path 3 → 1 → 33 → 65 → 117 → 118 → 120 → 97 → 92 →
        # 95 → 131 → 40 → 132 → 133 → 134 (Coin Niche).
        # 1 west + 11 east = 12 nav.
        {
            "name":       "deep_cave_batch_c_takes",
            "from":       "after_batch_b",
            "actions":    [
                ["plugh", ""],
                ["go", "west"],
                ["go", "east"], ["go", "east"], ["go", "east"],
                ["go", "east"], ["go", "east"], ["go", "east"],
                ["go", "east"], ["go", "east"], ["go", "east"],
                ["go", "east"], ["go", "east"],   # 11 easts → at 134
                ["take", "coins"],
                ["go", "east"],            # 134 → 135
                ["take", "statuette"],
            ],
            "asserts":    _assert_batch_c_carried,
            "checkpoint": "carrying_batch_c",
        },
        # End of batch_c takes: at 135. Reverse: 13 wests +
        # plugh + in.
        {
            "name":       "deposit_batch_c",
            "from":       "carrying_batch_c",
            "actions":    [
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"], ["go", "west"], ["go", "west"],
                ["go", "west"],
                ["plugh", ""],
                ["drop", "coins"],
                ["drop", "statuette"],
            ],
            "asserts":    _assert_all_15_deposited,
            "checkpoint": "all_deposited",
        },
        # ----- Endgame -----
        # The canonical playthrough deposits the 10th treasure
        # in deposit_batch_a, which transitions Endgame $Active
        # → $Closing (CLOSING_DURATION = 30 ticks). Real-command
        # navigation between batches uses many more than 30
        # ticks, so by the time the 15th treasure is deposited
        # we've already drained $Closing → $InRepository. This
        # is correct: test_cca_full uses player.move_to setter
        # teleports that don't tick, so it explicitly drives 30
        # ticks afterward; our stage DAG arrives at in_repository
        # naturally. detonate_marker then crowns the run with
        # the 50-point bonus.
        {
            "name":       "in_repository",
            "from":       "all_deposited",
            "actions":    [],
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
                ["go", "out"],              # 3 → 1
                ["go", "east"],             # 1 → 8
                ["go", "down"],             # 8 → 9 (grate already unlocked)
                ["go", "west"],             # 9 → 10
                ["go", "west"],             # 10 → 11
                ["go", "east"],             # 11 → 12
                ["go", "north"],            # 12 → 33
                ["go", "north"],            # 33 → 14
                ["go", "down"],             # 14 → 15
                ["go", "north"],            # 15 → 21
                ["go", "west"],             # 21 → 23 West Pit
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
    t._expect("at snake passage", adv.player_room(),    47)
    t._expect("snake state",      adv.snake_state(),    "blocking")
    t._expect("bird carried",     adv.player.carrying(100), true)

func _assert_snake_cleared(adv, t) -> void:
    t._expect("snake state",  adv.snake_state(),  "gone")
    t._expect("at room 47",   adv.player_room(),  47)

func _assert_at_dragon(adv, t) -> void:
    t._expect("player_room",   adv.player_room(),  71)
    t._expect("dragon alive",  adv.dragon_alive(), true)

func _assert_dragon_dead(adv, t) -> void:
    t._expect("dragon state",  adv.dragon_state(), "dead")
    t._expect("dragon alive",  adv.dragon_alive(), false)

func _assert_diamonds_rug_taken(adv, t) -> void:
    t._expect("diamonds carried", adv.player.carrying(112), true)
    t._expect("rug carried",      adv.player.carrying(122), true)
    t._expect("at scorched",      adv.player_room(),        71)

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

func _assert_pearl_emerald_at_plover(adv, t) -> void:
    t._expect("at Plover Room",   adv.player_room(),         100)
    t._expect("pearl carried",    adv.player.carrying(114),  true)
    t._expect("emerald carried",  adv.player.carrying(118),  true)

func _assert_room_and_bear(want_room: int, want_bear: String) -> Callable:
    return func(adv, t):
        t._expect("player_room", adv.player_room(),  want_room)
        t._expect("bear state",  adv.bear_state(),   want_bear)

func _assert_bear_following(adv, t) -> void:
    t._expect("bear state",     adv.bear_state(),         "following")
    t._expect("chain carried",  adv.player.carrying(101), true)
    t._expect("at bear chamber", adv.player_room(),       65)

func _assert_troll_vanished(adv, t) -> void:
    t._expect("troll state",   adv.troll_state(),         "vanished")
    t._expect("at troll bridge", adv.player_room(),       117)
    t._expect("chain dropped", adv.player.carrying(101),  false)

func _assert_jewelry_carried(adv, t) -> void:
    t._expect("jewelry carried", adv.player.carrying(113), true)
    t._expect("at cliff",        adv.player_room(),        118)

func _assert_batch_a_carried(adv, t) -> void:
    t._expect("vase carried",    adv.player.carrying(115), true)
    t._expect("eggs carried",    adv.player.carrying(116), true)
    t._expect("trident carried", adv.player.carrying(117), true)
    # Emerald moved to canon Plover Room — taken in the
    # take_pearl_emerald stage upstream, not here.

func _assert_batch_b_carried(adv, t) -> void:
    t._expect("spices carried",  adv.player.carrying(119), true)
    t._expect("chest carried",   adv.player.carrying(120), true)
    t._expect("pyramid carried", adv.player.carrying(121), true)

func _assert_batch_c_carried(adv, t) -> void:
    t._expect("coins carried",     adv.player.carrying(123), true)
    t._expect("statuette carried", adv.player.carrying(124), true)

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
    t._expect("at west pit",  adv.player_room(),         23)

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
