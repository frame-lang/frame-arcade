extends SceneTree

# Verifies the canon death-message room handling — anything that
# routes the player to canon 20 ("at the bottom of the pit with
# a broken neck") or canon 21 ("you didn't make it") fires
# player.die() with the matching canon message.
#
# Three port exits route to canon 20 — these are canon-aligned
# from the original advent.dat section 2 plain rows:
#   35:jump  → 20  (canon `35 20 39`)
#   88:jump  → 20  (canon `88 20 39`)
#   110:jump → 20  (canon `110 20 39` — leg of the upper canyon)
#
# Without the death-room hook the player would land at an empty
# `{}` room with no exits and be silently stuck. Each test below
# drives the canon route via real `do_command("move", "20")` so
# the FSM's `_verb_move` post-move check is the thing under test.
#
# Canon 21 isn't currently a destination of any port exit, but
# it's covered defensively — if a future change ever routes
# there, the same handler fires the right death message.

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

func _route_jump_to_20(label: String, from_room: int) -> void:
    print("Route: %d → JUMP → canon 20" % from_room)
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(from_room)
    _expect("at start room",      adv.player_room(),    from_room)
    _expect("alive at start",     adv.player_state(),   "alive")
    var resp: String = adv.do_command("move", "20")
    _expect("player died",        adv.player_state(),   "dead")
    _expect_contains("response is broken-bones msg", resp,
        "broke every bone")

func _route_to_21() -> void:
    print("Defensive: any → canon 21")
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(11)
    _expect("alive before route", adv.player_state(),   "alive")
    var resp: String = adv.do_command("move", "21")
    _expect("player died",        adv.player_state(),   "dead")
    _expect_contains("response is didn't-make-it msg", resp,
        "didn't make it")

func _init():
    print("=== CCA death-message room handling ===")

    # All three port routes that canonically land on room 20.
    _route_jump_to_20("35:jump", 35)
    _route_jump_to_20("88:jump", 88)
    _route_jump_to_20("110:jump", 110)

    # Defensive — no port exit currently goes to 21, but the
    # handler is symmetric.
    _route_to_21()

    if failures == 0:
        print("PASS — death-message rooms fire player.die() with canon prose")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
