extends SceneTree

# Smoke test for ScoreLedger (observe verdict).
# Verifies:
#   - try_handle is called for every dispatched event.
#   - Returns verdict=observe; never blocks the chain.
#   - Counts grow regardless of what other aspects do.
#   - Counts persist across save/restore.
#
# Important subtlety: a "consume" higher up the bus stops
# dispatch BEFORE ScoreLedger runs (because score=100 is
# below the consumers). So darkness-consumed and backpack-
# consumed commands DON'T show up in commands_seen.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA ScoreLedger (observe verdict) ===")

    var adv = Cca.new()
    adv.setup_default_aspects()

    print("Pass-through commands all observed:")
    adv.do_command("look", "")          # at end-of-road (1), lit, observed
    adv.player.move_to(11)              # into debris room (dark)
    adv.do_command("look", "")          # in dark room — consumed by darkness, NOT observed
    _expect("commands seen",     adv.commands_seen(), 1)
    _expect("darkness consumed", adv.darkness_consumed_count(), 1)

    print("Take a real treasure — observed and rolls up into the canonical score:")
    adv.do_command("light", "")          # 1 more observed
    var pre_cmds: int = adv.commands_seen()
    var r = adv.do_command("take", "gold")  # player at room 11 (debris), gold is here
    _expect("take observed (no consume)", adv.commands_seen(), pre_cmds + 1)
    _expect("take returned 'Taken'",      r.contains("Taken"),  true)

    print("Fill to limit by direct stuffing, then attempt one more take:")
    for i in range(101, 107):
        adv.player.take(i)               # six dummy IDs — bus not involved
    _expect("inventory at limit", adv.player.inventory_size(), 7)

    var pre_cmds_2: int = adv.commands_seen()
    adv.player.move_to(33)                # silver here
    adv.do_command("take", "silver")    # consumed by BackpackLimit, ledger not observed
    _expect("backpack blocked",     adv.backpack_blocked_count(),    1)
    _expect("commands unchanged",   adv.commands_seen(),             pre_cmds_2)

    print("Save / restore preserves ledger:")
    var bytes = adv.save_state()
    adv.do_command("look", "")           # mutates after save
    adv.do_command("look", "")
    var live_cmds: int = adv.commands_seen()

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored commands",  adv2.commands_seen(), live_cmds - 2)

    print()
    if failures == 0:
        print("PASS")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
