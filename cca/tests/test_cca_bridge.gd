extends SceneTree

# Smoke test for the rod + crystal-bridge puzzle (Round 5).
# Verifies:
#   - Rod is initially in the debris room (room 2), uncarried.
#   - Wave-without-rod gets a deflection, no bridge.
#   - Wave-with-rod-anywhere-but-fissure gets a deflection.
#   - Wave-with-rod-at-fissure (room 24) summons the bridge.
#   - Wave again toggles the bridge back to $NoBridge.
#   - Save/restore round-trips both rod state and bridge FSM
#     compartment.

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
    print("=== CCA Round 5: rod + crystal bridge ===")

    # --- Initial conditions ---
    print("Initial — rod is in the debris room, bridge not built:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    _expect("rod not carried",       adv.rod_in_inventory(),       false)
    _expect("rod location",          adv.rod_item.get_location(),             11)
    _expect("bridge not built",      adv.bridge_built(),           false)
    _expect("bridge state",          adv.crystal_bridge.get_state(), "no_bridge")

    # --- Wave without rod ---
    print("Wave without rod gets a deflection:")
    var r1 = adv.do_command("wave", "rod")
    _expect_contains("response",     r1, "don't have")
    _expect("still no bridge",       adv.bridge_built(),           false)

    # --- Take the rod ---
    print("Take the rod from the debris room:")
    adv.do_command("light", "")
    adv.player.move_to(11)
    var r2 = adv.do_command("take", "rod")
    _expect_contains("take response", r2, "OK")
    _expect("rod carried",           adv.rod_in_inventory(),       true)

    # --- Wave-with-rod-elsewhere ---
    print("Wave with rod, but not at the fissure → no bridge:")
    var r3 = adv.do_command("wave", "rod")
    _expect_contains("response",     r3, "Nothing happens")
    _expect("still no bridge",       adv.bridge_built(),           false)

    # --- At the fissure with the rod, wave → bridge ---
    print("At the fissure with the rod, wave → bridge appears:")
    adv.player.move_to(17)
    var r4 = adv.do_command("wave", "rod")
    _expect_contains("response",     r4, "crystal bridge now spans")
    _expect("bridge built",          adv.bridge_built(),           true)
    _expect("bridge state",          adv.crystal_bridge.get_state(), "built")

    # --- Wave again toggles it back ---
    print("Wave again — bridge fades:")
    var r5 = adv.do_command("wave", "rod")
    _expect_contains("response",     r5, "shimmers and vanishes")
    _expect("bridge gone",           adv.bridge_built(),           false)

    # --- Wave non-rod ---
    print("Wave something else — flat deflection:")
    var r6 = adv.do_command("wave", "hand")
    _expect_contains("response",     r6, "Waving that")

    # --- Save / restore ---
    print("Save with bridge built, mutate, restore:")
    adv.do_command("wave", "rod")               # build it again
    _expect("bridge built pre-save", adv.bridge_built(),            true)
    var bytes = adv.save_state()

    # Mutate after save
    adv.do_command("wave", "rod")               # tear it down
    _expect("bridge gone post-save", adv.bridge_built(),            false)

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored bridge built", adv2.bridge_built(),           true)
    _expect("restored rod carried",  adv2.rod_in_inventory(),       true)

    # --- Drop the rod, leave it in the fissure room ---
    print("Drop the rod — it stays where dropped:")
    var r7 = adv2.do_command("drop", "rod")
    _expect_contains("drop response", r7, "OK")
    _expect("rod not carried",       adv2.rod_in_inventory(),       false)
    _expect("rod at fissure",        adv2.rod_item.get_location(),             17)

    print()
    if failures == 0:
        print("PASS — bridge puzzle complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
