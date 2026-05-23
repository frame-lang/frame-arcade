extends SceneTree

# ============================================================
# test_cca_win_journey.gd
# ============================================================
# Proves a fully ORGANIC win: walk the WinJourney rail (a Frame
# FSM) through the real Driver with typed commands only — no
# treasure_deposited()/tick() pokes, no save_state surgery — and
# assert the game reaches $Won via a real BLAST.
#
# This is the rail the canonical_journey never was: it collects
# and deposits ten treasures by playing (rug, gold, silver,
# jewelry, coins, diamonds, vase, pyramid, pearl, and the
# pirate's chest), lets the 10th deposit arm the cave-closing
# naturally, rides the timer to the Repository, and blasts.
#
# Determinism comes from the model now: rng.seed = 42 AND the
# model-native Chance system reseeded to 42 (chance.reseed),
# dwarves dormant, pirate on its fixed seed. The whole run is
# reproducible and fast (~1s; no BFS, no state-space search).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")

func _init():
    print("=== CCA organic win journey (typed commands → BLAST) ===")
    var d = _make_driver()
    var j = WinJourney._create()
    var steps: int = 0

    while not j.is_done():
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
            steps += 1
        j.advance()

    var won: bool = d.fsm.endgame_state() == "won"
    var deposited: int = d.fsm.treasures_deposited()
    print("  commands run: %d   treasures deposited: %d   endgame: %s" % [
        steps, deposited, d.fsm.endgame_state()])

    var ok: bool = won and deposited >= 10
    if ok:
        print("PASS — organic typed-command playthrough reaches $Won (10 treasures, real BLAST)")
        quit(0)
        return
    print("FAIL — did not reach an organic win (won=%s, deposited=%d)" % [won, deposited])
    quit(1)

func _make_driver():
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true       # dwarves dormant (canon-completability convention)
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = 42
    d.fsm.chance.reseed(42)               # pin the model's probability rolls
    d._build_verb_synonyms_5()
    return d
