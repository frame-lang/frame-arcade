extends SceneTree

# ============================================================
# test_cca_area_explorer.gd
# ============================================================
# The waypoint-seeded exploration pattern: a deterministic RAIL
# drives to a chokepoint waypoint, we snapshot, then a SEEDED,
# BOUNDED BFS blooms to explore that area — reseeding the model's
# Chance system per seed so the area's probabilistic branches get
# sampled. Union the coverage across seeds.
#
# Rail = reach (deterministic, fast, gates pre-opened).
# Seeded BFS = cover (the area's combinatorial states).
#
# Here the waypoint is the win rail's $BridgeBuilt milestone
# (canon 17, east bank of the fissure, crystal bridge up). The
# bloom explores the Hall-of-Mists / Mountain-King side.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const StateSpace = preload("res://scripts/state_space.gd")

const SEEDS: Array = [42, 7, 99, 1234]

func _init():
    print("=== CCA area-explorer (rail → waypoint → seeded BFS) ===")

    # --- Rail to the $BridgeBuilt waypoint, snapshot. ---
    var d = _make_driver()
    var j = WinJourney._create()
    var snapshot: PackedByteArray = PackedByteArray()
    while not j.is_done():
        var name: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if name == "BridgeBuilt":
            snapshot = d.fsm.save_state()
            break
        j.advance()

    if snapshot.is_empty():
        print("FAIL — never reached the BridgeBuilt waypoint"); quit(1); return
    print("Waypoint: BridgeBuilt @ room %d (snapshot %d bytes)" % [d.fsm.player_room(), snapshot.size()])

    # --- Seeded BFS bloom per seed; union the covered rooms. ---
    var union: Dictionary = {}
    var best_single: int = 0
    for seed in SEEDS:
        var s = StateSpace.new()
        s.seed = seed
        s.max_states = 600
        s.seed_bytes = snapshot
        s.reseed_chance_after_restore = true   # sample the area's random branches
        s.progress_every = 0
        s.check_save_restore = false
        s.run()
        var cov: Dictionary = s.covered_rooms()
        best_single = max(best_single, cov.size())
        for r in cov.keys():
            union[r] = true
        print("  seed %-5d → %d rooms (%d states)" % [seed, cov.size(), s.states_visited])

    print("Union over %d seeds: %d distinct rooms" % [SEEDS.size(), union.size()])

    # The point: a sweep of seeds covers at least as much as the
    # best single seed, and the bloom from one waypoint reaches a
    # substantial local area.
    var ok: bool = union.size() >= best_single and union.size() >= 12
    if ok:
        print("PASS — waypoint-seeded BFS covers %d rooms (best single %d)" % [union.size(), best_single])
        quit(0)
        return
    print("FAIL — union %d rooms (best single %d, floor 12)" % [union.size(), best_single])
    quit(1)

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
