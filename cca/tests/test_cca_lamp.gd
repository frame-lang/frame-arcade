extends SceneTree

# Smoke test for the CCA Lamp system + Adventure orchestrator.
# Verifies:
#   1. Initial state (Off, battery full).
#   2. light() takes us to $Bright; ticks drain battery.
#   3. Crossing dim_threshold transitions to $Dim with the
#      warning surfaced once.
#   4. Reaching battery=0 transitions to $Out; is_lit goes
#      false; "lamp ran out" message surfaced.
#   5. extinguish() returns to $Off (regardless of which $On
#      sub-state we were in).
#   6. refresh() from $Off resets battery; from $Out also
#      transitions to $Bright.
#   7. @@[persist] round-trip preserves Lamp state, battery,
#      Adventure turn count.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Lamp + Adventure smoke test ===")

    var adv = Cca.new()

    print("Initial state:")
    _expect("lamp state",   adv.get_lamp_state(), "off")
    _expect("battery",      adv.battery_left(),   330)
    _expect("is_lit",       adv.is_lit(),         false)
    _expect("turn count",   adv.turn_count(),     0)

    print("After light_lamp():")
    adv.light_lamp()
    _expect("lamp state",   adv.get_lamp_state(), "bright")
    _expect("is_lit",       adv.is_lit(),         true)
    _expect("battery",      adv.battery_left(),   330)

    print("Tick 299 times — still bright:")
    for i in 299:
        adv.tick()
    _expect("lamp state",   adv.get_lamp_state(), "bright")
    _expect("battery",      adv.battery_left(),   31)
    _expect("turn count",   adv.turn_count(),     299)

    print("Tick once more — should cross dim threshold:")
    adv.tick()
    _expect("lamp state",   adv.get_lamp_state(), "dim")
    _expect("battery",      adv.battery_left(),   30)
    _expect("warning text begins canon", adv.get_lamp_message().begins_with("Your lamp is getting dim."), true)

    print("Tick 30 more times — should hit Out at battery 0:")
    for i in 30:
        adv.tick()
    _expect("lamp state",   adv.get_lamp_state(), "out")
    _expect("battery",      adv.battery_left(),   0)
    _expect("is_lit",       adv.is_lit(),         false)

    print("Save state mid-Out, mutate, restore:")
    var bytes = adv.save_state()
    print("  save bytes: %d" % bytes.size())

    # Mutate after save: refresh + light up.
    adv.refresh_lamp()
    _expect("post-refresh lamp", adv.get_lamp_state(), "bright")
    _expect("post-refresh battery", adv.battery_left(), 330)

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored lamp state", adv2.get_lamp_state(), "out")
    _expect("restored battery",    adv2.battery_left(),   0)
    _expect("restored is_lit",     adv2.is_lit(),         false)
    _expect("restored turns",      adv2.turn_count(),     330)

    print("From restored Out: refresh and verify:")
    adv2.refresh_lamp()
    _expect("after refresh state",   adv2.get_lamp_state(), "bright")
    _expect("after refresh battery", adv2.battery_left(),   330)

    print("Extinguish → off, then re-light:")
    adv2.extinguish_lamp()
    _expect("after extinguish",      adv2.get_lamp_state(), "off")
    _expect("battery preserved",     adv2.battery_left(),   330)
    adv2.light_lamp()
    _expect("re-lit",                adv2.get_lamp_state(), "bright")

    # Edge case: refresh() while in $Off — should reset battery
    # but stay in $Off (to be lit explicitly).
    adv2.extinguish_lamp()
    # Drain manually first by lighting and ticking, then test
    # refresh from $Off.
    adv2.light_lamp()
    for i in 330:
        adv2.tick()
    _expect("drained to out again",  adv2.get_lamp_state(), "out")
    adv2.extinguish_lamp()
    _expect("now off post-out",      adv2.get_lamp_state(), "off")
    _expect("battery 0 in off",      adv2.battery_left(),   0)
    adv2.refresh_lamp()
    _expect("refresh from off keeps off", adv2.get_lamp_state(), "off")
    _expect("battery refilled in off",    adv2.battery_left(),   330)

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
