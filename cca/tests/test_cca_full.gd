extends SceneTree

# Full canonical CCA playthrough with the expanded maze, all
# 15 treasures, and the endgame.
# Room numbers are Crowther+Woods canonical: well house = 3,
# debris = 11, snake = 47, dragon = 71, bear = 70, etc.

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

func _deposit(adv, treasure_name: String, return_room: int) -> void:
    adv.player.move_to(3)              # well house — DEPOSIT_ROOM
    adv.do_command("drop", treasure_name)
    adv.player.move_to(return_room)

func _init():
    print("=== CCA full playthrough — 15 treasures + endgame ===")

    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.wake_dwarves()
    adv.do_command("light", "")

    print("EXAMINE / READ / THROW verbs:")
    adv.player.move_to(33)              # Y2 (dwarf2 spawned there)
    var rx1 = adv.do_command("examine", "lamp")
    _expect_contains("examine lamp",       rx1, "lantern")
    var rx2 = adv.do_command("examine", "sign")
    _expect_contains("examine sign at Y2", rx2, "Y2")
    var rx3 = adv.do_command("read", "sign")
    _expect_contains("read sign at Y2",    rx3, "Y2")
    # Canon: throw verb requires the axe item (dwarf-thrown).
    # Without an axe in hand the verb refuses up front.
    var rx4 = adv.do_command("throw", "axe")
    _expect_contains("throw axe response", rx4, "no axe")

    print("Loot the surface treasures:")
    adv.player.move_to(18)              # gold-nugget room (canon 18)
    adv.do_command("take", "gold")
    _deposit(adv, "gold", 11)

    adv.player.move_to(28)              # silver canon room
    adv.do_command("take", "silver")
    _deposit(adv, "silver", 33)

    adv.player.move_to(33)
    adv.do_command("plover", "")
    _expect("at Plover Room",          adv.player_room(),    100)
    # Canon: emerald in Plover Room; pearl is dynamic (clam→oyster).
    adv.do_command("take", "emerald")
    adv.do_command("plover", "")
    adv.player.move_to(3); adv.do_command("drop", "emerald")
    # Pearl: take rod (canon 11), then clam at canon 103, break
    # it (with rod) — pearl falls out at the break room.
    adv.player.move_to(11)
    adv.do_command("take", "rod")
    adv.player.move_to(103)
    adv.do_command("take", "clam")
    adv.player.move_to(16)
    adv.do_command("break", "clam")
    adv.do_command("take", "pearl")
    _deposit(adv, "pearl", 33)
    adv.player.move_to(33)

    print("Bird → Snake → Dragon → rug + diamonds (canon split):")
    adv.player.move_to(10)              # cobble crawl — pick up cage first
    adv.do_command("take", "cage")
    adv.player.move_to(13)              # bird chamber
    adv.do_command("take", "bird")
    adv.player.move_to(19)              # Hall of Mt King — canon snake room (19)
    adv.do_command("release", "bird")
    adv.do_command("move", "119")       # canon dragon canyon (119)
    adv.do_command("attack", "dragon")
    adv.do_command("yes", "")
    _expect("dragon dead",             adv.dragon_alive(),   false)
    adv.do_command("take", "rug")
    _deposit(adv, "rug", 119)
    # Diamonds canonically live at canon room 27 (west bank
    # fissure, Hall of Mists), not with the dragon.
    adv.player.move_to(27)
    adv.do_command("take", "diamonds")
    _deposit(adv, "diamonds", 27)

    print("Bear → Troll bridge unlock:")
    adv.player.move_to(3)               # well house — pick up food
    adv.do_command("take", "food")
    adv.player.move_to(130)             # Barren Room — canon 130 (bear chamber)
    adv.do_command("feed", "bear")
    adv.do_command("take", "chain")
    adv.do_command("move", "117")       # troll bridge
    adv.do_command("drop", "chain")
    _expect("troll vanished",          adv.troll_state(),    "vanished")

    print("Jewelry at south side chamber (canon 29):")
    adv.player.move_to(29)              # south side chamber — canon 29
    adv.do_command("take", "jewelry")
    _deposit(adv, "jewelry", 117)       # return to troll bridge area

    print("Deep cave (3 batches to stay under 7-item cap):")
    # Canonical room IDs of the remaining deep-cave treasures
    # (emerald moved to Plover Room canon 100, taken alongside pearl):
    #   97 oriental(vase), 92 giant(eggs), 95 magnificent_cavern(trident),
    #   127 chamber-of-boulders(spices), 132 chest(chest),
    #   101 dark-room(pyramid), 30 west-side-chamber(coins), 135 statuette.
    var batch_a: Array = [[97, "vase"], [92, "eggs"], [95, "trident"]]
    for entry in batch_a:
        adv.player.move_to(entry[0])
        adv.do_command("take", entry[1])
    for entry in batch_a:
        adv.player.move_to(3)
        adv.do_command("drop", entry[1])

    # Canon: chest is dynamic — spawn it at CHEST_ROOM before
    # batch_b walks past it.
    adv.chest.reappear(adv.CHEST_ROOM)
    var batch_b: Array = [[127,"spices"], [132,"chest"], [101,"pyramid"]]
    for entry in batch_b:
        adv.player.move_to(entry[0])
        adv.do_command("take", entry[1])
    for entry in batch_b:
        adv.player.move_to(3)
        adv.do_command("drop", entry[1])

    # Batch C: coins (canon 30) + chain (15th canon treasure;
    # already lying at the troll bridge after the bear scared the
    # troll off — bear FSM is in $Released by now).
    var batch_c: Array = [[30, "coins"], [117, "chain"]]
    for entry in batch_c:
        adv.player.move_to(entry[0])
        adv.do_command("take", entry[1])
    for entry in batch_c:
        adv.player.move_to(3)
        adv.do_command("drop", entry[1])

    _expect("all 15 deposited",        adv.treasures_deposited(), 15)
    _expect("treasure score",          adv.treasure_score(), 210)
    _expect("endgame closing",         adv.endgame_closing(), true)

    print("Drive endgame timer to 0:")
    for i in 30:
        adv.tick()
    _expect("endgame in repository",   adv.endgame_state(),  "in_repository")

    print("Detonate marker → win + bonus:")
    var pre_score = adv.score()
    adv.detonate_marker()
    _expect("won",                     adv.endgame_won(),    true)
    _expect("score gained 50 bonus",   adv.score(), pre_score + 50)
    _expect("endgame component",       adv.endgame_score(),  50)

    print("Hint penalty (separate adventure):")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.player.move_to(13)             # bird chamber
    for i in 4:
        adv2.tick()
    _expect("bird_hint eligible",      adv2.hint_state("bird"), "eligible")
    adv2.request_hint("bird")
    _expect("hint penalty",            adv2.hint_penalty(),  -2)

    print()
    if failures == 0:
        print("PASS — full canonical playthrough complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
