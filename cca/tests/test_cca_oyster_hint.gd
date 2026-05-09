extends SceneTree

# Verifies canon OYSTER hint chain (advent.dat msgs #192/193/194):
#
#   READ OYSTER first time   → msg #192 prompt (Y/N, 10-pt cost)
#   YES                      → msg #193 reveal + 10-pt deduction
#   NO                       → cancel, no penalty
#   READ OYSTER post-reveal  → msg #194 ("same thing")
#
# Setup: clam must be broken first to materialize the oyster
# scenery in the player's room. We force the FSM into the
# post-clam-break state by giving the player the rod, placing
# the clam in the room, and breaking it.

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

func _make_driver_with_oyster() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    # Break the clam to spawn the oyster at the current room.
    # Item state needs both Item.try_take (to transition the
    # Item FSM from $InRoom → $Carried) AND player.take (to
    # update the inventory list). The FSM's _verb_take wraps
    # both; tests force-place by mimicking that pair.
    var here: int = d.fsm.player_room()
    d.fsm.clam_item.place(here)
    d.fsm.clam_item.try_take(here)
    d.fsm.player.take(d.fsm.CLAM_ID)
    d.fsm.rod_item.place(here)
    d.fsm.rod_item.try_take(here)
    d.fsm.player.take(d.fsm.ROD_ID)
    d.fsm.do_command("break", "clam")
    return d

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA oyster hint chain — msgs #192/193/194 ===")

    # ----- Phase 1: first READ OYSTER → prompt -----
    print("Phase 1: READ OYSTER first time → msg #192 prompt")
    var d := _make_driver_with_oyster()
    var l1: Array = _capture(d, "read oyster")
    _expect_any_match("READ OYSTER emits canon prompt msg #192",
        l1, "10 points")
    _expect("prompt active",                d._oyster_prompt_active, true)
    _expect("not yet revealed",             d._oyster_revealed,      false)

    # ----- Phase 2: YES at prompt → msg #193 + 10-pt deduction -----
    print("Phase 2: YES → msg #193 reveal + 10-pt deduction")
    var score_before: int = d.fsm.score()
    var hints_before: int = d.fsm.hint_penalty()
    var l2: Array = _capture(d, "yes")
    _expect_any_match("YES emits canon msg #193 reveal",
        l2, "something strange about this place")
    _expect_any_match("YES emits 'words I've always known' hint",
        l2, "words I've always known")
    _expect("revealed flag set",            d._oyster_revealed,      true)
    _expect("prompt cleared",               d._oyster_prompt_active, false)
    _expect("score dropped by 10",          d.fsm.score(),           score_before - 10)
    _expect("hint penalty dropped by 10",   d.fsm.hint_penalty(),    hints_before - 10)

    # ----- Phase 3: re-read after reveal → msg #194 -----
    print("Phase 3: re-read after reveal → msg #194 ('same thing')")
    var l3: Array = _capture(d, "read oyster")
    _expect_any_match("re-read emits canon msg #194",
        l3, "same thing it did before")

    # ----- Phase 4: NO branch — cancel without penalty -----
    print("Phase 4: NO at prompt → cancels with no penalty")
    var d2 := _make_driver_with_oyster()
    _capture(d2, "read oyster")             # arm prompt
    _expect("prompt armed",                 d2._oyster_prompt_active, true)
    var score_b4: int = d2.fsm.score()
    var l4: Array = _capture(d2, "no")
    _expect_any_match("NO emits 'OK.'",     l4, "OK.")
    _expect("prompt cleared",               d2._oyster_prompt_active, false)
    _expect("not revealed",                 d2._oyster_revealed,      false)
    _expect("score unchanged",              d2.fsm.score(),           score_b4)

    # Re-reading after a NO should re-prompt (canon: not revealed).
    var l4b: Array = _capture(d2, "read oyster")
    _expect_any_match("post-NO re-read re-prompts canon msg #192",
        l4b, "10 points")

    # ----- Phase 5: EXAMINE OYSTER also triggers the chain -----
    print("Phase 5: EXAMINE OYSTER (synonym) also enters the chain")
    var d3 := _make_driver_with_oyster()
    var l5: Array = _capture(d3, "examine oyster")
    _expect_any_match("EXAMINE OYSTER prompts canon msg #192",
        l5, "10 points")

    if failures == 0:
        print("PASS — oyster hint chain honors canon msgs #192/193/194")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
