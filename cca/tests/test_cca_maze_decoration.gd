extends SceneTree

# Verifies the canon "twisty maze" probabilistic-walk
# decoration at canon rooms 5 (forest), 65 (Bedquilt), 66
# (Swiss Cheese), and 111 (top of stalactite). Each verb at
# each room is a chain of probability rolls walked in canonical
# section-3 order; first hit wins, misses fall through to
# topology or no-exit.
#
# This test verifies BOTH gate shape (chains exist with right
# rules) and behavior under pinned RNG. Behavior tests use
# isolated _try_bumper_rule calls (rather than _process_input)
# to avoid lamp/dwarf-tick interference over large N — the
# pattern established in test_cca_19_sw_chain.gd Phase 5.
#
# Canon rows tested:
#   5   50005 6 7 45    forest/forward/north 50% self-loop
#   65  80556 46        south 80% bumper
#   65  80556 29        up   80% bumper
#   65  50070 29        up   50% to 70 (after 80% miss)
#   65  60556 45        north 60% bumper
#   65  75072 45        north 75% to 72 (after 60% miss)
#   65  80556 30        down 80% bumper
#   66  80556 46        south 80% bumper
#   66  50556 50        nw   50% bumper
#   111 40050 30 39 56  down/jump/climb 40% to 50
#   111 50053 30        down 50% to 53 (after 40% miss)

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const Topology = preload("res://scripts/topology.gd")

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

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-58s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-58s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
        failures += 1

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

# Roll the gate chain at (room, verb) N times under pinned RNG,
# counting hits per "fired-with-which-rule" outcome. Returns
# {"hit_room_X": count, ..., "fall_through": count}.
#
# Resets the player to `room` before each roll so the chain
# always evaluates from the same starting point. Direct
# _try_bumper_rule calls bypass tick/lamp consumption.
func _roll_chain(d: CapturedDriver, room: int, verb: String, n: int) -> Dictionary:
    var key: String = "%d:%s" % [room, verb]
    var entry = Topology.GATES.get(key, null)
    if entry == null:
        return {"error": "no gate at " + key}
    var rules: Array = entry if entry is Array else [entry]
    var counts: Dictionary = {"fall_through": 0}
    for _i in range(n):
        d.fsm.player.move_to(room)
        var fired_idx: int = -1
        for ri in range(rules.size()):
            if d._try_bumper_rule(rules[ri]):
                fired_idx = ri
                break
        var bucket: String
        if fired_idx == -1:
            bucket = "fall_through"
        else:
            var rule: Dictionary = rules[fired_idx]
            if "dest" in rule:
                bucket = "rule%d_dest_%d" % [fired_idx, int(rule.dest)]
            else:
                bucket = "rule%d_msg" % fired_idx
        counts[bucket] = counts.get(bucket, 0) + 1
    return counts

func _init():
    print("=== CCA twisty-maze probabilistic-walk decoration ===")

    # ----- Phase 1: room 5 forest random walk (canon `5 50005`) -----
    print("Phase 1: room 5 forest random walk — 50% self-loop")
    seed(0xCABBA9E)
    var d := _make_driver()
    for verb in ["forest", "forward", "north"]:
        var counts: Dictionary = _roll_chain(d, 5, verb, 1000)
        var loop: int = counts.get("rule0_dest_5", 0)
        var fall: int = counts.get("fall_through", 0)
        print("  5:%-7s %s" % [verb, str(counts)])
        _expect_in_range("5:%s self-loop hits ~500" % verb, loop, 425, 575)
        _expect_in_range("5:%s fall-through ~500" % verb, fall, 425, 575)

    # ----- Phase 2: room 65 Bedquilt — four directional chains -----
    print("Phase 2: room 65 Bedquilt maze chains")
    seed(0xCABBA9E)
    var d2 := _make_driver()

    var south: Dictionary = _roll_chain(d2, 65, "south", 1000)
    print("  65:south  %s" % str(south))
    _expect_in_range("65:south msg ~800",
        south.get("rule0_msg", 0), 750, 850)
    _expect_in_range("65:south fall-through ~200",
        south.get("fall_through", 0), 150, 250)

    var up: Dictionary = _roll_chain(d2, 65, "up", 1000)
    print("  65:up     %s" % str(up))
    _expect_in_range("65:up msg ~800",
        up.get("rule0_msg", 0), 750, 850)
    _expect_in_range("65:up to-70 ~100 (50% of remaining 200)",
        up.get("rule1_dest_70", 0), 60, 140)
    _expect_in_range("65:up fall-through ~100",
        up.get("fall_through", 0), 60, 140)

    var north: Dictionary = _roll_chain(d2, 65, "north", 1000)
    print("  65:north  %s" % str(north))
    _expect_in_range("65:north msg ~600",
        north.get("rule0_msg", 0), 550, 650)
    _expect_in_range("65:north to-72 ~300 (75% of remaining 400)",
        north.get("rule1_dest_72", 0), 250, 350)
    _expect_in_range("65:north fall-through ~100",
        north.get("fall_through", 0), 60, 140)

    var down: Dictionary = _roll_chain(d2, 65, "down", 1000)
    print("  65:down   %s" % str(down))
    _expect_in_range("65:down msg ~800",
        down.get("rule0_msg", 0), 750, 850)
    _expect_in_range("65:down fall-through ~200",
        down.get("fall_through", 0), 150, 250)

    # ----- Phase 3: room 66 Swiss Cheese -----
    print("Phase 3: room 66 Swiss Cheese maze chains")
    seed(0xCABBA9E)
    var d3 := _make_driver()

    var s66: Dictionary = _roll_chain(d3, 66, "south", 1000)
    print("  66:south  %s" % str(s66))
    _expect_in_range("66:south msg ~800",
        s66.get("rule0_msg", 0), 750, 850)

    var nw66: Dictionary = _roll_chain(d3, 66, "nw", 1000)
    print("  66:nw     %s" % str(nw66))
    _expect_in_range("66:nw msg ~500",
        nw66.get("rule0_msg", 0), 450, 550)
    _expect_in_range("66:nw fall-through ~500",
        nw66.get("fall_through", 0), 450, 550)

    # ----- Phase 4: room 111 stalactite -----
    print("Phase 4: room 111 stalactite probabilistic descent")
    seed(0xCABBA9E)
    var d4 := _make_driver()

    var d111: Dictionary = _roll_chain(d4, 111, "down", 1000)
    print("  111:down  %s" % str(d111))
    _expect_in_range("111:down to-50 ~400",
        d111.get("rule0_dest_50", 0), 350, 450)
    _expect_in_range("111:down to-53 ~300 (50% of remaining 600)",
        d111.get("rule1_dest_53", 0), 250, 350)
    _expect_in_range("111:down fall-through ~300",
        d111.get("fall_through", 0), 250, 350)

    var j111: Dictionary = _roll_chain(d4, 111, "jump", 1000)
    print("  111:jump  %s" % str(j111))
    _expect_in_range("111:jump to-50 ~400",
        j111.get("rule0_dest_50", 0), 350, 450)
    _expect_in_range("111:jump fall-through ~600",
        j111.get("fall_through", 0), 550, 650)

    var c111: Dictionary = _roll_chain(d4, 111, "climb", 1000)
    print("  111:climb %s" % str(c111))
    _expect_in_range("111:climb to-50 ~400",
        c111.get("rule0_dest_50", 0), 350, 450)

    if failures == 0:
        print("PASS — twisty-maze decoration honors canon section-3 probability rows")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
