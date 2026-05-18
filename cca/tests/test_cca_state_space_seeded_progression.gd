extends SceneTree

# ============================================================
# test_cca_state_space_seeded_progression.gd
# ============================================================
# RFC-0002 progression demonstrator: BFS coverage measured at
# successively deeper canonical-journey milestones.
#
# Companion to test_cca_state_space_seeded.gd (single-milestone
# demonstrator) and test_cca_state_space.gd (cold-start baseline).
# Together they form a coverage curve:
#
#   Cold start  →  16 locations
#   LampLit     →  30 locations  (this seeded test ↑)
#   SnakeGone   →  ?              (measured here)
#   DragonDead  →  ?              (measured here)
#
# Each successive milestone unlocks a deeper coverage cluster
# that prior milestones can't reach within BFS's action-ordering
# budget. The progression makes the prerequisite-chain
# bottleneck visible as a sequence of step functions.
#
# The journey is walked ONCE to capture all needed snapshots,
# then each BFS run starts from the captured FSM bytes. Test
# fails if any BFS run produces invariant violations.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

# Milestones at which to seed a BFS. Ordered by depth into the
# canonical journey; the walk captures all of them on the way to
# the deepest. Cap kept modest (2000) per seed to stay under the
# 120s per-test timeout — the goal here is the progression
# *delta*, not exhaustive coverage at each milestone.
const SEED_MILESTONES: Array = ["SnakeGone", "DragonDead"]
const PER_SEED_CAP: int = 2000

var total_violations: int = 0
var coverage_progression: Array = []   # [{milestone, locations, states}]

func _init():
    print("=== CCA state-space search (RFC-0002 progression) ===")
    print("")

    # ----- Phase 1: walk journey, capture all milestones -----
    var registry = MilestoneRegistry.new()
    if not _walk_journey_to_deepest(registry, SEED_MILESTONES):
        print("FAIL — couldn't reach the deepest milestone via canonical journey")
        quit(1)
        return
    print("Captured %d snapshots; running BFS from %d seed milestones" % [
        registry.size(), SEED_MILESTONES.size()])
    print("")

    # ----- Phase 2: BFS from each seed milestone in turn -----
    for milestone in SEED_MILESTONES:
        if not registry.has("canonical_journey", milestone):
            print("--- SKIP: '%s' not in registry ---" % milestone)
            continue
        _run_seeded_bfs(registry, milestone)
        print("")

    # ----- Progression summary -----
    print("=== Coverage progression summary ===")
    print("  cold start            16 locations  (test_cca_state_space.gd baseline)")
    print("  LampLit               30 locations  (test_cca_state_space_seeded.gd)")
    for entry in coverage_progression:
        print("  %-20s  %2d locations  %4d states" % [
            entry.milestone, entry.locations, entry.states])
    print("")

    if total_violations == 0:
        print("PASS — all milestone-seeded BFS runs clean")
        quit(0)
        return
    print("FAIL — %d invariant violation(s) across milestone-seeded BFS runs" %
        total_violations)
    quit(total_violations)

# Walk canonical_journey through Driver._process_input, capturing
# fsm.save_state() bytes at every milestone whose name is in
# `targets`. Returns true if every target was captured.
func _walk_journey_to_deepest(registry, targets: Array) -> bool:
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.wake_dwarves()
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = 42
    driver._build_verb_synonyms_5()
    driver._print_welcome()
    driver._print_room()

    var journey = CanonicalJourney._create()
    var captured: Dictionary = {}
    var deepest_target: String = targets[targets.size() - 1]

    while not journey.is_done():
        var state_name: String = journey.state_name()
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        # Capture every milestone — cheap; we just save the bytes
        # to a dictionary. The progression test consumes a subset
        # but the registry doesn't filter.
        registry.record("canonical_journey", state_name, driver.fsm.save_state())
        captured[state_name] = true
        if state_name == deepest_target:
            return true
        journey.advance()
    # Verify all targets captured.
    for t in targets:
        if not captured.has(t):
            print("  missing milestone: %s" % t)
            return false
    return true

# Run a BFS from the given milestone's snapshot and record the
# coverage numbers into coverage_progression. Bumps
# total_violations on any invariant failure.
func _run_seeded_bfs(registry, milestone: String) -> void:
    print("--- BFS from '%s' ---" % milestone)
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = PER_SEED_CAP
    s.seed_bytes = registry.get_snapshot("canonical_journey", milestone)
    s.seed_label = "canonical_journey:%s" % milestone
    s.run()
    var loc_count: int = _location_count(s)
    print("  states: %d   locations: %d   violations: %d" % [
        s.states_visited, loc_count, s.violations.size()])
    if s.violations.size() > 0:
        # Bucket violations by reason-prefix for diagnostic. Same
        # reason across many states usually points to one underlying
        # bug, not 192 distinct issues.
        var by_reason: Dictionary = {}
        for v in s.violations:
            var reason: String = v["reason"]
            # Strip trailing numbers/details for grouping.
            var prefix: String = reason.split(":")[0]
            by_reason[prefix] = by_reason.get(prefix, 0) + 1
        for prefix in by_reason.keys():
            print("    %4d × %s" % [by_reason[prefix], prefix])
        print("    sample: %s" % s.violations[0]["reason"])
    coverage_progression.append({
        "milestone": milestone,
        "states":    s.states_visited,
        "locations": loc_count,
    })
    total_violations += s.violations.size()

func _location_count(s) -> int:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms.size()
