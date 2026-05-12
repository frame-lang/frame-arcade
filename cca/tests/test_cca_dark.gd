extends SceneTree

# Smoke test for the Player FSM, DarknessGate aspect, and the
# Adventure orchestrator's bus dispatch loop.
#
# Verifies:
#   1. Initial registration via setup_default_aspects().
#   2. do_command in a lit room: bus passes, base handles.
#   3. do_command "move" transitions player into a dark room.
#   4. In darkness with lamp off: DarknessGate consumes "look"
#      and "examine" with the canon "pitch dark" message.
#   5. Lighting the lamp suppresses the gate (event passes).
#   6. Counter on the aspect tracks consumes accurately.
#   7. Player die/revive cycles + permadeath threshold.
#   8. @@[persist] round-trips bus + aspects + lamp + player.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Player + DarknessGate + Bus dispatch ===")

    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Initial state — end-of-road (1) is lit, lamp off:")
    _expect("room",                adv.player_room(),             1)
    _expect("dark now?",           adv.room_is_dark_now(),        false)
    _expect("lamp lit?",           adv.is_lit(),                  false)

    print("look in lit room (passes bus, base handles):")
    var r1 = adv.do_command("look", "")
    _expect("look response contains 'BUILDING'", r1.contains("BUILDING"), true)
    _expect("darkness consumed",   adv.darkness_consumed_count(), 0)

    print("Move into the cave (debris room, dark with lamp off):")
    adv.player.move_to(11)
    _expect("room after move",     adv.player_room(),             11)
    _expect("dark now?",           adv.room_is_dark_now(),        true)

    print("look in dark with lamp off (consumed by DarknessGate):")
    var r2 = adv.do_command("look", "")
    _expect("look response",       r2, "It is now pitch dark. If you proceed you will likely fall into a pit.")
    _expect("darkness consumed",   adv.darkness_consumed_count(), 1)

    print("examine also gated:")
    var r3 = adv.do_command("examine", "wall")
    _expect("examine response",    r3, "It is now pitch dark. If you proceed you will likely fall into a pit.")
    _expect("darkness consumed",   adv.darkness_consumed_count(), 2)

    print("light lamp, then look — passes through:")
    adv.do_command("light", "")
    _expect("lamp lit?",           adv.is_lit(),                  true)
    _expect("dark now?",           adv.room_is_dark_now(),        false)
    var r4 = adv.do_command("look", "")
    _expect("look response (lit) contains 'DEBRIS'", r4.contains("DEBRIS"), true)
    _expect("darkness consumed",   adv.darkness_consumed_count(), 2)

    print("save mid-state, mutate, restore:")
    var bytes = adv.save_state()
    print("  save bytes: %d" % bytes.size())

    # Mutate after save
    adv.extinguish_lamp()
    adv.do_command("look", "")     # consumes; bumps to 3
    _expect("post-save consumed",  adv.darkness_consumed_count(), 3)

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored room",       adv2.player_room(),             11)
    _expect("restored lamp lit",   adv2.is_lit(),                  true)
    _expect("restored consumed",   adv2.darkness_consumed_count(), 2)
    var r5 = adv2.do_command("look", "")
    _expect("restored look contains 'DEBRIS'", r5.contains("DEBRIS"), true)
    _expect("restored consumed++", adv2.darkness_consumed_count(), 2)

    print("Player death/revive lifecycle on a fresh adventure:")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.player.move_to(47)
    adv3.player.die()
    _expect("after 1st death",     adv3.player_state(),    "dead")
    _expect("deaths",              adv3.player.get_deaths(),  1)
    adv3.player.revive()
    _expect("after revive",        adv3.player_state(),    "alive")
    _expect("revived to start",    adv3.player_room(),     1)
    _expect("inventory dropped",   adv3.player.inventory_size(), 0)

    # 2nd, 3rd deaths recoverable
    adv3.player.die(); adv3.player.revive()
    adv3.player.die(); adv3.player.revive()
    _expect("after 3rd revive",    adv3.player_state(),    "alive")
    _expect("deaths total",        adv3.player.get_deaths(), 3)

    # 4th death is permanent
    adv3.player.die()
    _expect("after 4th death",     adv3.player_state(),    "permadead")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
