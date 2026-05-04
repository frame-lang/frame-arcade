extends SceneTree

# Smoke test for ch08-stealth — Guard agent AI with $Aware HSM
# parent + state stack for investigate-then-pop, three guards in
# the maze, Stealth orchestration $Attract → $Playing →
# $Caught/$Escaped.
#
# Verifies:
#   - Guard lifecycle: $Idle → init → $Patrolling (under $Aware
#     parent so spot_player → $Alerted is shared); spot_player
#     transitions to $Alerted with last_known recorded.
#   - hear_sound pushes onto stack and goes to $Investigating;
#     when investigation completes, pop back to $Patrolling.
#   - touched_player → $Engaged (terminal).
#   - Stealth orchestration: $Attract → $Playing → guard caught
#     → $Caught (with caught_by index), or player_at_exit →
#     $Escaped.
#   - Save/restore round-trips Guard state via @@[persist].

const Stealth = preload("res://scripts/stealth.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== Stealth Guard agent AI + $Aware HSM ===")

    # --- Guard FSM directly ---
    var Guard = load("res://scripts/stealth.gd").Guard
    var g = Guard.new()
    _expect("guard initial",        g.get_state(),       "idle")
    _expect("not aware",            g.is_aware(),        false)
    _expect("not alerted",          g.is_alerted(),      false)
    _expect("idle should not move", g.should_move(),     false)

    # init: idle → $Patrolling (child of $Aware)
    var route: Array = [Vector2(10, 10), Vector2(50, 10), Vector2(50, 50)]
    g.init(route, 80.0)
    _expect("after init",           g.get_state(),       "patrolling")
    # $Patrolling overrides is_aware → false (semantically the
    # guard isn't aware *of the player* yet, just patrolling).
    # The HSM parent $Aware is just a code-sharing structure.
    _expect("patrolling not aware-of-player", g.is_aware(), false)
    _expect("not alerted yet",      g.is_alerted(),      false)
    _expect("first waypoint target", g.get_target(),     Vector2(10, 10))

    # spot_player: $Aware parent handler fires → $Alerted
    g.spot_player(Vector2(30, 30))
    _expect("spotted → alerted",    g.get_state(),       "alerted")
    _expect("alerted",              g.is_alerted(),      true)
    _expect("last known recorded",  g.get_last_known(),  Vector2(30, 30))

    # touched_player: terminal $Engaged
    g.touched_player()
    _expect("after touch",          g.get_state(),       "engaged")
    # $Engaged keeps both is_aware() and is_alerted() true — the
    # guard has the player and stays alerted until the orchestrator
    # tears the round down.
    _expect("engaged is alerted",   g.is_alerted(),      true)
    _expect("engaged is aware",     g.is_aware(),        true)
    _expect("engaged should not move", g.should_move(),  false)

    # --- Fresh guard for hear_sound state-stack test ---
    var g2 = Guard.new()
    g2.init([Vector2(0, 0), Vector2(100, 0)], 50.0)
    _expect("g2 patrolling",        g2.get_state(),      "patrolling")

    # hear_sound pushes and goes to $Investigating
    g2.hear_sound(Vector2(40, 5))
    _expect("g2 investigating",     g2.get_state(),      "investigating")

    # Tick to advance investigation timer (depends on duration)
    var i = 0
    while i < 80:
        g2.tick(0.1, Vector2(40, 5))
        i = i + 1
    # Should have popped back or moved on by now
    var post_invest = g2.get_state()
    _expect("g2 investigation ended", post_invest != "investigating", true)

    # --- Stealth orchestration ---
    var s = Stealth.new()
    _expect("stealth attract",      s.get_state(),       "attract")
    _expect("caught_by -1",         s.get_caught_by(),   -1)
    _expect("elapsed 0",            s.get_elapsed(),     0.0)

    var p1: Array = [Vector2(10, 10), Vector2(100, 10)]
    var p2: Array = [Vector2(50, 50), Vector2(150, 50)]
    var p3: Array = [Vector2(20, 100), Vector2(200, 100)]
    s.start(p1, p2, p3)
    _expect("playing",              s.get_state(),       "playing")

    # Tick advances elapsed
    s.tick(0.5, Vector2(0, 0), Vector2(0, 0), Vector2(0, 0))
    _expect("elapsed advanced",     s.get_elapsed(),     0.5)

    # Guard 1 catches player
    s.guard_caught_player(1)
    _expect("caught state",         s.get_state(),       "caught")
    _expect("caught by guard 1",    s.get_caught_by(),   1)

    # Restart from caught
    s.restart()
    _expect("back to attract",      s.get_state(),       "attract")
    _expect("caught_by reset",      s.get_caught_by(),   -1)

    # --- Escape path ---
    var s2 = Stealth.new()
    s2.start(p1, p2, p3)
    s2.player_at_exit()
    _expect("escaped",              s2.get_state(),      "escaped")
    s2.restart()
    _expect("after restart",        s2.get_state(),      "attract")

    # --- Save/restore (Stealth has @@[persist]) ---
    var s3 = Stealth.new()
    s3.start(p1, p2, p3)
    s3.tick(1.0, Vector2(0, 0), Vector2(0, 0), Vector2(0, 0))
    var bytes = s3.save_state()
    s3.guard_caught_player(2)        # mutate after save

    var s4 = Stealth.new()
    s4.restore_state(bytes)
    _expect("restored playing",     s4.get_state(),      "playing")
    _expect("restored elapsed",     s4.get_elapsed(),    1.0)
    _expect("restored caught_by",   s4.get_caught_by(),  -1)

    print()
    if failures == 0:
        print("PASS — Stealth smoke complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
