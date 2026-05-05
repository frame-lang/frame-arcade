extends SceneTree

# Smoke test for BackpackLimit + MagicWordTeleport aspects.
# Verifies:
#   1. Take when inventory has room: passes through, base
#      handler stores the item.
#   2. Take when inventory at LIMIT (7): BackpackLimit
#      consumes with "you can't carry that many things"
#      message; counter increments.
#   3. XYZZY from room 0: transforms into MOVE-to-2; base
#      moves player there; transforms_count++.
#   4. XYZZY from room 2: pairs back to room 0.
#   5. PLUGH from room 0: transforms into MOVE-to-4 (Y2).
#   6. PLOVER from room 4: transforms into MOVE-to-6.
#   7. Magic words in unrecognized rooms: pass through, base
#      returns canon "Nothing happens."
#   8. @@[persist] round-trips both aspects' state +
#      bus listener registry.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA BackpackLimit + MagicWordTeleport ===")

    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Take a real treasure through the bus (should succeed):")
    adv.do_command("light", "")
    adv.player.move_to(18)                              # debris room — gold
    var r1 = adv.do_command("take", "gold")
    _expect("take response contains 'Taken'", r1.contains("Taken"), true)
    _expect("inventory size",      adv.player.inventory_size(), 1)

    print("Fill inventory to 7 by direct stuffing (skip the parser):")
    # The point of this section is the BackpackLimit aspect, which
    # only inspects player.inventory_size(). Stuffing six dummy IDs
    # is faster than walking 7 canonical treasures.
    for i in range(101, 107):
        adv.player.take(i)
    _expect("inventory at limit",  adv.player.inventory_size(), 7)

    print("Take 8th item via bus — BackpackLimit consumes:")
    adv.player.move_to(28)                             # silver canon room (28)
    var r2 = adv.do_command("take", "silver")
    _expect("take consumed",       r2, "You can't carry that many things at once.")
    _expect("inventory unchanged", adv.player.inventory_size(), 7)
    _expect("backpack consumed",   adv.backpack_blocked_count(), 1)

    print("Drop one, take again (passes again):")
    adv.player.drop(106)
    var r3 = adv.do_command("take", "silver")
    _expect("take after drop contains 'Taken'", r3.contains("Taken"), true)
    _expect("inventory size",      adv.player.inventory_size(), 7)
    _expect("backpack still 1",    adv.backpack_blocked_count(), 1)

    print("XYZZY from well house (3) → debris (11) — canon pair:")
    adv.player.move_to(3)                              # well house
    _expect("starting room",       adv.player_room(),           3)
    var r4 = adv.do_command("xyzzy", "")
    _expect("after xyzzy",         adv.player_room(),           11)
    _expect("magic transforms",    adv.magic_transforms_count(), 1)

    print("XYZZY from debris (11) → well house (3):")
    adv.do_command("xyzzy", "")
    _expect("after xyzzy back",    adv.player_room(),           3)
    _expect("magic transforms",    adv.magic_transforms_count(), 2)

    print("PLUGH from well house (3) → Y2 (33) — canon pair:")
    adv.do_command("plugh", "")
    _expect("after plugh",         adv.player_room(),           33)

    print("PLOVER from Y2 (33) → Plover Room (canon 100):")
    adv.do_command("plover", "")
    _expect("after plover",        adv.player_room(),           100)
    _expect("magic transforms",    adv.magic_transforms_count(), 4)

    print("XYZZY from unrecognized room (Plover) — passes through:")
    var r5 = adv.do_command("xyzzy", "")
    _expect("xyzzy nothing",       r5, "Nothing happens.")
    _expect("room unchanged",      adv.player_room(),           100)
    _expect("magic transforms",    adv.magic_transforms_count(), 4)

    print("Save mid-run, mutate, restore:")
    var bytes = adv.save_state()
    print("  save bytes: %d" % bytes.size())

    # Mutate
    adv.do_command("xyzzy", "")          # still in room 6, no transform
    adv.do_command("plover", "")         # transforms back to 4
    _expect("post-save room",      adv.player_room(),           33)
    _expect("post-save transforms",adv.magic_transforms_count(), 5)

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored room",       adv2.player_room(),           100)
    _expect("restored transforms", adv2.magic_transforms_count(), 4)
    _expect("restored backpack",   adv2.backpack_blocked_count(), 1)

    # And the bus is still wired; test the dispatch still works.
    adv2.do_command("plover", "")
    _expect("post-restore plover", adv2.player_room(),           33)

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
