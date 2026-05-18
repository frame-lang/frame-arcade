# ============================================================
# world_graph.gd — passive automata learner for CCA
# ============================================================
# Phase A of the L*-style learning track. The probe (probe.gd)
# emits one observation per step — (from_state, action, to_state)
# — and this module accumulates them into an explicit transition
# graph of the reachable world automaton.
#
# Lineage: this is the passive variant of automata learning
# (Angluin 1987's L* is the active form; Oncina & García 1992
# RPNI is the canonical passive learner). We don't try to learn
# a minimised DFA here — we just record observations and offer
# queries over the resulting graph. Minimisation (Hopcroft 1971)
# is a clean follow-on if it proves useful.
#
# The graph is deliberately tolerant of non-determinism. CCA has
# probabilistic transitions (Witt's End 95/5, dark-pit 35%,
# dwarf walks, pirate steals), so `(from, action)` is not a
# function: it's a multiset of destinations with observed
# frequencies. Shortest-path queries treat any observed edge as
# traversable (we know the destination is reachable with
# positive probability from `from` under `action`).
#
# Queries supported:
#   - shortest_path(from, to)        BFS over learned edges
#   - frontier(visit_counts)         states whose outgoing actions
#                                    lead to under-visited destinations
#   - audit_topology()               compare observed movement
#                                    transitions against topology.gd,
#                                    surfacing gate-driven divergences
#                                    and (hopefully) no real bugs
#   - reachable_from(start)          all states known to be reachable
#                                    from `start` via observed edges
# ============================================================
extends RefCounted

const Topology = preload("res://scripts/topology.gd")

# ----- Storage ------------------------------------------------------

# transitions[from_hash][action_key] → Dictionary[to_hash → count]
# Nested-dict form keeps the data structure flat in GDScript and
# makes per-edge counts cheap to update. The action_key uses the
# probe's stable identifier ("move:north", "take:gold", "magic:
# xyzzy") so audit queries can pattern-match by prefix.
var transitions: Dictionary = {}

# Set of every state hash we've ever seen, either as edge source
# or destination. Used to detect "reached as target but never
# explored from" states (a classic L* dangling-state signal).
var seen_states: Dictionary = {}

# State-hash → room id. We need this for the topology audit, and
# it's also handy when a caller wants to enumerate "states whose
# room is X." Probe emits the hash and room together; we just
# store the mapping.
var room_of: Dictionary = {}

# Canonical root state — the first hash seen on the first record()
# call. Used as the default `start` for reachable_from() and
# unreachable diagnostics.
var root_hash: String = ""

# ----- Recording ----------------------------------------------------

# Record one observation. Idempotent for repeated traversals —
# the count on the destination edge bumps each time.
func record(from_hash: String, from_room: int,
            action_key: String,
            to_hash: String, to_room: int) -> void:
    if root_hash == "":
        root_hash = from_hash
    seen_states[from_hash] = true
    seen_states[to_hash] = true
    room_of[from_hash] = from_room
    room_of[to_hash] = to_room
    if not transitions.has(from_hash):
        transitions[from_hash] = {}
    var out_by_action: Dictionary = transitions[from_hash]
    if not out_by_action.has(action_key):
        out_by_action[action_key] = {}
    var dests: Dictionary = out_by_action[action_key]
    dests[to_hash] = dests.get(to_hash, 0) + 1

# ----- Queries ------------------------------------------------------

