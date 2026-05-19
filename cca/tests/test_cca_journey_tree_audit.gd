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
const JourneyTreeC = preload("res://scripts/journey_tree.gd")
const Topology = preload("res://scripts/topology.gd")

# Deepest pre-endgame milestone the canonical journey reaches via
# pure player commands. Has bird-released, dragon-dead, troll-
# paid, bear-tamed, chain-taken, bear-released. The journey then
# walks back toward the well-house to deposit treasures —
# BearReleased is the moment when the most game-mechanic state
# has been unlocked.
const DEEP_MILESTONE: String = "BearReleased"
# Cap chosen to fit the 600s per-test timeout with margin. The BFS
# is asymptotic: cap=10000 reaches 121 rooms, 15000 reaches 122,
# 25000 reaches 123. Marginal +1 room past 15000 isn't worth the
# 50% wall-clock penalty. Phase 2's PlantUnlock extension will
# pick up additional rooms via the journey-tree, not by bumping
# this cap further.
const PER_SEED_CAP: int = 15000  # ~4-5 min runtime

# Coverage threshold for pass/fail. Baseline history:
#   • 32 rooms — cap=5000, pre-prompts-fix. The revive-prompt state
#     leak was eating every non-yes/no verb once any branch died.
#   • 104 rooms — cap=5000, post-prompts-fix. Most prereq-chain
#     rooms were just queued-but-not-popped before cap hit (probe
#     at cap=30000 dequeued room 4 ×468 times, reaching room 7
#     ×433 times — all the "prerequisite-chain" rooms in the
#     classifier were pure cap-budget, not real BFS blockers).
#   • 122 rooms — cap=15000, post-prompts-fix. Most surface +
#     deep-cave clusters resolved. Remaining 18 gaps:
#       1 — plant_huge (room 26; needs Phase 2 PlantUnlock journey;
#           ~4 rooms downstream of 26 also gated)
#       2 — dragon-redirects (119/121; unreachable from this seed
#           by design — would need a pre-dragon-kill seed)
#      ~15 — endgame/teleport-only (Repository + magic-word
#           destinations; would need an InRepository seed and/or
#           journeys through xyzzy/plugh)
const FLOOR_ROOMS: int = 115

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

    _annotate_unreached(reached, unreached, registry)

    if reached.size() >= FLOOR_ROOMS:
        print("")
        print("PASS — %d rooms reached (floor %d)" % [reached.size(), FLOOR_ROOMS])
        quit(0)
        return
    print("")
    print("FAIL — %d rooms reached, below floor of %d" % [
        reached.size(), FLOOR_ROOMS])
    quit(1)

# Walk to the named milestone via JourneyTree, which captures
# every milestone snapshot along the way into `registry`. This
# is the first test migrated to the JourneyTree API (Phase 4a);
# the other seeded tests still use hand-rolled walks but produce
# identical results since the underlying primitives match. The
# tree's create_default() registers canonical_journey only —
# Phase 2/3 extension journeys are added by their respective
# tests as those land.
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

    var tree = JourneyTreeC.new()
    tree.register_default()
    return tree.walk_to(driver, registry, "canonical_journey:" + target)

# Parse room numbers out of state hashes.
func _locations_in(s) -> Dictionary:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms

