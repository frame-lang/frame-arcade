# ============================================================
# state_space.gd — reusable harness for deterministic state-space
# search over CCA's reachable state graph
# ============================================================
# Implements the BFS described in cca/docs/rfcs/rfc-0001.md. The
# search uses `Adventure.save_state()` / `restore_state()` to
# checkpoint and roll back, exercises every reachable transition,
# and asserts invariants at each step.
#
# Intended to be used from a test like:
#
#   var s = StateSpace.new()
#   s.seed = 42
#   s.max_states = 500       # safety cap during development
#   s.run()
#   s.report()
#
# The harness is deliberately conservative on a first pass —
# enumerates only the direction commands from each room's
# `room_exits` dict, with the FULL state-hash matrix to be
# layered on in future iterations (see RFC-0001 §"Canonical
# state hash").
# ============================================================
extends RefCounted

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const Topology = preload("res://scripts/topology.gd")

# ----- Configuration ------------------------------------------------

# RNG seed for the driver's probabilistic rolls. Same seed +
# same action sequence → same state graph, every run.
var seed: int = 0

# Safety cap on visited-states. The full reachable graph may be
# large; during development we want predictable termination.
var max_states: int = 1000

# Whether to actually attempt round-trip save/restore at each
# state. Detects @@[persist] divergences. Costs ~30ms per state.
var check_save_restore: bool = true

# ----- Results -----------------------------------------------------

# Set of visited canonical hashes.
var visited: Dictionary = {}

# Per-hash: the action sequence from the root that first
# reached this state. Useful as a reproducer.
var reproducer: Dictionary = {}

# Invariant violations: array of {hash, action_sequence, reason}.
var violations: Array = []

# Stats.
var states_visited: int = 0
var actions_tried: int = 0
var hit_cap: bool = false

# ----- Search ------------------------------------------------------

func run() -> void:
    # Build the initial driver + FSM, headless.
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    # Suppress dwarf auto-wake so the search isn't fighting random
    # NPC walks. Per-NPC PRNG is seeded; this keeps them dormant.
    driver.fsm.dwarves_auto_woken = true
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = seed

    # Root state snapshot.
    var root_state: PackedByteArray = driver.fsm.save_state()
    var root_hash: String = _hash_state(driver)

    visited[root_hash] = true
    reproducer[root_hash] = []
    states_visited = 1

    # BFS queue: each entry is {state: PackedByteArray, path: Array[String]}
    var queue: Array = [{"state": root_state, "path": [], "hash": root_hash}]

    while not queue.is_empty():
        if states_visited >= max_states:
            hit_cap = true
            break

        var node = queue.pop_front()
        var node_state: PackedByteArray = node["state"]
        var node_path: Array = node["path"]
        var node_hash: String = node["hash"]

        # Restore to this node so action enumeration sees the
        # right room / inventory.
        driver.fsm.restore_state(node_state)

        # Save/restore round-trip check at every node.
        if check_save_restore:
            var re_state = driver.fsm.save_state()
            driver.fsm.restore_state(re_state)
            var re_hash = _hash_state(driver)
            if re_hash != node_hash:
                violations.append({
                    "hash": node_hash,
                    "path": node_path.duplicate(),
                    "reason": "save/restore round-trip diverged: %s → %s" % [node_hash, re_hash],
                })

        # Enumerate actions for this state.
        var actions: Array = _enumerate_actions(driver)
        for action in actions:
            actions_tried += 1
            # Restore to the node's state before each action.
            driver.fsm.restore_state(node_state)
            # Issue the action through the real Driver.
            driver._process_input(String(action).to_lower())
            # Check invariants on the new state.
            var inv_failures = _check_invariants(driver, node_path + [action])
            for f in inv_failures:
                violations.append(f)
            # Compute the new state's hash.
            var new_hash: String = _hash_state(driver)
            if not visited.has(new_hash):
                visited[new_hash] = true
                var new_path: Array = node_path.duplicate()
                new_path.append(action)
                reproducer[new_hash] = new_path
                queue.append({
                    "state": driver.fsm.save_state(),
                    "path": new_path,
                    "hash": new_hash,
                })
                states_visited += 1
                if states_visited >= max_states:
                    hit_cap = true
                    break
        if hit_cap:
            break

# ----- Canonical state hash ----------------------------------------

# Conservative first-pass hash: room + sorted inventory + NPC
# states. RFC-0001 enumerates the full design; this is the
# minimum-viable set for a working harness.
func _hash_state(driver) -> String:
    var room: int = driver.fsm.player_room()
    var inv: Array = _inventory_signature(driver)
    var npc: String = _npc_signature(driver)
    return "r=%d|i=%s|n=%s" % [room, "/".join(inv), npc]

func _inventory_signature(driver) -> Array:
    var carried: Array = []
    # Sorted by ID for order-independence.
    var ids: Array = [
        100, 101, 110, 111, 112, 113, 114, 115, 116, 117, 118,
        119, 120, 121, 122, 123,                                  # treasures
        130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140,
        141, 142,                                                  # carriables
    ]
    for id in ids:
        if driver.fsm.player.carrying(id):
            carried.append(str(id))
    return carried

func _npc_signature(driver) -> String:
    var fsm = driver.fsm
    return "%s,%s,%s,%s,%s" % [
        fsm.bird.get_state(),
        fsm.snake.get_state(),
        fsm.bear.get_state(),
        fsm.troll.get_state(),
        fsm.pirate.get_state(),
    ]

# ----- Action enumeration ------------------------------------------

# First-pass: direction commands from the current room's
# room_exits dict. Future iterations will layer in object verbs
# and magic-word teleports (see RFC-0001 §"Action enumeration").
func _enumerate_actions(driver) -> Array:
    var current: int = driver.fsm.player_room()
    var exits: Dictionary = Topology.ROOMS.get(current, {})
    var actions: Array = []
    for direction in exits.keys():
        actions.append(direction)
    return actions

# ----- Invariants --------------------------------------------------

# Returns array of {hash, path, reason} for each invariant the
# state fails. Empty array means the state is sound.
func _check_invariants(driver, path: Array) -> Array:
    var failures: Array = []
    var fsm = driver.fsm
    var room: int = fsm.player_room()
    var hash: String = _hash_state(driver)

    if room < 1 or room > 140:
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "player_room %d out of range [1..140]" % room,
        })

    if fsm.score() < -100:
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "score %d below sanity floor" % fsm.score(),
        })

    var battery: int = fsm.lamp.battery_left()
    if battery < 0 or battery > fsm.lamp.MAX_BATTERY:
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "lamp battery %d out of [0..%d]" % [battery, fsm.lamp.MAX_BATTERY],
        })

    return failures

# ----- Reporting ---------------------------------------------------

func report() -> void:
    print("=== State-space search report ===")
    print("Seed:           %d" % seed)
    print("States visited: %d  (cap: %d%s)" % [states_visited, max_states, " — HIT" if hit_cap else ""])
    print("Actions tried:  %d" % actions_tried)
    print("Violations:     %d" % violations.size())
    if violations.size() > 0:
        print("")
        print("--- Violation detail ---")
        for v in violations.slice(0, 10):  # cap at 10 for readability
            print("  %s" % v["reason"])
            print("    reproducer: %s" % "; ".join(v["path"]))
        if violations.size() > 10:
            print("  ... (%d more)" % (violations.size() - 10))
