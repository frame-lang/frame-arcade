extends SceneTree

# ============================================================
# test_cca_dag_coverage.gd
# ============================================================
# Room coverage via the journey-DAG, the fast bounded-seeded-BFS
# way: walk the win rail, snapshot at every milestone (each a
# chokepoint waypoint), and bloom a seeded BFS from each —
# reseeding Chance per seed to sample the area's branches. Union
# the rooms across every waypoint × seed.
#
# This is the bounded replacement for the one slow global BFS the
# journey-tree audits used. Reports how many of the 140 canon
# rooms the win-rail waypoints reach (the remaining transient-
# prose rooms are covered by test_cca_transient_prose).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const StateSpace = preload("res://scripts/state_space.gd")

const SEEDS: Array = [42, 7]

# Deep, distinct-area "hub" rooms to snapshot as waypoints when the
# rail first reaches them (the milestone snapshots all land at the
# room-3 deposit point, which are useless waypoints).
const HUBS: Array = [9, 19, 17, 97, 100, 103, 18, 116]

func _init():
    print("=== CCA journey-DAG room coverage (waypoint-seeded BFS) ===")

    # Walk the win rail command-by-command; snapshot the first time
    # the player reaches each deep hub room (distinct-area waypoints).
    var waypoints: Array = []          # [{name, bytes, room}]
    var captured: Dictionary = {}
    var d = _make_driver()
    var j = WinJourney._create()
    while not j.is_done():
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
            var r: int = d.fsm.player_room()
            if r in HUBS and not captured.has(r):
                captured[r] = true
                waypoints.append({"name": "hub-%d" % r, "bytes": d.fsm.save_state(), "room": r})
        j.advance()
    print("Collected %d hub waypoints from the win rail" % waypoints.size())

    # Bloom a seeded BFS from each waypoint; union the rooms.
    var union: Dictionary = {}
    for wp in waypoints:
        var before: int = union.size()
        for seed in SEEDS:
            var s = StateSpace.new()
            s.seed = seed
            s.max_states = 500
            s.seed_bytes = wp["bytes"]
            s.reseed_chance_after_restore = true
            s.progress_every = 0
            s.check_save_restore = false
            s.run()
            for r in s.covered_rooms().keys():
                union[r] = true
        print("  %-16s @ %-3d → union now %d rooms (+%d)" % [
            wp["name"], wp["room"], union.size(), union.size() - before])

    print("")
    print("DAG room coverage: %d distinct rooms from %d waypoints × %d seeds" % [
        union.size(), waypoints.size(), SEEDS.size()])
    print("(+ 6 transient-prose rooms via test_cca_transient_prose → 140 canon)")

    # Report which canon rooms are still unreached (1..140).
    var missing: Array = []
    for r in range(1, 141):
        if not union.has(r):
            missing.append(r)
    print("Unreached canon rooms (%d): %s" % [missing.size(), str(missing)])

    # Informational coverage report for now (floor TBD once the
    # troll far-side / plant waypoints are wired). Always passes;
    # the number is the signal.
    print("PASS — coverage report (informational)")
    quit(0)

func _make_driver():
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = 42
    d.fsm.chance.reseed(42)
    d._build_verb_synonyms_5()
    return d
