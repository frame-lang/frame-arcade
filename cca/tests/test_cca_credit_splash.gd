extends SceneTree

# Verifies the Crowther/Woods credit splash. Every CCA session
# opens with explicit attribution to the 1976/77 original before
# any game prose; the splash is the first thing a player sees
# on launch (standalone build) or on chapter-select (arcade
# build). The text lives in Driver._print_welcome and is mirrored
# verbatim in arcade/godot/scripts/cca_main.gd's _print_welcome.
#
# Captured-driver pattern: subclass Driver to override _println,
# call _print_welcome, scan the captured buffer for canonical
# attribution beats. The text is the user-facing tribute — if
# any of the eight checks below fail, the splash isn't paying
# the proper credit.

const H = preload("res://scripts/_test_helpers.gd")

# Extends the shared CapturedDriver with a `joined()` helper for
# scanning the welcome banner as a single string.
class JoinedDriver:
    extends H.CapturedDriver
    func joined() -> String:
        return "\n".join(self.captured)

func _make_driver() -> JoinedDriver:
    var d := JoinedDriver.new()
    d.fsm = H.Cca.new()
    d.fsm.setup_default_aspects()
    return d

var failures: int = 0

func _expect_contains(label: String, haystack: String, needle: String) -> void:
    if needle in haystack:
        print("  ok   %-32s contains '%s'" % [label, needle])
    else:
        print("  FAIL %-32s missing '%s'" % [label, needle])
        failures += 1

func _init():
    print("=== CCA Crowther/Woods credit splash ===")
    var d := _make_driver()
    d._print_welcome()
    var t: String = d.joined()

    _expect_contains("title",            t, "COLOSSAL CAVE ADVENTURE")
    _expect_contains("Crowther credit",  t, "Will Crowther")
    _expect_contains("year — Crowther",  t, "1976")
    _expect_contains("Woods credit",     t, "Don Woods")
    _expect_contains("year — Woods",     t, "1977")
    _expect_contains("Stanford AI Lab",  t, "Stanford AI Lab")
    _expect_contains("FORTRAN provenance", t, "PDP-10 FORTRAN-IV")
    _expect_contains("IF Archive",       t, "Interactive Fiction Archive")
    _expect_contains("public domain",    t, "Public domain")
    _expect_contains("HELP hint",        t, "HELP")

    if failures == 0:
        print("PASS — credit splash names Crowther + Woods + IF Archive")
    else:
        print("FAIL — %d check(s) missed" % failures)
    quit(failures)
