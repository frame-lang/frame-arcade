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
# Limitation: two milestones in canonical_journey are reached via
# FSM-direct manipulation rather than player commands —
# TreasuresFilled (13 endgame.treasure_deposited() calls) and
# InRepository (35 fsm.tick() calls). The adapter executes
# commands_from_previous() verbatim; tests that need to land on
# those milestones still use the FSM-shortcut pattern documented
# in test_cca_state_space_seeded_endgame.gd. A future revision
# could attach optional fsm_shortcut callables to those steps.
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
