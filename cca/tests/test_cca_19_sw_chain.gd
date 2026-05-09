extends SceneTree

# Verifies the canon SW chain at Hall of Mountain King (canon 19).
#
# Canon section 3 has TWO rows for 19:SW, walked in order:
#   `19 35074 49`  → 35% probability → walk to canon 74
#                     (the secret east/west canyon, dragon-side
#                     back-door).
#   `19 211032 49` → if snake here-or-carried → walk to canon 32
#                     (the "YOU CAN'T GET BY THE SNAKE." forced-
#                     motion bumper that bounces back to 19).
#
# Net canon behavior:
#   - Snake present (pre bird-release): 35% to 74, 65% snake bumper.
#   - Snake gone (post bird-release):   35% to 74, 65% no-exit.
#
# Port: GATES `19:sw` is a chain (Array of rules). Bumper dispatch
# walks the chain in order; first rule that fires wins. Topology
# row 19 no longer has `sw`, so when both rules miss the engine
# emits the standard no-exit message.
#
# This test exercises both pre/post-snake states under a pinned
# RNG seed and asserts the distribution is within ±5σ of canon.
# 1000 attempts each; canon 35% with σ = sqrt(1000*0.35*0.65) ≈
# 15, so ±5σ = ±75. Wide enough to absorb seed jitter without
# masking real regressions.

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

class CapturedDriver:
    extends Driver
    var captured: Array = []
    func _println(text: String) -> void:
        self.captured.append(text)

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-52s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-52s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-52s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-52s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-52s found '%s'" % [label, needle])
            return
    print("  FAIL %-52s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")          # avoid dark-pit hazard
    return d