# BFS shortest-path from `start` to `goal` over the learned graph.
# Returns an Array of action_key strings; empty array if `goal`
# isn't reachable from `start` via known edges (either it's
# genuinely unreachable or we haven't observed the connecting
# edges yet).
#
# Edge multiplicity (observed N times) doesn't affect the path —
# we treat every observed edge as available. A more sophisticated
# version would weight by 1/count or by transition probability
# for stochastic shortest path, but for the current "route to a
# frontier cell" use case unweighted BFS is right.
func shortest_path(start: String, goal: String) -> Array:
    if start == goal:
        return []
    var came_from: Dictionary = {}
    var via_action: Dictionary = {}
    came_from[start] = ""
    var queue: Array = [start]
    while not queue.is_empty():
        var cur: String = queue.pop_front()
        if not transitions.has(cur):
            continue
        for action_key in transitions[cur]:
            for dest in transitions[cur][action_key]:
                if came_from.has(dest):
                    continue
                came_from[dest] = cur
                via_action[dest] = action_key
                if dest == goal:
                    var path: Array = []
                    var node: String = goal
                    while node != start:
                        path.push_front(via_action[node])
                        node = came_from[node]
                    return path
                queue.append(dest)
    return []

# All states reachable from `start` via observed edges. Returns a
# Dictionary (used as a set) to keep "is this reachable?" checks
# O(1) downstream.
func reachable_from(start: String) -> Dictionary:
    var reached: Dictionary = {start: true}
    var queue: Array = [start]
    while not queue.is_empty():
        var cur: String = queue.pop_front()
        if not transitions.has(cur):
            continue
        for action_key in transitions[cur]:
            for dest in transitions[cur][action_key]:
                if reached.has(dest):
                    continue
                reached[dest] = true
                queue.append(dest)
    return reached

# States that appear as edge targets but were never explored from
# (no outgoing transitions recorded). They're the natural "next
# place to walk to" for an exploration-focused agent. In L* terms,
# the un-membership-queried set.
func dangling_states() -> Array:
    var dangling: Array = []
    for hash in seen_states:
        if not transitions.has(hash):
            dangling.append(hash)
    return dangling

# ----- Topology audit ----------------------------------------------

# For every observed (room, direction) movement, compare the
# learned destination against topology.gd::ROOMS. Three categories
# of divergence are possible:
#
#   1. Bug: topology claims A→X for direction D, but observation
#      shows A→Y consistently and no gate is registered at
#      `A:D`. This is what we're hunting — a real disagreement
#      between the topology table and what the driver actually
#      does.
#
#   2. Gate-conditional: topology claims A→X, observation shows
#      A→Y, AND `A:D` is in Topology.GATES. The driver's gate
#      intercept fired; the divergence is expected canon behaviour
#      (e.g. carrying-gold blocks 15:up).
#
#   3. Multi-destination probabilistic: topology claims A→X,
#      observation shows multiple destinations including X. Canon
#      probability rows (Witt's End 95/5, Bedquilt random walk).
#
# Returned dictionaries carry a `category` field so the report
# can group output, and `observations` count for confidence
# weighting (a 1-observation divergence might be a fluke; 50
# observations is conclusive).
func audit_topology() -> Array:
    var divergences: Array = []
    for from_hash in transitions:
        var from_room: int = room_of[from_hash]
        for action_key in transitions[from_hash]:
            if not action_key.begins_with("move:"):
                continue
            var direction: String = action_key.substr(5)
            var topo_exits: Dictionary = Topology.ROOMS.get(from_room, {})
            if not topo_exits.has(direction):
                # No topology entry — direction was accepted by a
                # gate or by a driver-side handler (e.g. magic-word
                # exit). Skip; not the audit's concern.
                continue
            var topo_dest = topo_exits[direction]
            var dests: Dictionary = transitions[from_hash][action_key]
            for to_hash in dests:
                var to_room: int = room_of[to_hash]
                if to_room == topo_dest:
                    continue
                # Four-way categorisation. The big distinction is
                # "stayed put" (player ended where they started —
                # action was rejected or a per-step death+revive
                # bounced them back) vs. "wrong destination" (they
                # did move but to an unexpected room — a much more
                # suspicious signal). Gated rows are correct canon
                # behaviour; the remaining stayed-put rows are most
                # likely death/revive artifacts; only wrong_dest
                # rows are real-bug candidates.
                var has_gate: bool = (
                    Topology.GATES.has("%d:%s" % [from_room, direction]))
                var category: String
                if has_gate:
                    category = "gate"
                elif to_room == from_room:
                    category = "stayed_put"
                else:
                    category = "wrong_dest"
                divergences.append({
                    "from_room":      from_room,
                    "from_hash":      from_hash,
                    "direction":      direction,
                    "topology_says":  topo_dest,
                    "observed":       to_room,
                    "observations":   dests[to_hash],
                    "category":       category,
                })
    return divergences

