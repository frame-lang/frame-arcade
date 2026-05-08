extends SceneTree

# Verifies the canonical "you can't carry the gold up the pit"
# fall-to-death at canon 14 (Top of Small Pit). Per cca/canon/
# advent.dat row `14 150020 30 31 34`:
#
#   M = 150  → carrying-conditional, obj #50 (GOLD).
#   N = 020  → dest = canon 20 (broken-neck pit-bottom death).
#   verbs    → 30 DOWN, 31 PIT, 34 STEPS.
#
# Companion to canon row `15 150022 …` (gold-blocks-the-steps).
# Together the pair forms the canonical inventory-aware barrier
# protecting the gold:
#
#   - At canon 15 (east end of Hall of Mists): UP/PIT/STEPS/DOME/
#     PASSAGE/EAST while carrying gold print "The dome is
#     unclimbable." and stay put. (Tested in test_cca_gold_blocks
#     _steps.gd.)
#   - At canon 14 (Top of Small Pit): DOWN/PIT/STEPS while
#     carrying gold dump the player into canon 20, where they
#     die with a broken neck. (This test.)
#
# Reaching 14 with gold isn't easy in canon — 15:up is gold-
# blocked, so the player must walk 18 → 15 (south side) → drop
# gold → climb steps to 14 → … or use the long-cave route
# (3 → XYZZY → 11 → 12:up → 13:west → 14). The pair makes the
# gold a real burden, encouraging the player to use the snake-
# cleared 19→28→33 long-way out.

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
    return d

func _init():
    print("=== CCA gold-falls-pit (canon 14 / row `14 150020 ...`) ===")

    # Phase 1: with gold, DOWN/PIT/STEPS at canon 14 walk the
    # player into canon 20 and trigger the broken-neck death.
    print("Phase 1: gold in hand at 14 — DOWN/PIT/STEPS fall to 20 (death)")
    for verb in ["down", "pit", "steps"]:
        var d := _make_driver()
        d.fsm.do_command("light", "")
        d.fsm.player.move_to(14)
        d.fsm.player.take(d.fsm.GOLD_ID)
        _expect("setup: at 14 with gold (%s)" % verb,
            [d.fsm.player_room(), d.fsm.player.carrying(d.fsm.GOLD_ID)],
            [14, true])
        var pre: int = d.captured.size()
        d._process_input(verb)
        var lines: Array = d.captured.slice(pre)
        _expect("with gold, %s walks to canon 20 (pit bottom)" % verb,
            d.fsm.player_room(), 20)
        _expect("with gold, %s leaves player dead" % verb,
            d.fsm.player_state(), "dead")
        _expect_any_match("with gold, %s emits broken-bone canon prose" % verb,
            lines, "broke every bone")

    # Phase 2: without gold, DOWN at canon 14 walks normally
    # to canon 15. PIT and STEPS aren't unconditionally defined
    # at 14 in canon, so they fall through to the FSM's "I
    # don't know how to X" response — same as canon, where
    # those verbs only exist on the carrying-conditional row.
    print("Phase 2: no gold at 14 — DOWN walks to 15, PIT/STEPS not defined")
    var d2 := _make_driver()
    d2.fsm.do_command("light", "")
    d2.fsm.player.move_to(14)
    _expect("d2: not carrying gold initially",
        d2.fsm.player.carrying(d2.fsm.GOLD_ID), false)
    d2._process_input("down")
    _expect("without gold, 14:down → 15 (Hall of Mists)",
        d2.fsm.player_room(), 15)

    var d3 := _make_driver()
    d3.fsm.do_command("light", "")
    d3.fsm.player.move_to(14)
    d3._process_input("pit")
    _expect("without gold, 14:pit stays at 14 (no canon row)",
        d3.fsm.player_room(), 14)
    _expect("without gold, 14:pit doesn't kill the player",
        d3.fsm.player_state(), "alive")

    # Phase 3: drop gold at 14 → DOWN walks normally again.
    print("Phase 3: gold dropped at 14 — DOWN walks to 15 (no death)")
    var d4 := _make_driver()
    d4.fsm.do_command("light", "")
    d4.fsm.player.move_to(14)
    d4.fsm.player.take(d4.fsm.GOLD_ID)
    _expect("d4: carrying gold", d4.fsm.player.carrying(d4.fsm.GOLD_ID), true)
    d4.fsm.player.drop(d4.fsm.GOLD_ID)
    _expect("d4: dropped gold", d4.fsm.player.carrying(d4.fsm.GOLD_ID), false)
    d4._process_input("down")
    _expect("after dropping gold, 14:down → 15 (no fall)",
        d4.fsm.player_room(), 15)
    _expect("after dropping gold, player still alive",
        d4.fsm.player_state(), "alive")

    if failures == 0:
        print("PASS — gold-falls-pit gate honors canon row 14:150020")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
