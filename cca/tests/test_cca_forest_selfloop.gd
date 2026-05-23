extends SceneTree

# ============================================================
# test_cca_forest_selfloop.gd
# ============================================================
# Regression test for the doubled room-description bug on
# self-loop moves.
#
# Canon forest rooms 5 and 6 have directions that lead back to
# the SAME room (room 5: WEST/SOUTH → 5; room 6: SOUTH → 5,
# i.e. a move that lands at `current`). The driver suppresses
# the FSM's mixed-case "move" response on successful moves and
# lets _print_room produce the canonical display — but the
# suppression guard keyed only on `player_room() == current`,
# which is ALSO true for a self-loop. The result: the response
# printed on top of _print_room, so every forest self-loop move
# showed the room description twice (one mixed-case line, one
# bold all-caps line).
#
# The fix adds `dest != current` to the guard. This test pins
# it: a self-loop move must emit the room description exactly
# once. A genuine rebuff (tried to leave, bounced back —
# dest != current) must still surface its prose, which the
# death/transient-prose suites already cover.
# ============================================================

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _init():
    print("=== CCA forest self-loop (no doubled description) ===")
    print("")
    _scenario_room5_west()
    _scenario_room5_south()
    _scenario_room6_south()
    print("")
    if failures == 0:
        print("PASS — forest self-loop moves describe the room exactly once")
        quit(0)
        return
    print("FAIL — %d self-loop move(s) doubled the room description" % failures)
    quit(failures)

func _scenario_room5_west() -> void:
    _assert_single_description("room 5 WEST → 5", 5, "west", "OPEN FOREST")

func _scenario_room5_south() -> void:
    _assert_single_description("room 5 SOUTH → 5", 5, "south", "OPEN FOREST")

func _scenario_room6_south() -> void:
    _assert_single_description("room 6 SOUTH → 5", 6, "south", "OPEN FOREST")

# Move the player into `room`, issue a self-loop `direction`, and
# assert the canonical room text (`needle`) appears in exactly one
# captured line.
func _assert_single_description(label: String, room: int, direction: String, needle: String) -> void:
    print("--- %s ---" % label)
    var d = H.make_driver()
    d.fsm.player.move_to(room)
    var lines: Array = H.capture(d, direction)
    var hits: int = 0
    for line in lines:
        if needle.to_lower() in String(line).to_lower():
            hits += 1
    if hits == 1:
        print("    ok — '%s' printed once" % needle)
    else:
        print("    FAIL — '%s' printed %d times (expected 1)" % [needle, hits])
        for line in lines:
            print("        | %s" % line)
        failures += 1
