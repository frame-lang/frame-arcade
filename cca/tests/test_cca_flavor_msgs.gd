extends SceneTree

# Verifies a batch of small canon flavor mechanics:
#
#   CALM/TAME             — canon msg #14 ("would you care to explain how?")
#   EAT <enemy>           — canon msg #71 ("don't be ridiculous!")
#   FEED bird             — canon msg #100 ("it's not hungry...")
#   FEED dwarf            — canon msg #103 ("dwarves eat only coal!")
#   FEED troll            — canon msg #182 ("gluttony is not one of...")
#   FEED snake            — canon msg #102 ("nothing here it wants to eat")
#   unknown verb random   — canon msg #60/#61/#13 mix (60/20/20)
#
# Sources: advent.for verb dispatch (STMT 9140 EAT, STMT 9210
# FEED) plus the unknown-verb randomization at STMT 3000.

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
    print("=== CCA flavor msgs (CALM/EAT/FEED variants + unknown-verb mix) ===")

    # ----- Phase 1: CALM/TAME -----
    print("Phase 1: CALM / TAME → canon flavor")
    var d := _make_driver()
    _expect_any_match("CALM emits canon prose",
        _capture(d, "calm"), "Would you care to explain")
    _expect_any_match("TAME emits canon prose",
        _capture(d, "tame"), "Would you care to explain")

    # ----- Phase 2: EAT ridiculous targets -----
    print("Phase 2: EAT <enemy> → canon msg #71")
    var d2 := _make_driver()
    for noun in ["bird", "snake", "clam", "dragon", "troll", "bear"]:
        _expect_any_match("EAT %s → 'don't be ridiculous'" % noun,
            _capture(d2, "eat " + noun), "ridiculous")

    # ----- Phase 3: FEED variants -----
    print("Phase 3: FEED variants")
    var d3 := _make_driver()
    _expect_any_match("FEED BIRD → canon 'pinin' for the fjords'",
        _capture(d3, "feed bird"), "fjords")
    _expect_any_match("FEED DWARF → canon 'eat only coal'",
        _capture(d3, "feed dwarf"), "eat only coal")
    _expect_any_match("FEED TROLL → canon 'gluttony is not one'",
        _capture(d3, "feed troll"), "Gluttony")
    _expect_any_match("FEED SNAKE → canon 'nothing it wants to eat'",
        _capture(d3, "feed snake"), "wants to eat")

    # ----- Phase 4: unknown-verb random distribution -----
    # Canon advent.for STMT 3000:
    #     SPK = 60
    #     IF (PCT(20)) SPK = 61
    #     IF (PCT(20)) SPK = 13
    # Two chained PCT(20) calls: 80%×80% = 64% msg #60,
    # 80%×20% = 16% msg #61, 20% msg #13.
    print("Phase 4: unknown-verb randomization (canon STMT 3000, 64/16/20)")
    seed(0xCABBA9E)
    var d4 := _make_driver()
    var c_60: int = 0       # canon msg #60
    var c_61: int = 0       # canon msg #61
    var c_13: int = 0       # canon msg #13
    var c_other: int = 0
    for i in 1000:
        var pre: int = d4.captured.size()
        d4._process_input("frobnicate")
        var lines: Array = d4.captured.slice(pre)
        var matched: bool = false
        for line in lines:
            if "I don't know that word" in line:
                c_60 += 1; matched = true; break
            if "What?" in line:
                c_61 += 1; matched = true; break
            if "I don't understand that" in line:
                c_13 += 1; matched = true; break
        if not matched:
            c_other += 1
    print("  observed: msg#60=%d / msg#61=%d / msg#13=%d / other=%d"
        % [c_60, c_61, c_13, c_other])
    # ±5σ tolerances: msg#60 ~640±76, msg#61 ~160±58, msg#13 ~200±63.
    if c_60 < 564 or c_60 > 716:
        print("  FAIL: msg#60 count %d outside [564, 716]" % c_60)
        failures += 1
    else:
        print("  ok   msg#60 'I don't know that word' ~640 (in [564, 716])")
    if c_61 < 102 or c_61 > 218:
        print("  FAIL: msg#61 count %d outside [102, 218]" % c_61)
        failures += 1
    else:
        print("  ok   msg#61 'What?' ~160 (in [102, 218])")
    if c_13 < 137 or c_13 > 263:
        print("  FAIL: msg#13 count %d outside [137, 263]" % c_13)
        failures += 1
    else:
        print("  ok   msg#13 'don't understand' ~200 (in [137, 263])")
    if c_other != 0:
        print("  FAIL: %d 'other' lines — randomization missed cases" % c_other)
        failures += 1
    else:
        print("  ok   no 'other' responses leaked through")

    if failures == 0:
        print("PASS — flavor msgs honor canon STMT 9140 / 9210 / 3000")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
