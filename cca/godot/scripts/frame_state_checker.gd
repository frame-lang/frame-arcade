# ============================================================
# frame_state_checker.gd — bounded explicit-state model checker
# for Frame-native programs
# ============================================================
# Domain-agnostic. Given a FrameModelAdapter (the seam to a
# specific Frame system), this computes bounded approximations of
# the classical model-checking properties:
#
#   • Reachability     — explore() enumerates the reachable state
#                        set by breadth-first frontier expansion
#                        (Holzmann/SPIN explicit-state search;
#                        bounded per Biere et al. 1999 via
#                        max_states).
#   • Safety           — invariants asserted at every reached
#                        state (Lamport 1977; Alpern & Schneider
#                        1985). A violation is a finite
#                        counterexample trace.
#   • Liveness (EF)    — reachable_satisfying() answers the CTL
#                        query EF φ: does SOME reachable state
#                        satisfy φ? Used for goal-reachability
#                        ("can you still win", φ = won).
#   • Bisimulation     — restore_soundness() checks observational
#                        equivalence (Milner 1980, Park 1981):
#                        does restoring to a state via the adapter
#                        produce behavior indistinguishable from a
#                        fresh instance at that state? This is the
#                        check that catches incomplete-state-vector
#                        bugs.
#
# HONEST SCOPE: this is *bounded, directed, possibly
# RNG-sampled* checking, not exhaustive verification. We
# approximate the formulas; we don't discharge them. With a
# state cap the search may miss states beyond the frontier; with
# a fixed RNG seed it explores one resolution of probabilistic
# transitions. Treat results as strong evidence (tested), not
# proof (verified). Directed search (seeding from a deep state)
# is the standard remedy for the reachability-depth problem —
# cf. directed model checking (Edelkamp) and Go-Explore (Ecoffet
# et al., Nature 2021).
# ============================================================
extends RefCounted

# ----- Config --------------------------------------------------
var adapter                       # FrameModelAdapter instance
var max_states: int = 5000        # bound (Biere et al. bounded MC)
var progress_every: int = 0       # 0 = silent; else heartbeat cadence

# ----- Results -------------------------------------------------
var visited: Dictionary = {}      # hash → true (the reached set)
var reproducer: Dictionary = {}   # hash → action path (counterexample witness)
var violations: Array = []        # [{hash, path, reason}]
var states_visited: int = 0
var actions_tried: int = 0
var hit_cap: bool = false

func _init(p_adapter):
    adapter = p_adapter

# ----- Reachability + safety -----------------------------------
# Breadth-first frontier expansion from the adapter's root.
# Asserts invariants (safety) at every reached state. Populates
# `visited` (the reachable set), `violations` (safety
# counterexamples with witness paths), and `reproducer` (shortest
# action path to each state).
func explore() -> void:
    var o = adapter.make_root()
    adapter.reset_session(o)
    var root_hash: String = adapter.state_hash(o)
    visited[root_hash] = true
    reproducer[root_hash] = []
    states_visited = 1

    var queue: Array = [{
        "state": adapter.save(o),
        "path": [],
        "hash": root_hash,
    }]
    var next_progress: int = progress_every

    while not queue.is_empty():
        if states_visited >= max_states:
            hit_cap = true
            break
        if progress_every > 0 and states_visited >= next_progress:
            print("  [checker] %d states, %d in queue, %d actions" % [
                states_visited, queue.size(), actions_tried])
            next_progress += progress_every

        var node = queue.pop_front()
        adapter.restore(o, node["state"])
        adapter.reset_session(o)

        for action in adapter.enumerate_actions(o):
            actions_tried += 1
            adapter.restore(o, node["state"])
            adapter.reset_session(o)
            adapter.apply(o, action)

            var path: Array = node["path"] + [_action_label(action)]
            for reason in adapter.invariants(o):
                violations.append({
                    "hash": adapter.state_hash(o),
                    "path": path.duplicate(),
                    "reason": reason,
                })

            var h: String = adapter.state_hash(o)
            if not visited.has(h):
                visited[h] = true
                reproducer[h] = path
                queue.append({"state": adapter.save(o), "path": path, "hash": h})
                states_visited += 1
                if states_visited >= max_states:
                    hit_cap = true
                    break
        if hit_cap:
            break

# ----- Liveness: EF φ (goal reachability) ----------------------
# Bounded answer to the CTL query EF φ — is there a reachable
# state satisfying `predicate`? Returns {found: bool, path: Array,
# states: int}. `predicate` is Callable(o) -> bool. Short-circuits
# on the first satisfying state, returning its witness path.
func reachable_satisfying(predicate: Callable) -> Dictionary:
    var o = adapter.make_root()
    adapter.reset_session(o)
    var seen: Dictionary = {adapter.state_hash(o): true}
    var queue: Array = [{"state": adapter.save(o), "path": []}]
    var explored: int = 0
    while not queue.is_empty():
        if explored >= max_states:
            return {"found": false, "path": [], "states": explored, "hit_cap": true}
        var node = queue.pop_front()
        adapter.restore(o, node["state"])
        adapter.reset_session(o)
        if predicate.call(o):
            return {"found": true, "path": node["path"], "states": explored, "hit_cap": false}
        explored += 1
        for action in adapter.enumerate_actions(o):
            adapter.restore(o, node["state"])
            adapter.reset_session(o)
            adapter.apply(o, action)
            var h: String = adapter.state_hash(o)
            if not seen.has(h):
                seen[h] = true
                queue.append({"state": adapter.save(o), "path": node["path"] + [_action_label(action)]})
    return {"found": false, "path": [], "states": explored, "hit_cap": false}

# ----- Bisimulation: restore soundness -------------------------
# Observational-equivalence check (Milner/Park). For each sample
# state, confirm that restoring to it on a REUSED, deliberately-
# dirtied instance produces the same observable signature as a
# FRESH instance restored to it. A divergence means restore (or
# the state vector) is incomplete — the incomplete-state-vector
# soundness trap. `dirty` is Callable(adapter, o) that mutates
# the reused instance into a worst-case prior state before the
# restore. Returns a list of divergence descriptions (empty ==
# sound).
func restore_soundness(samples: Array, dirty: Callable) -> Array:
    var divergences: Array = []
    for i in range(samples.size()):
        var bytes: PackedByteArray = samples[i]["bytes"]
        var name: String = samples[i].get("name", str(i))

        # Fresh instance restored to the sample.
        var fresh = adapter.make_root()
        adapter.restore(fresh, bytes)
        adapter.reset_session(fresh)
        var sig_fresh: String = adapter.observe(fresh)

        # Reused instance: dirty it, then restore to the sample.
        var reused = adapter.make_root()
        dirty.call(adapter, reused)
        adapter.restore(reused, bytes)
        adapter.reset_session(reused)
        var sig_reused: String = adapter.observe(reused)

        if sig_fresh != sig_reused:
            divergences.append({
                "name": name,
                "fresh": sig_fresh,
                "reused": sig_reused,
            })
    return divergences

# ----- Helpers -------------------------------------------------

func reached_count() -> int:
    return visited.size()

# Best-effort human label for an action descriptor. The engine
# treats actions as opaque; this only affects counterexample
# readability.
func _action_label(action) -> String:
    if action is Dictionary:
        return String(action.get("key", action.get("input", str(action))))
    return str(action)
