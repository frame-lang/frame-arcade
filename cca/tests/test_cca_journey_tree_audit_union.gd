extends SceneTree

# ============================================================
# test_cca_journey_tree_audit_union.gd
# ============================================================
# Multi-seed UNION coverage measurement. Companion to the
# single-seed gap audit (test_cca_journey_tree_audit.gd) which
# measures from BearReleased only.
#
# The convergence-loop hypothesis is: rooms unreachable from any
# single seed become reachable when we run BFS from a small set
# of well-chosen seeds + extension journeys. UNION coverage tells
# us how close we are to the 140-room target before writing more
# extensions.
#
# Current seeds:
#   • canonical_journey:SnakeGone     — pre-dragon-kill state.
#     Uniquely reaches canon 119/121 (dragon-side canyon rooms
#     that BearReleased's "dragon dead, redirect" gates skip).
#   • canonical_journey:BearReleased  — main deep-cave state.
#     Reaches most of the cave graph.
#   • PlantUnlock:PlantHugeGrown      — first extension journey.
#     Adds canon 26 + 88 + 92/93/94 (plant climb + decorated
#     chamber cluster), gated out by plant_huge at BearReleased.
#
# As Phase 3 extension journeys land (e.g., for the remaining
# "no canon-topology source" rooms — death rooms, FSM-teleport
# destinations), they get added to SEEDS and the floor rises.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const JourneyTreeC = preload("res://scripts/journey_tree.gd")
const ExtensionJourneyC = preload("res://scripts/extension_journey.gd")

# Seed list: [journey:milestone, full_cap, smoke_cap]. The full
# caps are sized to each seed's coverage curve (flat past these
# values). The smoke caps (CCA_SMOKE=1) drop to roughly 15% of
# full — exercises every BFS code path in pre-commit without
# paying the asymptotic runtime.
const SEEDS: Array = [
    ["canonical_journey:SnakeGone",     7500, 1000],
    ["canonical_journey:BearReleased",  7500, 1000],
    ["canonical_journey:InRepository",   500,  200],
    ["PlantUnlock:PlantHugeGrown",      1000,  300],
    ["RustyDoorUnlock:AtCanon91",        500,  200],
]

# PlantUnlock journey definition. Identical to the one in
# test_cca_journey_tree_plant_unlock.gd — duplicated here rather
# than imported because the steps are short and centralising via
# a shared file isn't worth the indirection at one consumer.
# (When a second test reuses PlantUnlock, move it into a shared
# scripts/journeys/ file.)
const PLANT_UNLOCK_STEPS: Array = [
    {"name": "AtBedquilt", "commands":
        ["w", "w", "n", "w", "w", "over", "sw",
         "down", "se", "se", "ne"]},
    {"name": "PlantTall", "commands":
        ["e", "up", "e", "e", "down",
         "fill bottle",
         "up", "west", "west", "bedquilt",
         "slab", "south", "down", "pour"]},
    {"name": "PlantHugeGrown", "commands":
        ["up", "west", "north",
         "e", "up", "e", "e", "down",
         "fill bottle",
         "up", "west", "west", "bedquilt",
         "slab", "south", "down", "pour"]},
]

# RustyDoorUnlock: branches off PlantHugeGrown. Walks plant
# climb to canon 94, FSM-shortcuts oil into the bottle (same
# pattern as canonical_journey TreasuresFilled), pours, walks
# through to canon 95 then west to 91. See
# test_cca_journey_tree_rusty_door.gd for the dedicated test.
func _rusty_door_steps() -> Array:
    return [
        {"name": "AtRustyDoor",
         "commands": ["climb", "east", "west", "north"]},
        {"name": "RustyDoorOiled",
         "fsm_pre": func(d): d.fsm.bottle.fill_oil(true),
         "commands": ["pour"]},
        {"name": "AtCanon91",
         "commands": ["north", "west"]},
    ]

# Floor for UNION coverage. Full-cap baseline (2026-05-19):
# 130 rooms across the 3 seeds. Smoke-mode baseline: ~100.
# As more extension journeys land, the full floor rises.
static func _union_floor() -> int:
    return 85 if OS.get_environment("CCA_SMOKE") == "1" else 132

