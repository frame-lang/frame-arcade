# ============================================================
# frame_model_adapter.gd — domain interface for FrameStateChecker
# ============================================================
# A Frame system is a labeled transition system (LTS) — a Kripke
# structure — by construction: explicit states, explicit
# transitions, query methods that serve as atomic propositions.
# Software model checking's expensive step is *extracting* such a
# structure from arbitrary code (predicate abstraction, abstract
# interpretation — the SLAM / BLAST / CBMC machinery). A
# Frame-native program skips that step: it is already in the form
# the checker wants.
#
# This adapter is the thin seam between a specific Frame domain
# and the generic FrameStateChecker. A domain implements these
# methods; the checker then computes the classical properties
# (Lamport safety, CTL reachability/AG-EF liveness, Milner
# bisimulation) over the domain's own transition system.
#
# Required overrides:
#   make_root()          — a fresh instance at the initial state.
#   save(o)              — serialize the full state (the "state
#                          vector", in SPIN terms).
#   restore(o, bytes)    — deserialize. MUST restore ALL state
#                          that affects transitions; see
#                          reset_session() for the subtle part.
#   enumerate_actions(o) — the enabled actions at this state
#                          (opaque descriptors; the engine passes
#                          them back to apply()).
#   apply(o, action)     — fire one action (one transition step).
#   hash(o)              — the state vector as a dedup key. Two
#                          states with the same hash are treated
#                          as identical by the search. SOUNDNESS
#                          DEPENDS ON THIS CAPTURING ALL
#                          TRANSITION-RELEVANT STATE (see below).
#   invariants(o)        — safety check. Returns a list of
#                          violation strings (empty == clean).
#
# Optional overrides:
#   reset_session(o)     — re-derive host-side state that lives
#                          OUTSIDE save()/restore() from the
#                          restored world state. Default: no-op.
#   observe(o)           — observable signature for bisimulation
#                          checks. Default: hash(o).
#
# THE SOUNDNESS TRAP (reset_session + hash completeness):
#   A model checker is only sound if its state vector is the
#   COMPLETE state — every component that influences the next
#   transition. If some transition-relevant state lives outside
#   save()/hash() (a host object the FSM doesn't persist, a
#   cached flag), the checker silently explores a corrupted
#   graph and reports wrong reachability. This is the classic
#   "incomplete state vector" failure. In this codebase it
#   showed up concretely: a modal prompt dispatcher lived on the
#   host (not in the FSM's save_state), so a death in one search
#   branch leaked into siblings and the reachability count came
#   back nearly half-right. reset_session() is the documented
#   remedy — re-derive that host state from the world after every
#   restore, exactly as the host would in a fresh session.
# ============================================================
extends RefCounted

func make_root():
    push_error("FrameModelAdapter.make_root() must be overridden")
    return null

func save(_o) -> PackedByteArray:
    push_error("FrameModelAdapter.save() must be overridden")
    return PackedByteArray()

func restore(_o, _bytes: PackedByteArray) -> void:
    push_error("FrameModelAdapter.restore() must be overridden")

func reset_session(_o) -> void:
    # Default: nothing lives outside save/restore. Override if the
    # host holds transition-relevant state the FSM doesn't persist.
    pass

func enumerate_actions(_o) -> Array:
    push_error("FrameModelAdapter.enumerate_actions() must be overridden")
    return []

func apply(_o, _action) -> void:
    push_error("FrameModelAdapter.apply() must be overridden")

func state_hash(_o) -> String:
    push_error("FrameModelAdapter.state_hash() must be overridden")
    return ""

func invariants(_o) -> Array:
    # Safety properties (Lamport 1977): refutable by a finite
    # prefix. Return a list of violation messages; empty == all
    # invariants hold at this state.
    return []

func observe(o) -> String:
    # Observable signature for bisimulation / observational-
    # equivalence checks (Milner 1980, Park 1981). Default to the
    # state vector; override to include host-side observables
    # (e.g. an open modal prompt) the hash omits.
    return state_hash(o)
