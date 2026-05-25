extends SceneTree

# Smoke test for ch02-breakout's three-system composition.
# Verifies:
#   - Ball lifecycle: $AttachedToPaddle → $InFlight → $Lost → attach.
#   - Ball state-variable velocity: launch sets it, bounce flips it.
#   - BrickField: reset, break_brick, remaining, is_cleared.
#   - Breakout orchestration: $Attract → start → $Playing → bricks
#     all hit → $LevelClear → start → $Playing → ball lost N
#     times → $GameOver → restart → $Attract.

const Breakout = preload("res://scripts/breakout.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _expect_close(label: String, actual: float, expected: float) -> void:
    if abs(actual - expected) < 0.001:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== Breakout three-system orchestration ===")

    # --- Ball directly: $AttachedToPaddle → $InFlight → bounces → $Lost ---
    var Ball = load("res://scripts/breakout.gd").Ball
    var ball = Ball.new()
    _expect("ball initial",        ball.get_state(),   "attached")
    _expect("vx zero",             ball.get_vx(),      0.0)
    ball.launch(150.0, -200.0)
    _expect("after launch state",  ball.get_state(),   "in_flight")
    _expect_close("vx after launch", ball.get_vx(),    150.0)
    _expect_close("vy after launch", ball.get_vy(),   -200.0)
    ball.bounce_x()
    _expect_close("vx after bounce_x", ball.get_vx(), -150.0)
    ball.bounce_y()
    _expect_close("vy after bounce_y", ball.get_vy(),  200.0)
    ball.lose()
    _expect("after lose",          ball.get_state(),   "lost")
    _expect("vx zero in lost",     ball.get_vx(),      0.0)
    ball.attach()
    _expect("after attach",        ball.get_state(),   "attached")

    # --- BrickField directly ---
    var BrickField = load("res://scripts/breakout.gd").BrickField
    var bf = BrickField.new()
    bf.reset(5)
    _expect("5 bricks remaining", bf.remaining(),     5)
    _expect("not cleared",        bf.is_cleared(),    false)
    _expect("brick 0 not broken", bf.is_broken(0),    false)
    var hit0 = bf.break_brick(0)
    _expect("first hit returns true", hit0,           true)
    _expect("brick 0 broken now", bf.is_broken(0),    true)
    _expect("4 remaining",        bf.remaining(),     4)
    var hit0_again = bf.break_brick(0)
    _expect("second hit returns false", hit0_again,   false)
    _expect("4 remaining still", bf.remaining(),      4)

    # --- Breakout orchestration ---
    var bo = Breakout.new()
    _expect("attract initial",   bo.get_state(),       "attract")
    _expect("score 0",           bo.get_score(),       0)
    _expect("lives 3",           bo.get_lives(),       3)
    _expect("level 1",           bo.get_level(),       1)

    bo.start()
    _expect("after start",       bo.get_state(),       "playing")
    _expect("ball attached",     bo.ball_state(),      "attached")

    bo.launch_ball(100.0, -100.0)
    _expect("ball in flight",    bo.ball_state(),      "in_flight")

    # pause()/resume() via push$/pop$: must pop back to $Playing
    # with the ball still in flight (state preserved across pause).
    bo.pause()
    _expect("paused",            bo.get_state(),       "paused")
    bo.resume()
    _expect("resume → playing",  bo.get_state(),       "playing")
    _expect("ball still flying", bo.ball_state(),      "in_flight")

    # Hit a few bricks (default field is 40)
    bo.brick_hit(0)
    bo.brick_hit(1)
    bo.brick_hit(2)
    _expect("score 30",          bo.get_score(),       30)
    _expect("37 remaining",      bo.bricks_remaining(), 37)

    # Ball falls off, lives decrements. The FSM's ball_fell_off
    # decrements lives and calls ball.attach() — but attach is
    # only valid from $Lost; the ball is currently $InFlight.
    # The driver layer calls ball.lose() outside the FSM to
    # park the ball on the paddle. We test the FSM contract
    # only: lives drops by 1.
    bo.ball_fell_off()
    _expect("lives 2",           bo.get_lives(),       2)

    # Clear all remaining bricks → $LevelClear
    bo.launch_ball(100.0, -100.0)
    var i = 3
    while i < 40:
        bo.brick_hit(i)
        i = i + 1
    _expect("level cleared state", bo.get_state(),     "level_clear")
    _expect("level incremented", bo.get_level(),       2)
    _expect("score = 40 * 10",   bo.get_score(),       400)

    # Start the next level
    bo.start()
    _expect("playing again",     bo.get_state(),       "playing")
    _expect("40 bricks back",    bo.bricks_remaining(), 40)

    # Drain to game over
    bo.launch_ball(100.0, -100.0)
    bo.ball_fell_off()
    bo.ball_fell_off()
    _expect("game over",         bo.get_state(),       "game_over")
    _expect("lives 0",           bo.get_lives(),       0)

    bo.restart()
    _expect("back to attract",   bo.get_state(),       "attract")
    _expect("score reset",       bo.get_score(),       0)
    _expect("lives reset",       bo.get_lives(),       3)
    _expect("level reset",       bo.get_level(),       1)

    print()
    if failures == 0:
        print("PASS — Breakout orchestration smoke complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
