extends SceneTree

# Verifies canon death/resurrection ladder (advent.for STMT
# 16000-16100, msgs #81/#82/#83/#84/#85/#86):
#
#   1st death  → msg #81 ("Oh dear, ... reincarnate you?")
#   1st YES    → msg #82 ("All right... POOF!! ... orange smoke")
#   2nd death  → msg #83 ("You clumsy oaf...")
#   2nd YES    → msg #84 ("Where did I put my orange smoke...")
#   3rd death  → msg #85 ("I'm out of orange smoke!")
#   3rd NO/4th → msg #86 ("Okay, if you're so smart...")

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _capture(d: H.CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

# Force a death + check the prompt text. Resets driver between
# deaths to a clean revive prompt by calling player.die() then
# letting _check_player_death emit the prompt.
func _die_and_capture(d: H.CapturedDriver) -> Array:
    d.fsm.player.die()
    var pre: int = d.captured.size()
    d._check_player_death()
    return d.captured.slice(pre)

func _init():
    print("=== CCA death/resurrection ladder — canon msgs #81-86 ===")

    # ----- Phase 1: 1st death → msg #81 -----
    print("Phase 1: 1st death → msg #81 ('Oh dear...')")
    var d := H.make_driver()
    var l1: Array = _die_and_capture(d)
    _expect_any_match("1st death emits canon msg #81",
        l1, "Oh dear, you seem to have gotten yourself killed")

    # 1st YES → msg #82.
    print("Phase 2: 1st YES → msg #82 ('orange smoke')")
    var l2: Array = _capture(d, "yes")
    _expect_any_match("1st revive emits canon msg #82 ('blame me')",
        l2, "don't blame me")
    _expect_any_match("1st revive includes orange-smoke prose",
        l2, "orange smoke")

    # ----- Phase 3: 2nd death → msg #83 -----
    print("Phase 3: 2nd death → msg #83 ('clumsy oaf')")
    var l3: Array = _die_and_capture(d)
    _expect_any_match("2nd death emits canon msg #83",
        l3, "clumsy oaf")

    # 2nd YES → msg #84.
    print("Phase 4: 2nd YES → msg #84 ('where did I put my orange smoke')")
    var l4: Array = _capture(d, "yes")
    _expect_any_match("2nd revive emits canon msg #84",
        l4, "where did I put my orange smoke")

    # ----- Phase 5: 3rd death → msg #85 -----
    print("Phase 5: 3rd death → msg #85 ('out of orange smoke')")
    var l5: Array = _die_and_capture(d)
    _expect_any_match("3rd death emits canon msg #85",
        l5, "out of orange smoke")

    # ----- Phase 6: NO at 1st death → msg #86 -----
    print("Phase 6: NO at 1st death → msg #86 ('do it yourself')")
    var d2 := H.make_driver()
    _die_and_capture(d2)
    var l6: Array = _capture(d2, "no")
    _expect_any_match("NO emits canon msg #86",
        l6, "do it yourself")

    if failures == 0:
        print("PASS — death/resurrection ladder honors canon msgs #81-86")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
