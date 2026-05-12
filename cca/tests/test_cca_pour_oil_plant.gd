extends SceneTree

# Verifies canon msg #112 — POUR oil at the West Pit plant
# emits the canonical rebuff:
#
#   "The plant indignantly shakes the oil off its leaves and
#    asks, 'Water?'"
#
# advent.for STMT 9220ish: when the player pours OIL at the
# plant's room, msg #112 fires. The plant doesn't grow.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_contains(label: String, s: String, needle: String) -> void:
    if needle in s:
        print("  ok   %-58s found '%s'" % [label, needle])
    else:
        print("  FAIL %-58s '%s' not in '%s'" % [label, needle, s])
        failures += 1

func _make_with_oil() -> Object:
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    # Player picks up the bottle from canon 3.
    adv.player.move_to(3)
    adv.bottle_item.try_take(3)
    adv.player.take(adv.BOTTLE_ID)
    # Empty (in case it had water).
    if adv.bottle.has_water() or adv.bottle.has_oil():
        adv.do_command("pour", "")
    # Walk to the canon oil source (24, Bottom of Eastern Pit).
    adv.player.move_to(24)
    adv.do_command("fill", "bottle")
    return adv

func _init():
    print("=== CCA POUR oil at plant — canon msg #112 ===")

    # ----- Phase 1: POUR oil at West Pit (canon 25) → msg #112 -----
    print("Phase 1: POUR oil @ West Pit (canon 25) → canon msg #112")
    var adv = _make_with_oil()
    _expect("setup: bottle has oil",          adv.bottle.has_oil(),       true)
    adv.player.move_to(25)                    # canon West Pit
    var msg: String = adv.do_command("pour", "")
    _expect_contains("POUR oil @ 25 emits 'indignantly shakes the oil'",
        msg, "indignantly shakes the oil")
    _expect_contains("msg includes 'Water?' rebuff",
        msg, "Water?")
    # Plant did NOT grow — should still be tiny.
    _expect("plant state unchanged",          adv.plant.get_state(),      "tiny")
    # Bottle is now empty (the pour fired).
    _expect("bottle drained",                 adv.bottle.has_oil(),       false)

    # ----- Phase 2: POUR oil elsewhere → no plant msg, just spills -----
    print("Phase 2: POUR oil elsewhere → no #112, just spills")
    var adv2 = _make_with_oil()
    adv2.player.move_to(50)                   # canon dry maze
    var msg2: String = adv2.do_command("pour", "")
    var saw_plant_msg: bool = "indignantly" in msg2
    _expect("no plant msg fires elsewhere",   saw_plant_msg,              false)

    # ----- Phase 3: POUR water still grows plant (regression check) -----
    print("Phase 3: POUR water @ 25 still grows plant (regression)")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.do_command("light", "")
    adv3.player.move_to(3)
    adv3.bottle_item.try_take(3)
    adv3.player.take(adv3.BOTTLE_ID)
    adv3.do_command("fill", "bottle")         # water at canon 3 (well-house)
    _expect("setup: bottle has water",        adv3.bottle.has_water(),    true)
    adv3.player.move_to(25)
    var msg3: String = adv3.do_command("pour", "")
    # Canon: POUR water at West Pit emits the plant grow message
    # directly (canon obj#PLANT prop=1 "THE PLANT SPURTS INTO
    # FURIOUS GROWTH..."). The earlier port "The water soaks into
    # the soil." prefix was port flavor.
    _expect_contains("POUR water @ 25 emits plant-grow msg",
        msg3, "spurts into furious growth")
    _expect("plant state advanced",           adv3.plant.get_state(),     "tall")

    if failures == 0:
        print("PASS — POUR oil at plant honors canon msg #112")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
