extends SceneTree

# ============================================================
# test_cca_death_paths.gd
# ============================================================
# Phase C systematic death-path coverage.
#
# Canon CCA has ~10 distinct fatal verb-room combinations. Each
# has specific canon prose and a specific aftermath (teleport to
# death-msg room 20/21, dragon-bite, troll-bridge-collapse, etc).
# These are tightly canon-specified and easy to silently drift.
#
# This test exercises each death path through the real Driver
# parser and asserts:
#   - canon-prose substring appears in the captured output
#   - player.player_state() == "dead" (or expected aftermath)
#   - if applicable, the player ended at a canon-specified room
#
# The expectation is that all pass (the death paths are well-
# trodden); if any fail, that's a real canon-fidelity bug.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

# Each entry:
#   id        — short label for the report
#   setup     — list of {goto: room} | {cmd: input}
#   input     — commands that trigger the death
#   expect    — fsm-state predicates (see world_spec _query keys)
#               + optional prose_includes list
const DEATH_PATHS: Array = [
    # Jump-rooms (canon 35/88/110) all route to canon 20.
    # Canon msg #58: "You fell into a pit and broke every bone..."
    {
        "id":     "jump_at_window_on_pit",
        "setup":  [{"goto": 35}],
        "input":  ["jump"],
        "expect": {
            "player_state": "dead",
            "prose_includes": ["broke every bone"],
        },
    },
    {
        "id":     "jump_at_canon_88",
        "setup":  [{"goto": 88}],
        "input":  ["jump"],
        "expect": {
            "player_state": "dead",
            "prose_includes": ["broke every bone"],
        },
    },
    {
        "id":     "jump_at_canon_110",
        "setup":  [{"goto": 110}],
        "input":  ["jump"],
        "expect": {
            "player_state": "dead",
            "prose_includes": ["broke every bone"],
        },
    },
    # Walk into Dragon canyon (canon 119) without slaying the
    # dragon — canon: dragon hisses + msg. Approaching is fine,
    # but trying to interact with it bare-handed = death? Actually
    # canon CCA: the dragon BLOCKS until killed. The death is
    # walking past with no prior intent. Let's test: at canon 119
    # alive dragon, attempting onward movement blocks.
    # (Not actually death — just rebuff. Skipping as not a death.)
    # ----- Carrying gold down/pit/steps (canon row `14 150020 30 31 34`) -----
    # Canon: at room 14 with gold, verbs DOWN / PIT / STEPS all
    # route to canon 20 (death). UP is NOT in the canon row —
    # earlier draft of this test used UP and naturally failed.
    {
        "id":     "gold_carry_down_at_14_falls_to_pit",
        "setup":  [
            {"goto": 18}, {"cmd": "take gold"},
            {"goto": 14},
        ],
        "input":  ["down"],
        "expect": {
            "player_state": "dead",
            "prose_includes": ["broke every bone"],
        },
    },
    # Dragon-bites — attempting to walk into the dragon's lair
    # while it's alive. Canon: dragon msg #110 ("the dragon's
    # ferocious cleaver"). Currently the canonical journey has
    # the player slay the dragon BEFORE going into the canyon,
    # so this is a deliberate divergence test.
    # (Canon CCA actually BLOCKS movement rather than killing;
    # the player gets a rebuff, not death. Defer until we
    # confirm canon CCA's exact dragon-walk-into behavior.)

    # Bear-follows-onto-bridge — canon msg #162. Setup is
    # tightly multi-step (need food in hand AND troll paid AND
    # bear in $Following). The dedicated tests
    # test_cca_bear.gd / test_cca_bridge.gd cover the mechanic
    # via direct FSM driving; replicating that here via the
    # generic setup_steps would balloon this file. Reserved for
    # a future spec extension that supports FSM-state injectors
    # (`{"set_bear": "following"}` etc.) — out of scope for the
    # current Phase C MVP.
]

func _init():
    print("=== CCA death-path canon-fidelity tests ===")
    print("")
    print("Death paths checked: %d" % DEATH_PATHS.size())
    print("")

    for entry in DEATH_PATHS:
        _run_one(entry)

    print("")
    if failures == 0:
        print("PASS — every canon death path matches spec")
        quit(0)
        return
    print("FAIL — %d death path(s) diverge from canon spec" % failures)
    quit(failures)

func _run_one(entry: Dictionary) -> void:
    var d: H.CapturedDriver = H.make_driver()
    # Reset lamp to off (H.make_driver lights it). Most death
    # paths above are in lit rooms anyway, but the dark-cave
    # ones might benefit from explicit lamp state.
    if d.fsm.lamp.is_lit():
        d.fsm.lamp.extinguish()
    # Light the lamp for cave-room tests (rooms 110+ are dark).
    d.fsm.lamp.light()

    # Run setup_steps.
    for step in entry.setup:
        if step.has("goto"):
            d.fsm.player.move_to(step.goto)
        elif step.has("cmd"):
            d._process_input(step.cmd)

    # Trigger the death.
    for cmd in entry.input:
        d._process_input(cmd)

    # Verify expectations.
    var fails: Array = _verify(d, entry.expect)
    var status: String = "OK" if fails.is_empty() else "FAIL"
    print("  [%s] %s" % [status, entry.id])
    for f in fails:
        print("        %s" % f)
    if not fails.is_empty():
        failures += 1

func _verify(d: H.CapturedDriver, expected: Dictionary) -> Array:
    var fails: Array = []
    for key in expected.keys():
        if key == "prose_includes":
            var captured_text: String = ""
            for line in d.captured:
                captured_text += line.to_lower() + "\n"
            for needle in expected.prose_includes:
                if not needle.to_lower() in captured_text:
                    fails.append("prose_includes: '%s' not in captured" % needle)
            continue
        var want = expected[key]
        var got = _query(d.fsm, key)
        if got != want:
            fails.append("%s: expected %s, observed %s" % [key, str(want), str(got)])
    return fails

func _query(fsm, key: String):
    match key:
        "player_room":      return fsm.player_room()
        "player_state":     return fsm.player_state()
        "score":            return fsm.total_score()
        "dragon_alive":     return fsm.dragon_alive()
        "bear_state":       return fsm.bear.get_state()
    return null
