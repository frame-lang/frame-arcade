extends SceneTree

# Verifies the canonical dark-room pit-fall hazard implemented in
# the driver. Headless: subclass the Driver so `_println` captures
# into an in-memory buffer (RichTextLabel.append_text doesn't
# accumulate readable text without a SceneTree), drive the hazard
# helper directly, and assert against the captured lines.
#
# Canon mechanic (Crowther/Woods, ODWY0350/advent.c):
#   1. Player is in a dark cave room with the lamp not lit.
#   2. First motion attempt → "It is now pitch dark. ..." warning.
#   3. Subsequent motion attempts → 35% chance to fall into a
#      pit and die.
#
# We pin Godot's global RNG seed so the 35% rolls inside the
# helper are deterministic across runs. We don't care which exact
# iteration triggers the kill — only that the kill *eventually*
# fires and the canon message is emitted at least once.

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-44s found '%s'" % [label, needle])
            return
    print("  FAIL %-44s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> H.CapturedDriver:
    # Skip _ready entirely — we only need `fsm`, `_dark_warned_room`,
    # and the `_check_dark_pit_hazard` method. Don't add to the
    # SceneTree so no UI bootstrap fires.
    var d := H.CapturedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    return d

func _init():
    print("=== CCA dark-room pit-fall hazard ===")

    # Pin Godot's global RNG so the 35% pit-fall roll is
    # deterministic across runs.
    seed(0xC0FFEE)

    var d := _make_driver()

    # 1. Lit room (canon 1, end of road) — hazard never fires.
    print("Phase 1: lit room — no hazard")
    _expect("at end of road",      d.fsm.player_room(),     1)
    _expect("dark now?",           d.fsm.room_is_dark_now(), false)
    var fired1 := d._check_dark_pit_hazard()
    _expect("hazard fired in lit room",  fired1, false)
    _expect("warned-room marker",        d._dark_warned_room, -1)
    _expect("buffer empty",              d.captured.size(),   0)

    # 2. Move into a dark cave room (debris, room 11) without
    #    lighting the lamp.
    print("Phase 2: dark room, lamp off — first attempt warns")
    d.fsm.player.move_to(11)
    _expect("at debris",           d.fsm.player_room(),     11)
    _expect("dark now?",           d.fsm.room_is_dark_now(), true)
    _expect("lamp lit?",           d.fsm.is_lit(),           false)

    var fired2 := d._check_dark_pit_hazard()
    _expect("first attempt fires (warning)", fired2, true)
    _expect("warned room marker set",        d._dark_warned_room, 11)
    _expect_any_match("warning message captured",
        d.captured, "pitch dark")
    _expect("player still alive",  d.fsm.player_state(), "alive")

    # 3. Subsequent attempts: roll the 35% — keep rolling until
    #    the player has died. With the seeded RNG this completes
    #    in a small number of attempts.
    print("Phase 3: subsequent attempts — pit-fall roll")
    var attempts := 0
    while d.fsm.player_state() != "dead" and attempts < 100:
        d._check_dark_pit_hazard()
        attempts += 1
    _expect("player died within 100 attempts",
        d.fsm.player_state(), "dead")
    _expect_any_match("death message captured",
        d.captured, "broke every bone")
    print("  (attempts to first death: %d)" % attempts)

    # 4. Lighting the lamp clears the marker so the next entry
    #    into a dark room re-fires the warning fresh.
    print("Phase 4: revive + light lamp — hazard cleared")
    d.fsm.player.revive()
    _expect("alive after revive",  d.fsm.player_state(), "alive")
    d.fsm.player.move_to(11)
    d.fsm.do_command("light", "")
    _expect("lamp lit?",           d.fsm.is_lit(),       true)
    var fired3 := d._check_dark_pit_hazard()
    _expect("hazard skipped while lit",   fired3, false)
    _expect("warned-room marker cleared", d._dark_warned_room, -1)

    # 5. Extinguish, move to a *different* dark room — warning
    #    must fire again because the marker is per-room.
    print("Phase 5: per-room marker — fresh warning in new dark room")
    d.fsm.extinguish_lamp()
    d.fsm.player.move_to(13)        # bird chamber, dark
    var pre_count: int = d.captured.size()
    var fired4 := d._check_dark_pit_hazard()
    _expect("first attempt at new dark room warns", fired4, true)
    _expect("warned-room marker = 13", d._dark_warned_room, 13)
    var fresh_lines: Array = d.captured.slice(pre_count)
    _expect_any_match("new warning emitted", fresh_lines, "pitch dark")

    if failures == 0:
        print("PASS — canonical dark-room pit-fall hazard")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
