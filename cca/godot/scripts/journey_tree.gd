# ============================================================
# journey_tree.gd — registry + walker for the journey tree
# ============================================================
# Holds every Journey known to the harness and knows how to walk
# from canonical-start to any "journey:milestone" address by
# recursively walking each parent chain. Tests/probes call
# walk_to() once and get a MilestoneRegistry populated with every
# milestone snapshot along the path.
#
# Why a registry rather than per-test ad-hoc walks: as Phase 2 and
# 3 add extension journeys (one per gate-unlock + one per
# prerequisite-chain frontier), tests that previously hand-rolled
# the canonical walk now just say `tree.walk_to(driver, registry,
# "PlantUnlock:PlantHugeGrown")` and the tree handles the
# canonical_journey → BearReleased → PlantUnlock chain.
# Centralising this also makes the tree the natural place to
# audit "every milestone in the tree" and to bolt on Phase 4b
# disk persistence later.
#
# Public API:
#   register(journey)
#       Adds a Journey to the tree. Idempotent: re-registering
#       under the same name overwrites.
#   walk_to(driver, registry, "journey:milestone") -> bool
#       Walks from canonical-start to the named milestone,
#       recording every milestone snapshot along the way.
#       Returns true on success, false if the milestone wasn't
#       reachable.
#   all_paths() -> Array
#       Flat list of every "journey:milestone" identifier known
#       to the tree. Diagnostic aid.
#
# Convenience:
#   register_default()
#       Registers canonical_journey on the tree. Tests/probes
#       typically construct an empty tree and call this before
#       layering on extension journeys.
# ============================================================
extends RefCounted

const CanonicalJourneyAdapter = preload("res://scripts/canonical_journey_adapter.gd")

# Map of journey name -> Journey instance.
var _journeys: Dictionary = {}

func register(journey) -> void:
    _journeys[journey.name] = journey

func get_journey(jname: String):
    return _journeys.get(jname)

func has_journey(jname: String) -> bool:
    return _journeys.has(jname)

# Walk from canonical-start to the named "journey:milestone"
# target, capturing every milestone snapshot into `registry`.
# Recursively resolves parent journeys first (so reaching
# "PlantUnlock:PlantHugeGrown" first walks canonical_journey to
# BearReleased, then PlantUnlock from there). The caller must
# have just constructed `driver` (fresh canonical-start FSM
# state, welcome printed, first room printed); no prior journey
# walk should have been performed on it. Returns true if the
# target milestone was reached.
func walk_to(driver, registry, full_path: String) -> bool:
    var parts = full_path.split(":")
    if parts.size() != 2:
        push_error("walk_to: expected 'journey:milestone' format, got '%s'" % full_path)
        return false
    var journey_name: String = parts[0]
    var milestone: String = parts[1]
    return _walk_internal(driver, registry, journey_name, milestone)

func _walk_internal(driver, registry, journey_name: String, milestone: String) -> bool:
    if not has_journey(journey_name):
        push_error("walk_to: no journey named '%s'" % journey_name)
        return false
    var journey = _journeys[journey_name]
    # Resolve parent chain. Roots (canonical_journey) have
    # parent_journey == "" and are walked directly from
    # canonical-start state.
    if journey.parent_journey != "":
        if not _walk_internal(driver, registry,
                              journey.parent_journey,
                              journey.parent_milestone):
            return false
        # _walk_internal may have walked past parent_milestone
        # (Journey.apply walks the *whole* journey when stop_at
        # is not the final milestone). Restore explicitly to the
        # parent milestone before applying this journey's steps.
        var bytes = registry.get_snapshot(journey.parent_journey,
                                          journey.parent_milestone)
        if bytes.is_empty():
            push_error("walk_to: parent milestone '%s:%s' had no snapshot after walk" % [
                journey.parent_journey, journey.parent_milestone])
            return false
        driver.fsm.restore_state(bytes)
    var reached: String = journey.apply(driver, registry, milestone)
    return reached == milestone

# Flat list of "journey:milestone" identifiers for every journey
# in the tree. Order: journeys in registration order, milestones
# in walk order within each journey.
func all_paths() -> Array:
    var out: Array = []
    for jname in _journeys.keys():
        for m in _journeys[jname].milestone_names():
            out.append("%s:%s" % [jname, m])
    return out

# Registers canonical_journey on this tree. Convenience for
# tests/probes that want extension journeys on top of the canon
# spine. Returns self so callers can chain register().
func register_default():
    register(CanonicalJourneyAdapter.new())
    return self
