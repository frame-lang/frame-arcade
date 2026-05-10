extends SceneTree

# Verifies canon verb-default messages closed in this batch:
#
#   FIND default (no carrying, no endgame)  → canon msg #59
#                ("I can only tell you what you see...")
#   EAT non-food, non-NPC                    → canon msg #71
#                ("I think I just lost my appetite.")
#   EAT NPC noun                             → "Don't be ridiculous!"
#   RUB lamp                                 → canon msg #75
#                ("Rubbing the electric lamp...")
#   RUB other                                → canon msg #76
#                ("Peculiar. Nothing unexpected happens.")

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

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

func _init():
    print("=== CCA verb defaults — FIND / EAT / RUB ===")

    # ----- Phase 1: FIND default → canon msg #59 -----
    print("Phase 1: FIND with non-carried noun → canon msg #59")
    var d1 := H.make_driver()
    var l1: Array = H.capture(d1, "find diamond")
    _expect_any_match("FIND emits 'I can only tell you what you see'",
        l1, "I can only tell you what you see")
    _expect_no_match("FIND no longer emits cave-finding (msg #57)",
        l1, "no stream can run on the surface")

    # ----- Phase 2: EAT non-food, non-NPC → canon msg #71 -----
    print("Phase 2: EAT non-food, non-NPC → canon msg #71")
    var d2 := H.make_driver()
    var l2: Array = H.capture(d2, "eat axe")
    _expect_any_match("EAT axe emits 'just lost my appetite'",
        l2, "just lost my appetite")

    # ----- Phase 3: EAT NPC noun → 'ridiculous' rebuff -----
    print("Phase 3: EAT NPC (snake) → 'Don't be ridiculous!'")
    var d3 := H.make_driver()
    var l3: Array = H.capture(d3, "eat snake")
    _expect_any_match("EAT snake emits 'Don't be ridiculous!'",
        l3, "ridiculous")

    # ----- Phase 4: RUB lamp → canon msg #75 -----
    print("Phase 4: RUB lamp → canon msg #75")
    var d4 := H.make_driver()
    var l4: Array = H.capture(d4, "rub lamp")
    _expect_any_match("RUB lamp emits 'Rubbing the electric lamp'",
        l4, "Rubbing the electric lamp")

    # ----- Phase 5: RUB non-lamp → canon msg #76 -----
    print("Phase 5: RUB non-lamp → canon msg #76 ('Peculiar')")
    var d5 := H.make_driver()
    var l5: Array = H.capture(d5, "rub rod")
    _expect_any_match("RUB rod emits 'Peculiar.'",
        l5, "Peculiar.")
    _expect_no_match("RUB rod does NOT emit lamp prose",
        l5, "Rubbing the electric lamp")

    if failures == 0:
        print("PASS — verb defaults honor canon (msgs #59 / #71 / #75 / #76)")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
