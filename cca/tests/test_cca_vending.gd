extends SceneTree

# Smoke test for the Vending Machine puzzle.
# Verifies:
#   - Machine starts $Loaded.
#   - INSERT without coins / from wrong room is deflected.
#   - INSERT coins at room 95 consumes them, transitions to
#     $Empty, refreshes the lamp.
#   - The coins are no longer counted toward treasure score
#     (the player traded points for batteries).
#   - Save/restore round-trips machine state + lamp battery.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _expect_contains(label: String, actual: String, fragment: String) -> void:
    if actual.contains(fragment):
        print("  ok   %-44s = (contains %s)" % [label, fragment])
    else:
        print("  FAIL %-44s = '%s' (missing %s)" % [label, actual, fragment])
        failures += 1

func _init():
    print("=== CCA Vending Machine ===")

    # --- Initial conditions ---
    print("Initial — vending machine loaded, coins in canon home:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    _expect("vending loaded",      adv.vending_loaded(),     true)
    _expect("vending state",       adv.vending.get_state(),  "loaded")
    _expect("coins in_room",       adv.coins.get_state(),    "in_room")
    _expect("coins location",      adv.coins.get_location(), 134)

    # --- INSERT without coins ---
    print("INSERT without coins deflects:")
    adv.player.move_to(95)
    var r1 = adv.do_command("insert", "coins")
    _expect_contains("response",   r1, "don't have any coins")
    _expect("still loaded",        adv.vending_loaded(),     true)

    # --- INSERT from wrong room ---
    print("INSERT from wrong room deflects:")
    adv.player.move_to(11)
    var r2 = adv.do_command("insert", "coins")
    _expect_contains("response",   r2, "nothing here")
    _expect("still loaded",        adv.vending_loaded(),     true)

    # --- Pick up coins, drain lamp partially, then insert ---
    print("Pick up coins, run the lamp down a bit, then insert:")
    adv.do_command("light", "")
    adv.player.move_to(134)
    adv.do_command("take", "coins")
    _expect("carrying coins",      adv.player.carrying(adv.COINS_ID), true)
    var bat_before: int = adv.battery_left()
    # Drain a bit
    for i in 50:
        adv.tick()
    var bat_drained: int = adv.battery_left()
    _expect("battery dropped",     bat_drained < bat_before,  true)

    # --- Insert at room 95 ---
    print("Insert at the vending machine room:")
    adv.player.move_to(95)
    var r3 = adv.do_command("insert", "coins")
    _expect_contains("response",   r3, "fresh set of lamp batteries")
    _expect("vending empty",       adv.vending_loaded(),     false)
    _expect("not carrying coins",  adv.player.carrying(adv.COINS_ID), false)
    _expect("coins consumed (loc 0)", adv.coins.get_location(), 0)
    _expect("lamp refreshed",      adv.battery_left(),       330)

    # --- Re-insert deflects (machine is now empty) ---
    print("Re-insert deflects — machine is empty:")
    var r4 = adv.do_command("insert", "coins")
    _expect_contains("empty msg",  r4, "OUT OF BATTERIES")

    # --- Coins not counted toward deposit (consumed, not deposited) ---
    print("Coins are consumed, not deposited — no points:")
    _expect("coins not deposited", adv.coins.is_deposited(), false)

    # --- Save / restore round-trips state ---
    print("Save / restore preserves vending state + refreshed lamp:")
    var bytes = adv.save_state()
    # Mutate: drain the lamp some more
    for i in 100:
        adv.tick()
    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored vending empty", adv2.vending_loaded(), false)
    _expect("restored battery",    adv2.battery_left(),       330)
    _expect("restored coins consumed", adv2.coins.get_location(), 0)

    print()
    if failures == 0:
        print("PASS — vending machine cycle complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
