extends SceneTree

# ============================================================
# test_cca_completable_multiseed.gd
# ============================================================
# Completability under adverse RNG. Everything else in the
# suite that proves the game is winnable uses RNG seed 42 — and
# the canonical journey deliberately routes around probabilistic
# hazards. This test asks the unasked question:
#
#   Does the canonical winning playthrough still reach $Won
#   under EVERY RNG seed, or only the lucky ones?
#
# Same fixed winning command sequence, different probabilistic
# realizations. The driver RNG drives:
#   • pirate movement + steal timing (the dangerous one — the
#     pirate relocates a treasure to its stash; a bad seed
#     could strand a treasure or steal at a moment the fixed
#     script can't recover from)
#   • probabilistic dispatch rows (19:sw 35%, etc.)
#   • dark-pit 35% rolls
#   • unknown-verb prose mix
#
# A seed that fails to reach $Won is either:
#   • a real RNG-dependent softlock (pirate makes a treasure
#     unrecoverable, dispatch strands the player), OR
#   • a seed-fragile script (the fixed commands assume seed-42
#     RNG outcomes at some probabilistic branch).
# Either is worth knowing. The per-seed diagnostic captures the
# derail point so failures are interpretable.
#
# Dwarves are kept dormant (dwarves_auto_woken) to match the
# canonical-journey + completability tests and isolate the
# pirate / dispatch RNG. Dwarf-active completability is a
# further frontier (the fixed script can't dodge a blocking
# dwarf, so it'd measure script fragility more than game
# softlock).
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

# Seed sweep. 42 is the known-good baseline; the rest are
# arbitrary spreads (same set the probe / multiseed BFS use,
# plus a couple more) to sample distinct pirate walks.
const SEEDS: Array = [42, 99, 1234, 7777, 31415, 27182, 8675309]

var failures: int = 0

func _init():
    print("=== Completability under RNG seed sweep ===")
    print("")
    for seed in SEEDS:
        _run_seed(seed)
    print("")
    if failures == 0:
        print("PASS — canonical journey reaches $Won under all %d seeds" % SEEDS.size())
        quit(0)
        return
    print("FAIL — %d seed(s) could not complete the game" % failures)
    quit(failures)

func _run_seed(seed: int) -> void:
    var driver = _make_driver(seed)
    var j = CanonicalJourney._create()
    var last_state: String = ""
    while not j.is_done():
        var state: String = j.state_name()
        _apply_shortcuts(driver, state)
        for cmd in j.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        last_state = state
        j.advance()

    var es: String = driver.fsm.endgame_state()
    if es == "won":
        print("  OK   seed %-8d → won" % seed)
        return
    # Diagnostic: where did it end up, and what does the world
    # look like? Pirate state + player state + room localize the
    # derail.
    print("  FAIL seed %-8d → endgame=%s (last milestone: %s)" % [seed, es, last_state])
    print("        player: %s @ canon %d   pirate: %s   score: %d" % [
        driver.fsm.player.get_state(),
        driver.fsm.player_room(),
        driver.fsm.pirate.get_state(),
        driver.fsm.score()])
    failures += 1

func _apply_shortcuts(driver, state: String) -> void:
    if state == "TreasuresFilled":
        for i in 13:
            driver.fsm.endgame.treasure_deposited()
    elif state == "InRepository":
        for i in 35:
            driver.fsm.tick()

func _make_driver(seed: int):
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = seed
    d._build_verb_synonyms_5()
    d._print_welcome()
    d._print_room()
    return d
