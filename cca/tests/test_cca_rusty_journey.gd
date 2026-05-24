extends SceneTree

# ============================================================
# test_cca_rusty_journey.gd
# ============================================================
# Verifies the rusty-door branch rail: win → BridgeBuilt →
# PlantJourney (Giant Room) → RustyJourney climbs down for oil,
# pours it on the sealed iron door at canon 94, and passes through
# to canon 95 and 91. Typed commands only, deterministic (seed 42
# + chance 42).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const PlantJourney = preload("res://scripts/plant_journey.gd")
const RustyJourney = preload("res://scripts/rusty_journey.gd")

func _init():
    print("=== CCA rusty-door rail (Giant Room → oil door → 91) ===")
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

    var r = RustyJourney._create()
    while not r.is_done():
        for cmd in r.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        r.advance()

    var room: int = d.fsm.player_room()
    var oiled: bool = d.fsm.rusty_door_oiled()
    print("  after rusty rail: room=%d oiled=%s" % [room, oiled])

    if oiled and room == 91:
        print("PASS — rusty rail oils the door and reaches canon 91 via 95")
        quit(0)
        return
    print("FAIL — room=%d (expected 91), oiled=%s" % [room, oiled])
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
