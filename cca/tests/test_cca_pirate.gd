extends SceneTree

# Smoke test for the pirate stash + retrieval cycle.
# Verifies:
#   - Pirate starts $Dormant; activates after carrying threshold.
#   - When the pirate steals, the stolen treasure is relocated
#     to the chest room (room 18) and removed from inventory.
#   - The player can then go to the chest room and take it back.
#   - The pick order is deterministic — given a fixed inventory,
#     the same treasure always goes first (gold > silver > ...).
#   - Save/restore round-trips a stashed treasure correctly.

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

func _drive_to_steal(adv) -> String:
    # Hammer try_steal until it triggers. Seeded PRNG → bounded.
    var attempts: int = 0
    while attempts < 50:
        var msg: String = adv.pirate_attempt_steal()
        if msg != "":
            return msg
        attempts += 1
    return ""

func _init():
    print("=== CCA Pirate stash + retrieval ===")

    # --- Initial state ---
    print("Initial — pirate is dormant:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    _expect("pirate state",          adv.pirate_state(),    "dormant")

    # --- Activate by carrying threshold ---
    print("Carry 3 treasures to activate the pirate:")
    adv.player.take(adv.GOLD_ID)
    adv.player.take(adv.SILVER_ID)
    adv.player.take(adv.DIAMONDS_ID)
    # tick so treasures_carried gets observed by the FSM
    adv.tick()
    _expect("pirate stalking",       adv.pirate_state(),    "stalking")

    # --- Force a steal ---
    print("Drive the pirate to steal (seeded PRNG → deterministic):")
    var msg: String = _drive_to_steal(adv)
    _expect_contains("steal message",msg,                   "snatches your gold")
    _expect("pirate vanished",       adv.pirate_state(),    "vanished")

    # --- Verify the gold is now in the chest room ---
    print("Stolen treasure now lives in the chest room (18):")
    _expect("gold not carried",      adv.player.carrying(adv.GOLD_ID), false)
    _expect("gold state",            adv.gold.get_state(),  "in_room")
    _expect("gold location",         adv.gold.get_location(), 132)

    # --- Player retrieves the gold from the chest room ---
    print("Player travels to chest room and takes the gold back:")
    adv.do_command("light", "")
    adv.player.move_to(132)
    var r = adv.do_command("take", "gold")
    _expect_contains("take response", r, "OK")
    _expect("gold carried again",    adv.player.carrying(adv.GOLD_ID), true)
    _expect("gold state again",      adv.gold.get_state(),  "carried")

    # --- Determinism: same setup, same first-stolen treasure ---
    print("Determinism — fresh adventure, same inventory, same first stolen treasure:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.player.take(adv2.GOLD_ID)
    adv2.player.take(adv2.SILVER_ID)
    adv2.player.take(adv2.DIAMONDS_ID)
    adv2.tick()
    var msg2: String = _drive_to_steal(adv2)
    _expect_contains("repeat steal", msg2, "snatches your gold")

    # --- Pick-order: pirate picks gold first (lowest ID first) ---
    print("Pick order — without gold, silver should be stolen:")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.player.take(adv3.SILVER_ID)
    adv3.player.take(adv3.DIAMONDS_ID)
    adv3.player.take(adv3.JEWELRY_ID)
    adv3.tick()
    var msg3: String = _drive_to_steal(adv3)
    _expect_contains("silver stolen",msg3,                  "snatches your silver")
    _expect("silver in chest room",  adv3.silver.get_location(), 132)

    # --- Pirate sees empty hands ---
    print("Pirate rolls a steal but player carries nothing:")
    var adv4 = Cca.new()
    adv4.setup_default_aspects()
    # Force activation manually since no treasures = no normal trigger
    adv4.pirate.treasures_carried(5)
    _expect("forced stalking",       adv4.pirate_state(),    "stalking")
    var msg4: String = _drive_to_steal(adv4)
    _expect_contains("empty-hands flavor", msg4, "empty hands")

    # --- Save / restore mid-stash ---
    print("Save with one treasure stashed, mutate, restore:")
    var adv5 = Cca.new()
    adv5.setup_default_aspects()
    adv5.player.take(adv5.GOLD_ID)
    adv5.player.take(adv5.SILVER_ID)
    adv5.player.take(adv5.DIAMONDS_ID)
    adv5.tick()
    _drive_to_steal(adv5)
    _expect("gold in chest pre-save", adv5.gold.get_location(), 132)
    var bytes = adv5.save_state()

    # Mutate after save: take the gold back
    adv5.player.move_to(132)
    adv5.do_command("light", "")
    adv5.do_command("take", "gold")
    _expect("gold carried post-mutate", adv5.gold.get_state(), "carried")

    var adv6 = Cca.new()
    adv6.restore_state(bytes)
    _expect("restored gold in chest",   adv6.gold.get_location(), 132)
    _expect("restored gold state",      adv6.gold.get_state(),    "in_room")
    _expect("restored pirate vanished", adv6.pirate_state(),      "vanished")

    print()
    if failures == 0:
        print("PASS — pirate stash cycle complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
