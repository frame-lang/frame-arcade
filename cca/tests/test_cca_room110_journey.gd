extends SceneTree

# ============================================================
# test_cca_room110_journey.gd
# ============================================================
# Verifies the bedquilt → room-110 branch rail: win →
# BridgeBuilt → Room110Journey crawls through Bedquilt (canon 65)
# and lands in canon 110. Typed commands only, deterministic
# (seed 42 + chance 42).
#
# Room 110 is the one graph room a blind walker can't reach: every
# exit out of Bedquilt is a probability gate. The rail pins those
# rolls to MISS via the inline "force:travel_gate=0" token (the
# Chance steering seam) so 65:north falls through to its topology
# exit (71 → 110), then unpins with "clear:travel_gate".
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const Room110Journey = preload("res://scripts/room110_journey.gd")

func _init():
    print("=== CCA room-110 rail (BridgeBuilt → Bedquilt → 110) ===")
    var d = _make_driver()

    var j = WinJourney._create()
    while not j.is_done():
        var name: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if name == "BridgeBuilt":
            break
        j.advance()

    var saw_bedquilt: bool = false
    var q = Room110Journey._create()
    while not q.is_done():
        for cmd in q.commands_from_previous():
            _feed(d, String(cmd))
        if q.state_name() == "AtBedquilt" and d.fsm.player_room() == 65:
            saw_bedquilt = true
        q.advance()

    var room: int = d.fsm.player_room()
    print("  passed Bedquilt(65)=%s, after rail: room=%d" % [saw_bedquilt, room])
    if saw_bedquilt and room == 110:
        print("PASS — room-110 rail crawls Bedquilt → 110")
        quit(0)
        return
    print("FAIL — bedquilt=%s room=%d (expected 65 then 110)" % [saw_bedquilt, room])
    quit(1)

# Honour the Chance steering tokens the rail emits; plain commands
# go to the driver as input.
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
