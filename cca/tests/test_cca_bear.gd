extends SceneTree

# Smoke test for the Bear FSM.
# Verifies:
#   - Initial state $Hungry — dangerous, not friendly.
#   - feed() → $Tame — friendly, not dangerous.
#   - take_chain() from $Tame → $Following.
#   - drop_chain() → $Released (terminal-ish).
#   - take_chain() from $Hungry (without feeding) → $Attacking
#     (the hazard branch).
#   - @@[persist] round-trips bear state across the whole tree.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Bear FSM smoke ===")

    # ---------------------------------------------------------
    # Path A: feed → tame → follow → release
    # ---------------------------------------------------------
    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Initial:")
    _expect("bear state",         adv.bear_state(),     "hungry")
    _expect("dangerous",          adv.bear_dangerous(), true)

    print("Feed:")
    adv.bear.feed()
    _expect("after feed",         adv.bear_state(),     "tame")
    _expect("not dangerous",      adv.bear_dangerous(), false)
    _expect("friendly",           adv.bear.is_friendly(), true)

    print("Take chain (safely from tame):")
    adv.bear.take_chain()
    _expect("after take_chain",   adv.bear_state(),     "following")
    _expect("still friendly",     adv.bear.is_friendly(), true)

    print("Drop chain → released:")
    adv.bear.drop_chain()
    _expect("after drop_chain",   adv.bear_state(),     "released")
    _expect("still friendly",     adv.bear.is_friendly(), true)
    _expect("not dangerous",      adv.bear_dangerous(), false)

    # ---------------------------------------------------------
    # Path B: hazard — take_chain from $Hungry
    # ---------------------------------------------------------
    print()
    print("Fresh adventure, take chain from hungry bear:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.bear.take_chain()
    _expect("after hostile chain", adv2.bear_state(),     "attacking")
    _expect("dangerous",           adv2.bear_dangerous(), true)
    _expect("not friendly",        adv2.bear.is_friendly(), false)

    # ---------------------------------------------------------
    # Path C: persistence round-trip mid-Following
    # ---------------------------------------------------------
    print()
    print("Persistence round-trip mid-Following:")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.bear.feed()
    adv3.bear.take_chain()
    var bytes = adv3.save_state()

    # Mutate post-save
    adv3.bear.drop_chain()
    _expect("post-save released",  adv3.bear_state(),    "released")

    var adv4 = Cca.new()
    adv4.restore_state(bytes)
    _expect("restored state",      adv4.bear_state(),    "following")
    _expect("restored friendly",   adv4.bear.is_friendly(), true)

    # And the FSM still works post-restore
    adv4.bear.drop_chain()
    _expect("after post-restore drop", adv4.bear_state(), "released")

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