func _init():
    print("=== CCA 19:sw canon chain — `19 35074 49` + `19 211032 49` ===")

    seed(0xCA17ED)

    # ----- Phase 1: gate shape -----
    print("Phase 1: gate at 19:sw is a chain (Array of 2 rules)")
    var Topology = preload("res://scripts/topology.gd")
    var entry = Topology.GATES.get("19:sw", null)
    _expect("gate exists at 19:sw",                   entry != null, true)
    _expect("gate is an Array (chain)",                entry is Array, true)
    if entry is Array:
        _expect("chain has 2 rules (probability + snake)", entry.size(), 2)
        if entry.size() >= 2:
            _expect("first rule is probability",       entry[0].get("check"), "probability")
            _expect("first rule pct=35",               entry[0].get("pct"),   35)
            _expect("first rule dest=74",              entry[0].get("dest"),  74)
            _expect("second rule is snake",            entry[1].get("check"), "snake")
            _expect_any_match("second rule msg names the snake",
                [entry[1].get("msg", "")], "snake")
    _expect("19:sw removed from topology",            Topology.ROOMS[19].has("sw"), false)

    # ----- Phase 2: snake present, 1000 SW attempts -----
    # Canon: 35% to 74, 65% snake bumper.
    # Re-seed at the start of each phase so the per-phase RNG
    # sequence starts identically. (Phase 3 consumes more randi
    # per iteration via fsm.do_command("sw") + tick + dwarf
    # simulation; without re-seeding the cumulative RNG drift
    # between phases skews the apparent probability rate.)
    seed(0xCA17ED)
    print("Phase 2: snake blocking — 1000 SW attempts under pinned RNG")
    var d := _make_driver()
    _expect("setup: snake is blocking",            d.fsm.snake.is_blocking(), true)
    var to_74: int = 0
    var bumpers: int = 0
    var saw_snake_msg: bool = false
    for _i in range(1000):
        d.fsm.player.move_to(19)
        var pre: int = d.captured.size()
        d._process_input("sw")
        if d.fsm.player_room() == 74:
            to_74 += 1
            d.fsm.player.move_to(19)            # reset for next iter
        else:
            bumpers += 1
            for line in d.captured.slice(pre):
                if "snake" in line:
                    saw_snake_msg = true
                    break
    print("  observed: %d to 74 / %d bumpers / saw_snake_msg=%s" % [
        to_74, bumpers, str(saw_snake_msg)])
    _expect_in_range("to_74 in 1000 attempts (canon ~350)", to_74, 275, 425)
    _expect_in_range("bumpers in 1000 attempts (canon ~650)", bumpers, 575, 725)
    _expect("at least one bumper printed snake msg",  saw_snake_msg, true)

    # ----- Phase 3: snake gone — qualitative verification only -----
    # Canon: 35% to 74, 65% no exit (topology has no sw).
    #
    # Running 1000 iterations through _process_input here is
    # *unstable* because each iteration ticks the world: lamp
    # battery decrements (~330 turns til dead), dark-pit hazard
    # then takes over and intercepts SW motion attempts before
    # the chain even runs. Phase 2 (snake-block bumper short-
    # circuits before tick) doesn't have this problem.
    #
    # We verify the canon behavior in two pieces instead:
    #   (a) the chain *fall-through* path runs at all (some
    #       SW attempts walk to 74, some emit a fallback msg);
    #   (b) the snake-block message never fires once snake gone.
    # Phase 5 below verifies the probability gate's hit rate
    # in isolation, free of tick-induced lamp drain.
    seed(0xCA17ED)
    print("Phase 3: snake gone — qualitative chain fall-through")
    var d2 := _make_driver()
    d2.fsm.snake.bird_released_here()           # snake → $Gone
    _expect("snake is gone",                      d2.fsm.snake.is_blocking(), false)
    var g_to_74: int = 0
    var g_bumpers: int = 0
    var saw_fallback: bool = false       # "no exit" or "don't know" — canon-equivalent fallbacks
    var saw_snake_msg2: bool = false
    # 100 iterations is well below the lamp-die threshold so
    # behavior stays clean.
    for _i in range(100):
        d2.fsm.player.move_to(19)
        var pre: int = d2.captured.size()
        d2._process_input("sw")
        if d2.fsm.player_room() == 74:
            g_to_74 += 1
            d2.fsm.player.move_to(19)
        else:
            g_bumpers += 1
            for line in d2.captured.slice(pre):
                var lo: String = line.to_lower()
                if "can't go" in lo or "no exit" in lo or "don't know" in lo:
                    saw_fallback = true
                if "snake" in lo:
                    saw_snake_msg2 = true
    print("  observed: %d to 74 / %d bumpers / saw_fallback=%s / saw_snake_msg=%s" % [
        g_to_74, g_bumpers, str(saw_fallback), str(saw_snake_msg2)])
    _expect("at least one SW attempt walked to 74",        g_to_74 > 0,        true)
    _expect("at least one SW attempt was bumpered",        g_bumpers > 0,      true)
    _expect("at least one bumper emitted fallback msg",    saw_fallback,       true)
    _expect("snake-block msg never fires when snake gone", saw_snake_msg2,     false)

    # ----- Phase 5: probability gate hit rate, isolated -----
    # Direct verification that the probability gate fires at the
    # canon 35% rate, free of tick / lamp / dark-pit interference.
    # Calls _try_bumper_rule on the probability rule 1000 times
    # without going through _process_input. RNG is re-seeded.
    seed(0xCA17ED)
    print("Phase 5: probability gate hit rate (isolated, 1000 rolls)")
    var d4 := _make_driver()
    d4.fsm.player.move_to(19)
    var prob_rule: Dictionary = entry[0]
    var hits: int = 0
    var pre_room: int = d4.fsm.player_room()
    for _i in range(1000):
        # Reset position so each iteration is identical.
        d4.fsm.player.move_to(19)
        var fired: bool = d4._try_bumper_rule(prob_rule)
        if fired and d4.fsm.player_room() == 74:
            hits += 1
    print("  observed: %d hits in 1000 rolls (canon ~350)" % hits)
    _expect_in_range("hits in [275, 425] (canon 35% ± 5σ)", hits, 275, 425)

    # ----- Phase 4: chain-shape sanity -----
    # Verify a single-Dict gate at e.g. 19:north still works (the
    # refactor mustn't have broken the non-chain code path).
    print("Phase 4: single-Dict gates still work (19:north unchanged)")
    var d3 := _make_driver()
    d3.fsm.player.move_to(19)
    var pre3: int = d3.captured.size()
    d3._process_input("north")
    var lines3: Array = d3.captured.slice(pre3)
    _expect("19:north blocked by snake",          d3.fsm.player_room(), 19)
    _expect_any_match("19:north emits snake bumper",
        lines3, "snake glares")

    if failures == 0:
        print("PASS — 19:sw canon chain honors `19 35074 49` + `19 211032 49`")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
