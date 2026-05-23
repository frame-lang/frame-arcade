extends SceneTree

# ============================================================
# test_cca_death_journeys.gd
# ============================================================
# Walks the DeathJourneys Frame rail. Each scenario is played
# from a fresh driver with typed commands only; probabilistic
# deaths are pinned via the model-native Chance seam through
# inline "force:NAME=VALUE" tokens. Asserts the player dies and
# the canon death prose fires — deterministically, no FSM-direct
# kill pokes.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const DeathJourneys = preload("res://scripts/death_journeys.gd")

var failures: int = 0

class CapDriver:
    extends Driver
    var log: Array = []
    func _println(text: String) -> void:
        log.append(text)

func _init():
    print("=== CCA death journeys (typed commands → canon death) ===")
    var j = DeathJourneys._create()
    while not j.is_done():
        _run_scenario(j.scenario_name(), j.commands(), j.expect_dead(), j.expect_msg())
        j.advance()
    print("")
    if failures == 0:
        print("PASS — every death rail kills the player with canon prose")
        quit(0)
        return
    print("FAIL — %d death rail(s) did not fire as expected" % failures)
    quit(failures)

func _run_scenario(name: String, commands: Array, expect_dead: bool, expect_msg: String) -> void:
    print("--- %s ---" % name)
    var d = _make_driver()
    for cmd in commands:
        var s := String(cmd)
        if s.begins_with("force:"):
            var body := s.substr(6)
            var parts := body.split("=")
            d.fsm.chance.force(parts[0], int(parts[1]))
        else:
            d._process_input(s.to_lower())
    var dead: bool = d.fsm.player_state() == "dead"
    var msg_seen: bool = false
    for line in d.log:
        if expect_msg != "" and expect_msg.to_lower() in String(line).to_lower():
            msg_seen = true
    if dead == expect_dead and (expect_msg == "" or msg_seen):
        print("    ok — dead=%s, prose '%s' seen" % [dead, expect_msg])
    else:
        print("    FAIL — dead=%s (expected %s), prose '%s' seen=%s" % [
            dead, expect_dead, expect_msg, msg_seen])
        failures += 1

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
