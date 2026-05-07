extends SceneTree

# Smoke test for the bear→troll cross-FSM narrative.
# Walks the full canonical play:
#   move to bear room → feed bear → take chain → move to troll
#   room → drop chain → bear scares troll → bridge open.
#
# Plus the hazard branch (take chain without feeding) and the
# bypass option (pay the troll's toll).

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA bear→troll cross-FSM narrative ===")

    # ---------------------------------------------------------
    # Path A: full happy path through the verb dispatcher
    # ---------------------------------------------------------
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.light_lamp()                 # avoid darkness gate

    print("Initial troll/bear:")
    _expect("troll state",      adv.troll_state(),   "demanding")
    _expect("bridge blocked",   adv.troll_blocking(), true)
    _expect("bear state",       adv.bear_state(),    "hungry")

    print("Pick up food at well house (canon 3) — required to feed bear:")
    adv.player.move_to(3)
    adv.do_command("take", "food")
    _expect("food carried",        adv.player.carrying(adv.FOOD_ID), true)

    print("Move to bear room (canon 130 — Barren Room), look:")
    adv.player.move_to(130)
    var r1 = adv.do_command("look", "")
    _expect("look mentions bear",  r1.contains("bear"), true)

    print("Feed bear → tame:")
    var r2 = adv.do_command("feed", "bear")
    _expect("feed response",       r2.contains("eats"), true)
    _expect("bear state",          adv.bear_state(),    "tame")

    print("Take chain → following:")
    var r3 = adv.do_command("take", "chain")
    _expect("take chain response", r3.contains("lumbers"), true)
    _expect("bear state",          adv.bear_state(),    "following")
    _expect("carrying chain",      adv.player.carrying(101), true)

    print("Move to troll room (117), look:")
    adv.player.move_to(117)
    var r4 = adv.do_command("look", "")
    _expect("look mentions troll", r4.contains("troll"), true)

    print("Drop chain → bear scares troll (cross-FSM):")
    var r5 = adv.do_command("drop", "chain")
    _expect("drop response",       r5.contains("scurries away"), true)
    _expect("bear state",          adv.bear_state(),    "released")
    _expect("troll state",         adv.troll_state(),   "vanished")
    _expect("bridge open",         adv.troll_blocking(), false)
    _expect("not carrying chain",  adv.player.carrying(101), false)

    # ---------------------------------------------------------
    # Path B: hazard — take chain without feeding
    # ---------------------------------------------------------
    print()
    print("Fresh adventure — take chain from hungry bear:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.light_lamp()
    adv2.player.move_to(130)
    var r6 = adv2.do_command("take", "chain")
    _expect("hostile response",    r6.contains("lunges"),    true)
    _expect("bear attacking",      adv2.bear_state(),         "attacking")
    _expect("not carrying chain",  adv2.player.carrying(101), false)

    # ---------------------------------------------------------
    # Path C: pay-toll alternative (bear avoids the bridge)
    # ---------------------------------------------------------
    print()
    print("Direct pay_toll path:")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.troll.pay_toll()
    _expect("troll paid",          adv3.troll_state(),    "toll_paid")
    _expect("bridge open",         adv3.troll_blocking(), false)

    # ---------------------------------------------------------
    # Path E: canon throw-treasure-at-troll (bridge toll via THROW verb)
    # ---------------------------------------------------------
    print()
    print("Canon throw-treasure path:")
    var adv6 = Cca.new()
    adv6.setup_default_aspects()
    adv6.light_lamp()
    # Pick up gold and walk to the troll bridge.
    adv6.player.move_to(18)        # canon stash room
    adv6.do_command("take", "gold")
    adv6.player.move_to(117)
    _expect("troll blocking",      adv6.troll_blocking(), true)
    _expect("carrying gold",       adv6.player.carrying(110), true)
    var rt = adv6.do_command("throw", "gold")
    _expect("throw response",      rt.contains("scurries away"), true)
    _expect("troll vanished",      adv6.troll_blocking(), false)
    _expect("gold consumed",       adv6.player.carrying(110), false)
    _expect("gold vanished state", adv6.gold.is_vanished(), true)
    _expect("gold worth zero",     adv6.gold.get_value(), 0)
    # Throwing a non-treasure should bounce.
    adv6.player.move_to(11)
    var rb = adv6.do_command("throw", "rock")
    _expect("rock bounces",        rb.contains("don't know how"), true)

    # ---------------------------------------------------------
    # Path D: full save/restore mid-Following with bear at troll
    # ---------------------------------------------------------
    print()
    print("Save mid-Following at troll's room, restore:")
    var adv4 = Cca.new()
    adv4.setup_default_aspects()
    adv4.light_lamp()
    adv4.player.move_to(3)
    adv4.do_command("take", "food")
    adv4.player.move_to(130)
    adv4.do_command("feed", "bear")
    adv4.do_command("take", "chain")
    adv4.player.move_to(117)
    var bytes = adv4.save_state()

    # Mutate post-save: drop chain to scare troll
    adv4.do_command("drop", "chain")

    var adv5 = Cca.new()
    adv5.restore_state(bytes)
    _expect("restored bear",       adv5.bear_state(),    "following")
    _expect("restored troll",      adv5.troll_state(),   "demanding")
    _expect("restored room",       adv5.player_room(),   117)
    _expect("restored carrying",   adv5.player.carrying(101), true)

    # And the FSM still works post-restore
    var r7 = adv5.do_command("drop", "chain")
    _expect("post-restore drop",   r7.contains("scurries away"), true)
    _expect("post-restore troll",  adv5.troll_state(),   "vanished")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
