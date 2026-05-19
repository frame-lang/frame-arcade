# ============================================================
# extension_journey.gd — Journey subclass for non-canonical paths
# ============================================================
# Pure-data journey: a parent reference + a list of
# (milestone_name, commands_to_reach_here) steps. Phase 2 builds
# these automatically (one per gate-unlock); Phase 3 adds them by
# hand for prerequisite-chain extensions. The Frame-generated
# canonical_journey.gd stays the authoritative spec for the
# original Crowther/Woods playthrough; everything that branches
# off from it is an ExtensionJourney.
#
# Construction:
#   var j = ExtensionJourney.new(
#       "PlantUnlock",         # this journey's name
#       "canonical_journey",   # parent journey
#       "BearReleased",        # parent milestone (start here)
#       [
#           {"name": "AtPlantRoom", "commands": ["xyzzy", "north", ...]},
#           {"name": "PlantHugeGrown", "commands": ["pour water"]},
#       ])
# ============================================================
extends "res://scripts/journey.gd"

# Each step is a Dictionary: { name: String, commands: Array }.
# commands are executed in order via driver._process_input();
# after the commands run, the journey is at `name` and a snapshot
# is recorded under this journey's registry key.
var steps: Array = []

func _init(p_name: String, p_parent_journey: String,
           p_parent_milestone: String, p_steps: Array):
    name = p_name
    parent_journey = p_parent_journey
    parent_milestone = p_parent_milestone
    steps = p_steps

func milestone_names() -> Array:
    var names: Array = []
    for s in steps:
        names.append(String(s["name"]))
    return names

func apply(driver, registry, stop_at: String = "") -> String:
    for step in steps:
        for cmd in step["commands"]:
            driver._process_input(String(cmd).to_lower())
        var state_name: String = String(step["name"])
        registry.record(name, state_name, driver.fsm.save_state())
        if stop_at != "" and state_name == stop_at:
            return state_name
    if stop_at != "":
        return ""   # stop_at never matched a step's name
    return String(steps[-1]["name"]) if not steps.is_empty() else ""
