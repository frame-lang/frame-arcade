extends SceneTree

# ============================================================
# test_cca_state_space_seeded_post_bridge.gd
# ============================================================
# Continues the RFC-0002 milestone-seeded BFS progression past
# the dragon canyon. Each successive seed lands deeper into the
# canonical journey:
#
#   TrollPaid    — troll vanished, bridge crossable from canon 117
#   BearFed      — bear tamed at canon 130
#   ChainTaken   — chain in inventory, bear now $Following
#
# Each exercises a different mid-game mechanic the cold-start
# BFS never reaches. The earlier progression test
# (test_cca_state_space_seeded_progression.gd) already surfaced
# the axe-place inventory inconsistency at SnakeGone; this test
# extends the same approach into post-troll-bridge territory
# where treasure-throw, food consumption, and bear-following
# transitions live.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

const SEED_MILESTONES: Array = ["TrollPaid", "BearFed", "ChainTaken"]
const PER_SEED_CAP: int = 1500   # tighter than the surface progression
                                  # so 3 seeds fit in the 120s timeout

var total_violations: int = 0
var coverage_progression: Array = []

func _init():
    print("=== CCA state-space search (post-bridge progression) ===")
    print("")

    var registry = MilestoneRegistry.new()
    if not _walk_journey_to_deepest(registry, SEED_MILESTONES):
        print("FAIL — couldn't reach deepest milestone")
        quit(1)
        return
    print("Captured %d snapshots; running BFS from %d seed milestones" % [
        registry.size(), SEED_MILESTONES.size()])
    print("")

    for milestone in SEED_MILESTONES:
        if not registry.has("canonical_journey", milestone):
            print("--- SKIP: '%s' not in registry ---" % milestone)
            continue
        _run_seeded_bfs(registry, milestone)
        print("")

    print("=== Post-bridge progression ===")
    for entry in coverage_progression:
        print("  %-20s  %2d locations  %4d states" % [
            entry.milestone, entry.locations, entry.states])
    print("")

    if total_violations == 0:
        print("PASS — all post-bridge milestone-seeded BFS runs clean")
        quit(0)
        return
    print("FAIL — %d invariant violation(s) across post-bridge BFS runs" %
        total_violations)
    quit(total_violations)

func _walk_journey_to_deepest(registry, targets: Array) -> bool:
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.dwarves_auto_woken = true    # short-circuit auto-wake; dwarves stay dormant
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
        registry.record("canonical_journey", state_name, driver.fsm.save_state())
        captured[state_name] = true
        if state_name == deepest_target:
            return true
        journey.advance()
    for t in targets:
        if not captured.has(t):
            print("  missing milestone: %s" % t)
            return false
    return true

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
        var by_reason: Dictionary = {}
        for v in s.violations:
            var reason: String = v["reason"]
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
