# ============================================================
# canonical_journey_adapter.gd — Journey wrapper around the
# Frame-generated canonical_journey.gd FSM
# ============================================================
# canonical_journey.gd is the authoritative spec for the
# Crowther/Woods playthrough: 33 milestones from AtRoad through
# BLAST/won, each annotated with the commands needed to reach it
# from the previous milestone. The FSM is generated from
# canonical_journey.fgd and kept in sync with the canon-fidelity
# tests (test_cca_canonical_journey.gd walks the whole thing).
#
# This adapter exposes that linear FSM through the Journey API so
# JourneyTree can treat it like any other journey. The adapter
# always starts from the canonical-start state (AtRoad) — there's
# no "resume from milestone N" path; the FSM is linear.
#
# Two milestones in canonical_journey are reached via FSM-direct
# manipulation rather than player commands:
#   • TreasuresFilled — endgame.treasure_deposited() ×13. The
#     full deposit chain is 15 treasures; the journey covers the
#     first 2 deposits (gold + something else) via real commands,
#     then shortcuts the remaining 13 here. Canonically reachable
#     via real play, just bypassed for runtime.
#   • InRepository — fsm.tick() ×35. Drives the post-15-deposit
#     endgame timer to zero so the cave-closes teleport fires
#     and the player lands at canon 116 (Repository). Canonically
#     reachable via 35 LOOK turns; shortcut keeps the journey
#     bounded.
# canonical_journey.gd's commands_from_previous() returns [] for
# these milestones — the adapter dispatches the shortcut by name
# before calling _process_input.
# ============================================================
extends "res://scripts/journey.gd"

const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

func _init():
    name = "canonical_journey"
    # Root journey: no parent.
    parent_journey = ""
    parent_milestone = ""

func milestone_names() -> Array:
    var fsm = CanonicalJourney._create()
    var names: Array = []
    while not fsm.is_done():
        names.append(fsm.state_name())
        fsm.advance()
    return names

func apply(driver, registry, stop_at: String = "") -> String:
    var fsm = CanonicalJourney._create()
    var last_reached: String = ""
    while not fsm.is_done():
        var state_name: String = fsm.state_name()
        # FSM-shortcut milestones (see header comment). canonical_journey.gd
        # returns [] for commands_from_previous on these states; the
        # actual transition happens via FSM-direct manipulation.
        if state_name == "TreasuresFilled":
            for i in 13:
                driver.fsm.endgame.treasure_deposited()
        elif state_name == "InRepository":
            for i in 35:
                driver.fsm.tick()
        for cmd in fsm.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        registry.record(name, state_name, driver.fsm.save_state())
        last_reached = state_name
        if stop_at != "" and state_name == stop_at:
            return state_name
        fsm.advance()
    if stop_at != "":
        return ""   # stop_at never matched
    return last_reached
