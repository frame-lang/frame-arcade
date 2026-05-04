# ============================================================
# state_explorer.gd — model-check a Frame state machine
# ============================================================
# Explores the reachable state graph of any Frame @@system that
# has @@[persist] (which gives us save_state / restore_state).
# We use save/restore to teleport between visited states rather
# than replaying paths from the initial state, so the cost is
# O(states × events) regardless of graph diameter.
#
# Usage:
#
#   const Cca = preload("res://scripts/cca.gd")
#   const StateExplorer = preload("res://scripts/state_explorer.gd")
#
#   var bear_factory = func() -> Variant: return Cca.Bear.new()
#   var bear_events = [
#       ["feed", []],
#       ["take_chain", []],
#       ["drop_chain", []],
#       ["scared_off", []],
#   ]
#
#   var report = StateExplorer.explore(bear_factory, bear_events)
#   StateExplorer.print_report(report, "Bear")
#
# Output:
#
#   === Bear ===
#   Initial: hungry
#   Discovered states (5):
#     - hungry
#     - tame
#     - following
#     - released
#     - attacking
#   Transitions (8):
#     hungry      -- feed         --> tame
#     hungry      -- take_chain   --> attacking
#     tame        -- feed         --> tame         (self-loop)
#     tame        -- take_chain   --> following
#     following   -- drop_chain   --> released
#     released    -- (no events fire)
#     attacking   -- (no events fire)
#   Dead-end states (no outgoing): attacking, released
#
# This is a Frame demonstration in itself: every @@[persist]
# system is automatically model-checkable. CrystalBridge, Grate,
# Lamp, Bear, Bird, Snake, Plant, Player, Pirate, Troll,
# VendingMachine, ExitDialog all qualify.
# ============================================================
class_name StateExplorer
extends RefCounted

# explore() is a static method called via StateExplorer.explore(...).
# It traverses the @@system's reachable state graph in BFS order,
# checkpointing each newly-discovered state via save_state and
# trying every (event, args) combination from each.
#
# Arguments:
#   system_factory  Callable returning a fresh @@system instance.
#                   A factory rather than a class because some
#                   @@systems take constructor args (e.g.
#                   Asteroids(difficulty)) — capturing them in
#                   the closure keeps the API uniform.
#   events          Array of [event_name: String, args: Array].
#                   The events you want to try from each state.
#                   You decide which interface methods are
#                   state-changers; queries like get_state() are
#                   skipped (they don't transition).
#   max_states      Defensive cap on discovered states. Most
#                   real Frame FSMs have <20; leaving the cap
#                   at 100 prevents runaway exploration in case
#                   of a bug in the system being explored.
#
# Returns a Dictionary:
#   initial      — the state get_state() returned on a fresh
#                  factory call
#   states       — Array<String> of every discovered state
#   transitions  — Array<{from, event, args, to}> of every
#                  attempted transition
#   dead_ends    — Array<String> of states that have no outgoing
#                  transition (every event leaves them where
#                  they are, or there are no events)
#   unreachable  — Array<String> of states discovered as a
#                  to-state but never as a from-state (means
#                  we found them but couldn't try events from
#                  them; usually shouldn't happen but flagged
#                  in case it does)
static func explore(system_factory: Callable, events: Array, max_states: int = 100) -> Dictionary:
    var initial = system_factory.call()
    var initial_state: String = initial.get_state()
    var saves: Dictionary = {}                  # state name → save bytes
    saves[initial_state] = initial.save_state()

    var queue: Array = [initial_state]
    var transitions: Array = []

    while not queue.is_empty() and saves.size() <= max_states:
        var current: String = queue.pop_front()
        var bytes = saves[current]

        for event in events:
            var event_name: String = event[0]
            var event_args: Array = event[1]

            # Restore to `current` and try the event.
            var inst = system_factory.call()
            inst.restore_state(bytes)
            inst.callv(event_name, event_args)
            var new_state: String = inst.get_state()

            transitions.append({
                "from":  current,
                "event": event_name,
                "args":  event_args,
                "to":    new_state,
            })

            if not saves.has(new_state):
                saves[new_state] = inst.save_state()
                queue.append(new_state)

    # Aggregate dead-ends and unreachable-from set.
    var has_real_outgoing: Dictionary = {}      # states with at least one non-self transition
    var has_been_from: Dictionary = {}          # states we explored from
    for t in transitions:
        has_been_from[t.from] = true
        if t.from != t.to:
            has_real_outgoing[t.from] = true
    var dead_ends: Array = []
    var unreachable: Array = []
    for s in saves.keys():
        if not has_real_outgoing.has(s):
            dead_ends.append(s)
        if not has_been_from.has(s) and s != initial_state:
            unreachable.append(s)

    return {
        "initial":     initial_state,
        "states":      saves.keys(),
        "transitions": transitions,
        "dead_ends":   dead_ends,
        "unreachable": unreachable,
    }

# Pretty-print the report. Width-padded for readability.
static func print_report(report: Dictionary, label: String = "system") -> void:
    print("=== %s ===" % label)
    print("Initial: %s" % report.initial)
    print("Discovered states (%d):" % report.states.size())
    for s in report.states:
        print("  - %s" % s)
    print("Transitions (%d):" % report.transitions.size())
    var width = _max_state_width(report.states)
    for t in report.transitions:
        var marker := ""
        if t.from == t.to:
            marker = "  (no change)"
        var args_str: String = "" if t.args.is_empty() else str(t.args)
        print("  %s -- %s%s --> %s%s" % [
            _pad(t.from, width),
            t.event,
            args_str,
            _pad(t.to, width),
            marker,
        ])
    if report.dead_ends.is_empty():
        print("No dead-end states.")
    else:
        print("Dead-end states (no event leaves them): %s" % ", ".join(report.dead_ends))
    if not report.unreachable.is_empty():
        print("WARNING: states discovered as a target but never explored from:")
        for s in report.unreachable:
            print("  - %s" % s)

# Render a Graphviz DOT diagram of the discovered transitions.
# Pipe to `dot -Tsvg` or paste into https://dreampuf.github.io/GraphvizOnline
static func to_dot(report: Dictionary, label: String = "system") -> String:
    var lines: Array = []
    lines.append("digraph %s {" % label.replace(" ", "_"))
    lines.append("  rankdir=LR;")
    lines.append("  node [shape=box, style=rounded];")
    lines.append("  \"%s\" [style=\"rounded,bold\"];" % report.initial)
    # Collapse identical (from, event, to) triples
    var seen: Dictionary = {}
    for t in report.transitions:
        if t.from == t.to:
            continue       # skip self-loops in the DOT for readability
        var key = "%s|%s|%s" % [t.from, t.event, t.to]
        if seen.has(key):
            continue
        seen[key] = true
        lines.append("  \"%s\" -> \"%s\" [label=\"%s\"];" % [t.from, t.to, t.event])
    lines.append("}")
    return "\n".join(lines)

static func _max_state_width(states: Array) -> int:
    var w := 0
    for s in states:
        if s.length() > w:
            w = s.length()
    return w

static func _pad(s: String, width: int) -> String:
    var pad: int = width - s.length()
    if pad <= 0:
        return s
    return s + " ".repeat(pad)
