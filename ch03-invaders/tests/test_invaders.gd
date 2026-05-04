extends SceneTree

# Smoke test for ch03-invaders' three-system composition with HSM.
# Verifies:
#   - Player lifecycle: $Alive → $Exploding (timed) → $Invulnerable
#     (timed) → $Alive; out of lives → $Dead.
#   - Fleet: reset, kill_invader, alive_count, defeat threshold,
#     direction reversal at edge, step-interval speedup as
#     invaders die.
#   - Invaders HSM: $Attract → $Playing → $WaveComplete → $Playing
#     (next wave) ... pause/resume covers $InGame → $Paused → back.

const Invaders = preload("res://scripts/invaders.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _expect_lt(label: String, actual: float, threshold: float) -> void:
    if actual < threshold:
        print("  ok   %-44s = %s (< %s)" % [label, str(actual), str(threshold)])
    else:
        print("  FAIL %-44s = %s (expected < %s)" % [label, str(actual), str(threshold)])
        failures += 1

func _init():
    print("=== Space Invaders three-system + HSM ===")

    # --- Player FSM directly ---
    var Player = load("res://scripts/invaders.gd").Player
    var p = Player.new()
    _expect("player initial",      p.get_state(),   "alive")
    _expect("can fire",            p.can_fire(),    true)
    _expect("can be hit",          p.can_be_hit(),  true)
    _expect("3 lives",             p.get_lives(),   3)

    p.hit()
    _expect("after hit",           p.get_state(),   "exploding")
    _expect("can't fire",          p.can_fire(),    false)
    _expect("can't be hit",        p.can_be_hit(),  false)

    # Tick past the 1.2s explosion duration → invulnerable
    p.tick(0.7)
    p.tick(0.7)
    _expect("after explosion",     p.get_state(),   "invulnerable")
    _expect("2 lives",             p.get_lives(),   2)
    _expect("can fire while invuln", p.can_fire(),  true)
    _expect("can't be hit while invuln", p.can_be_hit(), false)

    # Tick past 1.5s invuln duration → alive
    p.tick(0.8)
    p.tick(0.8)
    _expect("back to alive",       p.get_state(),   "alive")

    # Drain to dead
    p.hit()
    p.tick(1.5); p.tick(1.5)         # explode → invuln (1 life)
    p.tick(1.5); p.tick(1.5)         # invuln → alive
    p.hit()
    p.tick(1.5); p.tick(1.5)         # explode → dead (0 lives)
    _expect("0 lives → dead",      p.get_state(),   "dead")
    _expect("0 lives",             p.get_lives(),   0)

    p.respawn()
    _expect("respawned",           p.get_state(),   "alive")
    _expect("3 lives again",       p.get_lives(),   3)

    # --- Fleet FSM directly ---
    var Fleet = load("res://scripts/invaders.gd").Fleet
    var f = Fleet.new()
    f.reset(2, 3)                    # tiny test fleet: 6 invaders
    _expect("fleet marching",      f.get_state(),       "marching")
    _expect("6 alive",             f.alive_count(),     6)
    _expect("direction +1",        f.get_direction(),   1)
    var initial_step: float = f.get_step_interval()

    # Kill some — pace speeds up
    f.kill_invader(0)
    f.kill_invader(1)
    f.kill_invader(2)
    _expect("3 alive",             f.alive_count(),     3)
    _expect_lt("step interval shrunk", f.get_step_interval(), initial_step)

    # Edge reached → reverse direction (transient $Stepping)
    f.edge_reached()
    f.tick(0.0)                      # transient state advances
    _expect("back to marching",    f.get_state(),       "marching")
    _expect("direction reversed",  f.get_direction(),   -1)

    # Kill the rest → defeat
    f.kill_invader(3)
    f.kill_invader(4)
    f.kill_invader(5)
    _expect("fleet defeated",      f.get_state(),       "defeated")
    _expect("0 alive",             f.alive_count(),     0)

    # --- Invaders HSM orchestration ---
    var inv = Invaders.new()
    _expect("invaders attract",    inv.get_state(),     "attract")
    _expect("score 0",             inv.get_score(),     0)
    _expect("wave 1",              inv.get_wave(),      1)

    inv.start()
    _expect("playing",             inv.get_state(),     "playing")

    # Pause/resume routes through HSM parent ($InGame)
    inv.pause()
    _expect("paused",              inv.get_state(),     "paused")
    _expect("is_paused",           inv.is_paused(),     true)
    inv.resume()
    _expect("after resume",        inv.get_state(),     "playing")

    # Kill enough invaders to clear the wave (default fleet 5x11=55).
    # We use direct fleet access from the FSM's domain to grab the
    # right indices — driver normally figures these out from
    # collisions.
    var i = 0
    while i < 55:
        inv.player_killed_invader(i)
        i = i + 1
    _expect("wave complete",       inv.get_state(),     "wave_complete")
    _expect("score 55*10",         inv.get_score(),     550)

    # Tick past the 2.0s wave pause → $Playing wave 2
    inv.tick(1.1)
    inv.tick(1.1)
    _expect("wave 2 playing",      inv.get_state(),     "playing")
    _expect("wave 2",              inv.get_wave(),      2)

    # Player hit triggers $PlayerDying via HSM child
    inv.player_hit()
    _expect("player dying",        inv.get_state(),     "player_dying")

    # Restart from game over
    inv.fleet_reached_bottom()
    _expect("game over",           inv.get_state(),     "game_over")
    inv.restart()
    _expect("restart → attract",   inv.get_state(),     "attract")
    _expect("score reset",         inv.get_score(),     0)
    _expect("wave reset",          inv.get_wave(),      1)

    print()
    if failures == 0:
        print("PASS — Invaders smoke complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
