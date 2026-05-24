extends SceneTree

# ============================================================
# test_cca_stochastic_probe_dispatch.gd
# ============================================================
# Third binding of the domain-agnostic StochasticProbe FSM — this
# time a THREE-way Chance gate: the unknown-verb message mix.
#
# Canon STMT 3000: when the parser doesn't know a verb, it picks
# among three rebukes. The port routes the rolls through the
# Chance system (driver.gd _dispatch_to_fsm):
#   decide("dispatch_13", 20)  → msg #13 "I don't understand that!"
#   elif decide("dispatch_61", 20) → msg #61 "What?"
#   else → msg #60 "I don't know that word."
# Net distribution 20 / 16 / 64 % (the 61 branch is 20% of the
# 80% that missed the first roll).
#
# Setup-free: from a fresh driver, typing any unknown word
# ("flooble") triggers the mix. Per trial we reseed Chance, issue
# the word, and classify the rebuke. Over seeds 1..50:
#   • branch coverage — all three messages occur, and
#   • golden exact counts — {13: 11, 61: 7, 60: 32}.
# Ratios 22/14/64 % track canon 20/16/64; exact counts lock it.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StochasticProbe = preload("res://scripts/stochastic_probe.gd")

# Golden tally over seeds 1..50 (outcome = canon message number).
const GOLDEN := {13: 11, 61: 7, 60: 32}

class CapDriver:
    extends Driver
    var log: Array = []
    func _println(text: String) -> void:
        log.append(text)

func _init():
    print("=== CCA stochastic probe: unknown-verb message mix (3-way gate) ===")

    var probe = StochasticProbe._create()
    while not probe.is_done():
        var seed: int = probe.next_seed()
        var d = _make_driver()
        d.fsm.chance.reseed(seed)
        d.log.clear()
        d._process_input("flooble")        # unknown verb → STMT 3000 mix
        probe.record(_classify(d.log))

    var got := {13: probe.count(13), 61: probe.count(61), 60: probe.count(60)}
    print("  trials=%d  distinct=%d  tally=%s" % [
        probe.trials_done(), probe.distinct_outcomes(), str(got)])

    var fails: Array = []
    for branch in GOLDEN:
        if probe.count(branch) <= 0:
            fails.append("msg #%d never occurred" % branch)
        if probe.count(branch) != GOLDEN[branch]:
            fails.append("count(%d)=%d, golden %d" % [branch, probe.count(branch), GOLDEN[branch]])
    if probe.distinct_outcomes() != GOLDEN.size():
        fails.append("distinct outcomes %d, expected %d" % [probe.distinct_outcomes(), GOLDEN.size()])
    if probe.trials_done() != 50:
        fails.append("trials %d, expected 50" % probe.trials_done())

    if fails.is_empty():
        print("PASS — unknown-verb mix covers all 3 canon msgs; golden tally locked")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
    quit(1)

func _classify(lines: Array) -> int:
    var j: String = "\n".join(lines).to_lower()
    if "i don't understand that" in j:
        return 13
    if "what?" in j:
        return 61
    if "i don't know that word" in j:
        return 60
    return -1

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
