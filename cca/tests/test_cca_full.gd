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
    var rx4 = adv.do_command("throw", "axe")
    _expect_contains("throw axe response", rx4, "dwarf")

    print("Loot the surface treasures:")
    adv.player.move_to(11)              # debris
    adv.do_command("take", "gold")
    _deposit(adv, "gold", 11)

    adv.player.move_to(33)              # Y2
    adv.do_command("take", "silver")
    _deposit(adv, "silver", 33)

    adv.player.move_to(33)
    adv.do_command("plover", "")
    _expect("at Plover Room",          adv.player_room(),    41)
    adv.do_command("take", "pearl")
    adv.do_command("plover", "")
    _deposit(adv, "pearl", 33)

    print("Bird → Snake → Dragon → diamonds + rug:")
    adv.player.move_to(13)              # bird chamber
    adv.do_command("take", "bird")
    adv.player.move_to(47)              # snake passage
    adv.do_command("release", "bird")
    adv.do_command("move", "71")        # dragon cavern
    adv.do_command("attack", "dragon")
    adv.do_command("yes", "")
    _expect("dragon dead",             adv.dragon_alive(),   false)
    adv.do_command("take", "diamonds")
    adv.do_command("take", "rug")
    _deposit(adv, "diamonds", 71)
    adv.player.move_to(71)
    _deposit(adv, "rug", 71)

    print("Bear → Troll bridge unlock:")
    adv.player.move_to(70)              # bedquilt / bear chamber
    adv.do_command("feed", "bear")
    adv.do_command("take", "chain")
    adv.do_command("move", "117")       # troll bridge
    adv.do_command("drop", "chain")
    _expect("troll vanished",          adv.troll_state(),    "vanished")

    print("Beyond bridge — jewelry first:")
    adv.do_command("move", "118")       # cliff with ledge
    adv.do_command("take", "jewelry")
    _deposit(adv, "jewelry", 118)

    print("Deep cave (3 batches to stay under 7-item cap):")
    # Canonical room IDs of the deep-cave treasures:
    #   38 oriental(vase), 28 giant(eggs), 130 sapphire(trident),
    #   131 vast(emerald), 40 alcove(spices), 132 chest(chest),
    #   133 pyramid, 134 coins, 135 statuette.
    var batch_a: Array = [[38,"vase"], [28,"eggs"], [130,"trident"], [131,"emerald"]]
    for entry in batch_a:
        adv.player.move_to(entry[0])
        adv.do_command("take", entry[1])
    for entry in batch_a:
        adv.player.move_to(3)
        adv.do_command("drop", entry[1])

    var batch_b: Array = [[40,"spices"], [132,"chest"], [133,"pyramid"]]
    for entry in batch_b:
        adv.player.move_to(entry[0])
        adv.do_command("take", entry[1])
    for entry in batch_b:
        adv.player.move_to(3)
        adv.do_command("drop", entry[1])

    var batch_c: Array = [[134,"coins"], [135,"statuette"]]
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
