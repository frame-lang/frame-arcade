extends SceneTree

# Verifies the canon PDP-10 timesharing easter-egg verbs:
# HOURS, WIZARD, MAINT (and the MAGIC / "MAGIC MODE" aliases).
#
# In the original 1977 release these drove the cave's prime-time
# scheduling and the wizard authentication challenge — neither of
# which has any analog on a single-user desktop. The Godot port
# honors each verb with a canon-flavored flavor message that
# narrates what the original did and why it doesn't apply now.
#
# This test confirms each verb is recognised, produces output,
# and references the canon prose / provenance — without
# fabricating prime-time hours or a fake authentication.
#
# Canon references:
#   advent.for line 8310 → SUBROUTINE HOURS at line 2639
#   advent.for SUBROUTINE WIZARD at line 2578
#   advent.for SUBROUTINE MAINT at line 2521
#   ADVENT_DAT_INVENTORY.md section 12: magic msgs #1, #16-#20

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
        print("  ok   %-52s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-52s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-52s found '%s'" % [label, needle])
            return
    print("  FAIL %-52s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _expect_no_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  FAIL %-52s line contained banned '%s': %s" % [
                label, needle, line])
            failures += 1
            return
    print("  ok   %-52s no line contained '%s'" % [label, needle])

func _make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    return d

func _capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA PDP-10 timesharing easter-egg verbs ===")

    # ----- HOURS -----
    print("Phase 1: HOURS — canon timesharing schedule, replaced with always-open banner")
    var d := _make_driver()
    var lines: Array = _capture(d, "hours")
    _expect("HOURS produced output",                     lines.size() > 0,        true)
    _expect_any_match("HOURS names the cave as always open",
        lines, "open all day, every day")
    _expect_any_match("HOURS cites the 1977 PDP-10 provenance",
        lines, "1977 PDP-10")
    _expect_any_match("HOURS explains why the schedule is vestigial",
        lines, "timesharing")
    _expect_no_match("HOURS doesn't fabricate a time-of-day", lines, ":00")
    _expect_no_match("HOURS doesn't fake a Mon-Fri schedule", lines, "Mon -")

    # ----- WIZARD -----
    print("Phase 2: WIZARD — canon msg #16/#17/#18/#20 dialogue narrated single-shot")
    var d2 := _make_driver()
    var w_lines: Array = _capture(d2, "wizard")
    _expect("WIZARD produced output",                    w_lines.size() > 0,      true)
    _expect_any_match("WIZARD opens with canon msg #16",
        w_lines, "Are you a wizard?")
    _expect_any_match("WIZARD echoes canon msg #17 (PROVE IT)",
        w_lines, "Prove it")
    _expect_any_match("WIZARD echoes canon msg #17 (magic word challenge)",
        w_lines, "magic word")
    _expect_any_match("WIZARD ends with canon msg #20 (charlatan)",
        w_lines, "charlatan")

    # ----- MAINT (single-word) -----
    print("Phase 3: MAINT — canon msg #1 wizard-in-grey + msg #20 charlatan")
    var d3 := _make_driver()
    var m_lines: Array = _capture(d3, "maint")
    _expect("MAINT produced output",                     m_lines.size() > 0,      true)
    _expect_any_match("MAINT opens with canon green-smoke wizard",
        m_lines, "green smoke")
    _expect_any_match("MAINT names the canon wizard-in-grey",
        m_lines, "wizard, clothed in grey")
    _expect_any_match("MAINT names Don Woods (canon attribution)",
        m_lines, "Don Woods")
    _expect_any_match("MAINT ends with canon msg #20 (charlatan)",
        m_lines, "charlatan")

    # ----- MAGIC alias (single word) -----
    print("Phase 4: MAGIC — same dispatch as MAINT (canon synonym for MAGIC MODE)")
    var d4 := _make_driver()
    var mg_lines: Array = _capture(d4, "magic")
    _expect("MAGIC produced output",                     mg_lines.size() > 0,     true)
    _expect_any_match("MAGIC routes to MAINT handler",
        mg_lines, "wizard, clothed in grey")

    # ----- MAGIC MODE (two-word phrase, canon trigger) -----
    print("Phase 5: 'MAGIC MODE' — canon two-word trigger, parser drops MODE noun")
    var d5 := _make_driver()
    var mm_lines: Array = _capture(d5, "magic mode")
    _expect("MAGIC MODE produced output",                mm_lines.size() > 0,     true)
    _expect_any_match("MAGIC MODE routes to MAINT handler",
        mm_lines, "wizard, clothed in grey")

    # ----- MAINTENANCE alias -----
    print("Phase 6: MAINTENANCE — long-form alias for MAINT")
    var d6 := _make_driver()
    var mt_lines: Array = _capture(d6, "maintenance")
    _expect("MAINTENANCE produced output",               mt_lines.size() > 0,     true)
    _expect_any_match("MAINTENANCE routes to MAINT handler",
        mt_lines, "wizard, clothed in grey")

    if failures == 0:
        print("PASS — HOURS / WIZARD / MAINT honor canon with canon-flavored prose")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
