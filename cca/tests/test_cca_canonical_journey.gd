extends SceneTree

# ============================================================
# test_cca_canonical_journey.gd
# ============================================================
# FSM-driven canonical happy-path test.
#
# Unlike the other cca/tests/*.gd files (which drive the
# Adventure FSM directly via `adv.do_command(...)` + assert on
# FSM state), this test instantiates the actual Driver Control
# and walks the player UX: command-line input → parser → FSM
# dispatch → per-turn tick → log output. It catches player-
# visible bugs the FSM-direct tests can't see — e.g. an item
# missing from a room description, or a Y/N prompt firing too
# early.
#
# The journey itself is described by a Frame state machine
# (cca/frame/canonical_journey.fgd → CanonicalJourney). Each
# milestone state declares:
#   - commands_from_previous(): commands to type to ARRIVE here
#   - expected_room():           player_room after commands
#   - expected_in_log():         substrings that MUST appear
#   - expected_not_in_log():     substrings that MUST NOT appear
#
# The harness below is a tight loop: walk states, pipe commands
# through the Driver, diff the log, assert.
#
# Stage 1 (cave entry) ships first to surface the lamp /
# premature-hint bugs. Subsequent stages are additions to the
# Frame FSM, not changes to this harness.
# ============================================================

const Driver = preload("res://scripts/driver.gd")
const Cca = preload("res://scripts/cca.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

var failures: int = 0

func _ok(label: String, detail: String = "") -> void:
    var suffix: String = ""
    if detail != "":
        suffix = "  (" + detail + ")"
    print("  ok    %-58s%s" % [label, suffix])

func _fail(label: String, detail: String = "") -> void:
    var suffix: String = ""
    if detail != "":
        suffix = "  (" + detail + ")"
    print("  FAIL  %-58s%s" % [label, suffix])
    failures += 1

func _expect_eq(label: String, actual, expected) -> void:
    if actual == expected:
        _ok(label, "%s" % str(actual))
    else:
        _fail(label, "got %s, expected %s" % [str(actual), str(expected)])

func _expect_contains(label: String, haystack: String, needle: String) -> void:
    if haystack.contains(needle):
        _ok(label, "contains '%s'" % needle)
    else:
        _fail(label, "missing '%s'" % needle)

func _expect_not_contains(label: String, haystack: String, needle: String) -> void:
    if not haystack.contains(needle):
        _ok(label, "absent: '%s'" % needle)
    else:
        _fail(label, "unexpectedly present: '%s'" % needle)

func _init():
    print("=== CCA canonical journey — FSM-driven player UX (Stage 1) ===")

    # ----- Build a headless Driver -----
    # Driver extends Control; in production its _ready() builds the
    # UI (RichTextLabel + LineEdit) and constructs the fsm. Here we
    # construct each piece manually so we can drive _process_input
    # without entering the scene tree.
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.wake_dwarves()
    # PromptDispatcher is already initialized at var declaration in
    # driver.gd; no need to set it manually.

    # Replace the UI nodes with bare standalone instances. They don't
    # need to be in a scene tree — append_text() buffers internally
    # and get_parsed_text() returns the plain-text content.
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()

    # Snapshot the log length BEFORE the driver's priming output.
    # $AtRoad is the start state and produces no commands of its
    # own; its "delta" is the welcome banner + room-1 description
    # that _ready() would have printed. By snapshotting now, those
    # land in $AtRoad's delta where the assertions can see them.
    var pre_len: int = 0

    # Prime the log the way _ready() would have. _print_welcome
    # emits canon msg #1 + the help banner; _print_room emits the
    # room-1 description.
    driver._print_welcome()
    driver._print_room()

    # ----- Walk the journey -----
    var journey = CanonicalJourney._create()

    var state_count: int = 0

    while not journey.is_done():
        state_count += 1
        var state: String = journey.state_name()
        print("\n--- [%d] $%s ---" % [state_count, state])

        # Pipe each command through the Driver exactly as if the
        # player had typed it. _on_text_submitted lower-cases input;
        # we do the same here so the parser sees identical input.
        # For $AtRoad this is empty — the delta is just the priming
        # output that landed before the loop started.
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())

        # Compute the log delta produced since the LAST state's
        # assertions ran (or since the priming, for $AtRoad).
        var post_text: String = driver.output.get_parsed_text()
        var delta: String = post_text.substr(pre_len)
        pre_len = post_text.length()

        # Assertion: player_room.
        var expected_room: int = journey.expected_room()
        if expected_room >= 0:
            _expect_eq("[%s] player_room" % state,
                       driver.fsm.player_room(), expected_room)

        # Assertion: substrings that MUST appear in the delta.
        for s in journey.expected_in_log():
            _expect_contains("[%s] log contains" % state, delta, String(s))

        # Assertion: substrings that MUST NOT appear in the delta.
        # This is where the bug-discovery assertions live.
        for s in journey.expected_not_in_log():
            _expect_not_contains("[%s] log absent" % state, delta, String(s))

        # Advance to the next milestone. Once we reach $Done, the
        # while loop exits.
        journey.advance()

    print("")
    if failures == 0:
        print("PASS — canonical journey Stage 1 complete (%d states, 0 failures)" % state_count)
        quit(0)
    else:
        print("FAIL — %d/%d assertions failed across %d states" % [failures, failures, state_count])
        quit(failures)
