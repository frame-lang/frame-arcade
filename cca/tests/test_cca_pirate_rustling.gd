extends SceneTree

# Verifies canon msg #127 — pirate "faint rustling noises" hint
# fires ~20% per turn while the pirate is stalking and the
# player is in a deep-cave room (canon LOC>=15).
#
# advent.for STMT 6080-ish: the rustling is a hint that the
# pirate is nearby. We exercise it via the factored
# `_check_pirate_rustle()` helper rather than full
# `_check_pirate_steal` since that path consumes the pirate's
# state on a successful steal.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-58s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-58s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
        failures += 1

func _force_stalking(d: H.CapturedDriver) -> void:
    var here: int = d.fsm.player_room()
    for t in [d.fsm.gold, d.fsm.silver, d.fsm.diamonds]:
        t.reappear(here)
        t.try_take(here)
    d.fsm.player.take(d.fsm.GOLD_ID)
    d.fsm.player.take(d.fsm.SILVER_ID)
    d.fsm.player.take(d.fsm.DIAMONDS_ID)
    d.fsm.pirate.treasures_carried(d.fsm.player.inventory_size())

func _count_rustles(d: H.CapturedDriver) -> int:
    var c: int = 0
    for line in d.captured:
        if "rustling noises" in line:
            c += 1
    return c

func _init():
    print("=== CCA pirate rustling-noise hint — canon msg #127 ===")

    # ----- Phase 1: pirate dormant — no rustling -----
    print("Phase 1: pirate dormant — no rustling")
    seed(0xBEACEFEE)
    var d1 := H.make_driver()
    d1.fsm.player.move_to(15)
    for _i in 200:
        d1._check_pirate_rustle()
    _expect("dormant pirate emits 0 rustles in 200 ticks",
        _count_rustles(d1), 0)

    # ----- Phase 2: pirate stalking @ deep cave — ~20% rate -----
    # σ for 1000 rolls at 20% ≈ 12.6 → ±5σ ≈ ±63 → window [137, 263].
    print("Phase 2: pirate stalking @ canon 15 — ~20% rate (1000 rolls)")
    seed(0xBEACEFEE)
    var d2 := H.make_driver()
    _force_stalking(d2)
    d2.fsm.player.move_to(15)
    _expect("setup: pirate stalking",      d2.fsm.pirate_state(), "stalking")
    for _i in 1000:
        d2._check_pirate_rustle()
    var hits: int = _count_rustles(d2)
    print("  observed: %d rustling hits in 1000 rolls" % hits)
    _expect_in_range("rustling fires in [137, 263] (canon ~20%)",
        hits, 137, 263)

    # ----- Phase 3: pirate stalking @ surface — no rustling -----
    print("Phase 3: pirate stalking @ canon 2 (surface) — no rustling")
    seed(0xBEACEFEE)
    var d3 := H.make_driver()
    _force_stalking(d3)
    d3.fsm.player.move_to(2)
    for _i in 200:
        d3._check_pirate_rustle()
    _expect("surface room emits 0 rustles", _count_rustles(d3), 0)

    # ----- Phase 4: post-steal latch suppresses rustling -----
    print("Phase 4: _pirate_already_stole latch suppresses rustling")
    seed(0xBEACEFEE)
    var d4 := H.make_driver()
    _force_stalking(d4)
    d4.fsm.player.move_to(15)
    d4._pirate_already_stole = true
    for _i in 200:
        d4._check_pirate_rustle()
    _expect("post-steal latch emits 0 rustles", _count_rustles(d4), 0)

    if failures == 0:
        print("PASS — pirate rustling honors canon msg #127")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
