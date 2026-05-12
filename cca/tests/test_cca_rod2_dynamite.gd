extends SceneTree

# Verifies canon ROD2 examine behavior. Canon obj#6 (ROD2) has
# only prop=0 — "A three foot black rod with a rusty mark on an
# end lies nearby." — and NO post-endgame dynamite reveal. The
# port mirrors canon: EXAMINE ROD always returns the rusty-mark
# prose, regardless of $InRepository state. Discovering that the
# rod is dynamite is canonically left to BLAST.

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
    print("=== CCA ROD2 examine — canon obj#6 prop=0 (no dynamite reveal) ===")

    # ----- Phase 1: pre-CLOSED — EXAMINE ROD emits canon rusty-mark prose -----
    print("Phase 1: pre-CLOSED — EXAMINE ROD → canon rusty-mark prose")
    var d1 := _make_driver_with_mark_rod()
    var l1: Array = H.capture(d1, "examine rod")
    _expect_any_match("EXAMINE ROD emits canon obj#6 prose",
        l1, "rusty mark")
    _expect_no_match("port-only dynamite reveal does NOT fire",
        l1, "dynamite")

    # ----- Phase 2: $InRepository — same canon prose, NO dynamite reveal -----
    print("Phase 2: $InRepository — EXAMINE ROD still emits canon prose")
    var d2 := _make_driver_with_mark_rod()
    _force_repository(d2)
    var l2: Array = H.capture(d2, "examine rod")
    _expect_no_match("$InRepository: no port-only dynamite reveal",
        l2, "dynamite")
    _expect_no_match("$InRepository: no flame caveat",
        l2, "flame")

    # ----- Phase 3: READ ROD synonym — canon-aligned, no special endgame branch -----
    print("Phase 3: READ ROD synonym at endgame — canon prose, no dynamite")
    var d3 := _make_driver_with_mark_rod()
    _force_repository(d3)
    var l3: Array = H.capture(d3, "read rod")
    _expect_no_match("READ ROD post-CLOSED has no dynamite reveal",
        l3, "dynamite")

    if failures == 0:
        print("PASS — ROD2 examine honors canon obj#6 (no port-only dynamite reveal)")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
