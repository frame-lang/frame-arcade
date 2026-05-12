extends SceneTree

# Smoke test for the fragile-treasure path. Vase is the only
# fragile treasure in CCA; dropping it anywhere except the
# deposit room (well house, room 3) shatters it. Once broken,
# it can't be re-taken, has zero value, and the $Broken state
# round-trips through @@[persist].
#
# Verifies:
#   - Vase starts $InRoom in the Oriental Room (room 97).
#   - Take vase → $Carried.
#   - Drop vase outside deposit room → $Broken, response
#     contains "broken" / "shattered" / similar.
#   - Take from $Broken returns false; vase stays broken.
#   - Broken vase contributes 0 to score.
#   - A non-fragile treasure (eggs) dropped non-deposit goes
#     back to $InRoom rather than $Broken — confirms the
#     fragile branch is treasure-specific.
#   - Save/restore round-trips $Broken.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA fragile vase ===")

    # --- Initial conditions ---
    print("Initial — vase at home (room 97), uncarried, intact:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    _expect("vase state",          adv.vase.get_state(),      "in_room")
    _expect("vase location",       adv.vase.get_location(),   97)
    _expect("vase value",          adv.vase.get_value(),      14)
    _expect("vase intact",         adv.vase.is_broken(),      false)
    _expect("vase not deposited",  adv.vase.is_deposited(),   false)

    # --- Take vase ---
    print("Take vase from Oriental Room:")
    adv.player.move_to(97)
    adv.do_command("take", "vase")
    _expect("vase carried state",  adv.vase.get_state(),      "carried")
    _expect("vase location -1",    adv.vase.get_location(),   -1)

    # --- Drop outside deposit room — fragile shatters ---
    print("Drop vase in a non-deposit room (33 = Y2):")
    adv.player.move_to(33)
    adv.do_command("drop", "vase")
    _expect("vase broken state",   adv.vase.get_state(),      "broken")
    _expect("vase is_broken",      adv.vase.is_broken(),      true)
    _expect("vase value zeroed",   adv.vase.get_value(),      0)
    _expect("vase location 33",    adv.vase.get_location(),   33)

    # --- Try to re-take a broken vase ---
    print("Re-taking a broken vase fails (shards aren't a treasure):")
    var retook: bool = adv.vase.try_take(33)
    _expect("try_take returns false", retook,                  false)
    _expect("vase still broken",   adv.vase.get_state(),      "broken")

    # --- Broken vase contributes 0 to treasure_score ---
    print("Broken vase contributes 0 to treasure_score:")
    _expect("treasure_score 0",    adv.treasure_score(),      0)

    # --- Eggs (non-fragile) dropped non-deposit returns to InRoom ---
    print("Eggs (non-fragile) dropped non-deposit go back to in_room:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.player.move_to(92)
    adv2.do_command("take", "eggs")
    _expect("eggs carried",        adv2.eggs.get_state(),     "carried")
    adv2.player.move_to(33)
    adv2.do_command("drop", "eggs")
    _expect("eggs in_room",        adv2.eggs.get_state(),     "in_room")
    _expect("eggs not broken",     adv2.eggs.is_broken(),     false)
    _expect("eggs at room 33",     adv2.eggs.get_location(),  33)

    # --- Save / restore preserves $Broken ---
    print("Save/restore round-trips broken state:")
    var bytes = adv.save_state()
    var adv3 = Cca.new()
    adv3.restore_state(bytes)
    _expect("restored vase state", adv3.vase.get_state(),     "broken")
    _expect("restored is_broken",  adv3.vase.is_broken(),     true)
    _expect("restored value 0",    adv3.vase.get_value(),     0)
    _expect("restored location",   adv3.vase.get_location(),  33)

    # --- Canon msg #145: FILL VASE at a water source shatters it ---
    # advent.for STMT 9222: with VASE carried AND a liquid source
    # in the player's room, the thermal shock breaks the vase
    # in place. Try this fresh — separate Adventure instance so
    # we're not interacting with the prior shatter.
    print("FILL VASE at a water source — canon msg #145 cold shatter:")
    var adv4 = Cca.new()
    adv4.setup_default_aspects()
    adv4.player.move_to(97)
    adv4.do_command("take", "vase")
    _expect("vase carried setup", adv4.vase.get_state(),       "carried")
    # Canon water source: room 4 (valley stream) — present in
    # LIQLOC. Move there carrying the vase, then FILL.
    adv4.player.move_to(4)
    var fill_result: String = adv4.do_command("fill", "vase")
    _expect("fill at water source emits canon msg #145",
        "shattered" in fill_result, true)
    _expect("vase broken after fill",  adv4.vase.get_state(),  "broken")
    _expect("vase shards at room 4",   adv4.vase.get_location(), 4)

    # --- FILL VASE in a no-liquid room still emits canon msg #144 ---
    print("FILL VASE in dry room — canon msg #144:")
    var adv5 = Cca.new()
    adv5.setup_default_aspects()
    adv5.player.move_to(97)
    adv5.do_command("take", "vase")
    adv5.player.move_to(33)               # Y2 — dry
    var dry_result: String = adv5.do_command("fill", "vase")
    _expect("dry fill emits msg #144",
        "nothing here with which to fill" in dry_result, true)
    _expect("vase intact after dry fill", adv5.vase.get_state(), "carried")

    print()
    if failures == 0:
        print("PASS — fragile vase shatters and round-trips correctly")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
