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
# detection. ~30ms per state — adds up to minutes on a cap=15000
# audit. Default off; the canonical-start BFS test
# (test_cca_state_space.gd) opts in since save/restore soundness
# is itself a thing that test exercises. Most other consumers care
# about reachability, not save/restore divergence.
var check_save_restore: bool = false

# RFC-0002 milestone seeding. If non-empty, the BFS starts from
# the FSM state encoded in these bytes (via fsm.restore_state)
# instead of the canonical start. Use case: walk the canonical
# journey up to a milestone like LampLit-past-grate, snapshot,
# then BFS from there. Subsequent BFS reaches the deep-cave
# graph the cold-start BFS couldn't penetrate within its
# action-ordering budget.
var seed_bytes: PackedByteArray = PackedByteArray()

# Optional label for the seed snapshot (e.g. "canonical_journey:
# LampLit"). Printed in the report for traceability. No
# functional effect.
var seed_label: String = ""

# How often (in states-visited count) to emit a one-line BFS
# progress print. Set to 0 to disable. Long BFS runs at high caps
# can take several minutes; the progress line lets a watching
# operator see "still alive, still expanding" rather than a silent
# wait. Each print is cheap (one Dictionary walk over visited
# hashes to count distinct rooms).
var progress_every: int = 1000

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
    # The model's Chance system carries the probabilistic-travel /
    # pit-fall / etc. rolls now (they used to be driver-side rng).
    # Reseed it to the run seed so per-seed exploration still varies
    # those outcomes — otherwise every seed shares Chance's default
    # and union coverage collapses.
    driver.fsm.chance.reseed(seed)
    return driver

# Convenience: build + run. If `seed_bytes` is non-empty, the
# driver's FSM is restored to that snapshot first — the BFS then
# explores the reachable graph FROM the seeded state, not from
# canonical start. Use this for RFC-0002 milestone-seeded
# coverage: drive the canonical_journey FSM to a milestone,
# snapshot, feed bytes here.
func run() -> void:
    var driver = prepare_driver()
    if not seed_bytes.is_empty():
        driver.fsm.restore_state(seed_bytes)
        _reset_driver_session_state(driver)
    run_from(driver)

# PromptDispatcher state lives on the driver, not in fsm.save_state.
# The architect's documented contract (cca.fgd PromptDispatcher block)
# is that modal-prompt state does NOT survive a save/restore boundary
# — the driver re-detects it from world state in a fresh session. The
# BFS reuses one driver and rolls fsm back, so prompts state would
# otherwise leak across branches: one branch dies → prompts goes to
# $AwaitingRevive → all sibling branches inherit the prompt and find
# every verb getting eaten by the modal Y/N dispatcher. Resetting
# here mirrors the fresh-session semantics. Re-emit offer_revive() if
# the restored world state has a dead player so the prompt is
# correctly re-derived.
func _reset_driver_session_state(driver) -> void:
    driver.prompts = Cca.PromptDispatcher.new()
    if driver.fsm.player.get_state() == "dead":
        driver.prompts.offer_revive()

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
    var next_progress: int = progress_every

    while not queue.is_empty():
        if states_visited >= max_states:
            hit_cap = true
            break
        if progress_every > 0 and states_visited >= next_progress:
            var rooms_so_far: Dictionary = {}
            for h in visited.keys():
                rooms_so_far[int(h.substr(2).get_slice("|", 0))] = true
            print("  [BFS] %d states, %d locations, queue=%d, actions=%d" % [
                states_visited, rooms_so_far.size(), queue.size(), actions_tried])
            next_progress += progress_every

        var node = queue.pop_front()
        var node_state: PackedByteArray = node["state"]
        var node_path: Array = node["path"]
        var node_hash: String = node["hash"]

        driver.fsm.restore_state(node_state)
        _reset_driver_session_state(driver)

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
            _reset_driver_session_state(driver)
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
    if seed_label != "":
        print("Seed snapshot:  %s" % seed_label)
    print("States visited: %d  (cap: %d%s)" % [states_visited, max_states, " — HIT" if hit_cap else ""])
    # Per-location breakdown. A "state" is (room + inventory +
    # NPC states); a "location" is just the canon room number.
    # 140 canon locations total. Many states usually map to the
    # same location (e.g. "at room 5 empty-handed" vs "at room 5
    # carrying keys"). Reporting both numbers distinguishes
    # "how much of the world map did we reach" from "how many
    # world configurations did we enumerate".
    var states_per_location: Dictionary = {}
    for h in visited.keys():
        # Hash format: "r=N|i=...|d=...|e=...|n=..."
        var room: int = int(h.substr(2).get_slice("|", 0))
        states_per_location[room] = states_per_location.get(room, 0) + 1
    var locations: Array = states_per_location.keys()
    locations.sort()
    print("Locations:      %d  / 140 canon rooms" % locations.size())
    print("Actions tried:  %d" % actions_tried)
    print("Violations:     %d" % violations.size())
    if not locations.is_empty():
        print("")
        print("--- Locations reached (sorted) ---")
        print("  %s" % str(locations))
        var missing: Array = []
        for r in range(1, 141):
            if not states_per_location.has(r):
                missing.append(r)
        print("")
        print("--- Unreached locations (%d/140) ---" % missing.size())
        if missing.size() <= 30:
            print("  %s" % str(missing))
        else:
            print("  %s ...(+%d more)" % [str(missing.slice(0, 30)), missing.size() - 30])
        print("")
        print("--- Top 10 locations by state count ---")
        var by_count: Array = locations.duplicate()
        by_count.sort_custom(func(a, b): return states_per_location[a] > states_per_location[b])
        for r in by_count.slice(0, 10):
            print("  room %d: %d states" % [r, states_per_location[r]])
    if violations.size() > 0:
        print("")
        print("--- Violation detail ---")
        for v in violations.slice(0, 10):
            print("  %s" % v["reason"])
            print("    reproducer: %s" % "; ".join(v["path"]))
        if violations.size() > 10:
            print("  ... (%d more)" % (violations.size() - 10))
