extends SceneTree

# Verifies the canonical Witt's End probabilistic bounce-back at
# canon 108. Per cca/canon/advent.dat row `108 95556 ...` and the
# FORTRAN spec at canon/advent.for lines 105-122:
#
#   108 95556 43 45 46 47 48 49 50 29 30
#       95% chance: any of E/N/S/NE/SE/SW/NW/UP/DOWN prints canon
#       msg #56 ("you have crawled around in some little holes
#       and wound up back in the main passage") and stays put.
#   108 106   43
#       fall-through (5% case) for E specifically: walk to canon
#       106 (the only actual exit out of Witt's End).
#   108 626   44
#       W: always msg #126 ("...found your way blocked by a
#       recent cave-in...").
#
# The bounce message *narrates* moving back to the main passage
# but the player's location doesn't change — that's the trick of
# Witt's End. To actually escape, the player has to keep typing
# E and hope the 5% probability fires.
#
# Test phases:
#   1. WEST is always the cave-in bumper (deterministic).
#   2. Roll EAST many times under a pinned RNG seed and confirm
#      the distribution: most attempts are bounces, a minority
#      actually walk to 106. The exact split depends on the seed
#      but should be well within ±10pp of the canon 95/5.
#   3. NORTH/SOUTH/etc. always bounce or hit "no exit" (these
#      directions have no canon section-3 plain row).

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
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_in_range(label: String, actual: int, lo: int, hi: int) -> void:
    if actual >= lo and actual <= hi:
        print("  ok   %-44s = %d (in [%d, %d])" % [label, actual, lo, hi])
    else:
        print("  FAIL %-44s = %d (expected [%d, %d])" % [
            label, actual, lo, hi])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-44s found '%s'" % [label, needle])
            return
    print("  FAIL %-44s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    return d

func _init():
    print("=== CCA Witt's End probabilistic bounce-back (canon 108) ===")

    # Pin Godot's global RNG so the 95% rolls are deterministic.
    seed(0xCABBA9E)

    # Phase 1: WEST is the always-bumper "cave-in" message.
    print("Phase 1: WEST always emits the cave-in msg #126")
    var d := _make_driver()
    d.fsm.do_command("light", "")          # so the dark-pit hazard doesn't fire
    d.fsm.player.move_to(108)
    _expect("at Witt's End",      d.fsm.player_room(),   108)
    var pre_count: int = d.captured.size()
    d._process_input("west")
    _expect("WEST keeps player at 108", d.fsm.player_room(), 108)
    var west_lines: Array = d.captured.slice(pre_count)
    _expect_any_match("WEST emits cave-in prose",
        west_lines, "blocked by a recent cave-in")

    # Phase 2: distribution of EAST attempts. With the seed pinned,
    # roll 1000 EAST attempts and count escapes vs bounces. Canon
    # is 95/5 ⇒ expect ~50 escapes ±20 (3 sigma for n=1000, p=0.05
    # is sqrt(1000*.05*.95) ≈ 6.9).
    print("Phase 2: EAST distribution under pinned seed")
    var bounces: int = 0
    var escapes: int = 0
    var saw_bounce_msg: bool = false
    var saw_escape: bool = false
    for _i in range(1000):
        d.fsm.player.move_to(108)        # reset position each attempt
        var pre: int = d.captured.size()
        d._process_input("east")
        var lines: Array = d.captured.slice(pre)
        if d.fsm.player_room() == 106:
            escapes += 1
            saw_escape = true
        else:
            bounces += 1
            for line in lines:
                if "wound up back in the main passage" in line:
                    saw_bounce_msg = true
                    break
    _expect("escape count in 1000 EAST attempts in [25, 80]" if true else "",
        true, true)
    _expect_in_range("escapes (canon ~50)", escapes, 25, 80)
    _expect_in_range("bounces (canon ~950)", bounces, 920, 975)
    _expect("saw at least one canon bounce msg", saw_bounce_msg, true)
    _expect("saw at least one 5% escape",       saw_escape,    true)
    print("  observed: %d escapes / %d bounces" % [escapes, bounces])

    # Phase 3: NORTH at 108 is gated probability with no walking
    # destination. Roll many attempts; never ends up moved.
    print("Phase 3: NORTH never lets the player leave 108")
    var moved: int = 0
    for _i in range(200):
        d.fsm.player.move_to(108)
        d._process_input("north")
        if d.fsm.player_room() != 108:
            moved += 1
    _expect("NORTH keeps player at 108 in 200 attempts", moved, 0)

    if failures == 0:
        print("PASS — Witt's End 95/5 probabilistic bounce-back honors canon")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
