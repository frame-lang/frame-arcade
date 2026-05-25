extends SceneTree

# Smoke test for ch01-pong's Pong FSM.
# Verifies the lifecycle: AttractMode → Serving → InPlay →
# PointScored → Serving → ... → GameOver → AttractMode.

const Pong = preload("res://scripts/pong.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== Pong FSM ===")

    # --- Initial: AttractMode, scores zeroed, not playing ---
    var p = Pong.new()
    _expect("initial state",     p.get_state(),       "attract")
    _expect("score left",        p.get_score_left(),  0)
    _expect("score right",       p.get_score_right(), 0)
    _expect("not playing",       p.is_playing(),      false)
    _expect("no winner",         p.get_winner(),      "")

    # --- start() → Serving ---
    p.start()
    _expect("after start",       p.get_state(),       "serving")
    _expect("not playing yet",   p.is_playing(),      false)

    # --- pause from Serving pops back to Serving ---
    p.pause()
    _expect("paused from serving", p.get_state(),     "paused")
    p.resume()
    _expect("resume → serving",    p.get_state(),     "serving")

    # --- launch() → InPlay ---
    p.launch()
    _expect("after launch",      p.get_state(),       "in_play")
    _expect("playing",           p.is_playing(),      true)

    # --- pause()/resume() via push$/pop$: must pop back to the
    #     state that paused (InPlay here), not a hardcoded state ---
    p.pause()
    _expect("paused from in_play", p.get_state(),     "paused")
    _expect("paused not playing",  p.is_playing(),    false)
    p.resume()
    _expect("resume → in_play",    p.get_state(),     "in_play")
    _expect("playing again",       p.is_playing(),    true)

    # --- Right scores: ball_out_left ---
    p.ball_out_left()
    # PointScored is a transient state — its $> handler decides
    # next state. Since neither side has reached 11, we should
    # be back in $Serving by now.
    _expect("after right scores", p.get_state(),      "serving")
    _expect("score right",       p.get_score_right(), 1)
    _expect("score left",        p.get_score_left(),  0)
    _expect("serve toward left", p.get_serve_direction(), -1)

    # --- Several more rallies, alternating scores ---
    p.launch()
    p.ball_out_right()
    _expect("score left",        p.get_score_left(),  1)
    p.launch()
    p.ball_out_left()
    p.launch()
    p.ball_out_left()
    _expect("score right at 3",  p.get_score_right(), 3)

    # --- Drive right to winning score (11) ---
    for i in range(8):
        p.launch()
        p.ball_out_left()
    _expect("right reached 11",  p.get_score_right(), 11)
    _expect("game over",         p.get_state(),       "game_over")
    _expect("winner is right",   p.get_winner(),      "right")
    _expect("not playing",       p.is_playing(),      false)

    # --- restart() → AttractMode, scores zeroed ---
    p.restart()
    _expect("after restart",     p.get_state(),       "attract")
    _expect("scores cleared L",  p.get_score_left(),  0)
    _expect("scores cleared R",  p.get_score_right(), 0)
    _expect("winner cleared",    p.get_winner(),      "")

    # --- Second game: left wins ---
    p.start()
    for i in range(11):
        p.launch()
        p.ball_out_right()
    _expect("left reached 11",   p.get_score_left(),  11)
    _expect("game over again",   p.get_state(),       "game_over")
    _expect("winner is left",    p.get_winner(),      "left")

    print()
    if failures == 0:
        print("PASS — Pong FSM smoke complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
