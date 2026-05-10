extends SceneTree

# Verifies canon msg #94 — FIND when the object is visible in the
# player's current room (advent.for STMT 9190 AT(OBJ) branch).
#
# Canon FIND priority:
#   TOTING(OBJ)            → msg #24 ("already carrying")
#   AT(OBJ) (here visible) → msg #94 ("right here with you")
#   CLOSED                 → msg #138 ("around here somewhere")
#   otherwise              → msg #59 ("can only tell you what you see")

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

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-58s line contained banned '%s'" % [
                label, needle])
            failures += 1
            return
    print("  ok   %-58s no line contained '%s'" % [label, needle])

func _init():
    print("=== CCA FIND msg #94 — AT(OBJ) branch ===")

    # ----- Phase 1: KEYS at canon room 3 (well-house) — start placement -----
    # Keys start at canon 3, player starts at canon 1. FIND KEYS
    # at canon 1 → msg #59 (no AT match). Walk to canon 3 → msg #94.
    print("Phase 1: KEYS at well-house — FIND while elsewhere → msg #59")
    var d1 := H.make_driver()
    var l1: Array = H.capture(d1, "find keys")
    _expect_any_match("FIND keys far away → canon msg #59",
        l1, "I can only tell you what you see")

    print("Phase 2: walk to keys' room → FIND keys → canon msg #94")
    d1.fsm.player.move_to(3)            # well-house, where keys live
    var l2: Array = H.capture(d1, "find keys")
    _expect_any_match("FIND keys @ canon 3 → canon msg #94",
        l2, "right here with you")

    # ----- Phase 3: pick up keys → msg #24 (already carrying) -----
    print("Phase 3: TAKE keys → FIND keys → canon msg #24 (already carrying)")
    d1.fsm.keys_item.try_take(3)
    d1.fsm.player.take(d1.fsm.KEYS_ID)
    var l3: Array = H.capture(d1, "find keys")
    _expect_any_match("FIND keys (carrying) → canon msg #24",
        l3, "already carrying")

    # ----- Phase 4: bird at canon 13 (Bird Chamber, port BIRD_HOME_ROOM) -----
    print("Phase 4: bird at canon 13 — FIND bird in room → canon msg #94")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(13)           # canon Bird Chamber
    var l4: Array = H.capture(d2, "find bird")
    _expect_any_match("FIND bird @ canon 13 → canon msg #94",
        l4, "right here with you")

    # ----- Phase 5: treasure (gold) at canon 18 (port gold home) -----
    print("Phase 5: gold at canon 18 — FIND gold in room → canon msg #94")
    var d3 := H.make_driver()
    d3.fsm.player.move_to(18)
    var l5: Array = H.capture(d3, "find gold")
    _expect_any_match("FIND gold @ canon 18 → canon msg #94",
        l5, "right here with you")

    # ----- Phase 6: msg #94 does NOT fire when object isn't here -----
    print("Phase 6: object elsewhere → no msg #94, falls to msg #59")
    var d4 := H.make_driver()
    d4.fsm.player.move_to(2)            # canon hill, no objects
    var l6: Array = H.capture(d4, "find diamond")
    _expect_no_match("no msg #94 when object isn't visible",
        l6, "right here with you")
    _expect_any_match("falls through to canon msg #59",
        l6, "I can only tell you what you see")

    if failures == 0:
        print("PASS — FIND priority ladder honors canon msg #94 AT(OBJ) branch")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
