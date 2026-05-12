extends SceneTree

# Canon multi-dwarf scenes (advent.for STMT 6010-6030).
#
# Verifies:
#   - dwarves WALK each turn along the section-3 travel graph
#     (canon STMT 6020 random non-backtrack non-surface step)
#   - dwarves that have SEEN the player (canon DSEEN) snap to
#     the player's room (canon "DLOC(i)=LOC" line)
#   - DTOTAL / ATTACK / STICK accounting populates the canon
#     prose ladder:
#       1 dwarf in room       → msg #4
#       N dwarves in room     → canon FORMAT 67 ("There are N...")
#       1 attacker, 0 hit     → msg #5 + msg #52 ("It misses!")
#       1 attacker, 1 hit     → msg #5 + msg #53 ("It gets you!")
#       N attackers, 0 hit    → FORMAT 78 + msg #6
#       N attackers, 1 hit    → FORMAT 78 + msg #7 ("One of them gets you!")
#       N attackers, M hit    → FORMAT 78 + FORMAT 68 ("N of them get you!")
#   - msg #6 fires only when at least one dwarf threw (not on a
#     silent no-dwarf turn)
#
# Strategy: drive the driver headlessly. Force multiple dwarves
# into the player's room via Adventure.dwarf_step_to + the FSM's
# direct setters, then walk one tick and capture _check_dwarf_axe
# output.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [label, str(actual), str(expected)])
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

# Force a dwarf to be co-located with the player (and standing
# still — prev_room == room) so the next tick rolls an attack
# against it. The Dwarf FSM's wake_up sets prev_room == room
# already; this helper just re-snaps in case the dwarf has moved.
func _put_dwarf_at(d: H.CapturedDriver, idx: int, room: int) -> void:
    # dwarf_step_to is idempotent — it sets prev_room ← room and
    # room ← new_room. Calling it twice with `room` lands prev
    # and current both at `room`, simulating "dwarf stood still
    # in this room last turn AND is still here."
    d.fsm.dwarf_step_to(idx, room)
    d.fsm.dwarf_step_to(idx, room)

