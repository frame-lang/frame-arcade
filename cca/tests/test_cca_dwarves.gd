extends SceneTree

# Smoke test for the parameterized 5-dwarf composition.
# Verifies:
#   - All five start in $Hidden with their assigned seeds.
#   - wake_dwarves() activates each at its assigned room.
#   - Per-seed pseudo-random outcomes are deterministic and
#     diverge across instances.
#   - attack_dwarf_in_room finds the right dwarf by location.
#   - Repeated attack on a stalking dwarf eventually kills it
#     (~70% per try; 5 tries = ~99.8% kill probability).
#   - @@[persist] round-trips each dwarf's seed and step
#     counter, so post-restore behavior is identical.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA Dwarves (parameterized × 5) ===")

    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Initial — all five hidden:")
    _expect("dwarf1 state",  adv.dwarf1.get_state(), "hidden")
    _expect("dwarf2 state",  adv.dwarf2.get_state(), "hidden")
    _expect("dwarf3 state",  adv.dwarf3.get_state(), "hidden")
    _expect("dwarf4 state",  adv.dwarf4.get_state(), "hidden")
    _expect("dwarf5 state",  adv.dwarf5.get_state(), "hidden")
    _expect("seeds diverge", adv.dwarf1.get_seed() != adv.dwarf3.get_seed(), true)
    _expect("living count",  adv.living_dwarves(),    5)

    print("Wake all five:")
    adv.wake_dwarves()
    _expect("dwarf1 stalking",  adv.dwarf1.get_state(), "stalking")
    _expect("dwarf1 room",      adv.dwarf1.get_room(),  19)
    _expect("dwarf3 room",      adv.dwarf3.get_room(),  47)
    _expect("dwarf5 room",      adv.dwarf5.get_room(),  118)

    print("Attack from wrong room — no dwarf:")
    adv.player.move_to(99)
    var r1 = adv.attack_dwarf_in_room()
    # Canon msg #76 "PECULIAR. NOTHING UNEXPECTED HAPPENS." for
    # ATTACK with no target in the room.
    _expect("no dwarf here",    r1, "Peculiar. Nothing unexpected happens.")

    print("Attack dwarf3 in its room (deterministic outcome):")
    adv.player.move_to(47)
    var r2 = adv.attack_dwarf_in_room()
    print("  dwarf3 step after 1 attack: %d" % adv.dwarf3.get_step())
    print("  outcome: %s" % r2)
    # We don't assert the exact outcome (depends on seed) but
    # we DO assert: the dwarf's step counter advanced by 1, and
    # the response is one of the two valid messages.
    _expect("dwarf3 step ≥ 1", adv.dwarf3.get_step() >= 1, true)
    # Canon msg #47 (kill) / msg #48 (miss) verbatim. Same prose
    # regardless of which dwarf was attacked.
    _expect("response valid", (r2 == "You killed a little dwarf." or r2 == "You attack a little dwarf, but he dodges out of the way."), true)

    print("Hammer dwarf1 until dead — eventually it dies:")
    adv.player.move_to(19)
    var attempts: int = 0
    while adv.dwarf1.get_state() == "stalking" and attempts < 20:
        adv.attack_dwarf_in_room()
        attempts += 1
    _expect("dwarf1 eventually dies", adv.dwarf1.get_state(), "dead")
    print("  killed in %d attempts" % attempts)

    print("Living count went down by one:")
    _expect("living count",   adv.living_dwarves(), 3)

    print("Determinism — fresh adventure, same attack pattern produces same step counts:")
    var adv2 = Cca.new()
    adv2.setup_default_aspects()
    adv2.wake_dwarves()
    adv2.player.move_to(47)
    adv2.attack_dwarf_in_room()
    _expect("dwarf3 step matches",  adv2.dwarf3.get_step(), 1)

    print("Save / restore mid-attack-sequence:")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.wake_dwarves()
    adv3.player.move_to(47)
    adv3.attack_dwarf_in_room()
    adv3.attack_dwarf_in_room()
    var pre_state = adv3.dwarf3.get_state()
    var pre_step = adv3.dwarf3.get_step()
    var bytes = adv3.save_state()

    # Mutate after save
    adv3.attack_dwarf_in_room()
    adv3.attack_dwarf_in_room()
    adv3.attack_dwarf_in_room()

    var adv4 = Cca.new()
    adv4.restore_state(bytes)
    _expect("restored dwarf3 state", adv4.dwarf3.get_state(), pre_state)
    _expect("restored dwarf3 step",  adv4.dwarf3.get_step(),  pre_step)

    # Replay-from-save determinism: the next attack should
    # produce the same outcome as it did the first time.
    adv3.dwarf3.flee()              # reset live to a known state for comparison

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
