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
        else:
            adv.do_command(verb, arg)

        # Tick after every command — same as driver. Lamp
        # battery, endgame timer, hint streaks, pirate
        # threshold all depend on this firing.
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
            "name":       "rod_and_gold",
            "from":       "debris_room",
            "actions":    [["take", "rod"], ["take", "gold"]],
            "asserts":    _assert_rod_and_gold_carried,
            "checkpoint": "carrying_rod_gold",
        },
        # ----- Bird chamber -----
        # Y2 (33) is reachable via a sequence of canyons from
        # debris (11). The canon path: debris → awkward canyon
        # (12) east → Y2 (33) down → bird chamber (13).
        {
            "name":       "at_y2",
            "from":       "carrying_rod_gold",
            "actions":    [["go", "east"], ["go", "down"]],
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
    ]

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

func _assert_rod_and_gold_carried(adv, t) -> void:
    t._expect("rod carried",  adv.rod_in_inventory(),       true)
    t._expect("gold carried", adv.player.carrying(110),     true)
    t._expect("at debris",    adv.player_room(),            11)

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

# ------------------------------------------------------------
func _init():
    print("=== CCA canonical playthrough (stage DAG) ===")
    print()

    var stages: Array = _stages()
    for stage in stages:
        _run_stage(stage)

    print()
    if failures == 0:
        print("PASS — %d stages green, dragon killed via real commands only" % stages.size())
    else:
        print("FAIL — %d assertion(s) failed across %d stages" % [failures, stages.size()])
    quit(failures)
