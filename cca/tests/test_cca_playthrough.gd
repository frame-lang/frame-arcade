extends SceneTree

# End-to-end playthrough exercising the verbs and rooms a real
# player would touch. This is the wiring smoke test for the
# driver layer's verb/noun → FSM mapping. No UI; we drive the
# FSM directly via do_command and assert each response.

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
    print("=== CCA full-playthrough wiring test ===")

    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.wake_dwarves()

    print("Start at end-of-road (1, lit, surface):")
    _expect("starting room",  adv.player_room(),    1)
    _expect("not dark",       adv.room_is_dark_now(), false)

    var r1 = adv.do_command("look", "")
    _expect_contains("look mentions building", r1, "building")

    print("Move north → well house (3):")
    adv.do_command("move", "3")     # driver-translated direction
    _expect("at well house",  adv.player_room(),    3)

    print("XYZZY from well house → 11 (debris) — canon pair (3 ↔ 11):")
    var r2 = adv.do_command("xyzzy", "")
    _expect("after xyzzy",    adv.player_room(),    11)
    var r3 = adv.do_command("look", "")
    # In room 11 with lamp off → DarknessGate consumes:
    _expect_contains("dark consumes look", r3, "dark")

    print("Light lamp, look — gold mentioned:")
    adv.do_command("light", "")
    var r4 = adv.do_command("look", "")
    _expect_contains("look mentions gold", r4, "gold")

    print("Take gold:")
    var r5 = adv.do_command("take", "gold")
    _expect_contains("take gold response", r5, "Taken")
    _expect("carrying gold", adv.player.carrying(110), true)

    print("XYZZY back to well house (canon: 11 → 3 directly), drop gold:")
    adv.do_command("xyzzy", "")
    _expect("at deposit room", adv.player_room(),    3)
    var r6 = adv.do_command("drop", "gold")
    _expect_contains("deposited",     r6, "stowed")
    _expect("treasures deposited", adv.treasures_deposited(), 1)
    _expect("score",          adv.total_score(),    14)

    print("PLUGH from well house (3) → Y2 (33) — canon pair:")
    adv.do_command("plugh", "")
    _expect("at Y2",          adv.player_room(),    33)

    print("Move down to bird chamber (13), take bird:")
    adv.do_command("move", "13")
    _expect("at bird chamber", adv.player_room(),   13)
    var r7 = adv.do_command("take", "bird")
    _expect_contains("caught bird", r7, "catch")

    print("Move up to Y2, east to snake (47):")
    adv.do_command("move", "33")
    adv.do_command("move", "47")
    _expect("at snake passage", adv.player_room(),  47)
    _expect("snake blocking",   adv.snake.is_blocking(), true)

    print("Release bird in snake's room — snake flees:")
    var r8 = adv.do_command("release", "bird")
    _expect_contains("attacks snake", r8, "attacks")
    _expect("snake gone",       adv.snake.is_blocking(), false)

    print("Now east to dragon cavern (71):")
    adv.do_command("move", "71")
    _expect("at dragon",        adv.player_room(),  71)

    print("Attack dragon, say YES:")
    var r9 = adv.do_command("attack", "dragon")
    _expect_contains("with what",  r9, "what")
    var r10 = adv.do_command("yes", "")
    _expect_contains("vanquished", r10, "vanquished")
    _expect("dragon dead",      adv.dragon_alive(), false)

    print("Take diamonds (was here all along, now safe):")
    var r11 = adv.do_command("take", "diamonds")
    _expect_contains("took diamonds", r11, "Taken")

    print("North to bear chamber, feed bear, take chain:")
    adv.do_command("move", "70")
    _expect("at bear room",     adv.player_room(),  70)
    var r12 = adv.do_command("feed", "bear")
    _expect_contains("fed bear",   r12, "eats")
    var r13 = adv.do_command("take", "chain")
    _expect_contains("got chain",  r13, "lumbers")

    print("East to troll bridge, drop chain — troll flees:")
    adv.do_command("move", "117")
    _expect("at troll bridge",  adv.player_room(),  117)
    _expect("troll blocking",   adv.troll.is_blocking_bridge(), true)
    var r14 = adv.do_command("drop", "chain")
    _expect_contains("flees",      r14, "flees")
    _expect("troll gone",       adv.troll.is_blocking_bridge(), false)

    print("East to beyond bridge, take jewelry:")
    adv.do_command("move", "118")
    _expect("at beyond",        adv.player_room(),  118)
    var r15 = adv.do_command("take", "jewelry")
    _expect_contains("took jewelry", r15, "Taken")

    print("Save / restore mid-game:")
    var bytes = adv.save_state()
    adv.do_command("move", "117")
    var pre_room = adv.player_room()

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored room",    adv2.player_room(), 118)
    _expect("restored carrying jewelry", adv2.player.carrying(113), true)
    _expect("restored troll gone",  adv2.troll.is_blocking_bridge(), false)
    _expect("restored snake gone",  adv2.snake.is_blocking(), false)
    _expect("restored dragon dead", adv2.dragon_alive(), false)

    print()
    if failures == 0:
        print("PASS — playthrough wiring complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
