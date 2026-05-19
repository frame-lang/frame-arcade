extends SceneTree

# ============================================================
# test_cca_journey_tree_audit.gd
# ============================================================
# Phase 1 of the journey-tree convergence loop. Walks the
# canonical_journey to the deepest pre-endgame milestone
# (BearReleased), runs BFS with a high cap, computes the union
# of reached canon locations, then annotates each unreached
# canon room (1-140) with WHY it's unreached:
#
#   gate-blocked       — Topology.GATES has an entry for some
#                        (source, direction) → this room; the
#                        gate's check condition wasn't satisfied
#                        in the BFS frontier. Candidate for
#                        auto-extension (Phase 2).
#
#   prerequisite-chain — no gate, but no path from any reached
#                        room leads here either. The blocker is
#                        some item the player needs to have
#                        taken at a different location and
#                        carried to a specific room.  Candidate
#                        for manual extension (Phase 3).
#
#   unreachable        — no canon-topology path exists from any
#                        currently-reached room. Probably an
#                        endgame-only room, or a room reachable
#                        only via magic-word teleport from a
#                        non-reached source.
#
# Pass criterion: at least 32 rooms reached (current baseline).
# As Phases 2-3 land, the floor rises monotonically toward 140.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")
const Topology = preload("res://scripts/topology.gd")

# Deepest pre-endgame milestone the canonical journey reaches via
# pure player commands. Has bird-released, dragon-dead, troll-
# paid, bear-tamed, chain-taken, bear-released. The journey then
# walks back toward the well-house to deposit treasures —
# BearReleased is the moment when the most game-mechanic state
# has been unlocked.
const DEEP_MILESTONE: String = "BearReleased"
const PER_SEED_CAP: int = 5000   # high enough to exhaust from
                                  # BearReleased; ~2-3 min runtime

# Coverage threshold for pass/fail. Baseline history:
#   • 32 rooms — pre-fix; revive-prompt state leak in the BFS driver
#     was eating every non-yes/no verb once any branch died (see
#     state_space.gd _reset_driver_session_state docstring).
#   • 104 rooms — post-fix at cap=5000 (BFS hit cap). Big jump
#     because the leak had been masking most of the cave graph.
# As Phases 2-3 land more journey extensions, this floor rises.
const FLOOR_ROOMS: int = 95

func _init():
    print("=== Journey-tree gap audit (Phase 1) ===")
    print("")

    var registry = MilestoneRegistry.new()
    if not _walk_journey_to(registry, DEEP_MILESTONE):
        print("FAIL — couldn't reach %s via canonical journey" % DEEP_MILESTONE)
        quit(1)
        return

    var s = StateSpace.new()
    s.seed = 42
    s.max_states = PER_SEED_CAP
    s.seed_bytes = registry.get_snapshot("canonical_journey", DEEP_MILESTONE)
    s.seed_label = "canonical_journey:%s" % DEEP_MILESTONE
    s.run()

    var reached: Dictionary = _locations_in(s)
    var unreached: Array = []
    for r in range(1, 141):
        if not reached.has(r):
            unreached.append(r)

    print("Seed milestone: %s" % DEEP_MILESTONE)
    print("BFS:            %d states, %d locations (cap %d%s)" % [
        s.states_visited, reached.size(), PER_SEED_CAP,
        " — HIT" if s.hit_cap else ""])
    var reached_sorted: Array = reached.keys()
    reached_sorted.sort()
    print("Reached:        %s" % str(reached_sorted))
    print("")

    _annotate_unreached(reached, unreached)

    if reached.size() >= FLOOR_ROOMS:
        print("")
        print("PASS — %d rooms reached (floor %d)" % [reached.size(), FLOOR_ROOMS])
        quit(0)
        return
    print("")
    print("FAIL — %d rooms reached, below floor of %d" % [
        reached.size(), FLOOR_ROOMS])
    quit(1)

# Walk canonical_journey to the named milestone, capturing
# snapshots along the way. Mirrors the harness in other seeded
# tests.
func _walk_journey_to(registry, target: String) -> bool:
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
    while not journey.is_done():
        var state_name: String = journey.state_name()
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        if state_name == target:
            registry.record("canonical_journey", state_name, driver.fsm.save_state())
            return true
        journey.advance()
    return false

# Parse room numbers out of state hashes.
func _locations_in(s) -> Dictionary:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms

# For each unreached room, classify why it wasn't visited and
# print a structured report.
func _annotate_unreached(reached: Dictionary, unreached: Array) -> void:
    var by_category: Dictionary = {
        "gate-blocked":       [],
        "prerequisite-chain": [],
        "unreachable":        [],
    }
    var details: Dictionary = {}     # room → "explanation"

    for room in unreached:
        var category: String = "unreachable"
        var why: String = ""
        # Find all canon-topology sources for this room.
        var sources_reached: Array = []
        var sources_unreached: Array = []
        var gates_to_here: Array = []
        for source in range(1, 141):
            var exits: Dictionary = Topology.ROOMS.get(source, {})
            for direction in exits.keys():
                if exits[direction] == room:
                    var key: String = "%d:%s" % [source, direction]
                    var has_gate: bool = Topology.GATES.has(key)
                    if reached.has(source):
                        sources_reached.append("%d:%s" % [source, direction])
                        if has_gate:
                            gates_to_here.append("%d:%s" % [source, direction])
                    else:
                        sources_unreached.append("%d:%s" % [source, direction])
        if sources_reached.is_empty() and sources_unreached.is_empty():
            # No canon source — probably reachable only via magic
            # word or via FSM-driven teleport (e.g. repository).
            category = "unreachable"
            why = "no canon-topology source"
        elif sources_reached.is_empty():
            # Sources exist but none are reached.
            category = "unreachable"
            why = "%d source(s), none reached: %s" % [
                sources_unreached.size(), str(sources_unreached.slice(0, 3))]
        elif not gates_to_here.is_empty():
            category = "gate-blocked"
            why = "gates: %s" % str(gates_to_here)
        else:
            # Sources reached, no gates — the BFS should have
            # walked through but didn't. Means action wasn't in
            # list_actions_here() at the source, or the move was
            # consumed by a non-topology dispatch (e.g. probabilistic
            # bumper, intercept). Mark prerequisite-chain.
            category = "prerequisite-chain"
            why = "reached sources: %s" % str(sources_reached.slice(0, 3))
        by_category[category].append(room)
        details[room] = why

    print("--- Unreached by category ---")
    print("  gate-blocked        %3d rooms" % by_category["gate-blocked"].size())
    print("  prerequisite-chain  %3d rooms" % by_category["prerequisite-chain"].size())
    print("  unreachable         %3d rooms" % by_category["unreachable"].size())
    print("")
    for cat in ["gate-blocked", "prerequisite-chain", "unreachable"]:
        if by_category[cat].is_empty():
            continue
        print("--- %s (sample) ---" % cat)
        for r in by_category[cat].slice(0, 8):
            print("  room %d  %s" % [r, details[r]])
        if by_category[cat].size() > 8:
            print("  ...(+%d more)" % (by_category[cat].size() - 8))
        print("")
