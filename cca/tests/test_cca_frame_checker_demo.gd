extends SceneTree

# ============================================================
# test_cca_frame_checker_demo.gd
# ============================================================
# Demonstrates + validates the domain-agnostic FrameStateChecker
# on CCA. Three things, each a classical model-checking property
# computed through the generic engine via the thin
# CcaModelAdapter:
#
#   1. Reachability cross-validation. Run the generic checker's
#      explore() from the BearReleased seed, and confirm it
#      reaches the SAME distinct-room count as the bespoke
#      state_space.gd at the same cap + seed. This pins the
#      generic engine against the hand-written one — if they
#      diverge, one of them is wrong.
#
#   2. Liveness EF query. From the InRepository seed (one BLAST
#      from victory), reachable_satisfying(is_won) must find a
#      won state — the CTL query EF won, returning a witness
#      path. Demonstrates goal-reachability through the generic
#      engine.
#
#   3. Bisimulation / restore soundness. restore_soundness()
#      over milestone snapshots, with a "dirty" closure that
#      kills the player + opens a revive prompt before the
#      restore. Zero divergences == restore is observationally
#      sound (no incomplete-state-vector leak). This is the
#      prompts-state-leak guard, expressed as the generic
#      bisimulation check.
#
# The point: CCA binds to a model checker through ~10 adapter
# methods, all thin delegates, because it is Frame-native — the
# state vector is the FSM's own save_state, not an extracted
# abstraction.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const JourneyTreeC = preload("res://scripts/journey_tree.gd")
const FrameStateChecker = preload("res://scripts/frame_state_checker.gd")
const CcaModelAdapter = preload("res://scripts/cca_model_adapter.gd")

const CROSS_VALIDATE_CAP: int = 2000

var failures: int = 0

func _init():
    print("=== FrameStateChecker demo (CCA binding) ===")
    print("")

    var registry = MilestoneRegistry.new()
    if not _capture(registry):
        print("FAIL — couldn't capture milestone snapshots")
        quit(1)
        return
    var bear: PackedByteArray = registry.get_snapshot("canonical_journey", "BearReleased")
    var repo: PackedByteArray = registry.get_snapshot("canonical_journey", "InRepository")

    _check_reachability_cross_validation(bear)
    _check_liveness_EF_won(repo)
    _check_restore_bisimulation(registry)

    print("")
    if failures == 0:
        print("PASS — FrameStateChecker reproduces bespoke results + classical properties hold")
        quit(0)
        return
    print("FAIL — %d check(s) failed" % failures)
    quit(failures)

# ----- 1. Reachability cross-validation ------------------------
func _check_reachability_cross_validation(seed: PackedByteArray) -> void:
    print("--- reachability: generic checker vs bespoke state_space ---")

    # Generic checker.
    var adapter = CcaModelAdapter.new(42)
    adapter.seed_bytes = seed
    var checker = FrameStateChecker.new(adapter)
    checker.max_states = CROSS_VALIDATE_CAP
    checker.explore()
    var generic_rooms: int = _distinct_rooms(checker.visited)

    # Bespoke engine, same seed + cap.
    var ss = StateSpace.new()
    ss.seed = 42
    ss.max_states = CROSS_VALIDATE_CAP
    ss.seed_bytes = seed
    ss.run()
    var bespoke_rooms: int = _distinct_rooms(ss.visited)

    print("  generic checker:  %d states, %d rooms, %d violations" % [
        checker.states_visited, generic_rooms, checker.violations.size()])
    print("  bespoke state_space: %d states, %d rooms, %d violations" % [
        ss.states_visited, bespoke_rooms, ss.violations.size()])

    if generic_rooms == bespoke_rooms:
        print("  OK   distinct-room count matches (%d)" % generic_rooms)
    else:
        print("  FAIL room counts diverge: generic=%d bespoke=%d" % [
            generic_rooms, bespoke_rooms])
        failures += 1
    if checker.violations.size() != 0:
        print("  FAIL generic checker found %d safety violations" % checker.violations.size())
        failures += 1

# ----- 2. Liveness: EF won -------------------------------------
func _check_liveness_EF_won(seed: PackedByteArray) -> void:
    print("--- liveness: EF won from InRepository ---")
    var adapter = CcaModelAdapter.new(42)
    adapter.seed_bytes = seed
    var checker = FrameStateChecker.new(adapter)
    checker.max_states = 200    # victory is a step or two away
    var result: Dictionary = checker.reachable_satisfying(
        func(o): return adapter.is_won(o))
    if result["found"]:
        print("  OK   EF won satisfied — witness path: %s (explored %d states)" % [
            str(result["path"]), result["states"]])
    else:
        print("  FAIL EF won NOT satisfied within cap (explored %d, hit_cap=%s)" % [
            result["states"], result.get("hit_cap", false)])
        failures += 1

# ----- 3. Bisimulation: restore soundness ----------------------
func _check_restore_bisimulation(registry) -> void:
    print("--- bisimulation: restore soundness ---")
    var samples: Array = []
    for name in ["LampLit", "SnakeGone", "BearReleased"]:
        if registry.has("canonical_journey", name):
            samples.append({
                "name": name,
                "bytes": registry.get_snapshot("canonical_journey", name),
            })
    var adapter = CcaModelAdapter.new(42)
    var checker = FrameStateChecker.new(adapter)
    # Dirty closure: kill the player + open a revive prompt, the
    # worst-case prior state for the incomplete-state-vector trap.
    var dirty := func(adp, o):
        o.fsm.player.die()
        o.prompts.offer_revive()
    var divergences: Array = checker.restore_soundness(samples, dirty)
    if divergences.is_empty():
        print("  OK   restore observationally sound across %d samples" % samples.size())
    else:
        for d in divergences:
            print("  FAIL %s — fresh: %s | reused: %s" % [d["name"], d["fresh"], d["reused"]])
        failures += divergences.size()

# ----- helpers -------------------------------------------------

func _distinct_rooms(visited: Dictionary) -> int:
    var rooms: Dictionary = {}
    for h in visited.keys():
        rooms[int(h.substr(2).get_slice("|", 0))] = true
    return rooms.size()

func _capture(registry) -> bool:
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = 42
    d._build_verb_synonyms_5()
    d._print_welcome()
    d._print_room()
    var tree = JourneyTreeC.new()
    tree.register_default()
    return tree.walk_to(d, registry, "canonical_journey:InRepository")
