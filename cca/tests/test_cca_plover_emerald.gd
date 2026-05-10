extends SceneTree

# Verifies canon routine 302 — Plover-emerald drop (advent.for
# STMT 30200, plus section-3 rows `33 159302 71` and
# `100 159302 71`). When the player invokes PLOVER from canon
# Y2 (33) or Plover Room (100) while carrying the emerald
# (canon obj #59), the emerald is dropped at the current room
# *before* the teleport fires — leaving the player on the
# other side without the emerald, forced to use the canon
# routine 301 squeeze (99↔100) to retrieve it.
#
# This is the last canon special routine to land. With it the
# port honors all three routines (301, 302, 303).

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
    print("=== CCA canon routine 302 — Plover-emerald drop ===")

    # ----- Phase 1: PLOVER from Y2 carrying emerald -----
    print("Phase 1: PLOVER from Y2 (33) carrying emerald")
    var d := H.make_driver()
    d.fsm.player.move_to(33)
    # Acquire emerald via Treasure FSM + player inventory.
    d.fsm.emerald.reappear(33)
    d.fsm.emerald.try_take(33)
    d.fsm.player.take(d.fsm.EMERALD_ID)
    _expect("setup: at Y2 (33) carrying emerald",
        [d.fsm.player_room(), d.fsm.player.carrying(d.fsm.EMERALD_ID)],
        [33, true])
    var l: Array = H.capture(d, "plover")
    _expect_any_match("PLOVER emits canon emerald-drop prose",
        l, "slips from your grasp")
    _expect("PLOVER teleports player to Plover Room (100)",
        d.fsm.player_room(), 100)
    _expect("PLOVER routine 302: emerald no longer in inventory",
        d.fsm.player.carrying(d.fsm.EMERALD_ID), false)
    _expect("PLOVER routine 302: emerald left at canon 33",
        d.fsm.emerald.get_location(), 33)

    # ----- Phase 2: PLOVER from Plover Room carrying emerald -----
    # Symmetric mirror — emerald drops at 100, player teleports
    # to 33.
    print("Phase 2: PLOVER from Plover Room (100) carrying emerald")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(100)
    d2.fsm.emerald.reappear(100)
    d2.fsm.emerald.try_take(100)
    d2.fsm.player.take(d2.fsm.EMERALD_ID)
    _expect("setup: at Plover (100) carrying emerald",
        [d2.fsm.player_room(), d2.fsm.player.carrying(d2.fsm.EMERALD_ID)],
        [100, true])
    var l2: Array = H.capture(d2, "plover")
    _expect_any_match("PLOVER emits canon emerald-drop prose (mirror)",
        l2, "slips from your grasp")
    _expect("PLOVER teleports player to Y2 (33)",
        d2.fsm.player_room(), 33)
    _expect("PLOVER routine 302 mirror: emerald left at canon 100",
        d2.fsm.emerald.get_location(), 100)

    # ----- Phase 3: PLOVER without emerald — no special handling -----
    print("Phase 3: PLOVER without emerald — regular teleport (no msg)")
    var d3 := H.make_driver()
    d3.fsm.player.move_to(33)
    var l3: Array = H.capture(d3, "plover")
    _expect("PLOVER without emerald: walks to 100",
        d3.fsm.player_room(), 100)
    for line in l3:
        if "slips from your grasp" in line:
            _expect("PLOVER without emerald: NO emerald-drop msg fires",
                false, true)
    print("  ok   PLOVER without emerald: no emerald-drop msg fires")

    if failures == 0:
        print("PASS — Plover-emerald drop honors canon routine 302 (advent.for STMT 30200)")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
