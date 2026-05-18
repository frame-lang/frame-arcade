# ============================================================
# state_space.gd — reusable harness for deterministic state-space
# search over CCA's reachable state graph
# ============================================================
# Implements the BFS described in cca/docs/rfcs/rfc-0001.md. The
# search uses `Adventure.save_state()` / `restore_state()` to
# checkpoint and roll back, exercises every reachable transition,
# and asserts invariants at each step.
#
# Usage pattern:
#
#   var s = StateSpace.new()
#   s.seed = 42
#   s.max_states = 5000
#   var driver = s.prepare_driver()         # build the headless driver
#   # (optional) prep the initial state — give the player items,
#   # teleport to a specific room, etc.
#   driver.fsm.player.move_to(9)
#   driver.fsm.player.take(driver.fsm.KEYS_ID)
#   s.run_from(driver)
#   s.report()
#
# `prepare_driver()` returns the constructed Driver Control with
# a deterministic RNG. `run_from(driver)` does BFS from the
# driver's current state. Calling `run()` is a convenience that
# skips the prep step (root = canonical start state).
# ============================================================
extends RefCounted

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const Topology = preload("res://scripts/topology.gd")

# ----- Configuration ------------------------------------------------

# RNG seed for the driver's probabilistic rolls.
var seed: int = 0

# Safety cap on visited-states. The full reachable graph may be
# large; during development we want predictable termination.
var max_states: int = 1000

# Whether to round-trip save/restore at each state for divergence
# detection. ~30ms per state.
var check_save_restore: bool = true

# ----- Results -----------------------------------------------------

var visited: Dictionary = {}
var reproducer: Dictionary = {}
var violations: Array = []
var states_visited: int = 0
var actions_tried: int = 0
var hit_cap: bool = false

# ----- Item ID inventory ------------------------------------------

# All carryable item IDs the search considers for take/drop.
# Mirrors driver.gd's constants — duplicated here so the harness
# doesn't preload the entire driver class just for ID lookups.
const ITEM_IDS: Dictionary = {
    100: "bird",       101: "chain",     110: "gold",
    111: "silver",     112: "diamonds",  113: "jewelry",
    114: "pearl",      115: "vase",      116: "eggs",
    117: "trident",    118: "emerald",   119: "spices",
    120: "chest",      121: "pyramid",   122: "rug",
    123: "coins",
    130: "rod",        131: "keys",      132: "bottle",
    133: "cage",       134: "food",      135: "pillow",
    136: "axe",        137: "clam",      138: "oyster",
    139: "batteries",  140: "magazine",  141: "rod",       # mark_rod
    142: "lamp",
}

# ----- Driver lifecycle --------------------------------------------

# Build a headless driver suitable for the search. Returns it so
# the caller can prep the initial state.
func prepare_driver():
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    # Dwarves stay dormant — per-NPC seeded RNG is fine for
    # determinism, but their walks blow up the state space with
    # NPC-position dimensions we deliberately exclude from the
    # hash. (RFC-0001 §"Canonical state hash" — widened-hash mode
    # would re-include them.)
    driver.fsm.dwarves_auto_woken = true
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = seed
    return driver

# Convenience: build + run from the canonical start state.
func run() -> void:
    var driver = prepare_driver()
    run_from(driver)

# Search from the driver's current state. BFS frontier-expansion
# through real Driver commands.
#
# Coverage semantics (changed 2026-05-18): canonical-start BFS
# proves player-reachability of every visited state. Earlier
# version did three teleport-based sweeps; that only proved FSM-
# reachability — a state could be in `visited` because we
# teleported to it, even if no canonical command sequence reaches
# it. The single-sweep version eliminates that ambiguity: every
# state in `visited` was arrived at by some sequence of
# Driver._process_input calls from the canonical start.
#
# Action source: driver.list_actions_here() — the same affordance
# enumerator the probe uses. Filtered to non-wild actions in BFS
# because wild verbs (examine X / wave Y at every visible noun)
# almost always produce self-loops in the state graph (rebuff
# prose, no state change). They're valuable for parser-coverage
# tests (the probe's job) but waste BFS budget for reachability.
# The probe handles the parser-path-breadth dimension; this
# function handles the reachability dimension.
func run_from(driver) -> void:
    var root_state: PackedByteArray = driver.fsm.save_state()
    var root_hash: String = _hash_state(driver)

    visited[root_hash] = true
    reproducer[root_hash] = []
    states_visited = 1

    var queue: Array = [{"state": root_state, "path": [], "hash": root_hash}]

    while not queue.is_empty():
        if states_visited >= max_states:
            hit_cap = true
            break

        var node = queue.pop_front()
        var node_state: PackedByteArray = node["state"]
        var node_path: Array = node["path"]
        var node_hash: String = node["hash"]

        driver.fsm.restore_state(node_state)

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

        # Affordance enumeration via the driver's own
        # introspection. Wild verbs are filtered because they
        # don't expand the frontier (mostly self-loops); the
        # probe.gd walker exercises them for parser coverage
        # instead.
        var actions: Array = driver.list_actions_here()
        for action in actions:
            if action.kind == "wild":
                continue
            actions_tried += 1
            driver.fsm.restore_state(node_state)
            driver._process_input(action.input)
            var inv_failures = _check_invariants(driver, node_path + [action.key])
            for f in inv_failures:
                violations.append(f)
            var new_hash: String = _hash_state(driver)
            if not visited.has(new_hash):
                visited[new_hash] = true
                var new_path: Array = node_path.duplicate()
                new_path.append(action.key)
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

