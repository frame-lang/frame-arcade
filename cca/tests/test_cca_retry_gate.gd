extends SceneTree

# ============================================================
# test_cca_retry_gate.gd
# ============================================================
# Verifies the retry-until-success LOOP (RetryGate): reach canon
# 110 through the 65:north probability gate ORGANICALLY — no
# chance.force, just keep playing the odds until a roll falls
# through to 71→110.
#
# Setup: win → BridgeBuilt → crawl to Bedquilt (canon 65). Then
# the RetryGate loop drives: it reacts to wherever each command
# lands (bounce→retry, divert-to-72→return via bedquilt,
# 71→through), and exits when it reaches 110 (success) or hits a
# step cap (bound). Under the game seed it succeeds in 8 steps.
#
# Contrast with room110_journey, which PINS the gate
# (force:travel_gate=0) for a one-shot hop: same destination, two
# honest strategies — suppress the randomness, or beat it.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const RetryGate = preload("res://scripts/retry_gate.gd")

func _init():
    print("=== CCA retry-until-success loop (65:north → 110, no force) ===")
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

    var b = _make_driver()
    b.fsm.restore_state(bridge)
    b.prompts = Cca.PromptDispatcher.new()
    for cmd in ["east", "north", "north", "down", "bedquilt"]:
        b._process_input(cmd)
    if b.fsm.player_room() != 65:
        print("FAIL — setup did not reach Bedquilt (got %d)" % b.fsm.player_room())
        quit(1)
        return

    # Drive the retry loop.
    var loop = RetryGate._create()
    loop.arrive(b.fsm.player_room())
    while not loop.is_done():
        var cmd: String = loop.next_cmd()
        b._process_input(cmd)
        loop.arrive(b.fsm.player_room())

    var room: int = b.fsm.player_room()
    var steps: int = loop.steps_taken()
    print("  reached room %d in %d retry steps (success=%s)" % [room, steps, loop.reached()])

    if loop.reached() and room == 110 and steps < 60:
        print("PASS — pushed through 65:north to 110 organically (no force)")
        quit(0)
        return
    print("FAIL — room=%d reached=%s steps=%d" % [room, loop.reached(), steps])
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
