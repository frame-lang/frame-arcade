# ============================================================
# Shared test helpers for the CCA test suite.
# ============================================================
# Headless test pattern. Tests can't render to a RichTextLabel,
# so `CapturedDriver` overrides `_println` to append to an
# in-memory buffer instead. Tests `_capture(...)` an input,
# then assert against the returned captured-line array.
#
# Usage:
#     const H = preload("res://scripts/_test_helpers.gd")
#
#     func _init():
#         var d: H.CapturedDriver = H.make_driver()
#         var lines: Array = H.capture(d, "look")
#         _expect_any_match("description prints",
#             lines, "BUILDING")
#
# Tests with custom setup needs (different start room, pre-
# carried items, etc.) call H.make_driver() then mutate the
# returned driver, or build their own via H.CapturedDriver.new().
#
# This file's `class_name` is omitted so it doesn't pollute the
# editor's autocomplete with a global symbol — tests preload it.

extends RefCounted

# Re-exported under the helpers namespace so tests can use
# `H.Cca` / `H.Driver` rather than preloading separately.
const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

# Driver subclass that captures _println output instead of
# routing it to the RichTextLabel UI. Mirrors what every
# headless test was doing inline.
class CapturedDriver:
    extends Driver
    var captured: Array = []
    func _println(text: String) -> void:
        self.captured.append(text)

# Standard test setup — fresh FSM with default aspects + lit
# lamp. Tests that need other initial state (carrying items,
# pirate active, etc.) set those up after calling this.
static func make_driver() -> CapturedDriver:
    var d := CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.do_command("light", "")
    return d

# Run one input through the captured driver and return only the
# lines emitted by THIS input (slice from pre-input length).
static func capture(d: CapturedDriver, input: String) -> Array:
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)
