extends SceneTree

# Verifies four small canon mechanics that close audit gaps:
#
#   ENTER STREAM / ENTER WATER → canon msg #70 (feet wet)
#   LOOK detail counter        → canon msg #15 first 3 times
#   Lamp-out + above-ground    → canon msg #185 forced quit
#                                 (test verifies the msg fires;
#                                 the actual get_tree().quit()
#                                 isn't tested headlessly)

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

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-58s line contained banned '%s'" % [
                label, needle])
            failures += 1
            return
    print("  ok   %-58s no line contained '%s'" % [label, needle])

func _init():
    print("=== CCA lamp-quit + LOOK + ENTER STREAM ===")

    # ----- Phase 1: ENTER STREAM / ENTER WATER -----
    print("Phase 1: ENTER STREAM / ENTER WATER → canon msg #70")
    var d := H.make_driver()
    var l: Array = H.capture(d, "enter stream")
    _expect_any_match("ENTER STREAM emits 'feet are now wet'",
        l, "feet are now wet")
    var l2: Array = H.capture(d, "enter water")
    _expect_any_match("ENTER WATER emits 'feet are now wet'",
        l2, "feet are now wet")

    # ----- Phase 2: LOOK detail counter -----
    print("Phase 2: LOOK detail counter — msg #15 first 3 times only")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(3)
    var msg15_seen: int = 0
    for i in 5:
        var pre: int = d2.captured.size()
        d2._process_input("look")
        var lines: Array = d2.captured.slice(pre)
        for line in lines:
            if "not allowed to give more detail" in line:
                msg15_seen += 1
                break
    _expect("msg #15 fired exactly 3 times in 5 LOOKs", msg15_seen, 3)

    # ----- Phase 3: Lamp-out forced-quit msg fires -----
    # Simulate lamp running out of battery (transition to $Out
    # via the FSM's tick); then move to a room <= 8 and verify
    # canon msg #185 fires. We don't test get_tree().quit()
    # itself — headless tests can't observe that side effect.
    print("Phase 3: lamp-out + above-ground → canon msg #185")
    var d3 := H.make_driver()
    # Drain the lamp via direct FSM tick. Lamp battery is 330
    # (or 1000 with HINTED(3)); brute-force tick until $Out.
    for i in 1100:
        if d3.fsm.lamp.get_state() == "out":
            break
        d3.fsm.lamp.tick()
    _expect("setup: lamp is out",            d3.fsm.lamp.get_state(), "out")
    d3.fsm.player.move_to(3)
    var pre3: int = d3.captured.size()
    d3._check_lamp_warnings()
    var lines3: Array = d3.captured.slice(pre3)
    _expect_any_match("lamp-out at room 3 fires canon msg #185",
        lines3, "call it a day")

    # ----- Phase 4: lamp-out below-ground does NOT trigger quit -----
    print("Phase 4: lamp-out + below-ground (room > 8) does NOT force quit")
    var d4 := H.make_driver()
    for i in 1100:
        if d4.fsm.lamp.get_state() == "out":
            break
        d4.fsm.lamp.tick()
    _expect("setup: lamp is out",            d4.fsm.lamp.get_state(), "out")
    d4.fsm.player.move_to(15)              # canon Hall of Mists, room 15 > 8
    var pre4: int = d4.captured.size()
    d4._check_lamp_warnings()
    var lines4: Array = d4.captured.slice(pre4)
    _expect_no_match("below-ground lamp-out does NOT fire #185",
        lines4, "call it a day")

    if failures == 0:
        print("PASS — lamp-quit / LOOK / ENTER STREAM honor canon")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
