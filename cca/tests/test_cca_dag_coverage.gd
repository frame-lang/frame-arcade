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

# Small per-state bloom: from EVERY distinct room the rail passes
# through, run a tiny random BFS (this cap) to sample that room's
# local neighborhood. The rail is a dense line of micro-waypoints;
# the union of all the little neighborhoods covers everything the
# rail comes near — no hub-guessing.
const BLOOM_CAP: int = 80

func _init():
    print("=== CCA journey-DAG room coverage (waypoint-seeded BFS) ===")

    # Collect a snapshot at EVERY distinct room the rails pass through.
    var waypoints: Array = []          # [{bytes, room}]
    var captured: Dictionary = {}

    # Win rail (walked via its FSM, command by command).
    var d = _make_driver()
    var j = WinJourney._create()
    while not j.is_done():
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
            var r: int = d.fsm.player_room()
            if not captured.has(r):
                captured[r] = true
                waypoints.append({"bytes": d.fsm.save_state(), "room": r})
        j.advance()
    print("Win rail: %d distinct-room waypoints" % waypoints.size())

    # NOTE: this engine currently blooms only along the win rail.
    # Reaching the full 140 needs gate-pinned rails into the areas
    # the win rail never enters — plant/upper-complex, troll
    # far-side, and the two mazes — each contributing its own
    # distinct-room waypoints. Tracked as follow-up.

    # Small random BFS from each waypoint; union the rooms.
    var union: Dictionary = {}
    for wp in waypoints:
        for seed in SEEDS:
            var s = StateSpace.new()
            s.seed = seed
            s.max_states = BLOOM_CAP
            s.seed_bytes = wp["bytes"]
            s.reseed_chance_after_restore = true
            s.progress_every = 0
            s.check_save_restore = false
            s.run()
            for r in s.covered_rooms().keys():
                union[r] = true

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
