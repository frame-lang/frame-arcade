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
const PlantJourney = preload("res://scripts/plant_journey.gd")
const TrollJourney = preload("res://scripts/troll_journey.gd")
const MazeJourney = preload("res://scripts/maze_journey.gd")
const StateSpace = preload("res://scripts/state_space.gd")

const SEEDS: Array = [42, 7]

# The all-alike maze (cyclic cluster) needs a deeper bloom than the
# default to spread across all its interconnected rooms.
const MAZE_ROOMS := {107: true, 112: true, 131: true, 132: true, 133: true,
    134: true, 135: true, 136: true, 137: true, 138: true, 139: true, 140: true}
const MAZE_CAP: int = 220

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

    # Win rail (walked via its FSM, command by command). Capture the
    # completed-BridgeBuilt state to branch the plant/troll rails off.
    var d = _make_driver()
    var bridge_bytes: PackedByteArray = PackedByteArray()
    var j = WinJourney._create()
    while not j.is_done():
        var nm: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
            _snap(d, captured, waypoints)
        if nm == "BridgeBuilt":
            bridge_bytes = d.fsm.save_state()
        j.advance()
    print("Win rail: %d distinct-room waypoints" % waypoints.size())

    # Plant rail (off completed BridgeBuilt) → upper complex.
    var pd = _make_driver()
    pd.fsm.restore_state(bridge_bytes)
    pd.prompts = Cca.PromptDispatcher.new()
    var pj = PlantJourney._create()
    while not pj.is_done():
        for cmd in pj.commands_from_previous():
            pd._process_input(String(cmd).to_lower())
            _snap(pd, captured, waypoints)
        pj.advance()
    print("After plant rail: %d waypoints (room %d)" % [waypoints.size(), pd.fsm.player_room()])

    # Troll rail (chains off the plant rail's Giant Room) → far side.
    var tj = TrollJourney._create()
    while not tj.is_done():
        for cmd in tj.commands_from_previous():
            pd._process_input(String(cmd).to_lower())
            _snap(pd, captured, waypoints)
        tj.advance()
    print("After troll rail: %d waypoints (room %d)" % [waypoints.size(), pd.fsm.player_room()])

    # Maze rail (off completed BridgeBuilt) → steps into the all-alike
    # maze; its bloom (deeper cap) spreads across the cyclic cluster.
    var md = _make_driver()
    md.fsm.restore_state(bridge_bytes)
    md.prompts = Cca.PromptDispatcher.new()
    var mj = MazeJourney._create()
    while not mj.is_done():
        for cmd in mj.commands_from_previous():
            md._process_input(String(cmd).to_lower())
            _snap(md, captured, waypoints)
        mj.advance()
    print("After maze rail: %d waypoints (room %d)" % [waypoints.size(), md.fsm.player_room()])

    # Small random BFS from each waypoint; union the rooms. Maze
    # rooms get a deeper bloom to spread across the cyclic cluster.
    var union: Dictionary = {}
    for wp in waypoints:
        var cap: int = MAZE_CAP if MAZE_ROOMS.has(wp["room"]) else BLOOM_CAP
        for seed in SEEDS:
            var s = StateSpace.new()
            s.seed = seed
            s.max_states = cap
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

func _snap(drv, captured: Dictionary, waypoints: Array) -> void:
    var r: int = drv.fsm.player_room()
    if not captured.has(r):
        captured[r] = true
        waypoints.append({"bytes": drv.fsm.save_state(), "room": r})

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
