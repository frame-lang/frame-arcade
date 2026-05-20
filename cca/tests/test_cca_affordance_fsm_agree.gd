extends SceneTree

# ============================================================
# test_cca_affordance_fsm_agree.gd
# ============================================================
# Catches affordance/FSM divergence — places where the driver's
# affordance enumerator (`list_actions_here`) encodes the same
# fact as an FSM predicate, and the two have drifted apart.
#
# The class of bug this catches is real: from commit 5cac0e2.
# `list_actions_here` had `if room in [3, 23, 79]` for the
# fill-bottle affordance, claiming canon 23 was a water source.
# Adventure's `_at_water_source()` was
# `[1, 3, 4, 7, 38, 83, 84, 95, 113]`. Room 23 was advertised
# without backing; the eight real sources weren't advertised
# at all. BFS wasted turns trying `fill bottle` at 23 (no
# state change) and never tried fill at the eight real
# sources. Found by hand while debugging PlantUnlock.
#
# Approach: iterate every canon room, set up the inventory
# preconditions the affordance needs (empty carried bottle for
# fill-bottle), call list_actions_here, and check whether the
# canon-gated affordance appears (filtering OUT the kind="wild"
# entries — those cross every verb against every noun and
# trigger at every room, separately from the canon-precondition
# affordances). Compare against the FSM-side predicate.
#
# Each failure prints BOTH directions:
#   • advertised but FSM disagrees (affordance lies → false positive)
#   • FSM says yes but affordance silent (affordance gap → false negative)
#
# Either direction is a bug. The fix is unambiguous from the
# output.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

var failures: int = 0

func _init():
    print("=== Affordance / FSM agreement audit ===")
    print("")
    _check_fill_bottle_sources()
    print("")
    if failures == 0:
        print("PASS — affordance and FSM agree on every checked pair")
        quit(0)
        return
    print("FAIL — %d divergence(s) between affordance and FSM" % failures)
    quit(failures)

# ----- fill-bottle affordance agreement -----
# Affordance side: `list_actions_here` emits a canon-gated
# action with key="fill:bottle" (kind="verb", NOT kind="wild")
# whenever the player carries an empty bottle and the current
# room has SOMETHING to fill it with. FSM-side ground truth:
# (_at_water_source ∪ _at_oil_source) — the FSM's _verb_fill
# checks oil first, water second, both fail = "nothing here
# with which to fill the bottle." The affordance set must
# match the union.
func _check_fill_bottle_sources() -> void:
    print("--- fill-bottle sources ---")
    var advertised: Array = []
    var fsm_says: Array = []
    for r in range(1, 141):
        var d = _empty_bottle_driver_at(r)
        if _has_canon_affordance(d, "fill:bottle"):
            advertised.append(r)
        if d.fsm._at_water_source() or d.fsm._at_oil_source():
            fsm_says.append(r)
    _report_set_diff("fill-bottle sources", advertised, fsm_says)

# ============================================================
# Helpers
# ============================================================

# Driver with player at `room`, carrying an empty bottle (the
# precondition for list_actions_here to emit fill-bottle).
# Forces the bottle's FSM state directly rather than walking
# the take/drop chain, so we don't need a take-from-canon-3
# preamble at every room.
func _empty_bottle_driver_at(room: int):
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
    # Take the bottle into the player's inventory + transition
    # the bottle Item FSM to $Carried. Bypass the at-room check
    # (try_take requires player at item location) by calling
    # place(0) then try_take(0) — the BottleItem doesn't care
    # about the literal location once carried.
    d.fsm.player.take(d.fsm.BOTTLE_ID)
    d.fsm.bottle_item.place(0)
    d.fsm.bottle_item.try_take(0)
    d.fsm.player.move_to(room)
    return d

# Returns true iff `list_actions_here()` emits an action with
# the given `key` AND the action is NOT the "wild" variant.
# Wild verbs cross every verb against every noun and emit at
# every room — they're a separate parser-coverage mechanism,
# not a canon-gated affordance.
func _has_canon_affordance(d, key: String) -> bool:
    for action in d.list_actions_here():
        if action.get("kind", "") == "wild":
            continue
        if String(action.get("key", "")) == key:
            return true
    return false

func _report_set_diff(label: String, advertised: Array, fsm_says: Array) -> void:
    var lhs_set: Dictionary = {}
    for r in advertised: lhs_set[r] = true
    var rhs_set: Dictionary = {}
    for r in fsm_says: rhs_set[r] = true
    var only_advertised: Array = []
    var only_fsm: Array = []
    for r in advertised:
        if not rhs_set.has(r):
            only_advertised.append(r)
    for r in fsm_says:
        if not lhs_set.has(r):
            only_fsm.append(r)
    if only_advertised.is_empty() and only_fsm.is_empty():
        print("  OK   %s: affordance == FSM (%d rooms: %s)" % [
            label, advertised.size(), str(advertised)])
        return
    if not only_advertised.is_empty():
        print("  FAIL %s — advertised but FSM disagrees: %s" % [label, str(only_advertised)])
        failures += 1
    if not only_fsm.is_empty():
        print("  FAIL %s — FSM says yes but affordance silent: %s" % [label, str(only_fsm)])
        failures += 1
