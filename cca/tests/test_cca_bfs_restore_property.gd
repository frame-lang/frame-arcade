extends SceneTree

# ============================================================
# test_cca_bfs_restore_property.gd
# ============================================================
# Property-based check on the BFS harness's restore path. The
# property:
#
#   A REUSED driver, restored to state X via the BFS harness
#   path (fsm.restore_state + _reset_driver_session_state),
#   produces the IDENTICAL observable signature as a FRESH
#   driver restored to X — regardless of what the reused
#   driver did before.
#
# This is the invariant the prompts-state-leak (aadf097)
# violated. The BFS reuses ONE driver across thousands of
# branches; `driver.prompts` (the PromptDispatcher) lived
# outside fsm.save_state, so a death in any branch left
# $AwaitingRevive active and every sibling branch inherited
# it — the modal Y/N dispatcher then ate every non-yes/no
# verb. The harness fix was `_reset_driver_session_state`
# after every restore. This test pins that fix: remove the
# reset and this property fails loudly.
#
# Observable signature = (player_room, sorted non-wild action
# keys, prompts.is_active, prompts.current_prompt,
# player.get_state). Anything that changes how BFS expands
# from a state.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const JourneyTreeC = preload("res://scripts/journey_tree.gd")

# Milestones to use as test states. Spread across game depth so
# the property is exercised at varied inventory / NPC states.
const TEST_MILESTONES: Array = ["LampLit", "SnakeGone", "BearReleased"]

var failures: int = 0

func _init():
    print("=== BFS restore-path property test ===")
    print("")

    var registry = MilestoneRegistry.new()
    if not _capture(registry):
        print("FAIL — couldn't capture milestone snapshots")
        quit(1)
        return

    # The harness instance whose restore path we're pinning.
    var ss = StateSpace.new()
    ss.seed = 42

    # For every ordered pair of distinct milestones (A, B):
    #   sig_fresh(A)  — fresh driver restored to A
    #   sig_reused(A) — driver restored to B, dirtied (run a
    #                   death-inducing command so the RAW path
    #                   would leak a revive prompt), restored to A
    # Property: sig_fresh(A) == sig_reused(A).
    for a in TEST_MILESTONES:
        if not registry.has("canonical_journey", a):
            continue
        var bytes_a: PackedByteArray = registry.get_snapshot("canonical_journey", a)
        var sig_fresh: String = _fresh_signature(ss, bytes_a)
        for b in TEST_MILESTONES:
            if b == a or not registry.has("canonical_journey", b):
                continue
            var bytes_b: PackedByteArray = registry.get_snapshot("canonical_journey", b)
            var sig_reused: String = _reused_signature(ss, bytes_b, bytes_a)
            var label: String = "restore(%s) after dirtying via %s" % [a, b]
            if sig_fresh == sig_reused:
                print("  OK   %s" % label)
            else:
                print("  FAIL %s" % label)
                print("        fresh:  %s" % sig_fresh)
                print("        reused: %s" % sig_reused)
                failures += 1

    print("")
    if failures == 0:
        print("PASS — BFS restore path is leak-free across reuse")
        quit(0)
        return
    print("FAIL — %d restore-path divergence(s) (suspect driver-side state leak)" % failures)
    quit(failures)

# Signature from a brand-new driver restored to `bytes`.
func _fresh_signature(ss, bytes: PackedByteArray) -> String:
    var d = ss.prepare_driver()
    d.fsm.restore_state(bytes)
    ss._reset_driver_session_state(d)
    return _signature(d)

# Signature from a reused driver: restore to `dirty_bytes`,
# run a command that would leak a revive prompt under the raw
# restore path, then restore to `target_bytes` via the harness
# path. If the harness path is leak-free, this matches the
# fresh signature for target_bytes.
func _reused_signature(ss, dirty_bytes: PackedByteArray, target_bytes: PackedByteArray) -> String:
    var d = ss.prepare_driver()
    # Dirty the driver: restore to some state, then kill the
    # player so the PromptDispatcher enters $AwaitingRevive.
    d.fsm.restore_state(dirty_bytes)
    ss._reset_driver_session_state(d)
    d.fsm.player.die()
    d.prompts.offer_revive()        # simulate the revive prompt opening
    # Now restore to the target state via the harness path.
    d.fsm.restore_state(target_bytes)
    ss._reset_driver_session_state(d)
    return _signature(d)

# Observable signature: everything that affects how BFS would
# expand from this driver state.
func _signature(d) -> String:
    var keys: Array = []
    for action in d.list_actions_here():
        if action.get("kind", "") == "wild":
            continue
        keys.append(String(action.get("key", "")))
    keys.sort()
    return "r=%d|p=%s|prompt=%s/%s|actions=%s" % [
        d.fsm.player_room(),
        d.fsm.player.get_state(),
        d.prompts.is_active(),
        d.prompts.current_prompt(),
        ",".join(keys),
    ]

# Walk canonical_journey to the deepest test milestone,
# capturing all of them.
func _capture(registry) -> bool:
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
    d._print_welcome()
    d._print_room()
    var tree = JourneyTreeC.new()
    tree.register_default()
    # BearReleased is the deepest test milestone; walking to it
    # captures LampLit and SnakeGone along the way.
    return tree.walk_to(d, registry, "canonical_journey:BearReleased")
