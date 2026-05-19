extends SceneTree

# ============================================================
# test_cca_death_scenarios.gd
# ============================================================
# Canon-fidelity coverage for the multi-step death scenarios
# that no other test exercises end-to-end through player
# commands. The simpler deaths are covered elsewhere:
#
#   • Surface pit-fall (jump at 35/88/110, gold-carry-down-14):
#     test_cca_death_paths.gd
#   • Dark-pit fall (canon msg #16 + 35% gamble): test_cca_
#     dark_pit_fall.gd (uses a retry loop to handle the
#     probabilistic roll)
#   • Dwarf knife (count-aware ladder): test_cca_dwarf_canon.gd
#     + test_cca_dwarf_anger.gd
#
# Scenarios covered here:
#
#   • Bear take-chain at $Hungry (cca.fgd:3110-3119) — at the
#     bear's home room with the bear unfed, TAKE CHAIN
#     transitions Bear $Hungry → $Attacking AND fires
#     player.die. Canon: "With a roar the bear lunges at you.
#     You should have fed it first."
#   • Bridge collapse with bear following (driver.gd:1239,
#     canon msg #162) — bear in $Following, troll vanished/
#     paid, bridge built, player at canon 117. Crossing fires
#     the collapse prose; player dies.
#
# Each scenario sets up FSM state directly (bear/troll/bridge
# transitions), then triggers the death through real player
# commands via Driver._process_input — same shape as canon:
# the death is the response to a player verb, not an FSM-
# internal teleport.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _init():
    print("=== CCA multi-step death-scenario tests ===")
    print("")
    _scenario_bear_take_chain()
    _scenario_bridge_collapse_with_bear()
    print("")
    if failures == 0:
        print("PASS — multi-step canon death scenarios fire correctly")
        quit(0)
        return
    print("FAIL — %d death scenario(s) diverged from canon" % failures)
    quit(failures)

# ----- Scenario 1: bear take-chain at $Hungry -----
func _scenario_bear_take_chain() -> void:
    print("--- bear_take_chain ---")
    var d = H.make_driver()
    # Default state: bear $Hungry, chain at bear's home room.
    # Move to BEAR_HOME_ROOM (canon 130) and attempt to take
    # chain — bear lunges + player dies.
    d.fsm.player.move_to(d.fsm.BEAR_HOME_ROOM)
    var lines: Array = H.capture(d, "take chain")
    _assert_lines("bear-hungry take-chain prose", lines, "with a roar the bear lunges")
    _assert_state(d, "player_state", "dead")

# ----- Scenario 2: bridge collapse with bear following -----
func _scenario_bridge_collapse_with_bear() -> void:
    print("--- bridge_collapse_with_bear ---")
    var d = H.make_driver()
    # Set up: bear $Following (fed + chain taken via FSM-direct
    # transitions), troll paid, crystal bridge built. Place
    # player at canon 117 (Troll Bridge approach). Player has
    # chain in inventory (canon "FOLLOWED BY... TAME BEAR" state
    # requires chain carried).
    d.fsm.bear.feed()                    # $Hungry → $Tame
    d.fsm.bear.take_chain()              # $Tame → $Following
    d.fsm.player.take(d.fsm.CHAIN_ID)    # chain into player inv
    d.fsm.chain.try_take(d.fsm.BEAR_HOME_ROOM)  # chain treasure $Carried
    d.fsm.troll.pay_toll()               # troll vanished
    d.fsm.crystal_bridge.wave()          # bridge built
    d.fsm.player.move_to(117)
    var lines: Array = H.capture(d, "cross")
    _assert_lines("bridge collapse prose", lines, "bridge buckles beneath the weight of the bear")
    _assert_state(d, "player_state", "dead")

# ============================================================
# Helpers
# ============================================================

func _assert_lines(name: String, lines: Array, needle: String) -> void:
    var joined: String = "\n".join(lines).to_lower()
    if needle.to_lower() in joined:
        print("  OK   %s" % name)
        return
    print("  FAIL %s — '%s' not in captured" % [name, needle])
    print("        captured: %s" % joined.substr(0, 200))
    failures += 1

func _assert_state(d, key: String, expected) -> void:
    var got
    match key:
        "player_state":  got = d.fsm.player_state()
        "player_room":   got = d.fsm.player_room()
        _:               got = null
    if got == expected:
        print("  OK   %s == %s" % [key, str(expected)])
        return
    print("  FAIL %s — expected %s, got %s" % [key, str(expected), str(got)])
    failures += 1
