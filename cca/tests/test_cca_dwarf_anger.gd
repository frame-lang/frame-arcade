extends SceneTree

# Verifies canon dwarf-anger ramp (advent.for STMT 6090 +
# 9213 + DFLAG mechanics):
#
#   default `dwarf_anger = 2` → knife-throw hit pct = 0%
#                                (canon: first combat always misses)
#   FEED dwarf → bump_dwarf_anger() (canon DFLAG++)
#   try_throw_axe(anger) → roll < 95*(anger-2)/10
#                          (i.e. canon 95*(DFLAG-2)/1000 in pct)
#
# Also verifies FEED dwarf intercept emits canon msg #103
# ("dwarves eat only coal!") and routes through bump_dwarf_anger.

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

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-58s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-58s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
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
    print("=== CCA dwarf-anger ramp + FEED dwarf bump ===")

    # ----- Phase 1: default anger floor + 0% hit rate -----
    print("Phase 1: default anger=2 → 0% hit pct (canon first-combat miss)")
    var fsm := Cca.new()
    fsm.setup_default_aspects()
    fsm.wake_dwarves()
    _expect("default dwarf_anger == 2", fsm.get_dwarf_anger(), 2)
    var hits: int = 0
    for _i in 200:
        if fsm.dwarf1.try_throw_axe(2):
            hits += 1
    _expect("anger=2 produces 0 hits in 200 rolls", hits, 0)

    # ----- Phase 2: anger=10 → ~76% hit pct -----
    # 95*(10-2)/10 = 76. σ for 1000 rolls at 76% ≈ 13.5 → ±5σ ≈ ±68
    # → tolerance window [692, 828].
    print("Phase 2: anger=10 → ~76% hit pct (1000 rolls, ±5σ)")
    var fsm2 := Cca.new()
    fsm2.setup_default_aspects()
    fsm2.wake_dwarves()
    var hits2: int = 0
    for _i in 1000:
        if fsm2.dwarf1.try_throw_axe(10):
            hits2 += 1
    _expect_in_range("anger=10 hits in [692, 828] (canon 76%)",
        hits2, 692, 828)

    # ----- Phase 3: anger=5 → ~28.5% hit pct -----
    # 95*(5-2)/10 = 28. σ ≈ 14.3 → ±5σ ≈ ±72 → window [213, 357].
    print("Phase 3: anger=5 → ~28.5% hit pct")
    var fsm3 := Cca.new()
    fsm3.setup_default_aspects()
    fsm3.wake_dwarves()
    var hits3: int = 0
    for _i in 1000:
        if fsm3.dwarf1.try_throw_axe(5):
            hits3 += 1
    _expect_in_range("anger=5 hits in [213, 357]", hits3, 213, 357)

    # ----- Phase 4: bump_dwarf_anger() advances counter -----
    print("Phase 4: bump_dwarf_anger() increments DFLAG-equivalent")
    var fsm4 := Cca.new()
    fsm4.setup_default_aspects()
    _expect("baseline anger",                    fsm4.get_dwarf_anger(), 2)
    fsm4.bump_dwarf_anger()
    _expect("anger after 1 bump",                fsm4.get_dwarf_anger(), 3)
    fsm4.bump_dwarf_anger()
    fsm4.bump_dwarf_anger()
    _expect("anger after 3 bumps",               fsm4.get_dwarf_anger(), 5)

    # ----- Phase 5: FEED dwarf intercept emits canon msg + bumps anger -----
    print("Phase 5: FEED dwarf → canon msg #103 + anger bump")
    var d := _make_driver()
    var anger_before: int = d.fsm.get_dwarf_anger()
    var l5: Array = _capture(d, "feed dwarf")
    _expect_any_match("FEED dwarf emits 'dwarves eat only coal'",
        l5, "dwarves eat only coal")
    _expect("anger bumped by FEED",              d.fsm.get_dwarf_anger(),
                                                 anger_before + 1)

    # Repeat: each FEED bumps another point.
    _capture(d, "feed dwarf")
    _capture(d, "feed dwarf")
    _expect("3 FEEDs total → anger += 3",        d.fsm.get_dwarf_anger(),
                                                 anger_before + 3)

    if failures == 0:
        print("PASS — dwarf-anger ramp honors canon STMT 6090 + FEED bumps DFLAG")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
