extends SceneTree

# Verifies canon-aligned liquid source rooms (advent.for LIQLOC):
#
#   Water sources: canon 1, 3, 4, 7, 38, 95, 113
#                  (port also keeps 83/84 from a pre-canon iter)
#   Oil source:    canon 24 (Bottom of Eastern Pit, "small pool
#                  of oil in one corner")
#
# FILL bottle at any of these rooms transitions the bottle FSM
# from $Empty to $Water or $Oil.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _make_with_bottle() -> Object:
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    # The bottle's home room is canon 3 (well-house). Force-take
    # by setting the player there momentarily, then try_take the
    # item and update inventory.
    adv.player.move_to(3)
    adv.bottle_item.try_take(3)
    adv.player.take(adv.BOTTLE_ID)
    # Empty the bottle so each FILL test starts clean.
    if adv.bottle.has_water() or adv.bottle.has_oil():
        adv.do_command("pour", "")
    return adv

func _test_fill_water_at(room: int) -> void:
    var adv = _make_with_bottle()
    adv.player.move_to(room)
    adv.do_command("fill", "bottle")
    _expect("FILL water @ canon %d" % room, adv.bottle.has_water(), true)

func _test_fill_oil_at(room: int) -> void:
    var adv = _make_with_bottle()
    adv.player.move_to(room)
    adv.do_command("fill", "bottle")
    _expect("FILL oil @ canon %d" % room, adv.bottle.has_oil(), true)

func _init():
    print("=== CCA liquid sources (canon advent.for LIQLOC) ===")

    # Canon water sources
    print("Water sources — canon LIQLOC rooms:")
    _test_fill_water_at(1)        # canon road outside
    _test_fill_water_at(3)        # canon inside building
    _test_fill_water_at(4)        # canon valley stream
    _test_fill_water_at(7)        # canon slit in streambed
    _test_fill_water_at(38)       # canon bottom of pit with stream
    _test_fill_water_at(95)       # canon magnificent cavern
    _test_fill_water_at(113)      # canon edge of reservoir

    # Port-pragmatic alternates
    print("Port alternate water rooms (kept for back-compat):")
    _test_fill_water_at(83)
    _test_fill_water_at(84)

    # Canon oil source (was previously canon 105 in the port)
    print("Oil source — canon Bottom of Eastern Pit (room 24):")
    _test_fill_oil_at(24)

    # Negative case — non-source room should not yield liquid.
    print("Non-source negative case:")
    var adv = _make_with_bottle()
    adv.player.move_to(50)        # canon first-maze, dry room
    adv.do_command("fill", "bottle")
    _expect("FILL @ canon 50 (dry maze) — no water", adv.bottle.has_water(), false)
    _expect("FILL @ canon 50 (dry maze) — no oil",   adv.bottle.has_oil(),   false)

    if failures == 0:
        print("PASS — liquid sources honor canon LIQLOC")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
