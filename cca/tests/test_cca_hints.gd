extends SceneTree

# Smoke test for the Hint system (parallel parameterized × 3).
# Verifies:
#   - Three hints (bird, cave, snake) start in $Pending with
#     streak 0.
#   - Hints advance independently — observing the bird-room
#     condition doesn't affect the cave-entry hint's streak.
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
    _expect("cave_hint state",  adv.hint_state("cave"),  "pending")
    _expect("snake_hint state", adv.hint_state("snake"), "pending")
    _expect("bird_hint streak", adv.bird_hint.get_streak(), 0)

    print("Player in bird room (13) for 5 turns — bird_hint becomes eligible:")
    # Canon advent.dat section-11 threshold for bird = 5 turns
    # (was earlier hard-coded to 3 under the lowered-threshold
    # dev shortcut; restored 2026-05-18).
    adv.player.move_to(13)
    for i in 5:
        adv.do_command("look", "")    # tick fires (driver pattern: do_command then tick)
        adv.tick()
    _expect("bird_hint streak", adv.bird_hint.get_streak(), 5)
    _expect("bird_hint state",  adv.hint_state("bird"),  "eligible")
    # Other hints unaffected — they observe their own conditions
    _expect("cave_hint state",  adv.hint_state("cave"),  "pending")
    _expect("snake_hint state", adv.hint_state("snake"), "pending")

    print("Request the bird hint:")
    var r1 = adv.request_hint("bird")
    _expect("bird hint message",   r1.contains("bird"), true)
    _expect("bird_hint now offered", adv.hint_state("bird"), "offered")
    _expect("cave_hint untouched", adv.hint_state("cave"), "pending")

    print("Re-request bird hint — already given:")
    var r2 = adv.request_hint("bird")
    # Canon: hint already given emits msg #54 "OK".
    _expect("already given",       r2.contains("OK"), true)

    print("Streak resets when condition becomes false:")
    adv.player.move_to(1)              # leave bird room (end of road)
    adv.tick()                         # bird condition now false
    adv.player.move_to(13)             # back to bird room
    adv.tick()
    # Bird is still free at room 13 because we never took it.
    # cave_hint observes player on the surface (rooms 1-9); after
    # move_to(13) it sees the player off-surface, so the streak
    # resets to 0.
    _expect("cave_hint state",  adv.hint_state("cave"),  "pending")
    _expect("cave_hint streak (off-surface)", adv.cave_hint.get_streak(), 0)

    print("Request hint that's not eligible:")
    var r3 = adv.request_hint("snake")
    # Canon: hint not eligible emits msg #54 "OK".
    _expect("not eligible",        r3.contains("OK"), true)

    print("Save mid-streak, mutate, restore:")
    # Canon snake threshold = 8 (advent.dat section 11). Save at
    # streak 7 (one short), mutate post-save tick → 8 = eligible,
    # restore → still at 7, replay tick → eligible. The pre-save
    # streak was 2 under the lowered-threshold draft; updated
    # 2026-05-18 to canon.
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.player.move_to(19)             # snake room (canon 19 — Hall of Mt King)
    # snake_hint observes (room == SNAKE_ROOM and snake.is_blocking())
    for _i in 7:
        adv2.tick()
    _expect("snake_hint streak",   adv2.snake_hint.get_streak(), 7)
    _expect("snake_hint state",    adv2.hint_state("snake"), "pending")

    var bytes = adv2.save_state()

    # Mutate post-save — push snake_hint to eligible at streak 8
    adv2.tick()
    _expect("post-save eligible",  adv2.hint_state("snake"), "eligible")

    var adv3 = Cca.new()
    adv3.restore_state(bytes)
    _expect("restored state",      adv3.hint_state("snake"), "pending")
    _expect("restored streak",     adv3.snake_hint.get_streak(), 7)

    # Replay the same tick — same outcome
    adv3.tick()
    _expect("replay → eligible",   adv3.hint_state("snake"), "eligible")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
