extends SceneTree

# Verifies the canon BACK / RETREAT verb (advent.for STMT 20-25).
# Canonical semantics:
#   - Walk the player from LOC back to OLDLOC by finding any
#     exit that goes there.
#   - If OLDLOC was a forced-motion room, fall through to
#     OLDLC2 (the room before the bouncer).
#   - If no path exists from LOC back to the target, msg #140
#     "I no longer seem to remember how it was you got here."
#   - If LOC == target, msg #91 "Where?"
#
# Driver tracks _old_loc / _old_loc2 in `_handle_movement` and
# `_walk_to_dest` before each move, so BACK has a current
# history.

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

func _init():
    print("=== CCA BACK verb (canon advent.for STMT 20-25) ===")

    # ----- Phase 1: simple BACK after a normal move -----
    # Walk 3 → west → 1 (well house → end of road), then BACK
    # → should walk back to 3 via the EAST exit at 1.
    print("Phase 1: BACK after a normal move (3 → west → 1, BACK → 3)")
    var d := H.make_driver()
    d.fsm.player.move_to(3)
    d._process_input("west")               # walks 3 → 1
    _expect("setup: walked 3 → 1",         d.fsm.player_room(), 1)
    d._process_input("back")
    _expect("BACK from 1 walks to 3",      d.fsm.player_room(), 3)

    # ----- Phase 2: BACK with no history → "remember how" -----
    print("Phase 2: BACK with no movement history → canon msg #140")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(3)
    var l: Array = H.capture(d2, "back")
    _expect_any_match("BACK with no history emits canon 'remember how'",
        l, "no longer seem to remember")

    # ----- Phase 3: BACK from a forced-room escape verb -----
    # Forced rooms (16, 22, 26, 32, 40, 59, 79, 89, 90, 113)
    # have explicit `back` topology exits. Verify the topology
    # path takes precedence over the OLDLOC compute.
    print("Phase 3: BACK from forced room (canon 22 → 15 via topology)")
    var d3 := H.make_driver()
    d3.fsm.player.move_to(22)
    d3._process_input("back")
    _expect("BACK from 22 walks to 15",    d3.fsm.player_room(), 15)

    # ----- Phase 4: RETREAT alias routes to BACK -----
    print("Phase 4: RETREAT alias")
    var d4 := H.make_driver()
    d4.fsm.player.move_to(3)
    d4._process_input("north")             # 3 → 1
    d4._process_input("retreat")           # alias for BACK
    _expect("RETREAT from 1 walks to 3",   d4.fsm.player_room(), 3)

    # ----- Phase 5: BACK after multiple moves uses _old_loc -----
    # 3 → north → 1 → south → 3 → north → 1, then BACK should
    # walk to 3 (the most recent _old_loc).
    print("Phase 5: BACK uses most recent _old_loc")
    var d5 := H.make_driver()
    d5.fsm.player.move_to(3)
    d5._process_input("west")              # 3 → 1
    d5._process_input("east")              # 1 → 3
    _expect("d5: walked back to 3 via east",   d5.fsm.player_room(), 3)
    d5._process_input("west")              # 3 → 1
    _expect("d5: at 1 again",                  d5.fsm.player_room(), 1)
    d5._process_input("back")
    _expect("BACK after sequence walks to 3",  d5.fsm.player_room(), 3)

    if failures == 0:
        print("PASS — BACK verb honors canon advent.for STMT 20-25")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
