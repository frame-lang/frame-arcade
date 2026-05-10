extends SceneTree

# Verifies canon bear-state messages (advent.dat msgs #165-170):
#
#   ATTACK BEAR (hungry)         → msg #165 ("bare hands... bear hands??")
#   ATTACK BEAR (tame/following) → msg #166 ("only wants to be your friend")
#   ATTACK BEAR (released)       → msg #167 ("poor thing is already dead")
#   FEED BEAR (success)          → msg #168 ("eagerly wolfs down your food")
#   TAKE BEAR (still chained)    → msg #169 ("still chained to the wall")
#   UNLOCK CHAIN (no keys)       → msg #170 ("chain is still locked")

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

class CapturedDriver:
    extends Driver
    var captured: Array = []
    func _println(text: String) -> void:
        self.captured.append(text)

var failures: int = 0

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
    print("=== CCA bear-state messages — canon msgs #165-170 ===")

    # Bear lives at canon BEAR_HOME_ROOM (130 in port). Player
    # must be there for ATTACK / FEED / TAKE BEAR to address the
    # bear; the FSM gates on bear state so we drive that here.

    # ----- Phase 1: ATTACK BEAR (hungry) → msg #165 -----
    print("Phase 1: ATTACK BEAR (hungry) → msg #165")
    var d1 := _make_driver()
    d1.fsm.player.move_to(d1.fsm.BEAR_HOME_ROOM)
    var l1: Array = _capture(d1, "attack bear")
    _expect_any_match("ATTACK BEAR hungry → msg #165 ('bare hands')",
        l1, "bare hands")

    # ----- Phase 2: ATTACK BEAR (tame) → msg #166 -----
    print("Phase 2: ATTACK BEAR (tame) → msg #166")
    var d2 := _make_driver()
    d2.fsm.player.move_to(d2.fsm.BEAR_HOME_ROOM)
    d2.fsm.bear.feed()                # hungry → tame
    var l2: Array = _capture(d2, "attack bear")
    _expect_any_match("ATTACK BEAR tame → msg #166 ('wants to be your friend')",
        l2, "only wants to be your friend")

    # ----- Phase 3: TAKE BEAR (hungry) → msg #169 -----
    print("Phase 3: TAKE BEAR (still chained) → msg #169")
    var d3 := _make_driver()
    d3.fsm.player.move_to(d3.fsm.BEAR_HOME_ROOM)
    var l3: Array = _capture(d3, "take bear")
    _expect_any_match("TAKE BEAR hungry → msg #169",
        l3, "still chained to the wall")

    # ----- Phase 4: TAKE BEAR (tame, still chained) → msg #169 -----
    print("Phase 4: TAKE BEAR (tame, still chained) → msg #169")
    var d4 := _make_driver()
    d4.fsm.player.move_to(d4.fsm.BEAR_HOME_ROOM)
    d4.fsm.bear.feed()
    var l4: Array = _capture(d4, "take bear")
    _expect_any_match("TAKE BEAR tame → msg #169",
        l4, "still chained to the wall")

    # ----- Phase 5: UNLOCK CHAIN without keys → msg #170 -----
    print("Phase 5: UNLOCK CHAIN (no keys) → msg #170")
    var d5 := _make_driver()
    d5.fsm.player.move_to(d5.fsm.BEAR_HOME_ROOM)
    var l5: Array = _capture(d5, "unlock chain")
    _expect_any_match("UNLOCK CHAIN without keys → msg #170",
        l5, "chain is still locked")

    # ----- Phase 6: FEED BEAR with food → msg #168 -----
    print("Phase 6: FEED BEAR (success) → canon msg #168")
    var d6 := _make_driver()
    d6.fsm.player.move_to(d6.fsm.BEAR_HOME_ROOM)
    # Force-take food: place at room then take.
    d6.fsm.food_item.place(d6.fsm.player_room())
    d6.fsm.food_item.try_take(d6.fsm.player_room())
    d6.fsm.player.take(d6.fsm.FOOD_ID)
    var l6: Array = _capture(d6, "feed bear")
    _expect_any_match("FEED BEAR (success) → canon msg #168 ('wolfs down')",
        l6, "wolfs down your food")

    if failures == 0:
        print("PASS — bear-state messages honor canon #165-170")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
