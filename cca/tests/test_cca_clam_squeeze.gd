extends SceneTree

# Verifies the canon clam carry-state branch at the Shell Room
# (canon 103). Going SOUTH from canon 103 with the five-foot
# clam — or its post-BREAK form, the oyster — in inventory
# canonically fails with a specific bumper message because the
# shellfish doesn't fit through the narrow passage to canon 64.
#
# Canon section 2 rows:
#   103 114618 46    only_if_toting(CLAM)   → msg #118
#   103 115619 46    only_if_toting(OYSTER) → msg #119
#   103 64 46        unconditional fall-through → 64
#
# Without this branch the player could pocket the clam and
# carry it through a passage canon explicitly forbids — a
# direct canon-fidelity break, since the squeeze is the puzzle
# that motivates BREAKing the clam in place to get the pearl.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_contains(label: String, haystack: String, needle: String) -> void:
    if needle in haystack:
        print("  ok   %-44s contains '%s'" % [label, needle])
    else:
        print("  FAIL %-44s missing '%s' in: %s" % [
            label, needle, haystack])
        failures += 1

func _init():
    print("=== CCA clam carry-state at Shell Room (canon 103) ===")

    # Phase 1: empty-handed — canon fall-through, walk to canon 64.
    print("Phase 1: empty inventory — south works")
    var adv := Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(103)
    _expect("at shell room",      adv.player_room(), 103)
    _expect("clam not carried",   adv.player.carrying(adv.CLAM_ID),  false)
    _expect("oyster not carried", adv.player.carrying(adv.OYSTER_ID), false)
    var resp1: String = adv.do_command("move", "64")
    _expect("moved to canon 64",  adv.player_room(), 64)
    _expect("response is movement, not bumper",
        "five-foot" in resp1, false)

    # Phase 2: carrying the clam — canon msg #118 fires, no movement.
    print("Phase 2: carrying clam — south rejected")
    adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(103)
    adv.do_command("take", "clam")
    _expect("clam carried",       adv.player.carrying(adv.CLAM_ID),  true)
    _expect("at shell room",      adv.player_room(), 103)
    var resp2: String = adv.do_command("move", "64")
    _expect("still at shell room (move blocked)",
        adv.player_room(), 103)
    _expect_contains("response cites the clam",
        resp2, "five-foot clam")

    # Phase 3: carrying the oyster — same gate, different
    # message (msg #119). The port treats the oyster as
    # uncarryable via TAKE OYSTER ("you can't be serious — that
    # oyster weighs a ton" — a canonical port choice that
    # diverges from the original where you can carry it). We
    # force the inventory state directly via the player FSM so
    # the squeeze-gate's oyster branch is reachable for the
    # test. The gate code is symmetric — if a future canon-
    # fidelity pass restores carryable oysters, this branch
    # will fire from real player actions too.
    print("Phase 3: carrying oyster — south rejected with oyster prose")
    adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(103)
    adv.player.take(adv.OYSTER_ID)
    _expect("oyster carried",     adv.player.carrying(adv.OYSTER_ID), true)
    var resp3: String = adv.do_command("move", "64")
    _expect("still at shell room (move blocked)",
        adv.player_room(), 103)
    _expect_contains("response cites the oyster",
        resp3, "five-foot oyster")

    # Phase 4: drop the shellfish — south works again.
    print("Phase 4: drop oyster — south unblocks")
    adv.player.drop(adv.OYSTER_ID)
    _expect("oyster not carried", adv.player.carrying(adv.OYSTER_ID), false)
    var resp4: String = adv.do_command("move", "64")
    _expect("moved to canon 64",  adv.player_room(), 64)

    if failures == 0:
        print("PASS — clam/oyster squeeze at canon 103 honors canon section 2")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