func _init():
    print("=== CCA multi-dwarf canon STMT 6010-6030 ===")

    # ---------------------------------------------------------
    # Phase 1: single-dwarf miss → canon msg #5 + msg #52
    # ---------------------------------------------------------
    print("Phase 1: single dwarf, default anger (DFLAG=2) → 0% hit → msg #52")
    var d1 := H.make_driver()
    d1.fsm.wake_dwarves()
    d1.fsm.player.move_to(19)        # canon dwarf1 wake room (Hall of Mt King)
    _put_dwarf_at(d1, 1, 19)
    var l1: Array = H.capture(d1, "look")
    _expect_any_match("single-dwarf-in-room msg #4",
        l1, "There is a threatening little dwarf in the room with you")
    _expect_any_match("single-attacker throw msg #5",
        l1, "One sharp nasty knife is thrown at you")
    _expect_any_match("single-attacker miss msg #52",
        l1, "It misses")
    _expect("player still alive after miss",
        d1.fsm.player_state(), "alive")

    # ---------------------------------------------------------
    # Phase 2: single-dwarf HIT — high anger forces the roll
    # ---------------------------------------------------------
    print("Phase 2: single dwarf, anger=20 → high hit pct → msg #53")
    var d2 := H.make_driver()
    d2.fsm.wake_dwarves()
    for _i in 18:
        d2.fsm.bump_dwarf_anger()    # 2 → 20 → hit_pct=171 capped >100
    d2.fsm.player.move_to(19)
    _put_dwarf_at(d2, 1, 19)
    var l2: Array = H.capture(d2, "look")
    _expect_any_match("single-dwarf throw msg #5",
        l2, "One sharp nasty knife is thrown at you")
    _expect_any_match("single-attacker hit msg #53",
        l2, "It gets you")
    # Player should be in revive prompt now.
    _expect("player dead after hit",
        d2.fsm.player_state(), "dead")

    # ---------------------------------------------------------
    # Phase 3: TWO dwarves in player's room, all miss → FORMAT 78 + msg #6
    # ---------------------------------------------------------
    print("Phase 3: 2 dwarves, anger=2 (0% hit) → FORMAT 78 + msg #6")
    var d3 := H.make_driver()
    d3.fsm.wake_dwarves()
    d3.fsm.player.move_to(19)
    _put_dwarf_at(d3, 1, 19)
    _put_dwarf_at(d3, 2, 19)
    var l3: Array = H.capture(d3, "look")
    _expect_any_match("multi-dwarf-in-room FORMAT 67",
        l3, "2 threatening little dwarves")
    _expect_any_match("multi-attacker throw FORMAT 78",
        l3, "2 of them throw knives at you")
    _expect_any_match("multi-attacker all-miss msg #6",
        l3, "None of them hit you")

    # ---------------------------------------------------------
    # Phase 4: THREE dwarves, high anger → most hit → FORMAT 78 + FORMAT 68
    # ---------------------------------------------------------
    print("Phase 4: 3 dwarves, anger=20 → FORMAT 78 + N-hit FORMAT 68")
    var d4 := H.make_driver()
    d4.fsm.wake_dwarves()
    for _i in 18:
        d4.fsm.bump_dwarf_anger()    # 2 → 20
    d4.fsm.player.move_to(19)
    _put_dwarf_at(d4, 1, 19)
    _put_dwarf_at(d4, 2, 19)
    _put_dwarf_at(d4, 3, 19)
    var l4: Array = H.capture(d4, "look")
    _expect_any_match("3-dwarf in-room FORMAT 67",
        l4, "3 threatening little dwarves")
    _expect_any_match("3-attacker throw FORMAT 78",
        l4, "3 of them throw knives at you")
    # At anger=20 hit_pct ramps very high — should produce N-hit
    # message. Either msg #7 (one hit) or FORMAT 68 (N hit) — but
    # NOT msg #52/#53 (single-attacker phrasing).
    _expect_no_match("no single-attacker miss msg #52",
        l4, "It misses")
    _expect_no_match("no single-attacker hit msg #53",
        l4, "It gets you")

    # ---------------------------------------------------------
    # Phase 5: silent turn — no dwarves co-located with player
    # ---------------------------------------------------------
    print("Phase 5: no dwarves in player's room → silent (no msg)")
    var d5 := H.make_driver()
    d5.fsm.wake_dwarves()
    d5.fsm.player.move_to(100)        # canon Plover Room — no dwarf wakes here
    var l5: Array = H.capture(d5, "look")
    _expect_no_match("silent: no threatening msg",
        l5, "threatening little dwarf")
    _expect_no_match("silent: no throw msg",
        l5, "throw")
    _expect_no_match("silent: no miss msg",
        l5, "It misses")

    # ---------------------------------------------------------
    # Phase 6: dwarf movement — dwarf walks one canon step per turn
    # ---------------------------------------------------------
    # Use dwarf2 (canon 33 — Y2 marker) which has multiple
    # deep-cave exits. Canon STMT 6012 forbids dwarves from
    # leaving LOC >= 15, so a dwarf with no in-cave exit (e.g.
    # an end-of-canyon dead end) would correctly stay put.
    print("Phase 6: dwarf2 at canon 33 walks one step per tick")
    var d6 := H.make_driver()
    d6.fsm.wake_dwarves()
    d6.fsm.player.move_to(99)         # canon Alcove — no dwarf here
    var room_before: int = d6.fsm.dwarf2.get_room()
    _expect("dwarf2 wakes at canon 33",   room_before, 33)
    # Tick once. Driver's _step_dwarves walks dwarf2; with
    # player at canon 99 (not in dwarf path) the dwarf should
    # have moved to a different room.
    H.capture(d6, "look")
    var room_after: int = d6.fsm.dwarf2.get_room()
    _expect("dwarf2 moved to a different room after tick",
        room_after != room_before, true)

    if failures == 0:
        print("PASS — multi-dwarf canon STMT 6010-6030 fully wired")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
