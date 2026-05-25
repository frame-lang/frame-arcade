extends SceneTree

# ============================================================
# test_cca_dwarf_hitrate_curve.gd
# ============================================================
# Tests the dwarf axe-throw hit rate as a FUNCTION of anger, not
# at a single operating point. The probe tests
# (test_cca_stochastic_probe_dwarf) pin one anger level; this
# verifies the whole response CURVE matches canon.
#
# Canon advent.for STMT 6090ish: a stalking dwarf's thrown axe
# hits with probability 95*(DFLAG-2)/1000 — i.e. 95*(anger-2)/10
# percent (npcs.gd _s_Stalking_hdl_user_try_throw_axe). DFLAG=2
# (first combat) always misses; the rate ramps to ~95% by
# anger 12 and saturates at 100% beyond.
#
# For each anger 2..12 we throw across a fixed seed set and check
# the empirical hit rate lands within TOL of the formula. This is
# deterministic (fixed seeds) yet robust to the exact LCG: a
# uniform PRNG of ANY constants tracks the curve, but a formula or
# wiring bug (e.g. an off-by-one in the anger→DFLAG mapping, or a
# wrong divisor) shifts a point ~10-19% — far past TOL — and fails
# loudly. Also checks the curve is monotonic non-decreasing.
# ============================================================

const NPCs = preload("res://scripts/npcs.gd")

const N: int = 400          # throws per anger level
const TOL: int = 5          # max |empirical − formula| in percentage points

func _init():
    print("=== CCA dwarf axe-throw hit-rate curve vs canon 95*(anger-2)/10%% ===")
    var fails: Array = []
    var prev_emp: int = -1

    for anger in range(2, 13):
        var pct: int = 95 * (anger - 2) / 10
        if pct > 100:
            pct = 100
        var hits: int = 0
        for seed in range(1, N + 1):
            var dw = NPCs.Dwarf._create(seed)
            dw.wake_up(20)
            if dw.try_throw_axe(anger):
                hits += 1
        var emp: int = int(round(100.0 * hits / N))
        var delta: int = emp - pct
        print("  anger %2d: formula %3d%%  empirical %3d%%  (%+d)" % [anger, pct, emp, delta])

        if abs(delta) > TOL:
            fails.append("anger %d: empirical %d%% off formula %d%% by %d (> %d)" % [
                anger, emp, pct, abs(delta), TOL])
        if emp < prev_emp:
            fails.append("anger %d: curve dropped (%d%% < prev %d%%)" % [anger, emp, prev_emp])
        prev_emp = emp

    # Anchor checks: the canon endpoints must be exact-ish.
    # anger 2 = first combat, always misses (0%).
    var miss_hits: int = 0
    for seed in range(1, N + 1):
        var dw = NPCs.Dwarf._create(seed)
        dw.wake_up(20)
        if dw.try_throw_axe(2):
            miss_hits += 1
    if miss_hits != 0:
        fails.append("anger 2 (first combat) must always miss; got %d hits" % miss_hits)

    if fails.is_empty():
        print("PASS — dwarf hit-rate curve matches canon across anger 2..12")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
    quit(1)
