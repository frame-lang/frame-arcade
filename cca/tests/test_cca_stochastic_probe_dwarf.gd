extends SceneTree

# ============================================================
# test_cca_stochastic_probe_dwarf.gd
# ============================================================
# Fifth StochasticProbe binding, and the second NPC-internal PRNG
# (after the pirate): the DWARF's axe throw. Canon advent.for STMT
# 6090ish — a stalking dwarf throws an axe with hit rate
# 95*(DFLAG-2)/10 %, ramping with the dwarves' anger. The Dwarf
# FSM rolls this on its own (seed, attack_step) stream
# (npcs.gd _s_Stalking_hdl_user_try_throw_axe), separate from the
# player-attacks-dwarf rolls.
#
# Probed at anger 10 (canon "fully angry" → 76% hit). Per trial:
# a fresh Dwarf seeded to the trial seed, woken to $Stalking, one
# try_throw_axe(10). Over seeds 1..50:
#   • branch coverage — both hit and miss occur, and
#   • golden exact counts — {hit(1): 39, miss(0): 11}.
# 39/50 = 78 % tracks the canon 76 % hit rate at anger 10.
# ============================================================

const NPCs = preload("res://scripts/npcs.gd")
const StochasticProbe = preload("res://scripts/stochastic_probe.gd")

const ANGER := 10
const GOLDEN := {1: 39, 0: 11}   # 1 = hit, 0 = miss

func _init():
    print("=== CCA stochastic probe: dwarf axe throw (76% gate @ anger 10) ===")

    var probe = StochasticProbe._create()
    while not probe.is_done():
        var seed: int = probe.next_seed()
        var dw = NPCs.Dwarf._create(seed)
        dw.wake_up(20)                       # Hidden -> Stalking
        var hit: bool = dw.get_state() == "stalking" and dw.try_throw_axe(ANGER)
        probe.record(1 if hit else 0)

    var got := {1: probe.count(1), 0: probe.count(0)}
    print("  trials=%d  distinct=%d  tally=%s" % [
        probe.trials_done(), probe.distinct_outcomes(), str(got)])

    var fails: Array = []
    for branch in GOLDEN:
        if probe.count(branch) <= 0:
            fails.append("outcome %d never occurred" % branch)
        if probe.count(branch) != GOLDEN[branch]:
            fails.append("count(%d)=%d, golden %d" % [branch, probe.count(branch), GOLDEN[branch]])
    if probe.distinct_outcomes() != GOLDEN.size():
        fails.append("distinct outcomes %d, expected %d" % [probe.distinct_outcomes(), GOLDEN.size()])
    if probe.trials_done() != 50:
        fails.append("trials %d, expected 50" % probe.trials_done())

    if fails.is_empty():
        print("PASS — dwarf axe throw covers hit+miss; golden tally locked (78%% ≈ canon 76%%)")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
    quit(1)
