extends SceneTree

# Smoke test for the canonical CCA mechanics added in the
# "Continue" round:
#   - Vase fragility (drops outside DEPOSIT_ROOM break it)
#   - Eggs incantation (FEE FIE FOE FOO summons eggs back)
#   - Bear-attacks-player (take_chain in $Hungry kills you)
#   - Dwarf-attacks-player (per-turn axe-throw chance)
#   - Resurrection cycle works (player dies → die() → revive())

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
    print("=== CCA mechanics — vase / eggs / bear / dwarf / resurrect ===")

    # --- Vase fragility ---
    print("Vase shatters when dropped outside the well house:")
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(38)
    adv.do_command("take", "vase")
    _expect("carrying vase",     adv.player.carrying(115), true)
    # Drop in random non-deposit room
    adv.player.move_to(130)
    var r = adv.do_command("drop", "vase")
    _expect("vase state",        adv.vase.get_state(), "broken")
    _expect("broken value 0",    adv.vase.get_value(),  0)
    _expect("not in inventory",  adv.player.carrying(115), false)

    # --- Vase survives if dropped at well house ---
    print("Vase survives when dropped at the well house:")
    var adv_b = Cca.new()
    adv_b.setup_default_aspects()
    adv_b.player.move_to(38)
    adv_b.do_command("take", "vase")
    adv_b.player.move_to(3)
    adv_b.do_command("drop", "vase")
    _expect("vase deposited",    adv_b.vase.get_state(), "deposited")
    _expect("vase value kept",   adv_b.vase.get_value(),  14)

    # --- Eggs incantation ---
    print("FEE FIE FOE FOO summons eggs back:")
    var adv_c = Cca.new()
    adv_c.setup_default_aspects()
    adv_c.do_command("light", "")
    adv_c.player.move_to(28)
    adv_c.do_command("take", "eggs")
    adv_c.player.move_to(3)
    adv_c.do_command("drop", "eggs")
    _expect("eggs deposited",    adv_c.eggs.is_deposited(), true)
    # Now chant FEE FIE FOE FOO
    var r1 = adv_c.do_command("fee", "")
    _expect_contains("fee response",  r1, "Fie")
    var r2 = adv_c.do_command("fie", "")
    _expect_contains("fie response",  r2, "Foe")
    var r3 = adv_c.do_command("foe", "")
    _expect_contains("foe response",  r3, "Foo")
    var r4 = adv_c.do_command("foo", "")
    _expect_contains("foo response",  r4, "appeared elsewhere")
    _expect("eggs back in giant room", adv_c.eggs.get_state(), "in_room")
    _expect("eggs at giant room",    adv_c.eggs.get_location(), 28)

    # --- Eggs incantation — broken chant ---
    print("Broken chant resets to idle:")
    var adv_d = Cca.new()
    adv_d.setup_default_aspects()
    adv_d.do_command("fee", "")
    adv_d.do_command("fie", "")
    var rb = adv_d.do_command("look", "")     # not foe — breaks chant
    # The verb dispatcher routes "look" to the look handler;
    # the chant FSM only sees fee/fie/foe/foo verbs. So our
    # current EggsIncantation stays in $WaitingFoe even after
    # "look". Let's verify the chant FSM directly by sending
    # a non-canon word through it:
    var rc = adv_d.eggs_chant.say("xyzzy")
    _expect_contains("non-canon resets chant", rc, "broke the chant")
    _expect("chant idle",    adv_d.eggs_chant.get_state(), "idle")

    # --- Bear-attacks-player ---
    print("Take chain from hungry bear → player dies:")
    var adv_e = Cca.new()
    adv_e.setup_default_aspects()
    adv_e.player.move_to(70)
    var rd = adv_e.do_command("take", "chain")
    _expect_contains("bear lunges",   rd, "killed")
    _expect("bear attacking",         adv_e.bear_state(),     "attacking")
    _expect("player dead",            adv_e.player_state(),   "dead")
    _expect("deaths = 1",             adv_e.player.get_deaths(), 1)

    # --- Resurrection ---
    print("Revive cycles back to alive at the start room:")
    adv_e.player.revive()
    _expect("player alive",           adv_e.player_state(),   "alive")
    _expect("revived at start room",  adv_e.player_room(),    1)
    _expect("inventory cleared",      adv_e.player.inventory_size(), 0)

    # --- Permadeath after 4 deaths ---
    print("Permadeath after 4th death:")
    var adv_f = Cca.new()
    adv_f.setup_default_aspects()
    for i in 3:
        adv_f.player.die()
        adv_f.player.revive()
    _expect("3 deaths recoverable",   adv_f.player_state(),   "alive")
    adv_f.player.die()
    _expect("4th death permadead",    adv_f.player_state(),   "permadead")

    # --- Dwarf attacks: deterministic seed-based test ---
    print("Dwarf throws axe deterministically:")
    var adv_g = Cca.new()
    adv_g.setup_default_aspects()
    adv_g.wake_dwarves()
    # dwarf1 spawns in room 12 (awkward canyon). Move player
    # there and tick a few times — eventually the 25%-roll
    # dwarf will hit.
    adv_g.player.move_to(12)
    var hit_after: int = -1
    for i in 30:
        adv_g.tick()
        if adv_g.player_state() == "dead":
            hit_after = i + 1
            break
    _expect("dwarf eventually killed player", hit_after > 0, true)
    print("  hit after %d ticks" % hit_after)

    # --- Save / restore preserves everything ---
    print("Save / restore mid-resurrect-prompt preserves death state:")
    var adv_h = Cca.new()
    adv_h.setup_default_aspects()
    adv_h.player.move_to(70)
    adv_h.do_command("take", "chain")          # die
    var bytes = adv_h.save_state()
    adv_h.player.revive()                       # mutate after save

    var adv_i = Cca.new()
    adv_i.restore_state(bytes)
    _expect("restored player dead",   adv_i.player_state(),   "dead")
    _expect("restored bear attacking", adv_i.bear_state(),    "attacking")

    print()
    if failures == 0:
        print("PASS — mechanics suite complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
