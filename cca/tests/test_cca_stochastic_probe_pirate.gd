extends SceneTree

# ============================================================
# test_cca_stochastic_probe_pirate.gd
# ============================================================
# Reuses the domain-agnostic StochasticProbe FSM to verify a
# different randomized section: the PIRATE's steal roll. Where
# test_cca_stochastic_probe drives a travel gate (Chance-system
# RNG), this drives an NPC's own internal PRNG — same probe, a
# different random subsystem — proving the probe is general.
#
# The pirate's try_steal() is a 25% gate on the Pirate FSM's own
# (seed, step) LCG (npcs.gd _s_Stalking_hdl_user_try_steal). Per
# trial: construct a fresh Pirate seeded to the trial seed,
# activate it to $Stalking (treasures_carried ≥ threshold), and
# roll try_steal() once. Outcome 1 = stole (→ $Vanished), 0 = no.
#
# Asserts the two canon properties:
#   • branch coverage — both outcomes occur across the seed set,
#   • golden exact counts — over seeds 1..50: {stole=12, no=38}.
# 12/50 = 24 % tracks the canon 25 % steal chance; exact counts
# lock determinism.
# ============================================================

const NPCs = preload("res://scripts/npcs.gd")
const StochasticProbe = preload("res://scripts/stochastic_probe.gd")

# Golden tally over seeds 1..50 (outcome 1 = stole, 0 = no steal).
const GOLDEN := {1: 12, 0: 38}

func _init():
    print("=== CCA stochastic probe: pirate steal roll (25% gate) ===")

    var probe = StochasticProbe._create()
    while not probe.is_done():
        var seed: int = probe.next_seed()
        var p = NPCs.Pirate._create(seed)
        p.treasures_carried(3)                 # Dormant -> Stalking
        var stole: bool = p.get_state() == "stalking" and p.try_steal()
        probe.record(1 if stole else 0)

    var got := {1: probe.count(1), 0: probe.count(0)}
    print("  trials=%d  distinct=%d  tally=%s" % [
        probe.trials_done(), probe.distinct_outcomes(), str(got)])

    var fails: Array = []
    for branch in GOLDEN:
        if probe.count(branch) <= 0:
            fails.append("branch %d never occurred" % branch)
        if probe.count(branch) != GOLDEN[branch]:
            fails.append("count(%d)=%d, golden %d" % [branch, probe.count(branch), GOLDEN[branch]])
    if probe.distinct_outcomes() != GOLDEN.size():
        fails.append("distinct outcomes %d, expected %d" % [probe.distinct_outcomes(), GOLDEN.size()])
    if probe.trials_done() != 50:
        fails.append("trials %d, expected 50" % probe.trials_done())

    if fails.is_empty():
        print("PASS — pirate steal covers both outcomes; golden tally locked (24%% ≈ canon 25%%)")
        quit(0)
        return
    for f in fails:
        print("  FAIL %s" % f)
    quit(1)
