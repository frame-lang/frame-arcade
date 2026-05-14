extends SceneTree

# ============================================================
# Arcade CCA smoke test
# ============================================================
# A minimal-surface boot-up check that the arcade chapter's
# cca_main.gd successfully composes the FSM and runs an end-to-end
# verb. Catches the class of regression that bit us on 2026-05-10
# (arcade FSM mirror stale → NonexistentFunction crash on first
# Adventure call, only visible when the chapter actually launched
# in Godot). Headless test pattern — subclass cca_main, skip the
# UI-bootstrapping _ready, drive the FSM directly.
#
# Usage:
#   godot --headless --path godot/ --script res://../tests/test_arcade_cca_smoke.gd

const CcaMain = preload("res://scripts/cca_main.gd")
const Cca = preload("res://scripts/cca.gd")

class CapturedCcaMain:
    extends CcaMain
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

func _init():
    print("=== Arcade CCA smoke test ===")

    # Phase 1: FSM composes cleanly and a basic command round-trips.
    print("Phase 1: FSM boots + LOOK")
    var d := CapturedCcaMain.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    _expect("starting room",              d.fsm.player_room(),   1)
    _expect("endgame state",              d.fsm.endgame_state(), "active")
    var look_resp: String = d.fsm.do_command("look", "")
    _expect("LOOK returns non-empty",     look_resp.is_empty(),  false)

    # Phase 2: SAVED → DFLAG=20 hook (the exact API that broke 2026-05-10)
    print("Phase 2: mark_loaded_from_save bridge intact")
    _expect("not yet loaded-from-save",   d.fsm.is_loaded_from_save(), false)
    d.fsm.mark_loaded_from_save()
    _expect("loaded-from-save latch",     d.fsm.is_loaded_from_save(), true)

    # Phase 3: V1.2-vintage Adventure APIs are wired through
    print("Phase 3: V1.2 Adventure accessors present")
    d.fsm.set_old_loc(7)
    _expect("canon scalar set/get",       d.fsm.get_old_loc(),   7)
    d.fsm.enable_brief_mode()
    _expect("brief mode latch",           d.fsm.is_brief_mode(), true)
    d.fsm.mark_chest_hint_done()
    _expect("chest hint latch",           d.fsm.is_chest_hint_done(), true)
    d.fsm.mark_oyster_revealed()
    _expect("oyster reveal latch",        d.fsm.is_oyster_revealed(), true)

    # Phase 4: save/restore round-trip survives the V1.2 domain shape
    print("Phase 4: save/restore round-trip")
    var bytes = d.fsm.save_state()
    var d2 := CapturedCcaMain.new()
    d2.fsm = Cca.new()
    d2.fsm.setup_default_aspects()
    d2.fsm.restore_state(bytes)
    _expect("restored canon scalar",      d2.fsm.get_old_loc(),  7)
    _expect("restored brief mode",        d2.fsm.is_brief_mode(), true)
    _expect("restored chest hint",        d2.fsm.is_chest_hint_done(), true)
    _expect("restored oyster reveal",     d2.fsm.is_oyster_revealed(), true)

    # Phase 5: PromptDispatcher inner class composes
    print("Phase 5: PromptDispatcher (V1.2 Phase 0.2) wired")
    var prompts = Cca.PromptDispatcher.new()
    _expect("prompts idle on boot",       prompts.is_active(),   false)
    prompts.offer_quit()
    _expect("offer_quit transitions",     prompts.current_prompt(), "quit")

    if failures == 0:
        print("PASS — arcade CCA smoke test")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
