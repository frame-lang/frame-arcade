extends SceneTree

# ============================================================
# test_cca_canon_conditional_rows.gd
# ============================================================
# Locks in the 6 canon section-3 conditional rows that the
# topology-audit script (/tmp/conditional_audit.py) reports as
# "not in GATES dict." Investigation showed every one of the 6 IS
# canonically handled — just not via the topology GATES dict that
# the audit checks. This test asserts the canonical *behaviour*
# is preserved regardless of architectural routing, so a future
# refactor can't silently break a canon mechanic while still
# making the audit happy.
#
# Maps to canon advent.dat section 3:
#
#   1. `31 524089 1`     — plant-beanstalk climb (room 25 with
#                          plant tall → escape pit, plant tiny →
#                          canon rebuff "nothing here to climb").
#                          Our impl gates 25:up/25:climb directly
#                          and never routes the player through the
#                          canon-phantom room 31.
#   2. `33 159302 71`    — PLOVER at Y2 → teleport to Plover Room.
#                          (Canon verb 71 = PLOVER, not PLUGH —
#                          the audit script had this swapped.)
#   3. `61 100107 46`    — south at long-hall-W → room 107
#                          (unconditional in ROOMS dict).
#   4. `100 159302 71`   — PLOVER at Plover → teleport back to Y2.
#   5. `103 114618 46`   — south at Shell Room carrying clam:
#                          canon msg #118 fires, no movement.
#   6. `103 115619 46`   — south at Shell Room carrying oyster:
#                          canon msg #119 fires, no movement.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _init():
    print("=== CCA canon-conditional-row behavioural locks ===")
    print("")

    _test_plant_climb_rebuff()
    _test_plant_climb_success()
    _test_y2_plover_to_plover_room()
    _test_room_61_south_to_107()
    _test_plover_plover_to_y2()
    _test_clam_south_rebuff()
    _test_oyster_south_rebuff()

    print("")
    if failures == 0:
        print("PASS — all 7 canon conditional behaviours preserved")
        quit(0)
        return
    print("FAIL — %d canon conditional behaviour(s) diverge" % failures)
    quit(failures)

# Row `31 524089 1` half A: plant tiny / not tall → rebuff at room 25.
func _test_plant_climb_rebuff():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(25)
    # Plant defaults to $Tiny on a fresh FSM — no pour-water yet.
    var pre_room: int = d.fsm.player_room()
    d._process_input("up")
    var post_room: int = d.fsm.player_room()
    _assert("plant-tiny + 25:up stays put",      pre_room, post_room)
    _assert_captured("plant-tiny rebuff message", d, "nothing here to climb")

# Row `31 524089 1` half B: plant tall → climb succeeds, escape pit.
# Plant grows on water() — one pour for tall, two for huge.
func _test_plant_climb_success():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(25)
    d.fsm.plant.water()  # $Tiny → $Tall
    d._process_input("up")
    # Canon: climbing the tall plant escapes West Pit; the port
    # routes the player directly through to where canon's
    # phantom routing-room 31 would send them next.
    _assert("plant-tall + 25:up escapes pit (not still at 25)",
        d.fsm.player_room() != 25, true)

# Row `33 159302 71`: canon verb 71 = PLOVER. PLOVER at Y2 →
# Plover Room (canon 100). Audit script's verb table had 71
# mapped to "plugh" — that's the bug. Implementation handles
# PLOVER at Y2 → 100 correctly via the magic-word aspect.
func _test_y2_plover_to_plover_room():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(33)
    d._process_input("plover")
    _assert("PLOVER at Y2 → Plover Room (canon 100)", d.fsm.player_room(), 100)

# Row `61 100107 46`: SOUTH at canon 61 → room 107 unconditionally.
func _test_room_61_south_to_107():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(61)
    d._process_input("south")
    _assert("SOUTH at canon 61 → room 107", d.fsm.player_room(), 107)

# Row `100 159302 71`: canon verb 71 = PLOVER. PLOVER at Plover
# Room → back to Y2 (canon 33). Handled by the magic-word aspect.
func _test_plover_plover_to_y2():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(100)
    d._process_input("plover")
    _assert("PLOVER at Plover → Y2 (canon 33)", d.fsm.player_room(), 33)

# Row `103 114618 46`: SOUTH at Shell Room carrying clam → msg #118 + stay.
func _test_clam_south_rebuff():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(103)
    d.fsm.clam_item.try_take(103)
    d.fsm.player.take(d.fsm.CLAM_ID)
    var pre_room: int = d.fsm.player_room()
    d._process_input("south")
    _assert("clam-carrying + 103:south stays put",
        pre_room, d.fsm.player_room())
    # Canon msg #118 — the prose varies by port; assert against the
    # canon-distinctive phrase rather than exact match.
    _assert_captured("clam-carry rebuff prose", d, "clam")

# Row `103 115619 46`: SOUTH at Shell Room carrying oyster → msg #119.
func _test_oyster_south_rebuff():
    var d: H.CapturedDriver = H.make_driver()
    d.fsm.player.move_to(103)
    # The oyster is dynamic-spawn; reach it via canon BREAK CLAM.
    d.fsm.clam_item.try_take(103)
    d.fsm.player.take(d.fsm.CLAM_ID)
    d.fsm.player.drop(d.fsm.CLAM_ID)
    d.fsm.clam_item.try_drop(103)
    d._process_input("break clam")
    # Now oyster is in-room at 103. Pick it up.
    d.fsm.oyster_item.try_take(103)
    d.fsm.player.take(d.fsm.OYSTER_ID)
    var pre_room: int = d.fsm.player_room()
    d._process_input("south")
    _assert("oyster-carrying + 103:south stays put",
        pre_room, d.fsm.player_room())
    _assert_captured("oyster-carry rebuff prose", d, "oyster")

# ----- Test helpers ----------------------------------------------

func _assert(label: String, observed, expected) -> void:
    if observed == expected:
        print("  [OK] %s" % label)
    else:
        print("  [FAIL] %s — expected %s, observed %s" % [
            label, str(expected), str(observed)])
        failures += 1

func _assert_captured(label: String, d: H.CapturedDriver, needle: String) -> void:
    var hit: bool = false
    for line in d.captured:
        if needle in line.to_lower():
            hit = true
            break
    if hit:
        print("  [OK] %s (matched '%s')" % [label, needle])
    else:
        print("  [FAIL] %s — '%s' not in captured output" % [label, needle])
        failures += 1
