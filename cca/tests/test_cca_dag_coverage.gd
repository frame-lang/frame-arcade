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
const RustyJourney = preload("res://scripts/rusty_journey.gd")
const Room110Journey = preload("res://scripts/room110_journey.gd")
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
    var giant_bytes: PackedByteArray = pd.fsm.save_state()   # Giant Room, for the rusty branch

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

    # Rusty-door rail (off the plant rail's Giant Room) → oil the door,
    # reach canon 95 and 91.
    var rd = _make_driver()
    rd.fsm.restore_state(giant_bytes)
    rd.prompts = Cca.PromptDispatcher.new()
    var rj = RustyJourney._create()
    while not rj.is_done():
        for cmd in rj.commands_from_previous():
            rd._process_input(String(cmd).to_lower())
            _snap(rd, captured, waypoints)
        rj.advance()
    print("After rusty rail: %d waypoints (room %d)" % [waypoints.size(), rd.fsm.player_room()])

    # Room-110 rail (off completed BridgeBuilt) → crawls through
    # Bedquilt (65) to 110. Uses force:/clear: tokens to pin the
    # probability gate; _feed honours them so the snapshot still
    # captures each room the rail lands in.
    var qd = _make_driver()
    qd.fsm.restore_state(bridge_bytes)
    qd.prompts = Cca.PromptDispatcher.new()
    var qj = Room110Journey._create()
    while not qj.is_done():
        for cmd in qj.commands_from_previous():
            _feed(qd, String(cmd), captured, waypoints)
        qj.advance()
    print("After room110 rail: %d waypoints (room %d)" % [waypoints.size(), qd.fsm.player_room()])

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

    # The 6 transient-prose rooms are unreachable by walking (no port
    # exit routes there — they're FSM-direct teleports asserted by
    # test_cca_transient_prose). Every OTHER canon room must be
    # covered by the journey-DAG. So the only acceptable misses are
    # exactly that set; anything else is a coverage regression.
    var PROSE := {21: true, 22: true, 31: true, 32: true, 89: true, 90: true}
    var regressions: Array = []
    for r in missing:
        if not PROSE.has(r):
            regressions.append(r)

    if regressions.is_empty() and union.size() >= 134:
        print("PASS — 134 graph rooms + 6 transient-prose = 140/140 canon")
        quit(0)
        return
    print("FAIL — DAG coverage regressed: %d graph rooms, unexpected misses %s" % [
        union.size(), str(regressions)])
    quit(1)

# Feed one rail command to the driver, honouring the inline
# steering tokens "force:NAME=VALUE" and "clear:NAME" (the
# Chance seam — same convention as death_journeys.fgd), then
# snapshot the room. Plain commands are dispatched as input.
func _feed(drv, raw: String, captured: Dictionary, waypoints: Array) -> void:
    if raw.begins_with("force:"):
        var parts := raw.substr(6).split("=")
        drv.fsm.chance.force(parts[0], int(parts[1]))
        return
    if raw.begins_with("clear:"):
        drv.fsm.chance.clear_forced(raw.substr(6))
        return
    drv._process_input(raw.to_lower())
    _snap(drv, captured, waypoints)

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