# For each unreached room, classify why it wasn't visited and
# print a structured report. The classification looks at the
# seeded FSM state (BearReleased) and evaluates each gate's
# runtime status — so a `dragon_killed`-checked gate that
# redirects to canon 120 (when dragon dead) doesn't get lumped
# with a `plant_huge` gate that genuinely needs an unlock walk.
#
# Buckets (within "gate-blocked"):
#   • gate-closed-need-unlock — at least one reached-source gate
#     to this room currently fires with a deterministic block
#     (msg only). Phase 2 extension candidates: the player needs
#     to perform an unlock action (pour water, kill dragon, etc.)
#     before the gate falls through.
#   • gate-redirects-elsewhere — every reached-source gate to
#     this room currently fires AND walks the player to a
#     different `dest`. The room is unreachable from this seed
#     (typically post-state mirrored rooms: 119/121 reachable
#     only before dragon kill).
#   • gate-passable-but-unreached — the gate currently falls
#     through to topology AND the topology dest IS this room.
#     BFS should have walked it but didn't. Causes: probabilistic
#     gate (50% miss), cap-budget exhaustion, action-enumeration
#     issue, intermediate dark-room hazard.
func _annotate_unreached(reached: Dictionary, unreached: Array, registry) -> void:
    # Restore the seed FSM to evaluate gate predicates against it.
    var seed_driver = _make_driver_for_gate_eval(registry)
    var fsm = seed_driver.fsm

    var by_category: Dictionary = {
        "gate-closed-need-unlock":   [],
        "gate-redirects-elsewhere":  [],
        "gate-passable-but-unreached": [],
        "prerequisite-chain":        [],
        "unreachable":               [],
    }
    var details: Dictionary = {}     # room → "explanation"

    for room in unreached:
        var category: String = "unreachable"
        var why: String = ""
        # Per-source classification flags: did any reached source
        # have a passable / closed / redirecting gate to this
        # exact room?
        var any_passable: bool = false
        var any_no_gate: bool = false
        var any_closed: bool = false
        var any_redirects: bool = false
        var sources_reached: Array = []
        var sources_unreached: Array = []
        var gate_status_strs: Array = []  # short-form per gate

        for source in range(1, 141):
            var exits: Dictionary = Topology.ROOMS.get(source, {})
            for direction in exits.keys():
                if exits[direction] != room:
                    continue
                var key: String = "%d:%s" % [source, direction]
                if not reached.has(source):
                    sources_unreached.append(key)
                    continue
                sources_reached.append(key)
                if not Topology.GATES.has(key):
                    any_no_gate = true
                    continue
                var gate = Topology.GATES[key]
                var status: String = _gate_runtime_status(fsm, gate, room)
                gate_status_strs.append("%s=%s" % [key, status])
                if status == "closed":
                    any_closed = true
                elif status == "redirects":
                    any_redirects = true
                elif status == "passable":
                    any_passable = true
                # "probabilistic" doesn't set any flag — handled
                # separately below.

        if sources_reached.is_empty() and sources_unreached.is_empty():
            category = "unreachable"
            why = "no canon-topology source"
        elif sources_reached.is_empty():
            category = "unreachable"
            why = "%d source(s), none reached: %s" % [
                sources_unreached.size(), str(sources_unreached.slice(0, 3))]
        elif any_no_gate or any_passable:
            # A direct topology path is available right now; BFS
            # should have walked it. Real cause is action-enum,
            # probabilistic miss, or cap-budget.
            category = "prerequisite-chain" if any_no_gate else "gate-passable-but-unreached"
            why = "reached sources: %s" % str(sources_reached.slice(0, 3))
            if not gate_status_strs.is_empty():
                why += " | gates: %s" % str(gate_status_strs.slice(0, 3))
        elif any_closed:
            category = "gate-closed-need-unlock"
            why = "gates: %s" % str(gate_status_strs.slice(0, 3))
        elif any_redirects:
            category = "gate-redirects-elsewhere"
            why = "gates: %s" % str(gate_status_strs.slice(0, 3))
        else:
            # All gates probabilistic; player may reach with more
            # tries / different RNG.
            category = "gate-passable-but-unreached"
            why = "probabilistic gates: %s" % str(gate_status_strs.slice(0, 3))
        by_category[category].append(room)
        details[room] = why

    print("--- Unreached by category ---")
    for cat in ["gate-closed-need-unlock", "gate-redirects-elsewhere",
                "gate-passable-but-unreached", "prerequisite-chain",
                "unreachable"]:
        print("  %-30s %3d rooms" % [cat, by_category[cat].size()])
    print("")
    for cat in ["gate-closed-need-unlock", "gate-redirects-elsewhere",
                "gate-passable-but-unreached", "prerequisite-chain",
                "unreachable"]:
        if by_category[cat].is_empty():
            continue
        print("--- %s (sample) ---" % cat)
        for r in by_category[cat].slice(0, 8):
            print("  room %d  %s" % [r, details[r]])
        if by_category[cat].size() > 8:
            print("  ...(+%d more)" % (by_category[cat].size() - 8))
        print("")

# Build a driver and restore it to the seeded BearReleased state.
# Used purely to evaluate gate predicates (snake.is_blocking(),
# plant_is_huge(), dragon_alive(), etc.) — we never call
# _process_input on it, so RNG/lamp/etc. state doesn't matter.
func _make_driver_for_gate_eval(registry):
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
    d.fsm.restore_state(registry.get_snapshot("canonical_journey", DEEP_MILESTONE))
    return d

# Returns one of:
#   "closed"        — gate fires (blocks player at source) and has
#                      no `dest` field; player can't leave via this
#                      direction.
#   "redirects"     — gate fires and walks player to a `dest`
#                      different from `target_room`. Player ends
#                      up somewhere else, not at target_room.
#   "passable"      — gate doesn't fire; topology resolves and
#                      walks player to target_room.
#   "probabilistic" — gate is a probability roll; player may or
#                      may not reach target_room depending on RNG.
#
# Multi-rule chains (Array): walk each rule until one fires
# deterministically; chain-level result is that rule's status.
# If all rules are probabilistic-or-fall-through, status is
# "probabilistic" if any was a probability check, else "passable".
func _gate_runtime_status(fsm, gate, target_room: int) -> String:
    if gate is Array:
        var saw_probability: bool = false
        for rule in gate:
            var s: String = _rule_runtime_status(fsm, rule, target_room)
            if s == "closed" or s == "redirects":
                return s
            if s == "probabilistic":
                saw_probability = true
            # "passable" → continue to next rule (this rule didn't fire)
        return "probabilistic" if saw_probability else "passable"
    return _rule_runtime_status(fsm, gate, target_room)

func _rule_runtime_status(fsm, rule: Dictionary, target_room: int) -> String:
    var check: String = rule.get("check", "")
    var fires: bool = false
    match check:
        "always":           fires = true
        "snake":            fires = fsm.snake.is_blocking()
        "troll":            fires = fsm.troll.is_blocking_bridge()
        "bridge":           fires = not fsm.bridge_built()
        "grate":            fires = fsm.grate_locked()
        "plant_huge":       fires = not fsm.plant_is_huge()
        "plant_tall":       fires = not fsm.plant_is_tall()
        "plover_squeeze":   fires = fsm.plover_squeeze_blocked()
        "rusty":            fires = not fsm.rusty_door_oiled()
        "dragon_killed":    fires = not fsm.dragon_alive()
        "chasm_collapsed":  fires = true if "chasm_collapsed_now" in fsm and fsm.chasm_collapsed_now() else false
        "probability":      return "probabilistic"
        "carrying":
            var obj_name: String = rule.get("obj", "")
            if obj_name != "" and obj_name in fsm:
                fires = fsm.player.carrying(int(fsm.get(obj_name)))
        _:                  fires = false   # unknown check → assume passes
    if not fires:
        return "passable"
    # Rule fires. Does it redirect, or just block?
    if "dest" in rule:
        return "redirects" if int(rule["dest"]) != target_room else "passable"
    return "closed"
