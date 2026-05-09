extends SceneTree

# Verifies three canon dwarf mechanics (advent.for STMT 71/6000/
# 9010 + msgs #2/#3/#116):
#
#   msg #2  — movement into a stalking-dwarf room is blocked
#   msg #3  — first stalking-dwarf encounter narrates the canon
#             "walked around a corner, threw a little axe..." prose
#   msg #116 — TAKE KNIFE always emits "knives vanish" rebuff
#
# CapturedDriver bypasses _ready(), so tests must call
# fsm.wake_dwarves() explicitly before running movement checks.

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

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-58s line contained banned '%s'" % [
                label, needle])
            failures += 1
            return
    print("  ok   %-58s no line contained '%s'" % [label, needle])

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
    print("=== CCA dwarf canon — msgs #2 / #3 / #116 ===")

    # ----- Phase 1: movement into a stalking-dwarf room blocks -----
    # wake_dwarves places dwarf1 at canon 12 (East Canyon). From
    # canon 11 (East End of Hall of Mists), WEST → 12 should be
    # blocked by dwarf1.
    print("Phase 1: movement into stalking-dwarf room → msg #2")
    var d1 := _make_driver()
    d1.fsm.wake_dwarves()
    d1.fsm.player.move_to(11)         # canon East End of Hall of Mists
    var l1: Array = _capture(d1, "west")     # 11 → 12 has dwarf1
    _expect_any_match("walking into dwarf1's room emits msg #2",
        l1, "little dwarf with a big knife")
    _expect("player blocked, still at 11",   d1.fsm.player_room(), 11)

    # ----- Phase 2: msg #2 doesn't fire when no dwarf is adjacent -----
    print("Phase 2: movement with no dwarf at dest does NOT fire msg #2")
    var d2 := _make_driver()
    d2.fsm.wake_dwarves()
    d2.fsm.player.move_to(3)          # canon Inside Building
    var l2: Array = _capture(d2, "out")      # 3 → 1 (no dwarf at 1)
    _expect_no_match("no msg #2 when dest has no dwarf",
        l2, "little dwarf with a big knife")

    # ----- Phase 3: msg #3 first-encounter narration -----
    # Drive the player to dwarf1's room (canon 12) by force-placing.
    # _print_room is what fires the msg #3 narration on first
    # entry. Since we use _print_room directly the visit counts.
    print("Phase 3: first stalking-dwarf encounter → msg #3")
    var d3 := _make_driver()
    d3.fsm.wake_dwarves()
    d3.fsm.player.move_to(12)
    var pre3: int = d3.captured.size()
    d3._print_room()
    var lines3: Array = d3.captured.slice(pre3)
    _expect_any_match("first encounter narrates canon msg #3",
        lines3, "walked around a corner")
    # Second visit: no second narration.
    var pre3b: int = d3.captured.size()
    d3._print_room()
    var lines3b: Array = d3.captured.slice(pre3b)
    _expect_no_match("second visit does NOT re-narrate msg #3",
        lines3b, "walked around a corner")

    # ----- Phase 4: TAKE KNIFE → msg #116 -----
    print("Phase 4: TAKE KNIFE → canon msg #116")
    var d4 := _make_driver()
    var l4: Array = _capture(d4, "take knife")
    _expect_any_match("TAKE KNIFE emits canon msg #116",
        l4, "knives vanish as they strike")

    # GET KNIFE synonym → same msg
    var l4b: Array = _capture(d4, "get knife")
    _expect_any_match("GET KNIFE (synonym) emits canon msg #116",
        l4b, "knives vanish as they strike")

    if failures == 0:
        print("PASS — dwarf canon honors msgs #2 / #3 / #116")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
