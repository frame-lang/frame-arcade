extends SceneTree

# ============================================================
# test_cca_maze_sweep.gd
# ============================================================
# Verifies the counter-driven area-sweep LOOP (MazeSweep) — the
# cyclic counterpart to the acyclic success/death rails.
#
# Setup: win → BridgeBuilt → MazeJourney drops the player at the
# maze edge (canon 131). Then MazeSweep drives the loop: feed it
# the current room, take the direction it returns, repeat — until
# it declares the area mapped. Asserts:
#   • every one of the 12 cyclic maze rooms (107,112,131-140) is
#     seen,
#   • the loop exits via SUCCESS (transition to $Mapped, not the
#     step cap),
#   • it does so deterministically and quickly (well under cap).
#
# This is the model-native replacement for the bloom that used to
# cover the maze: a Frame loop with a deterministic exit, no blind
# BFS and no embedded topology.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")
const MazeJourney = preload("res://scripts/maze_journey.gd")
const MazeSweep = preload("res://scripts/maze_sweep.gd")

const TARGET := [107, 112, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140]

func _init():
    print("=== CCA maze-sweep loop (counter-driven, deterministic exit) ===")
    var d = _make_driver()

    # Walk to the maze edge via the existing rails.
    var j = WinJourney._create()
    while not j.is_done():
        var nm: String = j.state_name()
        for cmd in j.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        if nm == "BridgeBuilt":
            break
        j.advance()
    var m = MazeJourney._create()
    while not m.is_done():
        for cmd in m.commands_from_previous():
            d._process_input(String(cmd).to_lower())
        m.advance()
    print("  entered maze at room %d" % d.fsm.player_room())

    # Drive the sweep loop.
    var sweep = MazeSweep._create()
    sweep.arrive(d.fsm.player_room())
    while not sweep.is_done():
        var dir: String = sweep.next_dir()
        d._process_input(dir)
        sweep.arrive(d.fsm.player_room())

    var steps: int = sweep.steps_taken()
    var covered: int = sweep.covered_count()
    var mapped: bool = sweep.is_done() and steps < 400   # success, not cap
    print("  swept %d/%d rooms in %d steps (exit: %s)" % [
        covered, TARGET.size(), steps, "MAPPED" if mapped else "CAP"])

    var missing: Array = []
    for r in TARGET:
        if not sweep.seen(r):
            missing.append(r)

    if missing.is_empty() and mapped:
        print("PASS — maze-sweep loop mapped all 12 cyclic rooms, exited on success")
        quit(0)
        return
    print("FAIL — missing %s, mapped=%s" % [str(missing), mapped])
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
    d.fsm.chance.reseed(42)
    d._build_verb_synonyms_5()
    return d
