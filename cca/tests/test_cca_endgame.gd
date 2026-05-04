extends SceneTree

# Smoke test for the Endgame phase machine.
# Verifies:
#   - Initial $Active; treasure_deposited counts up.
#   - Crossing TREASURES_TO_TRIGGER (10 — canonical scope)
#     transitions $Active → $Closing.
#   - $Closing's $.timer state-var seeds to CLOSING_DURATION
#     on entry; tick() decrements; reaching 0 transitions to
#     $InRepository.
#   - detonate() in $InRepository → $Won (terminal).
#   - detonate() outside the repository is a no-op (defensive).
#   - @@[persist] round-trips the phase + the closing timer.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Endgame phase machine ===")

    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Initial — $Active:")
    _expect("endgame state",      adv.endgame_state(),      "active")
    _expect("not closing",        adv.endgame_closing(),    false)
    _expect("not won",            adv.endgame_won(),        false)
    _expect("treasures",          adv.endgame.treasures_count(), 0)

    print("Detonate during $Active is a no-op:")
    adv.detonate_marker()
    _expect("still active",       adv.endgame_state(),      "active")

    print("Deposit 9 treasures — still active (threshold is 10):")
    for i in 9:
        adv.deposit_treasure()
    _expect("treasures",          adv.endgame.treasures_count(), 9)
    _expect("still active",       adv.endgame_state(),      "active")

    print("Deposit 10th treasure — crosses threshold to $Closing:")
    adv.deposit_treasure()
    _expect("endgame state",      adv.endgame_state(),      "closing")
    _expect("closing flag",       adv.endgame_closing(),    true)
    _expect("timer seeded",       adv.endgame_timer(),      30.0)
    _expect("treasures",          adv.endgame.treasures_count(), 10)

    print("Tick 15 times — timer decrements, still closing:")
    for i in 15:
        adv.tick()
    _expect("endgame state",      adv.endgame_state(),      "closing")
    _expect("timer ≈ 15",         adv.endgame_timer(),      15.0)

    print("Tick 15 more times — closing timer hits 0, transitions to $InRepository:")
    for i in 15:
        adv.tick()
    _expect("endgame state",      adv.endgame_state(),      "in_repository")
    _expect("not closing",        adv.endgame_closing(),    false)
    _expect("not won",            adv.endgame_won(),        false)

    print("Detonate in repository → $Won:")
    adv.detonate_marker()
    _expect("endgame state",      adv.endgame_state(),      "won")
    _expect("won flag",           adv.endgame_won(),        true)

    # ---------------------------------------------------------
    # Persistence: save mid-$Closing, mutate, restore
    # ---------------------------------------------------------
    print()
    print("Save mid-$Closing, mutate, restore — verify timer:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    for i in 10:
        adv2.deposit_treasure()
    _expect("entered closing",    adv2.endgame_state(),     "closing")
    for i in 23:
        adv2.tick()
    _expect("timer ≈ 7",          adv2.endgame_timer(),     7.0)

    var bytes = adv2.save_state()

    # Mutate after save
    for i in 7:
        adv2.tick()
    _expect("post-save state",    adv2.endgame_state(),     "in_repository")

    var adv3 = Cca.new()
    adv3.restore_state(bytes)
    _expect("restored state",     adv3.endgame_state(),     "closing")
    _expect("restored timer",     adv3.endgame_timer(),     7.0)
    _expect("restored treasures", adv3.endgame.treasures_count(), 10)

    # Replay forward from save
    for i in 7:
        adv3.tick()
    _expect("replay reaches repo",adv3.endgame_state(),     "in_repository")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
