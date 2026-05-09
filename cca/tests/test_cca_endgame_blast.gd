extends SceneTree

# Verifies the canon endgame win path: BLAST verb (advent.for
# STMT 9230), plus the WAKE-DWARVES (STMT 9290) and BREAK
# MIRROR (STMT 9280) closed-only deaths. All three are
# repository-only mechanics that close the game.
#
# Canon BLAST outcomes (from STMT 9230 + scoring at 20000):
#   pre-CLOSED                    → msg #67 ("BLASTING REQUIRES DYNAMITE.")
#   CLOSED + rod2 here            → blast_klutz, msg #135, +25
#   CLOSED + LOC=115 + rod2 elsewhere → blast_wrong_way, msg #134, +30
#   CLOSED + otherwise            → blast_mastery, msg #133, +45
#
# WAKE/BREAK MIRROR canon flow:
#   pre-CLOSED                    → msg default ("I don't understand"
#                                     / "It is beyond your power")
#   CLOSED                        → canon prose + msg #136 (dwarves
#                                     wake → death)

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

# Drive the FSM into $InRepository: deposit 10 treasures, tick
# 30 turns until the closing timer fires.
func _force_in_repository(d: CapturedDriver) -> void:
    for i in 10:
        d.fsm.deposit_treasure()
    for i in 30:
        d.fsm.tick()

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA endgame BLAST + WAKE + BREAK MIRROR ===")

    # ----- Phase 1: pre-closed BLAST → 'requires dynamite' -----
    print("Phase 1: pre-closed BLAST → canon msg #67")
    var d := _make_driver()
    var lines: Array = _capture(d, "blast")
    _expect("pre-closed BLAST stays alive",         d.fsm.player_state(),    "alive")
    _expect("pre-closed BLAST: endgame still active", d.fsm.endgame_state(), "active")
    _expect_any_match("pre-closed BLAST emits 'requires dynamite'",
        lines, "requires dynamite")

    # ----- Phase 2: BLAST mastery (closed, rod2 not here, LOC != 115) -----
    # Port lands the player at canon 116 (SW end) on repository
    # entry — that's the canon `LOC=116` setup. We move to 116
    # explicitly to match canon's default BLAST mastery setup
    # (rod2 in inventory was at 116; player has dropped it
    # elsewhere or never picked it up).
    print("Phase 2: BLAST mastery — canon msg #133, +45 endgame, $Won")
    var d2 := _make_driver()
    _force_in_repository(d2)
    _expect("setup: in repository",                 d2.fsm.endgame_state(),  "in_repository")
    d2.fsm.player.move_to(116)
    _expect("setup: at 116 (NOT 115, the wrong-way room)", d2.fsm.player_room(), 116)
    _expect("setup: rod2 not here",                 d2.fsm.mark_rod_here(),  false)
    var pre_score: int = d2.fsm.endgame_score()
    var l2: Array = _capture(d2, "blast")
    _expect_any_match("BLAST mastery emits canon-#133 elves narration",
        l2, "cheering band of")
    _expect("BLAST mastery: endgame transitions to $Won",
        d2.fsm.endgame_state(), "won")
    _expect("BLAST mastery: +45 endgame score",
        d2.fsm.endgame_score() - pre_score, 45)

    # ----- Phase 3: BLAST wrong-way (closed, LOC=115, rod2 elsewhere) -----
    print("Phase 3: BLAST wrong-way — canon msg #134, +30 endgame, $Won")
    var d3 := _make_driver()
    _force_in_repository(d3)
    d3.fsm.player.move_to(115)            # canon's wrong-way trigger room
    _expect("setup: at canon 115",                  d3.fsm.player_room(),    115)
    _expect("setup: rod2 not here",                 d3.fsm.mark_rod_here(),  false)
    var pre3: int = d3.fsm.endgame_score()
    var l3: Array = _capture(d3, "blast")
    _expect_any_match("BLAST wrong-way emits canon-#134 lava narration",
        l3, "molten lava")
    _expect_any_match("BLAST wrong-way ends with 'including you'",
        l3, "including you")
    _expect("BLAST wrong-way: endgame transitions to $Won",
        d3.fsm.endgame_state(), "won")
    _expect("BLAST wrong-way: +30 endgame score",
        d3.fsm.endgame_score() - pre3, 30)

    # ----- Phase 4: BLAST klutz (closed, rod2 in player's hand) -----
    print("Phase 4: BLAST klutz — canon msg #135, +25 endgame, $Won")
    var d4 := _make_driver()
    _force_in_repository(d4)
    # Place mark_rod_item at player's room and pick up.
    d4.fsm.mark_rod_item.place(d4.fsm.player_room())
    _expect("setup: rod2 here",                     d4.fsm.mark_rod_here(),  true)
    var pre4: int = d4.fsm.endgame_score()
    var l4: Array = _capture(d4, "blast")
    _expect_any_match("BLAST klutz emits canon-#135 splash narration",
        l4, "splashed across")
    _expect("BLAST klutz: endgame transitions to $Won",
        d4.fsm.endgame_state(), "won")
    _expect("BLAST klutz: +25 endgame score",
        d4.fsm.endgame_score() - pre4, 25)

    # ----- Phase 5: WAKE pre-closed → 'I don't understand' -----
    print("Phase 5: pre-closed WAKE → 'I don't understand'")
    var d5 := _make_driver()
    var l5: Array = _capture(d5, "wake")
    _expect("pre-closed WAKE: player alive",        d5.fsm.player_state(),   "alive")
    _expect_any_match("pre-closed WAKE emits 'don't understand'",
        l5, "don't understand")

    # ----- Phase 6: WAKE in repository → death (msg #199 + #136) -----
    print("Phase 6: WAKE in repository → canon msg #199 + #136 death")
    var d6 := _make_driver()
    _force_in_repository(d6)
    var l6: Array = _capture(d6, "wake")
    _expect_any_match("WAKE emits canon-#199 'prod the nearest dwarf'",
        l6, "prod the nearest dwarf")
    _expect_any_match("WAKE emits canon-#136 'awakened the dwarves'",
        l6, "awakened the dwarves")
    _expect("WAKE: player is dead",                 d6.fsm.player_state(),   "dead")

    # ----- Phase 7: BREAK MIRROR pre-closed -----
    print("Phase 7: pre-closed BREAK MIRROR → canon msg #146")
    var d7 := _make_driver()
    var l7: Array = _capture(d7, "break mirror")
    _expect("pre-closed BREAK MIRROR: player alive", d7.fsm.player_state(),   "alive")
    _expect_any_match("pre-closed BREAK MIRROR: canon msg #146",
        l7, "beyond your power")

    # ----- Phase 8: BREAK MIRROR in repository → death -----
    print("Phase 8: BREAK MIRROR in repository → canon msg #197 + #136 death")
    var d8 := _make_driver()
    _force_in_repository(d8)
    var l8: Array = _capture(d8, "break mirror")
    _expect_any_match("BREAK MIRROR emits canon-#197 'shatters into a myriad'",
        l8, "shatters into a")
    _expect_any_match("BREAK MIRROR emits canon-#136 'awakened the dwarves'",
        l8, "awakened the dwarves")
    _expect("BREAK MIRROR: player is dead",         d8.fsm.player_state(),   "dead")

    # ----- Phase 9: DETONATE alias (backward-compat) -----
    print("Phase 9: DETONATE alias routes to BLAST")
    var d9 := _make_driver()
    _force_in_repository(d9)
    d9.fsm.player.move_to(116)            # mastery setup
    var l9: Array = _capture(d9, "detonate")
    _expect_any_match("DETONATE alias hits BLAST mastery prose",
        l9, "cheering band of")
    _expect("DETONATE alias: $Won",                 d9.fsm.endgame_state(),  "won")

    if failures == 0:
        print("PASS — endgame BLAST / WAKE / BREAK MIRROR honor canon section-3 + STMT 9230 / 9280 / 9290")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
