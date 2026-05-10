extends SceneTree

# Verifies canon ROD2 prop change (advent.dat object 6 prop
# ladder): the marked rod (ROD2) examines as "a black rod with a
# rusty mark" pre-CLOSED, and reveals as "stick of dynamite" once
# the player is in the endgame repository.

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

func _make_driver_with_mark_rod() -> H.CapturedDriver:
    var d := H.CapturedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    # Place mark_rod (ROD2) at player's room and pick it up so
    # mark_rod_here() returns true regardless of which path the
    # examine handler takes (carried OR same-room).
    var here: int = d.fsm.player_room()
    d.fsm.mark_rod_item.place(here)
    d.fsm.mark_rod_item.try_take(here)
    return d

func _force_repository(d: H.CapturedDriver) -> void:
    # Drive Endgame to $InRepository: deposit triggers + tick.
    for _i in 15:
        d.fsm.endgame.treasure_deposited()
    while d.fsm.endgame_state() == "closing":
        d.fsm.endgame.tick()

func _init():
    print("=== CCA ROD2 prop change — pre-CLOSED rod / post-CLOSED dynamite ===")

    # ----- Phase 1: pre-CLOSED — rod is just a rod -----
    print("Phase 1: pre-CLOSED — EXAMINE ROD → 'rusty mark' flavor")
    var d1 := _make_driver_with_mark_rod()
    var l1: Array = H.capture(d1, "examine rod")
    _expect_any_match("pre-CLOSED rod is 'rusty mark'",
        l1, "rusty mark")
    _expect_no_match("pre-CLOSED rod is NOT yet dynamite",
        l1, "dynamite")

    # ----- Phase 2: $InRepository — rod reveals as dynamite -----
    print("Phase 2: $InRepository — EXAMINE ROD → dynamite flavor")
    var d2 := _make_driver_with_mark_rod()
    _force_repository(d2)
    var l2: Array = H.capture(d2, "examine rod")
    _expect_any_match("post-CLOSED rod reveals dynamite",
        l2, "dynamite")
    _expect_any_match("dynamite warning includes flame caveat",
        l2, "flame")

    # ----- Phase 3: READ ROD also triggers the dynamite reveal -----
    print("Phase 3: READ ROD synonym also reveals dynamite at endgame")
    var d3 := _make_driver_with_mark_rod()
    _force_repository(d3)
    var l3: Array = H.capture(d3, "read rod")
    _expect_any_match("READ ROD post-CLOSED → dynamite",
        l3, "dynamite")

    if failures == 0:
        print("PASS — ROD2 prop change honors canon (advent.dat obj 6)")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
