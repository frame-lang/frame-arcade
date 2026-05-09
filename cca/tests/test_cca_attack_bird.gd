extends SceneTree

# Verifies canon ATTACK BIRD (advent.for STMT 9120) → msg #137:
# "Oh, leave the poor unhappy bird alone."
#
# KILL BIRD is a synonym (canon verb 12 + KILL/FIGHT both map to
# attack via the synonym table).

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
    print("=== CCA ATTACK BIRD — canon msg #137 ===")

    # ----- Phase 1: ATTACK BIRD → msg #137 -----
    print("Phase 1: ATTACK BIRD → 'leave the poor unhappy bird alone'")
    var d := _make_driver()
    var l1: Array = _capture(d, "attack bird")
    _expect_any_match("ATTACK BIRD emits canon msg #137",
        l1, "leave the poor unhappy bird alone")

    # ----- Phase 2: KILL BIRD synonym → msg #137 -----
    print("Phase 2: KILL BIRD synonym → msg #137")
    var d2 := _make_driver()
    var l2: Array = _capture(d2, "kill bird")
    _expect_any_match("KILL BIRD emits canon msg #137",
        l2, "leave the poor unhappy bird alone")

    if failures == 0:
        print("PASS — ATTACK BIRD honors canon msg #137")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
