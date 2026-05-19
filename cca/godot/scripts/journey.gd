# ============================================================
# journey.gd — Journey base class
# ============================================================
# A Journey is a named sequence of milestones reachable from a
# parent journey's milestone via specific player commands. The
# whole tree forms a DAG rooted at canonical_journey (the
# Crowther/Woods linear playthrough). New journeys extend from any
# milestone in any journey, building a tree of named state
# snapshots that covers progressively more of the canon room
# graph.
#
# Concrete subclasses:
#   • CanonicalJourneyAdapter (canonical_journey_adapter.gd) —
#     wraps the existing canonical_journey.gd FSM as a root
#     journey. The FSM stays the authoritative spec for canonical
#     play; the adapter exposes its iteration through the Journey
#     API so JourneyTree can treat it like any other journey.
#   • ExtensionJourney (extension_journey.gd) — pure-data journey
#     holding a parent reference + list of {milestone, commands}
#     steps. Used for Phase 2 auto-extensions (gate-unlock walks)
#     and Phase 3 manual extensions (prerequisite-chain walks).
#
# Naming convention: a journey identifies itself by `name` (e.g.
# "PlantUnlock"); a milestone within it is addressed as
# "<journey_name>:<milestone>" (e.g. "PlantUnlock:PlantHugeGrown").
# This matches MilestoneRegistry's existing key format so
# snapshots from any journey land in the same registry without
# collision.
# ============================================================
extends RefCounted

# Display name; used as the journey side of the
# "<journey>:<milestone>" snapshot key.
var name: String = ""

# Parent journey name and the milestone within it where this
# journey starts. Empty strings indicate a root journey (only
# canonical_journey at the moment).
var parent_journey: String = ""
var parent_milestone: String = ""

# Walk this journey from its starting state, capturing each
# milestone snapshot into `registry`. The caller must have
# restored driver.fsm to the parent_milestone state before
# calling (or the canonical-start state if this is a root).
# Returns the milestone name reached. If `stop_at` is non-empty
# the walk halts there; returns "" if stop_at was never reached
# (e.g. journey doesn't include that milestone). If `stop_at` is
# "" the walk runs to completion and returns the final milestone.
func apply(driver, registry, stop_at: String = "") -> String:
    push_error("Journey.apply() must be overridden by subclass")
    return ""

# Names of every milestone this journey adds, in walk order.
# Parent-journey milestones are NOT included.
func milestone_names() -> Array:
    push_error("Journey.milestone_names() must be overridden by subclass")
    return []
