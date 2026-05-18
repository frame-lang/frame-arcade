# ============================================================
# milestone_registry.gd — snapshot store for canonical journeys
# ============================================================
# RFC-0002's foundational primitive: a named-snapshot registry
# that captures `fsm.save_state()` bytes at canonical-journey
# milestone states. Any test or BFS run can later restore from
# these snapshots to start exploration from a deep-game state
# instead of the canonical start.
#
# The registry is instance-based (not singleton) because Godot
# tests run in separate processes — there's no shared global
# across files. Each test that wants milestones either:
#   1. Runs the journey itself and captures snapshots locally
#      (the pattern in test_cca_state_space_seeded.gd), or
#   2. Loads from a future persisted form (deferred until cross-
#      process snapshot sharing has a concrete use case).
#
# The named-key convention is "<journey_name>:<milestone_name>"
# so the same registry can hold snapshots from multiple journey
# variants without collision (RFC-0002 anticipates a catalog of
# journeys: canonical_journey, canonical_journey_dragon_first,
# canonical_journey_maze_deep, etc).
# ============================================================
extends RefCounted

var _snapshots: Dictionary = {}

# Store a save_state() snapshot under the given journey + milestone.
# Idempotent: re-recording the same key overwrites (later journey
# runs are presumed to supersede earlier ones for the same FSM).
func record(journey_name: String, milestone_name: String, bytes: PackedByteArray) -> void:
    var key: String = "%s:%s" % [journey_name, milestone_name]
    _snapshots[key] = bytes

# Returns the stored snapshot bytes, or an empty PackedByteArray
# if not recorded. Callers MUST check is_empty() before passing
# to fsm.restore_state().
func get_snapshot(journey_name: String, milestone_name: String) -> PackedByteArray:
    var key: String = "%s:%s" % [journey_name, milestone_name]
    return _snapshots.get(key, PackedByteArray())

func has(journey_name: String, milestone_name: String) -> bool:
    var key: String = "%s:%s" % [journey_name, milestone_name]
    return _snapshots.has(key)

# Returns the list of "journey:milestone" keys currently recorded.
# Useful for diagnostic reports.
func keys() -> Array:
    return _snapshots.keys()

func size() -> int:
    return _snapshots.size()

func clear() -> void:
    _snapshots.clear()
