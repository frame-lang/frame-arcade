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
    print("Phase 4: unknown-verb randomization (canon STMT 3000, 60/20/20)")
    seed(0xCABBA9E)
    var d4 := _make_driver()
    var c_eh: int = 0
    var c_pardon: int = 0
    var c_understand: int = 0
    var c_other: int = 0
    for i in 1000:
        var pre: int = d4.captured.size()
        d4._process_input("frobnicate")
        var lines: Array = d4.captured.slice(pre)
        var matched: bool = false
        for line in lines:
            if "Eh?" in line:
                c_eh += 1; matched = true; break
            if "I beg your pardon" in line:
                c_pardon += 1; matched = true; break
            if "I don't understand that" in line:
                c_understand += 1; matched = true; break
        if not matched:
            c_other += 1
    print("  observed: Eh=%d / pardon=%d / understand=%d / other=%d"
        % [c_eh, c_pardon, c_understand, c_other])
    # Wide tolerance: 60% / 20% / 20% over 1000.
    if c_eh < 540 or c_eh > 660:
        print("  FAIL: Eh? hit count %d outside [540, 660]" % c_eh)
        failures += 1
    else:
        print("  ok   Eh? hit ~600 (in [540, 660])")
    if c_pardon < 150 or c_pardon > 250:
        print("  FAIL: pardon hit count %d outside [150, 250]" % c_pardon)
        failures += 1
    else:
        print("  ok   pardon hit ~200 (in [150, 250])")
    if c_understand < 150 or c_understand > 250:
        print("  FAIL: understand hit count %d outside [150, 250]" % c_understand)
        failures += 1
    else:
        print("  ok   understand hit ~200 (in [150, 250])")
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
