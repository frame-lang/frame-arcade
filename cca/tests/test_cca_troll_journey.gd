extends SceneTree

# ============================================================
# test_cca_troll_journey.gd
# ============================================================
# Verifies the troll-cross branch rail: win → BridgeBuilt →
# PlantJourney (Giant Room, carrying eggs) → TrollJourney
# (navigate to the troll bridge, throw the eggs to pay the toll,
# cross to the far side, canon 122). Typed commands only,
# deterministic (seed 42 + chance 42). Opens the volcano /
# breath-taking-view / bear-chamber cluster (canon 122-130).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const PlantJourney = preload("res://scripts/plant_journey.gd")
const TrollJourney = preload("res://scripts/troll_journey.gd")

func _init():
    print("=== CCA troll-cross rail (Giant Room → far side) ===")
    var d = _make_driver()

    var j = WinJourney._create()
    while not j.is_done():
        var name: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if name == "BridgeBuilt":
            break
        j.advance()

    var p = PlantJourney._create()
    while not p.is_done():
        for cmd in p.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        p.advance()

    var t = TrollJourney._create()
    while not t.is_done():
        for cmd in t.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        t.advance()

    var room: int = d.fsm.player_room()
    var troll: String = d.fsm.troll_state()
    print("  after troll rail: room=%d troll=%s" % [room, troll])

    if room == 122 and troll == "vanished":
        print("PASS — troll rail crosses to the far side (122); troll vanished")
        quit(0)
        return
    print("FAIL — room=%d (expected 122), troll=%s" % [room, troll])
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
