extends SceneTree

# Verifies canon row `38 595 60 14 30 4 5` — at canon 38 (Bottom of
# Pit with Stream), the verbs SLIT / STREAM / DOWN / UPSTREAM /
# DOWNSTREAM all emit canon msg #95 ("You don't fit through a
# two-inch slit!"). UP at canon 38 is the legitimate exit (back
# to canon 37) and is NOT bumpered.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> H.CapturedDriver:
    var d := H.CapturedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    d.fsm.player.move_to(38)
    return d

func _check_bumper(verb: String) -> void:
    var d := _make_driver()
    var lines: Array = H.capture(d, verb)
    _expect_any_match("'%s' @ 38 emits canon msg #95" % verb,
        lines, "two-inch slit")
    _expect("'%s' @ 38 player still at 38" % verb,
        d.fsm.player_room(), 38)

func _init():
    print("=== CCA canon-38 directional bumpers (msg #95) ===")

    print("Canon `38 595 60 14 30 4 5` — 5 verbs all bumpered:")
    _check_bumper("slit")
    _check_bumper("stream")
    _check_bumper("down")
    _check_bumper("upstream")
    _check_bumper("downstream")

    # UP is the legitimate exit — should walk to canon 37, not bumper.
    print("UP @ 38 is the legitimate exit (canon 37):")
    var d := _make_driver()
    var lines: Array = H.capture(d, "up")
    var saw_bump: bool = false
    for line in lines:
        if "two-inch slit" in line:
            saw_bump = true
            break
    _expect("UP @ 38 does NOT emit msg #95", saw_bump, false)
    _expect("UP @ 38 walks to canon 37",     d.fsm.player_room(), 37)

    if failures == 0:
        print("PASS — canon-38 bumpers honor row `38 595 60 14 30 4 5`")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