# Conservative hash: room + sorted inventory + NPC states. Score,
# lamp battery, and turn counter are intentionally excluded from
# dedup (they're invariants, not state-distinguishers).
func _hash_state(driver) -> String:
    var room: int = driver.fsm.player_room()
    var inv: Array = _inventory_signature(driver)
    var npc: String = _npc_signature(driver)
    return "r=%d|i=%s|n=%s" % [room, "/".join(inv), npc]

func _inventory_signature(driver) -> Array:
    var carried: Array = []
    var ids: Array = ITEM_IDS.keys()
    ids.sort()
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


# ----- Invariants --------------------------------------------------

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

    # Endgame phase: state strings are "active" / "closing" /
    # "in_repository" / "won" / "permadead". Catches typos and
    # any new state the search reaches before this is updated.
    var es: String = fsm.endgame_state()
    if not (es in ["active", "closing", "in_repository", "won", "permadead"]):
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "unknown endgame state '%s'" % es,
        })

    # Treasure deposit count never exceeds canon 15.
    var deposits: int = fsm.treasures_deposited()
    if deposits < 0 or deposits > 15:
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "treasures_deposited %d out of [0..15]" % deposits,
        })

    # Treasure-count consistency: the deposits counter must match
    # the number of treasure FSMs actually in their $Deposited state.
    # Catches the "score incremented but FSM never transitioned" bug
    # class — a real risk on persist-restore paths.
    var actual_deposited: int = 0
    for t in [fsm.gold, fsm.silver, fsm.diamonds, fsm.jewelry,
              fsm.pearl, fsm.vase, fsm.eggs, fsm.trident,
              fsm.emerald, fsm.spices, fsm.chest, fsm.pyramid,
              fsm.rug, fsm.coins, fsm.chain]:
        if t.get_state() == "deposited":
            actual_deposited += 1
    if actual_deposited != deposits:
        failures.append({
            "hash": hash, "path": path.duplicate(),
            "reason": "deposit-count mismatch: counter=%d, treasure FSMs=%d" % [
                deposits, actual_deposited],
        })

    # Inventory consistency: every item the Player FSM thinks is
    # carried must agree with the corresponding _item FSM.
    # Mismatch indicates a take/drop path that updates one side
    # but not the other.
    var item_checks: Array = [
        [fsm.ROD_ID, fsm.rod_item], [fsm.KEYS_ID, fsm.keys_item],
        [fsm.BOTTLE_ID, fsm.bottle_item], [fsm.CAGE_ID, fsm.cage_item],
        [fsm.FOOD_ID, fsm.food_item], [fsm.PILLOW_ID, fsm.pillow_item],
        [fsm.AXE_ID, fsm.axe_item], [fsm.CLAM_ID, fsm.clam_item],
        [fsm.MAGAZINE_ID, fsm.magazine_item], [fsm.LAMP_ID, fsm.lamp_item],
    ]
    for pair in item_checks:
        var player_thinks: bool = fsm.player.carrying(pair[0])
        var item_thinks: bool = pair[1].is_carried()
        if player_thinks != item_thinks:
            failures.append({
                "hash": hash, "path": path.duplicate(),
                "reason": "inventory inconsistency for id %d: player=%s, item=%s" % [
                    pair[0], player_thinks, item_thinks],
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
        for v in violations.slice(0, 10):
            print("  %s" % v["reason"])
            print("    reproducer: %s" % "; ".join(v["path"]))
        if violations.size() > 10:
            print("  ... (%d more)" % (violations.size() - 10))
