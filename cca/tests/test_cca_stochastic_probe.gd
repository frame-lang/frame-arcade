extends SceneTree

# ============================================================
# test_cca_stochastic_probe.gd
# ============================================================
# Verifies a RANDOMIZED section of the game is canon-faithful,
# using the StochasticProbe FSM. Where the success/death rails
# pin a probabilistic gate to one outcome (chance.force), this
# drives the gate across a fixed seed set and checks the spread.
#
# Gate under test: canon 65:north (Bedquilt). Its section-3 chain
# is `60% bounce-back to 65 / 75% of the rest → 72 / else → 71`
# (topology.gd GATES "65:north"). So there are exactly three
# canonical outcomes: {65, 72, 71}.
#
# The probe restores the same Bedquilt start for every trial and
# only varies the Chance seed, so it samples the gate's outcome
# distribution deterministically. Asserts:
#   • branch coverage — all three canonical outcomes occur, and
#   • golden exact counts — over seeds 1..50 the tally is exactly
#     {65: 29, 72: 17, 71: 4}.
# Ratios (~58/34/8 %) track canon's 60/30/10 — evidence the model
# is faithful — while the exact counts lock determinism.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const StochasticProbe = preload("res://scripts/stochastic_probe.gd")

# Golden tally over seeds 1..50 (see header).
const GOLDEN := {65: 29, 72: 17, 71: 4}

func _init():
    print("=== CCA stochastic probe: 65:north gate distribution ===")

    # Build the Bedquilt (canon 65) start state once.
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
    var at65: PackedByteArray = b.fsm.save_state()

    # Run the probe loop: one trial per dispensed seed.
    var probe = StochasticProbe._create()
    while not probe.is_done():
        var seed: int = probe.next_seed()
        var t = _make_driver()
        t.fsm.restore_state(at65)
        t.prompts = Cca.PromptDispatcher.new()
        t.fsm.chance.reseed(seed)            # vary only the roll
        t._process_input("north")
        probe.record(t.fsm.player_room())

    var got := {65: probe.count(65), 72: probe.count(72), 71: probe.count(71)}
    print("  trials=%d  distinct=%d  tally=%s" % [
        probe.trials_done(), probe.distinct_outcomes(), str(got)])

    var fails: Array = []
    # Branch coverage: every canonical outcome occurs.
    for branch in GOLDEN:
        if probe.count(branch) <= 0:
            fails.append("branch %d never occurred" % branch)
    # Golden exact counts.
    for branch in GOLDEN:
        if probe.count(branch) != GOLDEN[branch]:
            fails.append("count(%d)=%d, golden %d" % [branch, probe.count(branch), GOLDEN[branch]])
    if probe.distinct_outcomes() != GOLDEN.size():
        fails.append("distinct outcomes %d, expected %d" % [probe.distinct_outcomes(), GOLDEN.size()])
    if probe.trials_done() != 50:
        fails.append("trials %d, expected 50" % probe.trials_done())

    if fails.is_empty():
        print("PASS — 65:north covers all 3 canon branches; golden tally locked")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
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
