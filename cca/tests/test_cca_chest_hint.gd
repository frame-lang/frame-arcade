extends SceneTree

# Verifies canon chest-only-outstanding hint (advent.for STMT
# 6020, canon msg #186). When the player has 14 of 15 treasures
# deposited and the chest is still missing, msg #186 fires once
# pointing them toward the maze.
#
# Setup: drive 14 of the 15 treasures through the canonical
# Treasure FSM deposit() handler, leaving the chest. Tick a
# turn — the hint should fire on the next per-turn check.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-58s line contained banned '%s'" % [
                label, needle])
            failures += 1
            return
    print("  ok   %-58s no line contained '%s'" % [label, needle])

func _make_driver() -> H.CapturedDriver:
    var d := H.CapturedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

# Force-deposit a treasure by walking the canon FSM path:
# reappear at deposit room → try_take → try_drop. The treasure
# transitions $InRoom → $Carried → $Deposited.
func _force_deposit(t) -> void:
    var deposit_room: int = 3       # canon WELL_HOUSE_ROOM
    t.reappear(deposit_room)
    t.try_take(deposit_room)
    t.try_drop(deposit_room)

func _deposit_all_but_chest(d: H.CapturedDriver) -> void:
    _force_deposit(d.fsm.gold)
    _force_deposit(d.fsm.silver)
    _force_deposit(d.fsm.diamonds)
    _force_deposit(d.fsm.jewelry)
    _force_deposit(d.fsm.pearl)
    _force_deposit(d.fsm.vase)
    _force_deposit(d.fsm.eggs)
    _force_deposit(d.fsm.trident)
    _force_deposit(d.fsm.emerald)
    _force_deposit(d.fsm.spices)
    _force_deposit(d.fsm.pyramid)
    _force_deposit(d.fsm.rug)
    _force_deposit(d.fsm.coins)
    _force_deposit(d.fsm.chain)

func _init():
    print("=== CCA chest-only-outstanding hint (canon msg #186) ===")

    # ----- Phase 1: pre-condition — hint NOT fired with <14 deposited -----
    print("Phase 1: <14 treasures deposited — no hint")
    var d1 := _make_driver()
    var l1: Array = H.capture(d1, "north")
    _expect_no_match("no msg #186 with 0 treasures deposited",
        l1, "Shiver me timbers")
    _expect("hint latch still false",     d1.fsm.is_chest_hint_done(),    false)

    # ----- Phase 2: 14 deposited, chest still missing → hint fires -----
    print("Phase 2: 14 deposited + chest missing → msg #186 fires")
    var d2 := _make_driver()
    _deposit_all_but_chest(d2)
    _expect("setup: 14 treasures deposited", d2.fsm.treasures_deposited(), 14)
    _expect("setup: chest not deposited",    d2.fsm.chest.is_deposited(),  false)
    var l2: Array = H.capture(d2, "north")
    _expect_any_match("first turn after threshold fires canon msg #186",
        l2, "Shiver me timbers")
    _expect_any_match("msg #186 mentions the maze",
        l2, "maze to hide me chest")
    _expect("hint latch armed",           d2.fsm.is_chest_hint_done(),    true)

    # ----- Phase 3: re-fire suppressed by latch -----
    print("Phase 3: subsequent turns don't re-fire")
    var l3: Array = H.capture(d2, "north")
    _expect_no_match("second turn does NOT re-fire msg #186",
        l3, "Shiver me timbers")

    # ----- Phase 4: chest carried (not deposited) — hint suppressed -----
    # If the player picks up the chest before the 14-threshold,
    # the hint shouldn't fire — they already know about the
    # chest. Test by depositing 14 + carrying chest, no hint.
    print("Phase 4: chest carried by player → hint suppressed")
    var d4 := _make_driver()
    _deposit_all_but_chest(d4)
    # Synthetic carry: place chest at player's room, take it.
    var here: int = d4.fsm.player_room()
    d4.fsm.chest.reappear(here)
    d4.fsm.chest.try_take(here)
    d4.fsm.player.take(d4.fsm.CHEST_ID)
    var l4: Array = H.capture(d4, "north")
    _expect_no_match("hint suppressed when chest is carried",
        l4, "Shiver me timbers")

    if failures == 0:
        print("PASS — chest-only-outstanding hint honors canon msg #186")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