# ----- Reporting ---------------------------------------------------

func report() -> void:
    print("--- Learned world graph ---")
    print("States observed:    %d  (every from-or-to hash ever seen)" % seen_states.size())
    print("Source states:      %d  (states with outgoing observations)" % transitions.size())
    print("Dangling states:    %d  (seen as targets, never explored from)" % dangling_states().size())
    var total_edges: int = 0
    var total_obs: int = 0
    for from_hash in transitions:
        for action_key in transitions[from_hash]:
            total_edges += transitions[from_hash][action_key].size()
            for to_hash in transitions[from_hash][action_key]:
                total_obs += transitions[from_hash][action_key][to_hash]
    print("Distinct edges:     %d  (unique (state, action, next-state) triples)" % total_edges)
    print("Edge observations:  %d  (sum of traversal counts)" % total_obs)
    # Reachability from root: a state observed as a target but not
    # reachable-from-root indicates the probe perturbed the FSM
    # directly (rather than walking to that state). For pure-
    # probe runs the gap should be zero.
    if root_hash != "":
        var reached: Dictionary = reachable_from(root_hash)
        var unreachable: int = seen_states.size() - reached.size()
        print("Reachable from root: %d (%d unreachable from canonical start)" % [
            reached.size(), unreachable])

# Audit + categorise + print. Calling code can also pull the raw
# array via audit_topology() if it wants different grouping.
func report_topology_audit(limit_per_category: int = 15) -> void:
    var divergences: Array = audit_topology()
    var by_category: Dictionary = {
        "gate":       [],
        "stayed_put": [],
        "wrong_dest": [],
    }
    for d in divergences:
        by_category[d.category].append(d)
    print("--- Topology audit ---")
    print("Total divergences:    %d  (movement edges whose observed destination ≠ topology.gd claim)" % divergences.size())
    print("  gate-conditional:   %d  (Topology.GATES entry exists — expected canon behaviour)" % by_category.gate.size())
    print("  stayed-put no-gate: %d  (no movement happened — death+revive, dark-pit, or missing gate registration)" % by_category.stayed_put.size())
    print("  wrong-destination:  %d  (player did move but landed at unexpected room — bug candidate)" % by_category.wrong_dest.size())

    if by_category.wrong_dest.size() > 0:
        print("")
        print("  --- Wrong-destination (first %d) — INVESTIGATE ---" % min(limit_per_category, by_category.wrong_dest.size()))
        for d in by_category.wrong_dest.slice(0, limit_per_category):
            print("    room %d  move:%s  topology→%d  observed→%d  (×%d)" % [
                d.from_room, d.direction, d.topology_says,
                d.observed, d.observations])
    if by_category.stayed_put.size() > 0 and limit_per_category > 0:
        print("")
        print("  --- Stayed-put (first %d) — usually benign ---" % min(limit_per_category, by_category.stayed_put.size()))
        for d in by_category.stayed_put.slice(0, limit_per_category):
            print("    room %d  move:%s  topology→%d  stayed at %d  (×%d)" % [
                d.from_room, d.direction, d.topology_says,
                d.observed, d.observations])
    if by_category.gate.size() > 0 and limit_per_category > 0:
        print("")
        print("  --- Gate-conditional (first %d) — expected ---" % min(limit_per_category, by_category.gate.size()))
        for d in by_category.gate.slice(0, limit_per_category):
            print("    room %d  move:%s  topology→%d  observed→%d  (×%d) [gate]" % [
                d.from_room, d.direction, d.topology_says,
                d.observed, d.observations])
