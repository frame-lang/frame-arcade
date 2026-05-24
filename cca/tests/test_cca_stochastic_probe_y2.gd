extends SceneTree

# ============================================================
# test_cca_stochastic_probe_y2.gd
# ============================================================
# Fourth StochasticProbe binding — the Y2 "hollow voice" whisper,
# a 25% Chance gate. Canon advent.for line 808: each visit to
# canon room 33 (Y2), 25% chance to print msg #8, "A hollow voice
# says PLUGH" (driver.gd _print_room; suppressed during closing).
#
# Per trial: a fresh driver with the player at Y2 (room 33),
# reseed Chance, re-print the room, and record whether the
# whisper fired. Over seeds 1..50:
#   • branch coverage — both outcomes occur, and
#   • golden exact counts — {whisper(1): 12, silent(0): 38}.
# 12/50 = 24 % tracks the canon 25 % whisper chance.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StochasticProbe = preload("res://scripts/stochastic_probe.gd")

const GOLDEN := {1: 12, 0: 38}   # 1 = whisper, 0 = silent

class CapDriver:
    extends Driver
    var log: Array = []
    func _println(text: String) -> void:
        log.append(text)

func _init():
    print("=== CCA stochastic probe: Y2 hollow-voice whisper (25% gate) ===")

    var probe = StochasticProbe._create()
    while not probe.is_done():
        var seed: int = probe.next_seed()
        var d = _make_driver()
        d.fsm.player.move_to(33)            # Y2
        d.fsm.chance.reseed(seed)
        d.log.clear()
        d._print_room()
        var whispered: bool = false
        for line in d.log:
            if "hollow voice" in String(line).to_lower():
                whispered = true
        probe.record(1 if whispered else 0)

    var got := {1: probe.count(1), 0: probe.count(0)}
    print("  trials=%d  distinct=%d  tally=%s" % [
        probe.trials_done(), probe.distinct_outcomes(), str(got)])

    var fails: Array = []
    for branch in GOLDEN:
        if probe.count(branch) <= 0:
            fails.append("outcome %d never occurred" % branch)
        if probe.count(branch) != GOLDEN[branch]:
            fails.append("count(%d)=%d, golden %d" % [branch, probe.count(branch), GOLDEN[branch]])
    if probe.distinct_outcomes() != GOLDEN.size():
        fails.append("distinct outcomes %d, expected %d" % [probe.distinct_outcomes(), GOLDEN.size()])
    if probe.trials_done() != 50:
        fails.append("trials %d, expected 50" % probe.trials_done())

    if fails.is_empty():
        print("PASS — Y2 whisper covers both outcomes; golden tally locked (24%% ≈ canon 25%%)")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
    quit(1)

func _make_driver():
    var d = CapDriver.new()
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
