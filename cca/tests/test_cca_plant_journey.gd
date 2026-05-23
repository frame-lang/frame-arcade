extends SceneTree

# ============================================================
# test_cca_plant_journey.gd
# ============================================================
# Verifies the plant/beanstalk branch rail: walk the win rail to
# the COMPLETED BridgeBuilt waypoint (post-"wave rod", bridge
# up), then run the PlantJourney rail — water the west-pit plant
# twice, climb the beanstalk, reach the Giant Room and take the
# eggs. Typed commands only, deterministic (seed 42 + chance 42).
#
# (The DAG-coverage harness diverged earlier because it branched
# off the FIRST-entry room-17 snapshot, taken before the bridge
# was waved. This test branches off the completed milestone.)
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const PlantJourney = preload("res://scripts/plant_journey.gd")

func _init():
    print("=== CCA plant branch rail (BridgeBuilt → Giant Room) ===")
    var d = _make_driver()

    # Walk the win rail to the END of the BridgeBuilt milestone.
    var j = WinJourney._create()
    while not j.is_done():
        var name: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if name == "BridgeBuilt":
            break
        j.advance()
    print("  at BridgeBuilt: room=%d bridge_built=%s" % [d.fsm.player_room(), d.fsm.bridge_built()])

    # Run the plant rail.
    var p = PlantJourney._create()
    while not p.is_done():
        for cmd in p.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        p.advance()

    var room: int = d.fsm.player_room()
    var eggs: bool = d.fsm.player.carrying(116)
    print("  after plant rail: room=%d eggs=%s" % [room, eggs])

    if room == 92 and eggs:
        print("PASS — plant rail reaches the Giant Room (92) and takes the eggs")
        quit(0)
        return
    print("FAIL — room=%d (expected 92), eggs=%s" % [room, eggs])
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
