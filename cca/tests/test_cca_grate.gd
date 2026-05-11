extends SceneTree

# Smoke test for the Grate + keys puzzle.
# Verifies:
#   - Grate starts $Locked; keys live in the well house (room 3).
#   - UNLOCK without keys deflects.
#   - Take keys, return to depression (8), UNLOCK works.
#   - LOCK after re-locks.
#   - Save/restore round-trips both grate state and keys carrying.

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
    print("=== CCA Grate + keys puzzle ===")

    # --- Initial conditions ---
    print("Initial — grate locked, keys in well house, not carried:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    _expect("grate locked",        adv.grate_locked(),       true)
    _expect("grate state",         adv.grate.get_state(),    "locked")
    _expect("keys not carried",    adv.keys_in_inventory(),  false)
    _expect("keys location",       adv.keys_item.get_location(),        3)

    # --- Unlock without keys ---
    print("UNLOCK without keys deflects:")
    adv.player.move_to(8)                    # depression
    var r1 = adv.do_command("unlock", "grate")
    # Canon msg #31 — "You have no keys!"
    _expect_contains("response",   r1, "no keys")
    _expect("still locked",        adv.grate_locked(),       true)

    # --- UNLOCK from wrong room ---
    print("UNLOCK at the wrong room deflects:")
    adv.player.move_to(11)                   # debris
    var r2 = adv.do_command("unlock", "grate")
    # Canon msg #28 — "There is nothing here with a lock!"
    _expect_contains("response",   r2, "nothing here with a lock")

    # --- Take keys ---
    print("Take keys from the well house:")
    adv.player.move_to(3)
    var r3 = adv.do_command("take", "keys")
    _expect_contains("take response", r3, "OK")
    _expect("keys carried",        adv.keys_in_inventory(),  true)

    # --- Move to grate, UNLOCK ---
    print("With keys, UNLOCK at the grate works:")
    adv.player.move_to(8)
    var r4 = adv.do_command("unlock", "grate")
    _expect_contains("response",   r4, "now unlocked")
    _expect("grate unlocked",      adv.grate_locked(),       false)
    _expect("grate state",         adv.grate.get_state(),    "unlocked")

    # --- OPEN as synonym ---
    print("OPEN is a synonym for UNLOCK:")
    var rA = adv.do_command("lock", "grate")
    _expect_contains("re-locked",  rA, "now locked")
    var rB = adv.do_command("open", "grate")
    _expect_contains("open works", rB, "now unlocked")

    # --- LOCK re-locks ---
    print("LOCK re-locks the grate:")
    var r5 = adv.do_command("lock", "grate")
    _expect_contains("response",   r5, "now locked")
    _expect("grate locked again",  adv.grate_locked(),       true)

    # --- Drop keys, leave them at depression ---
    print("Drop keys at the depression:")
    var r6 = adv.do_command("drop", "keys")
    _expect_contains("drop response", r6, "OK")
    _expect("keys not carried",    adv.keys_in_inventory(),  false)
    _expect("keys at depression",  adv.keys_item.get_location(),        8)

    # --- Save / restore mid-puzzle ---
    print("Save / restore mid-puzzle preserves state:")
    adv.do_command("take", "keys")
    adv.do_command("unlock", "grate")
    _expect("pre-save unlocked",   adv.grate_locked(),       false)
    var bytes = adv.save_state()
    adv.do_command("lock", "grate")
    adv.do_command("drop", "keys")

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored unlocked",   adv2.grate_locked(),      false)
    _expect("restored keys carried", adv2.keys_in_inventory(), true)

    print()
    if failures == 0:
        print("PASS — grate puzzle complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
