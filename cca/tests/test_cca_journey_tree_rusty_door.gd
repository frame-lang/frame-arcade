extends SceneTree

# ============================================================
# test_cca_journey_tree_rusty_door.gd
# ============================================================
# Second journey-tree extension. Covers canon 91 + 95 (the
# magnificent-cavern / steep-incline cluster), gated behind the
# rusty-door puzzle at canon 94.
#
# Starting from PlantUnlock:PlantHugeGrown (player at canon 25
# with the plant grown $Huge), the journey:
#   1. Climbs out of the West Pit via the plant: canon
#      25 → 26 → 88 → 92 → 94.
#   2. Cheats the bottle into $Oil via FSM-direct
#      bottle.fill_oil(true). Canonically the player would walk
#      to canon 79 (oil pipe, the only oil source) and back —
#      a 30+ command round-trip with no incremental coverage
#      payoff. Same shortcut shape as canonical_journey's
#      TreasuresFilled (13 × endgame.treasure_deposited()) and
#      InRepository (35 × fsm.tick()) — documented FSM-state
#      injection rather than a player-canonical walk.
#   3. POUR at canon 94 oils the rusty door.
#   4. NORTH walks through the now-passable door to canon 95
#      (Magnificent Cavern).
#   5. WEST walks down to canon 91 (Steep incline).
#
# BFS from AtCanon91 confirms both 91 and 95 land in `visited`.
# Together with the existing union audit, this brings canon
# coverage to 134/140 — the remaining 6 are all transient
# bounce-back prose rooms (21, 22, 31, 32, 89, 90) with no
# canon-topology source, covered separately by
# test_cca_death_rooms.gd + test_cca_transient_prose.gd.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const JourneyTreeC = preload("res://scripts/journey_tree.gd")
const ExtensionJourneyC = preload("res://scripts/extension_journey.gd")

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

# RustyDoorUnlock journey steps. Walks the plant-climb path to
# canon 94, applies the oil-fill shortcut, oils the door, then
# walks to canon 95 and 91.
func _build_rusty_door_steps() -> Array:
    return [
        # Walk 25 → 94 via plant climb: climb (25→26), east
        # (26→88), west (88→92), north (92→94).
        {
            "name": "AtRustyDoor",
            "commands": ["climb", "east", "west", "north"],
        },
        # Oil the bottle (FSM shortcut — see header comment).
        # POUR at canon 94 oils the rusty door.
        {
            "name": "RustyDoorOiled",
            "fsm_pre": func(d): d.fsm.bottle.fill_oil(true),
            "commands": ["pour"],
        },
        # Walk through the now-passable door to canon 95, then
        # west to canon 91.
        {
            "name": "AtCanon91",
            "commands": ["north", "west"],
        },
    ]

const POST_UNLOCK_BFS_CAP: int = 500
const EXPECTED_NEW_ROOMS: Array = [91, 95]

func _init():
    print("=== RustyDoorUnlock journey extension ===")
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
        _build_rusty_door_steps()))

    if not tree.walk_to(driver, registry, "RustyDoorUnlock:AtCanon91"):
        print("FAIL — couldn't reach RustyDoorUnlock:AtCanon91")
        print("  Final room: %d   rusty_door_oiled: %s   bottle: %s" % [
            driver.fsm.player_room(), driver.fsm.rusty_door_oiled(),
            driver.fsm.bottle.get_state()])
        quit(1)
        return

    if driver.fsm.player_room() != 91:
        print("FAIL — journey completed but player at %d, expected 91" % [
            driver.fsm.player_room()])
        quit(1)
        return

    print("RustyDoorUnlock:AtCanon91 reached:")
    print("  Player at canon %d (Steep incline)" % driver.fsm.player_room())
    print("  rusty_door_oiled: %s" % driver.fsm.rusty_door_oiled())
    print("  bottle state: %s" % driver.fsm.bottle.get_state())
    print("")

    print("--- BFS from AtCanon91 (cap %d) ---" % POST_UNLOCK_BFS_CAP)
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = POST_UNLOCK_BFS_CAP
    s.seed_bytes = registry.get_snapshot("RustyDoorUnlock", "AtCanon91")
    s.seed_label = "RustyDoorUnlock:AtCanon91"
    s.progress_every = 250
    s.run()

    var reached: Dictionary = {}
    for h in s.visited.keys():
        reached[int(h.substr(2).get_slice("|", 0))] = true
    var sorted_rooms: Array = reached.keys()
    sorted_rooms.sort()
    print("  states: %d   locations: %d" % [s.states_visited, reached.size()])
    print("  reached: %s" % str(sorted_rooms))
    print("")

    var missing: Array = []
    for r in EXPECTED_NEW_ROOMS:
        if not reached.has(r):
            missing.append(r)
    if missing.is_empty():
        print("PASS — rusty-door unlock opened canon %s" % str(EXPECTED_NEW_ROOMS))
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
