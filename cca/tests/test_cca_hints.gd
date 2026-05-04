extends SceneTree

# Smoke test for the Hint system (parallel parameterized × 3).
# Verifies:
#   - Three hints (bird, dark, snake) start in $Pending with
#     streak 0.
#   - Hints advance independently — observing the bird-room
#     condition doesn't affect the dark-room hint's streak.
#   - Streak resets when condition becomes false.
#   - Threshold crossing transitions $Pending → $Eligible.
#   - request_hint() in $Eligible returns the hint text and
#     transitions to $Offered (terminal).
#   - request_hint() in $Pending or $Offered returns the
#     appropriate canned message (no hint / already given).
#   - @@[persist] preserves each hint's state and streak
#     independently.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Hint × 3 (parallel parameterized) ===")

    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.light_lamp()  # avoid darkness gate side effects on do_command

    print("Initial state — all three pending:")
    _expect("bird_hint state",  adv.hint_state("bird"),  "pending")
    _expect("dark_hint state",  adv.hint_state("dark"),  "pending")
    _expect("snake_hint state", adv.hint_state("snake"), "pending")
    _expect("bird_hint streak", adv.bird_hint.get_streak(), 0)

    print("Player in bird room (13) for 3 turns — bird_hint becomes eligible:")
    adv.player.move_to(13)
    for i in 3:
        adv.do_command("look", "")    # tick fires (driver pattern: do_command then tick)
        adv.tick()
    _expect("bird_hint streak", adv.bird_hint.get_streak(), 3)
    _expect("bird_hint state",  adv.hint_state("bird"),  "eligible")
    # Other hints unaffected — they observe their own conditions
    _expect("dark_hint state",  adv.hint_state("dark"),  "pending")
    _expect("snake_hint state", adv.hint_state("snake"), "pending")

    print("Request the bird hint:")
    var r1 = adv.request_hint("bird")
    _expect("bird hint message",   r1.contains("bird"), true)
    _expect("bird_hint now offered", adv.hint_state("bird"), "offered")
    _expect("dark_hint untouched", adv.hint_state("dark"), "pending")

    print("Re-request bird hint — already given:")
    var r2 = adv.request_hint("bird")
    _expect("already given",       r2.contains("already"), true)

    print("Streak resets when condition becomes false:")
    adv.player.move_to(1)              # leave bird room (end of road)
    adv.tick()                         # bird condition now false
    adv.player.move_to(13)             # back to bird room
    adv.tick()
    # Note: bird is still free at room 13 because we never
    # took it. dark_hint observes is_dark which is false (room
    # 1 is lit, lamp on). So dark_hint streak should be 0.
    _expect("dark_hint state",  adv.hint_state("dark"),  "pending")
    _expect("dark_hint streak (lit)", adv.dark_hint.get_streak(), 0)

    print("Request hint that's not eligible:")
    var r3 = adv.request_hint("snake")
    _expect("not eligible",        r3.contains("No hint"), true)

    print("Save mid-streak, mutate, restore:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.player.move_to(47)             # snake room
    # snake_hint observes (room == SNAKE_ROOM and snake.is_blocking())
    adv2.tick()
    adv2.tick()
    _expect("snake_hint streak",   adv2.snake_hint.get_streak(), 2)
    _expect("snake_hint state",    adv2.hint_state("snake"), "pending")

    var bytes = adv2.save_state()

    # Mutate post-save — push snake_hint to eligible
    adv2.tick()
    _expect("post-save eligible",  adv2.hint_state("snake"), "eligible")

    var adv3 = Cca.new()
    adv3.restore_state(bytes)
    _expect("restored state",      adv3.hint_state("snake"), "pending")
    _expect("restored streak",     adv3.snake_hint.get_streak(), 2)

    # Replay the same tick — same outcome
    adv3.tick()
    _expect("replay → eligible",   adv3.hint_state("snake"), "eligible")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
