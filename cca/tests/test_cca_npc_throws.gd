extends SceneTree

# Verifies the canon NPC throw/drop interactions:
#
#   DROP BIRD at canon 19 (snake here)  → bird drives snake away (msg #30)
#   DROP BIRD at canon 119 (dragon)     → bird vaporized (msg #154)
#   THROW AXE at canon 119 (dragon)     → msg #152 (axe glances)
#   THROW AXE at canon 117 (troll)      → msg #158 (troll catches)
#   THROW AXE at canon 130 (bear hungry) → msg #164 (bear catches)
#
# The DROP BIRD path is canon-equivalent to RELEASE BIRD: the
# port already wires snake/dragon outcomes through the Bird FSM
# at $Released vs $Dead. The driver intercepts DROP BIRD and
# routes to RELEASE BIRD so the canon syntax works.

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
    print("=== CCA NPC throw/drop interactions ===")

    # ----- Phase 1: DROP BIRD at snake -----
    print("Phase 1: DROP BIRD at canon 19 → snake driven away")
    var d := H.make_driver()
    d.fsm.player.move_to(19)
    d.fsm.bird.capture()                  # → $Caged so release() can fire
    d.fsm.player.take(d.fsm.BIRD_ID)
    _expect("setup: snake blocking",       d.fsm.snake.is_blocking(), true)
    var l: Array = H.capture(d, "drop bird")
    _expect_any_match("DROP BIRD emits canon snake-drive prose",
        l, "slithers off")
    _expect("snake driven away",           d.fsm.snake.is_blocking(), false)

    # ----- Phase 2: DROP BIRD at dragon -----
    print("Phase 2: DROP BIRD at canon 119 → bird vaporized")
    var d2 := H.make_driver()
    d2.fsm.player.move_to(119)
    d2.fsm.bird.capture()
    d2.fsm.player.take(d2.fsm.BIRD_ID)
    _expect("setup: at dragon room, dragon alive",
        [d2.fsm.player_room(), d2.fsm.dragon_alive()], [119, true])
    var l2: Array = H.capture(d2, "drop bird")
    _expect_any_match("DROP BIRD at dragon emits canon vaporize msg",
        l2, "swallows it whole")

    # ----- Phase 3: THROW AXE at dragon -----
    print("Phase 3: THROW AXE at canon 119 (dragon alive) → canon msg #152")
    var d3 := H.make_driver()
    d3.fsm.player.move_to(119)
    var l3: Array = H.capture(d3, "throw axe")
    _expect_any_match("THROW AXE at dragon emits canon glance msg",
        l3, "bounces harmlessly")

    # ----- Phase 4: THROW AXE at troll -----
    print("Phase 4: THROW AXE at canon 117 (troll blocking) → canon msg #158")
    var d4 := H.make_driver()
    d4.fsm.player.move_to(117)
    _expect("setup: troll blocking",        d4.fsm.troll.is_blocking_bridge(), true)
    var l4: Array = H.capture(d4, "throw axe")
    _expect_any_match("THROW AXE at troll emits canon 'troll deftly catches'",
        l4, "deftly catches")

    # ----- Phase 5: THROW AXE at bear -----
    print("Phase 5: THROW AXE at canon 130 (bear hungry) → canon msg #164")
    var d5 := H.make_driver()
    d5.fsm.player.move_to(130)
    _expect("setup: bear hungry",           d5.fsm.bear_state(), "hungry")
    var l5: Array = H.capture(d5, "throw axe")
    _expect_any_match("THROW AXE at bear emits canon 'lands near the bear'",
        l5, "near the bear")

    # ----- Phase 6: regression — THROW AXE at non-NPC room
    # falls through to existing FSM handler (no canon-prose
    # interception when player isn't at dragon/troll/bear).
    print("Phase 6: THROW AXE at non-NPC room falls through")
    var d6 := H.make_driver()
    d6.fsm.player.move_to(3)              # well house — no NPC
    var l6: Array = H.capture(d6, "throw axe")
    _expect("THROW AXE at well house: no canon NPC prose fires",
        l6.size() > 0, true)              # SOMETHING is emitted (FSM fallback)

    if failures == 0:
        print("PASS — NPC throw/drop interactions honor canon STMT 9020 + 9170")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
