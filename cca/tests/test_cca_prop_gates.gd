extends SceneTree

# Verifies the canon prop-conditioned gates wired in this batch:
#
#   `17 412021 7`   — FORWARD @ 17 with no bridge → die in canon 21
#   `27 412021 7`   — FORWARD @ 27 with no bridge → die in canon 21
#   `69 331120 46`  — SOUTH @ 69 after dragon killed → walk to 120
#   `74 331120 44`  — WEST  @ 74 after dragon killed → walk to 120
#   `117 332021 39` — JUMP @ 117 after bear-bridge collapsed → die
#   `122 332021 39` — JUMP @ 122 after bear-bridge collapsed → die
#
# The port models each via a single-rule gate (or a 2-rule chain
# at 117/122:jump where the post-bear death has to layer on top
# of the pre-bear msg #96 bumper).
#
# Each phase sets up the FSM state directly (rather than walking
# the puzzle path) so the test is fast and isolated. Drives the
# verb through _process_input so the full bumper-dispatch ladder
# runs.

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

class CapturedDriver:
    extends Driver
    var captured: Array = []
    func _println(text: String) -> void:
        self.captured.append(text)

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA prop-conditioned gates (5 canon rows, 6 verbs) ===")

    # ----- Phase 1: 17:forward + 27:forward — bridge missing → die -----
    print("Phase 1: fissure FORWARD with no bridge → death in canon 21")
    for room in [17, 27]:
        var d := _make_driver()
        d.fsm.player.move_to(room)
        _expect("setup: at room %d, bridge not built" % room,
            [d.fsm.player_room(), d.fsm.bridge_built()], [room, false])
        var lines: Array = _capture(d, "forward")
        _expect("FORWARD @ %d walks to canon 21 (death)" % room,
            d.fsm.player_room(), 21)
        _expect("FORWARD @ %d kills the player" % room,
            d.fsm.player_state(), "dead")
        _expect_any_match("FORWARD @ %d emits canon broken-bones msg" % room,
            lines, "didn't make it")

    # ----- Phase 2: 17:forward with bridge built — gate falls through -----
    print("Phase 2: fissure FORWARD with bridge built → no exit (gate falls through)")
    var d2 := _make_driver()
    d2.fsm.crystal_bridge.wave()                # build the bridge
    _expect("setup: bridge built", d2.fsm.bridge_built(), true)
    d2.fsm.player.move_to(17)
    var lines2: Array = _capture(d2, "forward")
    _expect("FORWARD @ 17 with bridge stays at 17",
        d2.fsm.player_room(), 17)
    _expect("FORWARD @ 17 with bridge: player alive",
        d2.fsm.player_state(), "alive")

    # ----- Phase 3: 69:south + 74:west pre-kill — topology fallback -----
    print("Phase 3: 69:south / 74:west pre-kill — topology fallback (snake-cleared 119/121)")
    for triple in [[69, "south", 119], [74, "west", 121]]:
        var d3 := _make_driver()
        _expect("setup: dragon alive", d3.fsm.dragon_alive(), true)
        d3.fsm.player.move_to(triple[0])
        d3._process_input(triple[1])
        _expect("pre-kill %d:%s walks to canon %d" % triple,
            d3.fsm.player_room(), triple[2])

    # ----- Phase 4: 69:south + 74:west post-kill — gate to 120 -----
    print("Phase 4: 69:south / 74:west after dragon killed → walk to canon 120")
    for pair in [[69, "south"], [74, "west"]]:
        var d4 := _make_driver()
        # Direct state mutation: drive Dragon to $Dead.
        d4.fsm.dragon.attack()                  # → $Asked
        d4.fsm.dragon.yes()                     # → $Dead
        _expect("setup: dragon killed", d4.fsm.dragon_alive(), false)
        d4.fsm.player.move_to(pair[0])
        d4._process_input(pair[1])
        _expect("post-kill %d:%s walks to canon 120 (connecting canyon)" % pair,
            d4.fsm.player_room(), 120)

    # ----- Phase 5: 117:jump + 122:jump pre-bear — msg #96 bumper -----
    print("Phase 5: 117/122:jump pre-bear → canon msg #96 'use the bridge'")
    for room in [117, 122]:
        var d5 := _make_driver()
        d5.fsm.player.move_to(room)
        var lines5: Array = _capture(d5, "jump")
        _expect("pre-bear JUMP @ %d stays put" % room,
            d5.fsm.player_room(), room)
        _expect_any_match("pre-bear JUMP @ %d emits msg #96" % room,
            lines5, "I respectfully suggest")

    # ----- Phase 6: 117:jump + 122:jump post-bear — death in canon 21 -----
    print("Phase 6: 117/122:jump after bear-bridge collapsed → die in canon 21")
    for room in [117, 122]:
        var d6 := _make_driver()
        # Direct state mutation: drive Troll to $Vanished
        # (the port's "chasm collapsed" state).
        d6.fsm.troll.scared_off()
        _expect("setup: troll vanished",
            d6.fsm.troll_state(), "vanished")
        d6.fsm.player.move_to(room)
        var lines6: Array = _capture(d6, "jump")
        _expect("post-bear JUMP @ %d walks to canon 21 (death)" % room,
            d6.fsm.player_room(), 21)
        _expect("post-bear JUMP @ %d kills the player" % room,
            d6.fsm.player_state(), "dead")
        _expect_any_match("post-bear JUMP @ %d emits broken-bones msg" % room,
            lines6, "didn't make it")

    if failures == 0:
        print("PASS — 5 canon prop-conditioned gates honor section-3 rows")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