# Select per-seed cap based on smoke vs full mode. Smoke-mode is
# the 3rd column of each SEEDS entry, full-mode is the 2nd.
static func _cap_for(entry) -> int:
    return int(entry[2]) if OS.get_environment("CCA_SMOKE") == "1" else int(entry[1])

func _init():
    print("=== Multi-seed UNION coverage audit ===")
    print("Seeds:")
    for entry in SEEDS:
        print("  %-35s cap=%d" % [entry[0], _cap_for(entry)])
    print("")

    var registry = MilestoneRegistry.new()
    var driver = _make_driver()

    var tree = JourneyTreeC.new()
    tree.register_default()
    tree.register(ExtensionJourneyC.new(
        "PlantUnlock", "canonical_journey", "BearReleased",
        PLANT_UNLOCK_STEPS))
    tree.register(ExtensionJourneyC.new(
        "RustyDoorUnlock", "PlantUnlock", "PlantHugeGrown",
        _rusty_door_steps()))

    # Walk every seed milestone we need. The CanonicalJourneyAdapter
    # walks from canonical-start each call, but it assumes the
    # driver's FSM is also at canonical-start. Multiple walks
    # against the same driver leave the FSM at the deepest
    # milestone visited, so a second walk_to that re-runs the
    # canonical adapter would re-record every milestone snapshot
    # against a wrong start state — clobbering the good snapshots.
    # Use a fresh driver per walk to keep snapshots clean.
    for target in ["canonical_journey:InRepository",
                   "RustyDoorUnlock:AtCanon91"]:
        var d = _make_driver()
        if not tree.walk_to(d, registry, target):
            print("FAIL — couldn't reach %s" % target)
            quit(1)
            return

    var per_seed_reached: Dictionary = {}
    for entry in SEEDS:
        var full_path: String = entry[0]
        var cap: int = _cap_for(entry)
        var parts = full_path.split(":")
        if not registry.has(parts[0], parts[1]):
            print("SKIP %s — not captured" % full_path)
            continue
        print("--- BFS from %s (cap %d) ---" % [full_path, cap])
        var reached = _bfs(registry, parts[0], parts[1], cap)
        per_seed_reached[full_path] = reached
        print("  reached %d rooms" % reached.size())
        print("")

    # Union + unique-per-seed contributions.
    var union_set: Dictionary = {}
    for full_path in per_seed_reached.keys():
        for r in per_seed_reached[full_path].keys():
            union_set[r] = true

    var unique_by_seed: Dictionary = {}
    for full_path in per_seed_reached.keys():
        var u: Array = []
        for r in per_seed_reached[full_path].keys():
            var only_here = true
            for other in per_seed_reached.keys():
                if other != full_path and per_seed_reached[other].has(r):
                    only_here = false
                    break
            if only_here:
                u.append(r)
        u.sort()
        unique_by_seed[full_path] = u

    var union_count: int = union_set.size()
    var unreached: Array = []
    for r in range(1, 141):
        if not union_set.has(r):
            unreached.append(r)

    print("=== UNION coverage ===")
    print("Reached: %d / 140 canon rooms" % union_count)
    print("Unreached: %s" % str(unreached))
    print("")
    print("=== Per-seed unique contributions ===")
    for entry in SEEDS:
        var full_path: String = entry[0]
        if not unique_by_seed.has(full_path):
            continue
        var u: Array = unique_by_seed[full_path]
        print("  %-35s %3d unique  %s" % [
            full_path, u.size(), str(u.slice(0, 12))])
    print("")

    var floor_v: int = _union_floor()
    if union_count >= floor_v:
        print("PASS — %d / 140 union coverage (floor %d)" % [union_count, floor_v])
        quit(0)
        return
    print("FAIL — %d / 140 union coverage, below floor %d" % [
        union_count, floor_v])
    quit(1)

func _make_driver():
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
    return d

func _bfs(registry, journey: String, milestone: String, cap: int) -> Dictionary:
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = cap
    s.seed_bytes = registry.get_snapshot(journey, milestone)
    s.seed_label = "%s:%s" % [journey, milestone]
    s.progress_every = 2000
    s.run()
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        rooms[int(h.substr(2).get_slice("|", 0))] = true
    return rooms
