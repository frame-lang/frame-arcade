extends SceneTree

# Verifies three small canon mechanics:
#
#   CAVE outdoors (rooms 1-8) → canon msg #57
#   CAVE indoors  (rooms 9+)  → canon msg #58
#   Y2 (canon room 33) PLUGH-whisper rolls msg #8 at ~25%
#   BACK with no remembered prior room → canon msg #91
#
# Phase 4 verifies the Y2 whisper at a much higher iteration count
# (1000) than would normally happen in play, with a pinned RNG
# seed, and asserts the rate is within ±5σ of canon's 25%.
# σ = sqrt(1000*0.25*0.75) ≈ 13.7 → ±5σ = ±69 → tolerance window
# [181, 319] around the 250 expected mean.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-58s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-58s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _init():
    print("=== CCA CAVE / Y2 whisper / BACK fallback ===")

    # ----- Phase 1: CAVE outdoors → msg #57 -----
    print("Phase 1: CAVE @ canon room 3 (outdoors) → msg #57")
    var d1 := H.make_driver()
    d1.fsm.player.move_to(3)
    var l1: Array = H.capture(d1, "cave")
    _expect_any_match("CAVE outdoors emits 'I don't know where the cave is'",
        l1, "I don't know where the cave is")

    # ----- Phase 2: CAVE indoors → msg #58 -----
    print("Phase 2: CAVE @ canon room 9 (indoors) → msg #58")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(9)
    var l2: Array = H.capture(d2, "cave")
    _expect_any_match("CAVE indoors emits 'I need more detailed instructions'",
        l2, "I need more detailed instructions")

    # ----- Phase 3: BACK with no prior location → msg #91 -----
    print("Phase 3: BACK with no prior loc → msg #91")
    var d3 := H.make_driver()
    var l3: Array = H.capture(d3, "back")
    _expect_any_match("BACK with no prior loc emits 'no longer seem to remember'",
        l3, "no longer seem to remember")

    # ----- Phase 4: Y2 whisper at canon 33 fires ~25% per visit -----
    # Direct hits via _print_room. RNG re-seeded.
    print("Phase 4: Y2 whisper rate (1000 visits, pinned seed)")
    seed(0xC4FE33)
    var d4 := H.make_driver()
    d4.fsm.player.move_to(33)
    var whispers: int = 0
    for _i in range(1000):
        var pre: int = d4.captured.size()
        d4._print_room()
        for line in d4.captured.slice(pre):
            if "hollow voice" in line.to_lower():
                whispers += 1
                break
    print("  observed: %d whispers in 1000 Y2 visits (canon ~250)" % whispers)
    _expect_in_range("whispers in [181, 319] (canon 25% ± 5σ)",
        whispers, 181, 319)

    # ----- Phase 5: Y2 whisper does NOT fire elsewhere -----
    print("Phase 5: hollow whisper does NOT fire at non-Y2 rooms")
    seed(0xC4FE33)
    var d5 := H.make_driver()
    d5.fsm.player.move_to(3)
    var noise: int = 0
    for _i in range(200):
        var pre: int = d5.captured.size()
        d5._print_room()
        for line in d5.captured.slice(pre):
            if "hollow voice" in line.to_lower():
                noise += 1
                break
    _expect("0 whispers at canon room 3 (200 visits)", noise, 0)

    if failures == 0:
        print("PASS — CAVE / Y2 whisper / BACK fallback honor canon")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
