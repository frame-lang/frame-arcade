extends SceneTree

# Verifies the canonical "you can't get the gold up the steps"
# puzzle at canon 15 (Hall of Mists east end). Per cca/canon/
# advent.dat row `15 150022 29 31 34 35 23 43` and the FORTRAN
# spec at canon/advent.for lines 105-122:
#
#   M = 150  → carrying-conditional, obj #50 (GOLD).
#   N = 022  → dest = canon 22 (the dome-unclimbable bouncer).
#   verbs    → 29 UP, 31 PIT, 34 STEPS, 35 DOME, 23 PASSAGE, 43 EAST.
#
# When the player is at 15 carrying the gold nugget, those six
# verbs should all print "The dome is unclimbable." and leave
# the player at 15. When the player is NOT carrying gold, the
# same verbs (only UP has a fall-through canon row at all) walk
# normally to canon 14 (top of small pit).
#
# This test exercises the gate end-to-end:
#   1. With gold in inventory: each blocked verb fires the canon
#      bumper and the player stays at 15.
#   2. With gold in inventory: the OTHER 15: exits (south/north/
#      down/west) still work — the canon row only blocks the
#      six verbs listed above.
#   3. Without gold: 15:up walks normally to 14.
#   4. The gate fires from the bumper-key dispatch (i.e. the
#      driver's `_process_input` path), not just inside the
#      topology lookup — same as the other gates.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-52s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-52s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-52s found '%s'" % [label, needle])
            return
    print("  FAIL %-52s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> H.CapturedDriver:
    var d := H.CapturedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    return d

# Try a movement verb starting at 15 with gold in hand. Returns
# the destination room afterwards and the captured lines from
# that single command. Resets to 15 with gold each time.
func _try_blocked(d: H.CapturedDriver, verb: String) -> Dictionary:
    d.fsm.player.move_to(15)
    if not d.fsm.player.carrying(d.fsm.GOLD_ID):
        d.fsm.player.take(d.fsm.GOLD_ID)
    var pre: int = d.captured.size()
    d._process_input(verb)
    var lines: Array = d.captured.slice(pre)
    return {"room": d.fsm.player_room(), "lines": lines}

func _init():
    print("=== CCA gold-blocks-the-steps (canon 15 / row `15 150022 ...`) ===")

    # Phase 1: with gold, the six canon-blocked verbs all bumper
    # and keep the player at 15.
    print("Phase 1: gold in hand — UP/PIT/STEPS/DOME/PASSAGE/EAST blocked")
    var d := _make_driver()
    d.fsm.do_command("light", "")              # avoid dark-pit interference

    for verb in ["up", "pit", "steps", "dome", "passage", "east"]:
        var r: Dictionary = _try_blocked(d, verb)
        _expect("with gold, %s keeps player at 15" % verb, r.room, 15)
        _expect_any_match("with gold, %s emits dome-bumper" % verb,
            r.lines, "dome is unclimbable")

    # Phase 2: with gold, the other 15: exits still walk.
    # Canon row's blocked-verb list is exactly UP/PIT/STEPS/DOME/
    # PASSAGE/EAST; SOUTH (to 18), NORTH (to 19), DOWN (to 19),
    # and WEST (to 17) are all on separate plain rows and ignore
    # the carrying condition entirely.
    print("Phase 2: gold in hand — south/north/down/west still walk")

    d.fsm.player.move_to(15)
    if not d.fsm.player.carrying(d.fsm.GOLD_ID):
        d.fsm.player.take(d.fsm.GOLD_ID)
    d._process_input("south")
    _expect("with gold, 15:south → 18 (gold-nugget room)",
        d.fsm.player_room(), 18)

    d.fsm.player.move_to(15)
    d._process_input("north")
    _expect("with gold, 15:north → 19 (Hall of Mt King)",
        d.fsm.player_room(), 19)

    d.fsm.player.move_to(15)
    d._process_input("down")
    _expect("with gold, 15:down → 19 (Hall of Mt King)",
        d.fsm.player_room(), 19)

    d.fsm.player.move_to(15)
    d._process_input("west")
    _expect("with gold, 15:west → 17 (east bank fissure)",
        d.fsm.player_room(), 17)

    # Phase 3: without gold, UP walks normally. The canon row
    # `15 14 29` (UP→14) is the ungated fall-through; the other
    # five blocked verbs only exist on the gated row and have
    # no ungated counterpart, so without gold they fall through
    # to the engine's "you can't go that way" path. We only
    # verify UP, since it's the one verb with a real fall-through.
    print("Phase 3: no gold — 15:up walks to 14")
    var d2 := _make_driver()
    d2.fsm.do_command("light", "")
    d2.fsm.player.move_to(15)
    _expect("d2: not carrying gold initially",
        d2.fsm.player.carrying(d2.fsm.GOLD_ID), false)
    d2._process_input("up")
    _expect("without gold, 15:up → 14 (top of small pit)",
        d2.fsm.player_room(), 14)

    # Phase 4: dropping gold at 15 lifts the gate — UP walks
    # again. This is the canonical "drop the gold here, climb
    # up empty-handed, come back via the long-way" out we used
    # to suggest before adding the gate. Now it just confirms
    # the gate is *actually* keyed off carrying-gold, not off
    # gold-existence-anywhere.
    print("Phase 4: gold dropped at 15 — UP walks again")
    var d3 := _make_driver()
    d3.fsm.do_command("light", "")
    d3.fsm.player.move_to(15)
    d3.fsm.player.take(d3.fsm.GOLD_ID)
    _expect("d3: carrying gold", d3.fsm.player.carrying(d3.fsm.GOLD_ID), true)
    d3.fsm.player.drop(d3.fsm.GOLD_ID)
    _expect("d3: dropped gold", d3.fsm.player.carrying(d3.fsm.GOLD_ID), false)
    d3._process_input("up")
    _expect("after dropping gold, 15:up → 14",
        d3.fsm.player_room(), 14)

    if failures == 0:
        print("PASS — gold-blocks-the-steps gate honors canon row 15:150022")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
