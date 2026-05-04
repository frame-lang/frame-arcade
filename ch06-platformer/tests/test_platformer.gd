extends SceneTree

# Smoke test for ch06-platformer — orthogonal-state composition:
# Locomotion (motion FSM) and PowerUp (form FSM) live as
# independent sub-systems under Player. Demonstrates the
# "two-FSMs-instead-of-product-state" alternative to HSM.
#
# Verifies:
#   - Locomotion: $Idle ↔ $Walking ↔ $Running on press/release;
#     $Idle/$Walking → $Jumping → $Falling → $Landing/$Idle.
#   - Facing direction tracks the last horizontal press.
#   - PowerUp: $Small → mushroom → $Big → flower → $Fiery; damage
#     decays one tier; reset → $Small.
#   - Player composition: forwards events to right sub-FSM,
#     queries blend both ('locomotion_state' + 'form').

const Player = preload("res://scripts/platformer.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== Platformer two-FSM composition (Locomotion + PowerUp) ===")

    # --- Locomotion FSM directly ---
    var Locomotion = load("res://scripts/platformer.gd").Locomotion
    var loco = Locomotion.new()
    _expect("loco initial",         loco.get_state(),    "idle")
    _expect("idle wants vx 0",      loco.wants_velocity_x(),  0.0)
    _expect("idle grounded",        loco.is_grounded(),  true)
    _expect("idle facing default",  loco.facing(),       1)

    loco.press_right()
    _expect("after press_right",    loco.get_state(),    "walking")
    _expect("walk vx > 0",          loco.wants_velocity_x() > 0.0, true)
    _expect("facing right",         loco.facing(),       1)

    loco.press_left()
    _expect("walking left",         loco.get_state(),    "walking")
    _expect("walk vx < 0",          loco.wants_velocity_x() < 0.0, true)
    _expect("facing left",          loco.facing(),       -1)

    loco.press_sprint()
    _expect("running",              loco.get_state(),    "running")

    loco.release_sprint()
    # Released sprint while still pressing → walking
    _expect("back to walking",      loco.get_state(),    "walking")

    loco.release_horizontal()
    _expect("idle after release",   loco.get_state(),    "idle")

    # Jump → Falling → Landing/Idle
    loco.press_jump()
    _expect("jumping",              loco.get_state(),    "jumping")
    _expect("wants jump impulse",   loco.wants_jump_impulse(), true)
    loco.consume_jump_impulse()
    _expect("impulse consumed",     loco.wants_jump_impulse(), false)

    # Tick to apex/falling. Test relies on tick advancing physics.
    var i = 0
    while i < 60:
        loco.tick(0.016)
        i = i + 1
    # Should have transitioned out of jumping by now
    _expect("not jumping after 1s", loco.get_state() == "jumping", false)

    # Drop back to ground via ground_contact
    loco.ground_contact()
    # State could be $Landing or $Idle (depending on transition)
    var grounded_state = loco.get_state()
    _expect("grounded post contact", loco.is_grounded() or grounded_state == "landing", true)

    # --- PowerUp FSM directly ---
    var PowerUp = load("res://scripts/platformer.gd").PowerUp
    var power = PowerUp.new()
    _expect("power initial",        power.get_form(),    "small")
    _expect("small can't shoot",    power.can_shoot(),   false)
    _expect("small hitbox 24",      power.hit_box_height(), 24)

    power.pickup_mushroom()
    _expect("now big",              power.get_form(),    "big")
    _expect("big hitbox 48",        power.hit_box_height(), 48)

    power.pickup_mushroom()
    _expect("still big",            power.get_form(),    "big")

    power.pickup_flower()
    _expect("now fiery",            power.get_form(),    "fiery")
    _expect("fiery can shoot",      power.can_shoot(),   true)

    var still_alive = power.take_damage()
    _expect("damage from fiery: alive", still_alive,     true)
    _expect("decayed to big",       power.get_form(),    "big")

    var still_alive2 = power.take_damage()
    _expect("damage from big: alive", still_alive2,      true)
    _expect("decayed to small",     power.get_form(),    "small")

    var dead = power.take_damage()
    _expect("damage from small: dead", dead,             false)
    _expect("still small (driver kills)", power.get_form(), "small")

    power.pickup_flower()
    power.reset()
    _expect("reset to small",       power.get_form(),    "small")

    # --- Player orchestrates both sub-FSMs ---
    var p = Player.new()
    _expect("player loco",          p.locomotion_state(), "idle")
    _expect("player form",          p.form(),             "small")

    p.press_right()
    _expect("player walking",       p.locomotion_state(), "walking")
    _expect("player facing right",  p.facing(),           1)

    p.pickup_mushroom()
    _expect("player big now",       p.form(),             "big")
    _expect("player hitbox 48",     p.hit_box_height(),   48)

    var alive = p.take_damage()
    _expect("damage returns true",  alive,                true)
    _expect("decayed to small",     p.form(),             "small")

    print()
    if failures == 0:
        print("PASS — Platformer two-FSM smoke complete")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)
