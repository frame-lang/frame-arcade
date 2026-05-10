extends SceneTree

# Verifies canon ATTACK BIRD (advent.for STMT 9120) → msg #137:
# "Oh, leave the poor unhappy bird alone."
#
# KILL BIRD is a synonym (canon verb 12 + KILL/FIGHT both map to
# attack via the synonym table).

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

func _init():
    print("=== CCA ATTACK BIRD — canon msg #137 ===")

    # ----- Phase 1: ATTACK BIRD → msg #137 -----
    print("Phase 1: ATTACK BIRD → 'leave the poor unhappy bird alone'")
    var d := H.make_driver()
    var l1: Array = H.capture(d, "attack bird")
    _expect_any_match("ATTACK BIRD emits canon msg #137",
        l1, "leave the poor unhappy bird alone")

    # ----- Phase 2: KILL BIRD synonym → msg #137 -----
    print("Phase 2: KILL BIRD synonym → msg #137")
    var d2 := H.make_driver()
    var l2: Array = H.capture(d2, "kill bird")
    _expect_any_match("KILL BIRD emits canon msg #137",
        l2, "leave the poor unhappy bird alone")

    if failures == 0:
        print("PASS — ATTACK BIRD honors canon msg #137")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
