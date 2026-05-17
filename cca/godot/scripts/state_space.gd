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

# Whether to enumerate take/drop interactions in addition to
# directions. Significantly widens the search.
var enumerate_items: bool = true

# Whether to enumerate magic-word teleports at canonical source
# rooms. Cheap (3 verbs max per state).
var enumerate_magic_words: bool = true

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

# Magic-word teleports — verbs and the rooms they're canonically
# anchored to (any of the listed rooms makes the verb relevant).
const MAGIC_WORDS: Dictionary = {
    "xyzzy":  [1, 11],
    "plugh":  [3, 33],
    "plover": [33, 100],
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

# Search from the driver's current state.
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

        var actions: Array = _enumerate_actions(driver)
        for action in actions:
            actions_tried += 1
            driver.fsm.restore_state(node_state)
            driver._process_input(String(action).to_lower())
            var inv_failures = _check_invariants(driver, node_path + [action])
            for f in inv_failures:
                violations.append(f)
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

# ----- Action enumeration ------------------------------------------

func _enumerate_actions(driver) -> Array:
    var actions: Array = []
    var current: int = driver.fsm.player_room()

    # Direction commands — all keys in the current room's exits.
    var exits: Dictionary = Topology.ROOMS.get(current, {})
    for direction in exits.keys():
        actions.append(direction)

    # Magic-word teleports if at a canonical source room.
    if enumerate_magic_words:
        for word in MAGIC_WORDS.keys():
            if current in MAGIC_WORDS[word]:
                actions.append(word)

    # Object interactions — take items in the current room,
    # drop items currently carried. EXAMINE / READ are no-ops
    # for state, so we skip them in the action enumeration
    # (they'd just waste BFS time without expanding coverage).
    if enumerate_items:
        for id in ITEM_IDS.keys():
            var name: String = ITEM_IDS[id]
            if driver.fsm.player.carrying(id):
                actions.append("drop " + name)
            elif _item_in_room(driver, id, current):
                actions.append("take " + name)

    # State-changing verbs gated on preconditions. Each fires
    # only when its target is plausibly present; rebuffs at
    # other rooms are OK (no state change, just a wasted action
    # — not a correctness issue).
    var fsm = driver.fsm
    if fsm.player.carrying(fsm.LAMP_ID):
        if not fsm.lamp.is_lit():
            actions.append("light lamp")
        else:
            actions.append("extinguish lamp")
    if fsm.player.carrying(fsm.KEYS_ID) and (current == 8 or current == 9):
        actions.append("unlock grate")
    if fsm.player.carrying(fsm.ROD_ID):
        # Wave-rod-at-fissure is the canonical crystal-bridge
        # builder; fires at rooms 17 (east bank) or 27 (west).
        actions.append("wave rod")
    # NPC interaction verbs — gated by the NPC being canonically
    # at the current room (we approximate with hard-coded canon
    # rooms; cheaper than querying every NPC's location).
    if current == 119 and fsm.dragon_alive():
        actions.append("attack dragon")
    if current == 19 and fsm.snake.is_blocking():
        actions.append("attack snake")
        actions.append("release bird") if fsm.player.carrying(fsm.BIRD_ID) else null
    if current == 130:
        # Bear room — feed / take chain are the canon mechanics.
        if fsm.player.carrying(fsm.FOOD_ID):
            actions.append("feed bear")
    # Bird-cage capture
    if current == 13 and fsm.bird.get_state() == "free":
        actions.append("take bird")
    # Break clam → pearl (at any room with clam carried or in room)
    if fsm.player.carrying(fsm.CLAM_ID) and fsm.player.carrying(fsm.ROD_ID):
        actions.append("break clam")
    # Bottle fluid interactions
    if fsm.player.carrying(fsm.BOTTLE_ID):
        if fsm.bottle.has_water():
            actions.append("pour water")
        elif fsm.bottle.has_oil():
            actions.append("pour oil")

    return actions

# Best-effort check whether item `id` is visible in `room`. The
# driver has a more comprehensive `_object_in_room` helper but it
# requires matching on every concrete `_item` FSM; we approximate
# by querying the most common ones. False positives just cause an
# extra "take X" action that no-ops with "You can't be serious!" —
# wasted action but not a correctness issue.
func _item_in_room(driver, id: int, room: int) -> bool:
    var fsm = driver.fsm
    # Inline the most-common items. Others fall through to a
    # generic try — if the FSM exposes is_in_room(room), use it.
    match id:
        100: return fsm.bird.get_location() == room
        101: return fsm.chain.get_location() == room
        110: return fsm.gold.get_location() == room
        111: return fsm.silver.get_location() == room
        112: return fsm.diamonds.get_location() == room
        113: return fsm.jewelry.get_location() == room
        114: return fsm.pearl.get_location() == room
        115: return fsm.vase.get_location() == room
        116: return fsm.eggs.get_location() == room
        117: return fsm.trident.get_location() == room
        118: return fsm.emerald.get_location() == room
        119: return fsm.spices.get_location() == room
        120: return fsm.chest.get_location() == room
        121: return fsm.pyramid.get_location() == room
        122: return fsm.rug.get_location() == room
        123: return fsm.coins.get_location() == room
        130: return fsm.rod_item.is_in_room(room)
        131: return fsm.keys_item.is_in_room(room)
        132: return fsm.bottle_item.is_in_room(room)
        133: return fsm.cage_item.is_in_room(room)
        134: return fsm.food_item.is_in_room(room)
        135: return fsm.pillow_item.is_in_room(room)
        136: return fsm.axe_item.is_in_room(room)
        137: return fsm.clam_item.is_in_room(room)
        138: return fsm.oyster_item.is_in_room(room)
        139: return fsm.batteries_item.is_in_room(room)
        140: return fsm.magazine_item.is_in_room(room)
        141: return fsm.mark_rod_item.is_in_room(room)
        142: return fsm.lamp_item.is_in_room(room)
    return false

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
