extends SceneTree

# ============================================================
# test_cca_death_journeys.gd
# ============================================================
# Walks the DeathJourneys Frame rail. Each scenario plays typed
# commands only — no FSM-direct kill pokes — and asserts the
# player dies with the canon death prose, deterministically.
#
# Two scenario shapes (selected by the rail's seed_milestone()):
#   • fresh start (seed_milestone == "") — commands() is the full
#     typed sequence from the building (e.g. DarkPit's xyzzy hop).
#   • milestone-seeded — the runner restores a success-rail
#     waypoint ("BridgeBuilt"/"TrollFarSide"/"Room110") first, then
#     plays commands() as the death tail. Deaths branch off the
#     same journey-DAG chokepoints as the success branch-rails.
#
# Probabilistic deaths are pinned via the model-native Chance seam
# through inline "force:NAME=VALUE" / "clear:NAME" tokens.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const DeathJourneys = preload("res://scripts/death_journeys.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const PlantJourney = preload("res://scripts/plant_journey.gd")
const TrollJourney = preload("res://scripts/troll_journey.gd")
const Room110Journey = preload("res://scripts/room110_journey.gd")

var failures: int = 0
var milestones: Dictionary = {}   # name → saved-state bytes (built lazily)

class CapDriver:
    extends Driver
    var log: Array = []
    func _println(text: String) -> void:
        log.append(text)

func _init():
    print("=== CCA death journeys (typed commands → canon death) ===")
    _build_milestones()
    var j = DeathJourneys._create()
    while not j.is_done():
        _run_scenario(j.scenario_name(), j.seed_milestone(), j.commands(),
                      j.expect_dead(), j.expect_msg())
        j.advance()
    print("")
    if failures == 0:
        print("PASS — every death rail kills the player with canon prose")
        quit(0)
        return
    print("FAIL — %d death rail(s) did not fire as expected" % failures)
    quit(failures)

# Build the success-rail waypoints the milestone-seeded deaths
# branch off. Each is walked once with typed commands; restoring
# the bytes round-trips the Chance seed+step so death tails replay
# deterministically.
func _build_milestones() -> void:
    var d = _make_driver()
    var j = WinJourney._create()
    while not j.is_done():
        var nm: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if nm == "BridgeBuilt":
            milestones["BridgeBuilt"] = d.fsm.save_state()
        j.advance()

    # Room110: BridgeBuilt → Room110Journey (honours force:/clear:).
    var r = _make_driver()
    r.fsm.restore_state(milestones["BridgeBuilt"])
    r.prompts = Cca.PromptDispatcher.new()
    var rq = Room110Journey._create()
    while not rq.is_done():
        for cmd in rq.commands_from_previous():
            _feed(r, String(cmd))
        rq.advance()
    milestones["Room110"] = r.fsm.save_state()

    # TrollFarSide: BridgeBuilt → Plant (Giant Room) → Troll (122).
    var t = _make_driver()
    t.fsm.restore_state(milestones["BridgeBuilt"])
    t.prompts = Cca.PromptDispatcher.new()
    var pj = PlantJourney._create()
    while not pj.is_done():
        for cmd in pj.commands_from_previous():
            t._process_input(String(cmd).to_lower())
        pj.advance()
    var tj = TrollJourney._create()
    while not tj.is_done():
        for cmd in tj.commands_from_previous():
            t._process_input(String(cmd).to_lower())
        tj.advance()
    milestones["TrollFarSide"] = t.fsm.save_state()

func _run_scenario(name: String, milestone: String, commands: Array,
                   expect_dead: bool, expect_msg: String) -> void:
    print("--- %s ---" % name)
    var d = _make_driver()
    if milestone != "":
        d.fsm.restore_state(milestones[milestone])
        d.prompts = Cca.PromptDispatcher.new()
    for cmd in commands:
        _feed(d, String(cmd))
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

# Honour the Chance steering tokens; plain commands go to input.
func _feed(d, raw: String) -> void:
    if raw.begins_with("force:"):
        var parts := raw.substr(6).split("=")
        d.fsm.chance.force(parts[0], int(parts[1]))
        return
    if raw.begins_with("clear:"):
        d.fsm.chance.clear_forced(raw.substr(6))
        return
    d._process_input(raw.to_lower())

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
