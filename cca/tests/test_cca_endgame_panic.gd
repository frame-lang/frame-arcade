extends SceneTree

# Verifies canon PANIC mechanic (advent.for STMT 2):
#
#   During $Closing, attempting to move toward a surface room
#   (canon dest 1..8) emits canon msg #130 ("A mysterious recorded
#   voice... 'This exit is closed.'"), the move is blocked, and
#   CLOCK2 (closing_timer) is capped at 15 — but only the FIRST
#   attempt re-caps. Subsequent attempts re-emit msg #130 but
#   don't shorten the timer further (PANIC latch).
#
# Outside $Closing the panic intercept is a no-op.

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

class CapturedDriver:
    extends Driver
    var captured: Array = []
    func _println(text: String) -> void:
        self.captured.append(text)

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

# Force the Endgame into $Closing by depositing canon TREASURES_TO_TRIGGER
# treasures via the public interface. There's no direct test hook,
# so we drive the public API.
func _force_closing(d: CapturedDriver) -> void:
    for _i in 15:
        d.fsm.endgame.treasure_deposited()

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA endgame PANIC + CLOCK2 cap (canon STMT 2 + msg #130) ===")

    # ----- Phase 1: pre-closing — panic intercept is a no-op -----
    print("Phase 1: pre-closing — moving to a surface room is normal")
    var d1 := _make_driver()
    d1.fsm.player.move_to(2)         # canon hill
    var l1: Array = _capture(d1, "south")
    _expect("$Active panic flag false",   d1.fsm.endgame_panicked(), false)
    var saw_msg130: bool = false
    for line in l1:
        if "exit is closed" in line:
            saw_msg130 = true
            break
    _expect("no msg #130 fires pre-closing", saw_msg130, false)

    # ----- Phase 2: $Closing — first surface move triggers PANIC -----
    print("Phase 2: $Closing — first surface move → msg #130 + CLOCK2 cap")
    var d2 := _make_driver()
    _force_closing(d2)
    _expect("setup: endgame is closing",  d2.fsm.endgame_closing(), true)
    _expect("setup: not yet panicked",    d2.fsm.endgame_panicked(), false)
    var timer_before: float = d2.fsm.endgame_timer()
    _expect("setup: timer at CLOSING_DURATION",
        timer_before > 15.0, true)

    # Place player at canon 9 (transit cave, deep cave) so the
    # destination of a SOUTH attempt could land in a surface room.
    # Easier: place at canon 2 (hill) and walk back to 1 — but
    # canon 2 is itself a surface room. We need a deep-cave room
    # with an exit toward a surface room. Use canon 11 (East end
    # of Hall of Mists) which has east → 10 (also deep), but
    # outdoors entry is via room 9 etc. The cleanest test is to
    # force-place at canon 4 (valley, surface) and try to walk to
    # canon 1 (road — also surface) — but canon 1 ≤ 8 so that's
    # still a panic-trigger destination.
    d2.fsm.player.move_to(4)         # canon valley
    var l2: Array = _capture(d2, "north")  # 4 → 1 (road)
    _expect_any_match("first $Closing surface attempt emits canon msg #130",
        l2, "exit is closed")
    _expect("PANIC latch armed",          d2.fsm.endgame_panicked(), true)
    _expect("player still at canon 4",    d2.fsm.player_room(),       4)
    _expect("CLOCK2 capped at 15",        d2.fsm.endgame_timer(),     15.0)

    # ----- Phase 3: second attempt re-emits msg #130 but doesn't re-cap -----
    print("Phase 3: second attempt — msg #130 re-emits, no further cap")
    # Tick the timer down a little so we can detect a re-cap.
    d2.fsm.endgame.tick()
    d2.fsm.endgame.tick()
    var timer_after_ticks: float = d2.fsm.endgame_timer()
    _expect("timer ticked down to 13",    timer_after_ticks,          13.0)
    var l3: Array = _capture(d2, "north")
    _expect_any_match("second attempt re-emits msg #130",
        l3, "exit is closed")
    _expect("timer stays at 13 (no re-cap)",
        d2.fsm.endgame_timer(),           13.0)

    # ----- Phase 4: in $InRepository, panic() is a no-op -----
    print("Phase 4: $InRepository — panic() does nothing (PANIC latch already past)")
    var d3 := _make_driver()
    _force_closing(d3)
    # Force the timer to 0 and tick to enter $InRepository.
    while d3.fsm.endgame_state() == "closing":
        d3.fsm.endgame.tick()
    _expect("setup: in_repository",       d3.fsm.endgame_state(),    "in_repository")
    d3.fsm.endgame.panic()                # canon: no-op
    _expect("repository panicked? false", d3.fsm.endgame_panicked(), false)

    if failures == 0:
        print("PASS — endgame PANIC honors canon STMT 2 + msg #130 + CLOCK2 cap")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
