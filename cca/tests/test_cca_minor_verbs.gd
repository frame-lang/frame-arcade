extends SceneTree

# Verifies the canon "minor verbs" batch: FIND, BRIEF, RUB,
# SAY, plus the WEST-counter snark and the PLUGH-whisper-at-Y2
# Easter eggs.
#
# Canon references:
#   FIND  — advent.for STMT 9190 (msgs #24/#94/#138/#59)
#   BRIEF — advent.for STMT 8260 (msg #156, sets ABBNUM=10000)
#   RUB   — advent.for STMT 9160 (msg #76 default)
#   SAY   — advent.for STMT 9030 (echo + magic-word redispatch)
#   WEST  — advent.for line 901-902 (msg #17 on 10th typed WEST)
#   Y2    — advent.for line 808 (25% chance msg #8 at room 33)

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

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-58s line contained banned '%s'" % [
                label, needle])
            failures += 1
            return
    print("  ok   %-58s no line contained '%s'" % [label, needle])

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA minor canon verbs (FIND/BRIEF/RUB/SAY/WEST/Y2) ===")

    # ----- Phase 1: FIND -----
    print("Phase 1: FIND verb")
    var d := _make_driver()
    # FIND with no carry → cave-finding hint (canon msg #59)
    var l: Array = _capture(d, "find bird")
    _expect_any_match("FIND BIRD (not carried) → canon hint",
        l, "I don't know where the cave is")
    # FIND with carry → "you are already carrying it!"
    d.fsm.player.take(d.fsm.GOLD_ID)
    var l2: Array = _capture(d, "find gold")
    _expect_any_match("FIND GOLD (carrying) → 'already carrying'",
        l2, "already carrying")
    # FIND in repository → 'around here somewhere'
    var d2 := _make_driver()
    for i in 10:
        d2.fsm.deposit_treasure()
    for i in 30:
        d2.fsm.tick()
    _expect("setup: in repository",          d2.fsm.endgame_state(), "in_repository")
    var l3: Array = _capture(d2, "find emerald")
    _expect_any_match("FIND in repository → 'around here somewhere'",
        l3, "around here somewhere")

    # ----- Phase 2: BRIEF -----
    print("Phase 2: BRIEF — sets brief_mode and short-circuits revisits")
    var d3 := _make_driver()
    var l4: Array = _capture(d3, "brief")
    _expect_any_match("BRIEF emits canon ack 'first time'",
        l4, "first time")
    _expect("BRIEF sets _brief_mode",         d3._brief_mode, true)
    # Visit a room, leave, come back — second visit should suppress
    # description in brief mode.
    d3.fsm.player.move_to(33)
    d3._maybe_print_room_after_move()
    d3.fsm.player.move_to(34)
    d3._maybe_print_room_after_move()
    d3.fsm.player.move_to(33)
    var pre: int = d3.captured.size()
    d3._maybe_print_room_after_move()
    var l5: Array = d3.captured.slice(pre)
    _expect_no_match("BRIEF revisit to room 33 suppresses long desc",
        l5, "Y2")

    # ----- Phase 3: RUB -----
    print("Phase 3: RUB — canon msg #76 'not productive'")
    var d4 := _make_driver()
    var l6: Array = _capture(d4, "rub lamp")
    _expect_any_match("RUB LAMP → 'nothing exciting happens'",
        l6, "nothing exciting happens")

    # ----- Phase 4: SAY -----
    print("Phase 4: SAY echoes 'Okay, X' for non-magic; redispatches magic words")
    var d5 := _make_driver()
    var l7: Array = _capture(d5, "say hello")
    _expect_any_match("SAY HELLO echoes 'Okay, hello'",
        l7, "Okay, \"hello\"")
    # SAY with no noun
    var l8: Array = _capture(d5, "say")
    _expect_any_match("SAY (no noun) prompts 'Say what?'",
        l8, "Say what?")
    # SAY XYZZY at room 11 → teleports to 3 (well house)
    var d6 := _make_driver()
    d6.fsm.player.move_to(11)
    d6._process_input("say xyzzy")
    _expect("SAY XYZZY redispatches as XYZZY (player at 3)",
        d6.fsm.player_room(), 3)

    # ----- Phase 5: WEST counter -----
    print("Phase 5: WEST counter — 10th 'west' fires msg #17 once")
    var d7 := _make_driver()
    d7.fsm.player.move_to(3)               # well house has west exit
    var seen_msg: bool = false
    for i in 12:
        var pre_i: int = d7.captured.size()
        d7._process_input("west")
        var lines_i: Array = d7.captured.slice(pre_i)
        d7.fsm.player.move_to(3)            # reset position so we keep typing
        for line in lines_i:
            if "simply type W" in line:
                _expect("WEST counter fires on iter %d" % (i + 1), i + 1, 10)
                seen_msg = true
                break
    _expect("WEST counter eventually fired",  seen_msg, true)
    _expect("WEST counter ended at exactly 10", d7._iwest_count >= 10, true)

    # ----- Phase 6: Y2 PLUGH whisper -----
    print("Phase 6: Y2 PLUGH whisper — 25% per visit, room 33 only")
    seed(0xCABBA9E)
    var d8 := _make_driver()
    var whispers: int = 0
    for i in 1000:
        d8.fsm.player.move_to(33)
        d8._last_room = -1                  # force re-print
        var pre_w: int = d8.captured.size()
        d8._print_room()
        for line in d8.captured.slice(pre_w):
            if "PLUGH" in line:
                whispers += 1
                break
    print("  observed: %d whispers in 1000 visits" % whispers)
    _expect("Y2 whispers in [200, 300] (canon 25%)",
        whispers >= 200 and whispers <= 300, true)
    # Whisper does NOT fire at non-Y2 rooms
    var d9 := _make_driver()
    var off_y2: int = 0
    for i in 200:
        d9.fsm.player.move_to(34)
        d9._last_room = -1
        var pre_n: int = d9.captured.size()
        d9._print_room()
        for line in d9.captured.slice(pre_n):
            if "PLUGH" in line:
                off_y2 += 1
                break
    _expect("PLUGH whisper never fires off-Y2", off_y2, 0)

    if failures == 0:
        print("PASS — minor canon verbs honor section-3 + STMT 9030/9160/9190/8260 + line 808/901")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
