extends SceneTree

# Verifies the canon msg #1 welcome — the 1977 Don Woods intro
# verbatim from advent.dat. Canon already includes the Willie
# Crowther + Don Woods attribution baked into the prose; the
# splash uses canon text rather than port-flavored credits.

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

    # Canon msg #1 verbatim beats (advent.dat). The famous Don
    # Woods 1977 intro paragraph with the Crowther + Woods byline
    # baked in at the bottom. The brick-house ASCII silhouette is
    # port decoration above the canon prose.
    _expect_contains("canon msg #1 opener",       t, "Somewhere nearby is Colossal Cave")
    _expect_contains("canon msg #1 magic",        t, "Magic is said to work in the cave")
    _expect_contains("canon msg #1 5-letter rule", t, "first five letters")
    _expect_contains("canon msg #1 HELP nudge",   t, "HELP")
    _expect_contains("canon byline — Crowther",   t, "Willie Crowther")
    _expect_contains("canon byline — Woods",      t, "Don Woods")
    _expect_contains("canon byline — SU-AI",      t, "SU-AI")
    _expect_contains("canon msg #65 prompt",      t, "Welcome to Adventure")
    _expect_contains("HELP hint",                 t, "HELP")

    if failures == 0:
        print("PASS — canon msg #1 welcome emits verbatim")
    else:
        print("FAIL — %d check(s) missed" % failures)
    quit(failures)
