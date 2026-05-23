extends SceneTree

# ============================================================
# test_cca_maze_journey.gd
# ============================================================
# Verifies the all-alike maze branch rail: win → BridgeBuilt →
# MazeJourney steps into the maze (lands in canon 131). Typed
# commands only, deterministic (seed 42 + chance 42). From this
# one maze room a coverage bloom spreads across the whole cyclic
# cluster (112, 131-140) — see test_cca_dag_coverage.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const MazeJourney = preload("res://scripts/maze_journey.gd")

func _init():
    print("=== CCA all-alike maze rail (BridgeBuilt → maze) ===")
    var d = _make_driver()

    var j = WinJourney._create()
    while not j.is_done():
        var name: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if name == "BridgeBuilt":
            break
        j.advance()

    var m = MazeJourney._create()
    while not m.is_done():
        for cmd in m.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        m.advance()

    var room: int = d.fsm.player_room()
    print("  after maze rail: room=%d" % room)
    if room == 131:
        print("PASS — maze rail steps into the all-alike maze (131)")
        quit(0)
        return
    print("FAIL — room=%d (expected 131)" % room)
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
