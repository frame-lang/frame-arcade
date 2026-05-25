extends SceneTree

# ============================================================
# test_cca_restore_soundness_milestones.gd
# ============================================================
# Re-arms the incomplete-state-vector guard at the DEEP journey-DAG
# chokepoints. The FrameStateChecker demo runs restore_soundness
# over three shallow milestones (LampLit / SnakeGone /
# BearReleased); this extends the bisimulation check to the
# late-game waypoints the success rails generate — where far more
# state is live (bear following, troll paid, plant grown, bottle
# filled, rusty door oiled).
#
# For each milestone: restore a FRESH adapter instance to it and a
# DIRTIED, reused instance (player killed + revive prompt opened)
# to it, and compare observable signatures. A divergence means
# some transition-relevant state at that chokepoint lives outside
# fsm.save_state and didn't survive the restore — exactly the
# leak class that once produced the "53/140" lie. Zero divergences
# == restore is observationally sound at every deep chokepoint.
#
# EF won is deliberately NOT run from these milestones: they are
# mid-game (victory is 100+ commands away), so a bounded BFS can't
# reach `won` from here — "not found" would be a search-depth
# artifact, not a softlock. EF won is meaningful only near
# victory (covered from InRepository in test_cca_frame_checker_demo).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const PlantJourney = preload("res://scripts/plant_journey.gd")
const TrollJourney = preload("res://scripts/troll_journey.gd")
const Room110Journey = preload("res://scripts/room110_journey.gd")
const FrameStateChecker = preload("res://scripts/frame_state_checker.gd")
const CcaModelAdapter = preload("res://scripts/cca_model_adapter.gd")

func _init():
    print("=== CCA restore soundness at deep journey-DAG chokepoints ===")

    var samples: Array = []

    # BridgeBuilt (win rail) — crystal bridge up.
    var d = _make_driver()
    var bridge: PackedByteArray = PackedByteArray()
    var j = WinJourney._create()
    while not j.is_done():
        var nm: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if nm == "BridgeBuilt":
            bridge = d.fsm.save_state()
        j.advance()
    samples.append({"name": "BridgeBuilt", "bytes": bridge})

    # GiantRoom (plant rail off BridgeBuilt) — beanstalk grown, eggs taken.
    var pd = _make_driver()
    pd.fsm.restore_state(bridge)
    pd.prompts = Cca.PromptDispatcher.new()
    var pj = PlantJourney._create()
    while not pj.is_done():
        for cmd in pj.commands_from_previous():
            pd._process_input(String(cmd).to_lower())
        pj.advance()
    samples.append({"name": "GiantRoom", "bytes": pd.fsm.save_state()})

    # TrollFarSide (troll rail off GiantRoom) — troll paid, across the bridge.
    var tj = TrollJourney._create()
    while not tj.is_done():
        for cmd in tj.commands_from_previous():
            pd._process_input(String(cmd).to_lower())
        tj.advance()
    samples.append({"name": "TrollFarSide", "bytes": pd.fsm.save_state()})

    # Room110 (room110 rail off BridgeBuilt) — pinned through the 65:north gate.
    var qd = _make_driver()
    qd.fsm.restore_state(bridge)
    qd.prompts = Cca.PromptDispatcher.new()
    var qj = Room110Journey._create()
    while not qj.is_done():
        for cmd in qj.commands_from_previous():
            _feed(qd, String(cmd))
        qj.advance()
    samples.append({"name": "Room110", "bytes": qd.fsm.save_state()})

    print("  captured %d deep milestones: %s" % [
        samples.size(), str(samples.map(func(s): return s["name"]))])

    # Bisimulation check via the generic engine.
    var adapter = CcaModelAdapter.new(42)
    var checker = FrameStateChecker.new(adapter)
    var dirty := func(adp, o):
        o.fsm.player.die()
        o.prompts.offer_revive()
    var divergences: Array = checker.restore_soundness(samples, dirty)

    if divergences.is_empty():
        print("PASS — restore observationally sound at all %d deep chokepoints" % samples.size())
        quit(0)
        return
    for dv in divergences:
        print("  FAIL %s — fresh: %s | reused: %s" % [dv["name"], dv["fresh"], dv["reused"]])
    quit(divergences.size())

func _feed(drv, raw: String) -> void:
    if raw.begins_with("force:"):
        var parts := raw.substr(6).split("=")
        drv.fsm.chance.force(parts[0], int(parts[1]))
        return
    if raw.begins_with("clear:"):
        drv.fsm.chance.clear_forced(raw.substr(6))
        return
    drv._process_input(raw.to_lower())

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
