extends SceneTree

# ============================================================
# test_cca_journey_tree_plant_unlock.gd
# ============================================================
# First concrete journey-tree extension. Demonstrates the
# convergence-loop pattern that Phase 1's audit identifies and
# Phase 4a's JourneyTree threads:
#
#   1. Pick an unreached canon room flagged "gate-closed-need-
#      unlock" by the audit (here: canon 25's "climb" gate to
#      26, gated by plant_huge — needs `pour water` ×2).
#   2. Define an ExtensionJourney that walks from a parent
#      milestone (BearReleased) through the canonical commands
#      that satisfy the gate, snapshotting at the new milestone
#      ("PlantHugeGrown" — at canon 25 with plant in $Huge).
#   3. Register on a JourneyTree alongside canonical_journey.
#      JourneyTree resolves the parent chain: canonical_journey
#      to BearReleased, then PlantUnlock from there.
#   4. Run BFS from the PlantHugeGrown snapshot. Because the
#      gate is now passable, BFS discovers canon 26 and 88
#      (downstream of the plant climb).
#
# Coverage delta vs the single-seed BearReleased audit:
#   • +3 rooms expected (26, 88, plus whichever neighbors 88
#     opens up — canon 88 = "DECORATED CHAMBER" which connects
#     into further passages).
#
# The journey is a fixed canonical sequence. No RNG except the
# driver's standard tick chain. The walk is bounded (20-ish
# commands) so runtime stays negligible compared to the BFS.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const JourneyTreeC = preload("res://scripts/journey_tree.gd")
const ExtensionJourneyC = preload("res://scripts/extension_journey.gd")

# PlantUnlock journey: from BearReleased (player at canon 130
# with chain dropped, bear in $Released, lamp lit, bottle
# empty), walk the canyon back to canon 65 then divert through
# the slab-corridor to the fissure pool (canon 23), execute the
# two-pour plant-growth cycle, end at canon 25 with plant_huge.
#
# Steps are split for diagnostic clarity — each names the
# milestone reached so future failures localize.
const PLANT_UNLOCK_STEPS: Array = [
    # Walk 130 → 65 reusing canonical_journey's WalkBackToWellHouse
    # prefix (the first 11 commands of that 21-command sequence).
    # Lands the player at canon 65 (Bedquilt).
    {
        "name": "AtBedquilt",
        "commands": ["w", "w", "n", "w", "w", "over", "sw",
                     "down", "se", "se", "ne"],
    },
    # First trip to a real water source. canon 38 (bottom of
    # small pit, slit-in-streambed) is the closest from the
    # cave-side. NOTE: canon 23 LOOKS like a water source from
    # the affordance enumerator (driver.list_actions_here's
    # `room in [3, 23, 79]` advertises "fill bottle") but the
    # FSM's _at_water_source() doesn't include 23 — affordance/
    # FSM mismatch, harmless wasted turn but worth fixing.
    # Path: 65 → e → 64 → up → 39 → e → 36 → e → 37 → down → 38.
    # First "fill bottle" lands the bottle in $Water, first
    # "pour" at canon 25 transitions plant $Sprout → $Tall
    # (opens 25:up/out gates so the player can climb back).
    {
        "name": "PlantTall",
        "commands": ["e", "up", "e", "e", "down",
                     "fill bottle",
                     "up", "west", "west", "bedquilt",
                     "slab", "south", "down", "pour"],
    },
    # Refill + second pour: $Tall → $Huge. The path mirrors
    # PlantTall's but reversed at the start (climb back out of
    # 25). With $Huge, 25:climb opens to canon 26 → 88
    # (decorated chamber). End-state: player at canon 25,
    # plant $Huge, ready for BFS expansion through the climb.
    {
        "name": "PlantHugeGrown",
        "commands": ["up", "west", "north",
                     "e", "up", "e", "e", "down",
                     "fill bottle",
                     "up", "west", "west", "bedquilt",
                     "slab", "south", "down", "pour"],
    },
]

# How much of the unlocked downstream BFS should explore. Tight
# cap because the plant-cluster downstream is small (26, 88, and
# a couple of neighbors); 1000 saturates it well within ~30s.
const POST_UNLOCK_BFS_CAP: int = 1000

# New rooms expected after the unlock that BearReleased alone
# can't see. If 26 and 88 are both present we know the gate
# was unlocked AND the post-unlock BFS expanded through it.
const EXPECTED_NEW_ROOMS: Array = [26, 88]

func _init():
    print("=== PlantUnlock journey extension ===")
    print("")

    var registry = MilestoneRegistry.new()
    var driver = _make_driver()

    # Build the tree: canonical_journey as root, PlantUnlock
    # registered as extension off BearReleased.
    var tree = JourneyTreeC.new()
    tree.register_default()
    var plant_unlock = ExtensionJourneyC.new(
        "PlantUnlock", "canonical_journey", "BearReleased",
        PLANT_UNLOCK_STEPS)
    tree.register(plant_unlock)

    # Walk via the tree: canonical_journey → BearReleased, then
    # PlantUnlock → PlantHugeGrown. JourneyTree handles the
    # parent-chain resolution.
    if not tree.walk_to(driver, registry, "PlantUnlock:PlantHugeGrown"):
        print("FAIL — couldn't reach PlantUnlock:PlantHugeGrown")
        print("  Final room: %d   plant_huge: %s   bottle has water: %s" % [
            driver.fsm.player_room(), driver.fsm.plant_is_huge(),
            driver.fsm.bottle.has_water()])
        quit(1)
        return

    # Sanity-check the resulting FSM state.
    if not driver.fsm.plant_is_huge():
        print("FAIL — journey completed but plant_is_huge() is false")
        quit(1)
        return
    if driver.fsm.player_room() != 25:
        print("FAIL — journey completed but player is at %d, expected 25" % [
            driver.fsm.player_room()])
        quit(1)
        return

    print("PlantUnlock:PlantHugeGrown reached:")
    print("  Player at canon %d (West Pit)" % driver.fsm.player_room())
    print("  plant.get_state(): %s" % driver.fsm.plant.get_state())
    print("  bottle state: %s" % driver.fsm.bottle.get_state())
    print("")

    # Run a BFS from PlantHugeGrown. Coverage delta = rooms
    # reached here that BearReleased alone couldn't see.
    print("--- BFS from PlantHugeGrown (cap %d) ---" % POST_UNLOCK_BFS_CAP)
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = POST_UNLOCK_BFS_CAP
    s.seed_bytes = registry.get_snapshot("PlantUnlock", "PlantHugeGrown")
    s.seed_label = "PlantUnlock:PlantHugeGrown"
    s.progress_every = 250
    s.run()

    var reached: Dictionary = {}
    for h in s.visited.keys():
        reached[int(h.substr(2).get_slice("|", 0))] = true
    var rooms_sorted: Array = reached.keys()
    rooms_sorted.sort()
    print("  states: %d   locations: %d" % [s.states_visited, reached.size()])
    print("  reached: %s" % str(rooms_sorted))
    print("")

    # Verify the expected new rooms are reached.
    var missing: Array = []
    for r in EXPECTED_NEW_ROOMS:
        if not reached.has(r):
            missing.append(r)
    if missing.is_empty():
        print("PASS — plant unlock opened canon %s" % str(EXPECTED_NEW_ROOMS))
        quit(0)
        return
    print("FAIL — expected rooms %s but missing %s" % [
        str(EXPECTED_NEW_ROOMS), str(missing)])
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
