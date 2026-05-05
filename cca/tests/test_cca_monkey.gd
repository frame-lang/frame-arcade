extends SceneTree

# Random-walk fuzzer of the CCA world. Builds a fresh
# Adventure, feeds it pseudo-random commands from a fixed
# vocabulary for N steps, and reports coverage. The actual
# logic lives in scripts/monkey.gd; this file is the test
# harness + the canonical thresholds we expect a healthy
# build to clear.
#
# Why this is a test, not just an exploratory tool:
#   - if the FSM ever crashes on a recognised verb, the
#     godot process exits non-zero and run_tests.sh flags it
#   - if room coverage collapses (e.g. a refactor strands a
#     region of the map behind a now-unreachable gate),
#     we'll see it as MIN_ROOMS dropping below threshold
#   - if soft_lock_count grows (the monkey found fingerprints
#     where every command bumps), that's a real regression —
#     either a missing event handler or a state with no exit
#
# The fixed seed (42) makes any failure reproducible: hand
# the seed and step count to the monkey and it walks the same
# path bit-for-bit.

const Monkey = preload("res://scripts/monkey.gd")
const Topology = preload("res://scripts/topology.gd")

# Tuned against current CCA build (10000 steps, seed 42).
# Measured baselines:
#   pre-canon-magic-word-fix: 64 rooms / 974 fps / 4324 moves
#   post-canon-magic-word-fix (XYZZY/PLUGH only fire from room 3):
#                              41 rooms / 613 fps / 4248 moves
# The canonical pairs are HARDER for a random walker — magic
# words are gated behind reaching the well house (3) first,
# which is itself ~3 random commands of work. Thresholds below
# reflect the post-canon baseline with ~15% margin.
# If a number here drops below threshold, that's a real
# regression.
const SEED         := 42
const MAX_STEPS    := 10000
const MIN_ROOMS    := 30      # post-canon baseline drifts as canon moves land
const MIN_FPS      := 525     # post-canon baseline 613
const MIN_MOVES    := 3500    # post-canon baseline 4248
const MAX_SOFTLOCK := 0       # ANY soft-lock candidate is a real finding

var failures: int = 0

func _init():
    print("=== CCA monkey fuzzer ===")
    print("seed=%d  steps=%d" % [SEED, MAX_STEPS])
    print()

    var report: Dictionary = Monkey.run(Topology.ROOMS, SEED, MAX_STEPS)

    print("Coverage:")
    print("  rooms visited:     %d  (need >= %d)" % [report.rooms_visited, MIN_ROOMS])
    print("  fingerprints:      %d  (need >= %d)" % [report.fingerprints, MIN_FPS])
    print("  state-change cmds: %d  (need >= %d)" % [report.moves, MIN_MOVES])
    print("  no-op cmds:        %d" % report.bumps)
    print("  max score:         %d" % report.max_score)
    print("  revives:           %d" % report.revives)
    print("  permadeaths:       %d" % report.permadeaths)
    print("  soft-lock fps:     %d  (need == %d)" % [report.soft_lock_count, MAX_SOFTLOCK])
    print()

    _check("rooms_visited",   report.rooms_visited,   MIN_ROOMS,    "ge")
    _check("fingerprints",    report.fingerprints,    MIN_FPS,      "ge")
    _check("moves",           report.moves,           MIN_MOVES,    "ge")
    _check("soft_lock_count", report.soft_lock_count, MAX_SOFTLOCK, "le")

    if not report.soft_lock_count == 0:
        print("Soft-lock candidate fingerprints:")
        for fp in report.soft_locks:
            print("  - %s" % fp)
        print()

    if failures == 0:
        print("PASS — monkey survived %d steps and met coverage thresholds" % MAX_STEPS)
    else:
        print("FAIL — %d threshold(s) missed" % failures)
    quit(failures)

func _check(label: String, got: int, want: int, cmp: String) -> void:
    var ok: bool = (got >= want) if cmp == "ge" else (got <= want)
    if ok:
        print("  ok   %s %s %d (got %d)" % [label, ">=" if cmp == "ge" else "<=", want, got])
    else:
        print("  FAIL %s %s %d (got %d)" % [label, ">=" if cmp == "ge" else "<=", want, got])
        failures += 1
