extends SceneTree

# Smoke test for the Bird + Snake cross-FSM interaction.
# Verifies:
#   - Bird starts in $Free at room 5 (bird home).
#   - "look" describes bird presence in room 5.
#   - "take bird" only works when player is in bird's room.
#   - Capturing the bird transitions Bird to $Caged with
#     location=-1 (with-player marker).
#   - Releasing in snake room transitions Bird → $Released
#     AND triggers Snake → $Gone via Adventure orchestration.
#   - Releasing in dragon room transitions Bird → $Dead.
#   - Releasing elsewhere transitions Bird → $Free at that
#     room.
#   - @@[persist] round-trip preserves all NPC state.

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
    print("=== CCA Bird + Snake cross-FSM ===")

    # ---------------------------------------------------------
    # Path A: bird kills snake
    # ---------------------------------------------------------
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.light_lamp()              # avoid darkness gate

    print("Initial NPC state:")
    _expect("bird state",     adv.bird_state(),     "free")
    _expect("bird location",  adv.bird_location(),  13)
    _expect("snake state",    adv.snake_state(),    "blocking")

    print("Try take bird from wrong room:")
    var r1 = adv.do_command("take", "bird")
    # Canon advent.for STMT 9010 SPK=25 — TAKE X with X not here.
    _expect("take bird wrong room", r1, "You can't be serious!")
    _expect("bird still free",      adv.bird_state(), "free")

    print("Take cage at cobbles (canon 10) — required to take bird:")
    adv.player.move_to(10)
    adv.do_command("take", "cage")
    _expect("cage carried",   adv.player.carrying(adv.CAGE_ID), true)

    print("Move to bird home (13), look, take:")
    adv.player.move_to(13)
    var r2 = adv.do_command("look", "")
    _expect("room desc mentions bird", r2.contains("bird"), true)
    var r3 = adv.do_command("take", "bird")
    # Canon: TAKE BIRD with cage emits msg #54 "OK". The caged
    # state shows up on the next LOOK via obj#BIRD prop=1.
    _expect("take response",  r3, "OK")
    _expect("bird state",     adv.bird_state(),     "caged")
    _expect("bird location",  adv.bird_location(),  -1)
    _expect("player carrying", adv.player.carrying(100), true)

    print("Move to snake room (canon 19, Hall of Mt King), look:")
    adv.player.move_to(19)
    var r4 = adv.do_command("look", "")
    _expect("snake mentioned",      r4.contains("snake"), true)

    print("Release bird → snake driven off (cross-FSM):")
    var r5 = adv.do_command("release", "bird")
    _expect("release response",     r5.contains("attacks"), true)
    _expect("bird state",           adv.bird_state(),       "released")
    _expect("snake state",          adv.snake_state(),      "gone")
    _expect("player not carrying",  adv.player.carrying(100), false)

    print("Look in snake room — snake no longer mentioned:")
    var r6 = adv.do_command("look", "")
    _expect("no snake in look",     r6.contains("snake"),   false)

    # ---------------------------------------------------------
    # Path B: dragon eats bird (separate adventure)
    # ---------------------------------------------------------
    print()
    print("Fresh adventure — release bird in dragon room (canon 119):")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.light_lamp()
    adv2.player.move_to(10)
    adv2.do_command("take", "cage")
    adv2.player.move_to(13)
    adv2.do_command("take", "bird")
    adv2.player.move_to(119)
    var r7 = adv2.do_command("release", "bird")
    _expect("release at dragon",   r7.contains("dragon"), true)
    _expect("bird state",          adv2.bird_state(),     "dead")

    # ---------------------------------------------------------
    # Path C: release in benign room — bird flies free
    # ---------------------------------------------------------
    print()
    print("Fresh adventure — release bird in Y2 (33):")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.light_lamp()
    adv3.player.move_to(10)
    adv3.do_command("take", "cage")
    adv3.player.move_to(13)
    adv3.do_command("take", "bird")
    adv3.player.move_to(33)
    var r8 = adv3.do_command("release", "bird")
    # Canon: RELEASE BIRD in a benign room emits msg #54 "OK".
    # The bird's new free-state is observable via bird_state() and
    # bird_location() below.
    _expect("released benign",      r8.contains("OK"),     true)
    _expect("bird back to free",    adv3.bird_state(),     "free")
    _expect("bird at release room", adv3.bird_location(),  33)

    # ---------------------------------------------------------
    # Path D: save / restore the snake-killed snapshot
    # ---------------------------------------------------------
    # ---------------------------------------------------------
    # Path E: bird vanishes when carried into the Plover Room
    # ---------------------------------------------------------
    print()
    print("Bird-into-Plover canon: bird vanishes for good:")
    var adv_p = Cca.new()
    adv_p.setup_default_aspects()
    adv_p.light_lamp()
    adv_p.player.move_to(10)
    adv_p.do_command("take", "cage")
    adv_p.player.move_to(13)               # bird chamber
    adv_p.do_command("take", "bird")
    _expect("bird carried pre-plover",   adv_p.player.carrying(100), true)
    adv_p.player.move_to(33)               # Y2
    var rp = adv_p.do_command("plover", "")
    # Canon: PLOVER chant with carried bird emits msg #54 "OK"; the
    # bird's $Dead state is observable via bird_state().
    _expect_contains("plover bird msg",   rp, "OK")
    _expect("at Plover Room",            adv_p.player_room(),  100)
    _expect("bird not carried",          adv_p.player.carrying(100), false)
    _expect("bird state dead",           adv_p.bird_state(),   "dead")

    print()
    print("Save state mid-Path-A (snake just killed), restore:")
    var bytes = adv.save_state()
    print("  save bytes: %d" % bytes.size())

    # Mutate post-save: bring player back, move around
    adv.player.move_to(1)
    adv.do_command("look", "")
    adv.do_command("look", "")

    var adv4 = Cca.new()
    adv4.restore_state(bytes)
    _expect("restored bird state",  adv4.bird_state(),     "released")
    _expect("restored snake state", adv4.snake_state(),    "gone")
    _expect("restored room",        adv4.player_room(),    19)
    # Look in the restored snake room — should still NOT mention snake
    var r9 = adv4.do_command("look", "")
    _expect("restored look no snake", r9.contains("snake"), false)

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
