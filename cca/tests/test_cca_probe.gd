extends SceneTree

# ============================================================
# test_cca_probe.gd
# ============================================================
# Runs the LFU-biased coverage walker (probe.gd) for a fixed
# number of walks and asserts coverage breadth. Per-room/action
# coverage data is printed for inspection; the pass/fail gate is
# "did we visit a meaningful fraction of canon rooms?"
#
# The probe walks the world through the real Driver's text
# pipeline (driver._process_input), so any crash inside the
# command path during exploration surfaces as a test failure.
# That's the bug-finding mechanism — "ran N walks without
# crashing" IS the success signal.
# ============================================================

const Probe = preload("res://scripts/probe.gd")

# Walk-count parameters tuned for a CI-friendly default. Local
# deeper sweeps can run this file directly with the `PROBE_WALKS`
# / `PROBE_STEPS` / `PROBE_SEEDS` environment variables overriding
# (see _init below).
#
# Multi-seed sweep is the default: 4 seeds chosen to exercise
# different slices of CCA's probabilistic mechanics (Witt's End
# 95/5, dark-pit 35%, dwarf walks, pirate stalking). Coverage
# pools across sweeps, so the later sweeps are pushed toward
# cells the earlier ones under-explored. Total walks = WALKS_PER_SEED
# × len(SEEDS) so the per-sweep walk count is lower than the
# old single-sweep default but the aggregate run is comparable.
const DEFAULT_SEEDS: Array = [42, 99, 1234, 7777]
# Per-sweep walk count. Total walks = WALKS_PER_SEED × len(SEEDS).
# With the wild-combo emission expanding per-state action counts
# from ~30 to ~150, each step is a bit more expensive; 15 walks ×
# 4 seeds × 500 steps fits inside run_tests.sh's 120s per-test
# timeout on a modern Mac.
const DEFAULT_WALKS_PER_SEED: int = 12
const DEFAULT_STEPS: int = 500

# Coverage floor: how many of the 140 canon rooms must be
# visited across the configured walks. Walks start at the canonical
# well-house with empty inventory, so depth depends on the walker
# stumbling into XYZZY/PLUGH and the keys+lamp pickup sequence —
# 48 rooms is the observed steady-state for 50 walks × 500 steps at
# seed 42. Floor set conservatively below that to leave room for
# minor RNG-path drift from incidental refactoring.
#
# Raising the floor materially is the natural next step once
# multi-sector seeding (state_space.gd-style sweeps from deep-cave
# starts) bolts on. The architecture supports it: the probe
# already accepts a pre-prepared driver via its `_make_driver`
# extension point; sectoring is "build N drivers with N different
# start states and walk each."
# Phase B coverage thresholds. The probe trades off two coverage
# dimensions: rooms-visited (breadth across canon's 140-room graph)
# vs. coverage-cells (distinct (room, action) pairs exercised).
# Routed walks + storm permutation skew the trade toward cells,
# wild-verb emission likewise. Pass criterion: meet EITHER floor.
# A run that's narrow-but-deep (few rooms, many cells per room) is
# as valuable as one that's wide-but-shallow.
const ROOM_COVERAGE_FLOOR: int = 30
const CELL_COVERAGE_FLOOR: int = 1500

func _init():
    print("=== CCA probe — LFU-biased coverage walk ===")
    print("")

    var walks: int = DEFAULT_WALKS_PER_SEED
    var steps: int = DEFAULT_STEPS
    var seed_list: Array = DEFAULT_SEEDS.duplicate()
    var walks_env: String = OS.get_environment("PROBE_WALKS")
    var steps_env: String = OS.get_environment("PROBE_STEPS")
    var seeds_env: String = OS.get_environment("PROBE_SEEDS")
    if walks_env != "":
        walks = int(walks_env)
    if steps_env != "":
        steps = int(steps_env)
    if seeds_env != "":
        # Comma-separated integers, e.g. PROBE_SEEDS=42,99
        seed_list = []
        for s in seeds_env.split(","):
            seed_list.append(int(s.strip_edges()))

    var p: Probe = Probe.new()
    p.seeds = seed_list
    p.walk_count = walks
    p.max_steps_per_walk = steps
    p.run()

    p.report()
    print("")
    p.report_by_kind()
    print("")
    p.report_unvisited_rooms()
    print("")
    p.report_least_actuated(20)
    print("")
    p.report_most_actuated(10)
    print("")
    # Phase A automata-learning report — the transition graph the
    # probe assembled across all walks, plus a topology audit
    # cross-checking observed movement edges against topology.gd.
    p.graph.report()
    print("")
    p.graph.report_topology_audit(15)
    print("")
    # Phase B Go-Explore — if the walker won, dump the trajectory
    # so the run produces a replayable winning sequence.
    p.report_victory_trajectory(0)
    print("")
    # Phase C model-based testing — items observed in unjustified
    # limbo during walks. Empty list = canon item-placement
    # invariants hold across the probe's coverage.
    p.report_spec_violations()
    print("")

    # Pass/fail: meet EITHER coverage threshold (rooms or cells)
    # plus no-stuck-walks. The dual threshold lets routed/storm
    # runs (narrow-but-deep) pass without artificially demanding
    # the same room breadth as pure-LFU runs.
    var failures: int = 0
    var rooms_ok: bool = p.rooms_seen.size() >= ROOM_COVERAGE_FLOOR
    var cells_ok: bool = p.coverage.size() >= CELL_COVERAGE_FLOOR
    if not rooms_ok and not cells_ok:
        print("FAIL — coverage below both floors: rooms %d (floor %d), cells %d (floor %d)" % [
            p.rooms_seen.size(), ROOM_COVERAGE_FLOOR,
            p.coverage.size(), CELL_COVERAGE_FLOOR])
        failures += 1
    if p.stuck_walks > 0:
        print("FAIL — %d walk(s) ended stuck (empty action list)" % p.stuck_walks)
        failures += 1

    if failures == 0:
        print("PASS — %d walks, %d rooms covered, %d coverage cells" % [
            p.walks_run, p.rooms_seen.size(), p.coverage.size()])
        quit(0)
    else:
        quit(failures)
