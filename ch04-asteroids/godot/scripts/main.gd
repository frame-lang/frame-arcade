# ============================================================
# Asteroids — Godot driver (main.gd)
# ============================================================
# Owns an Asteroids state machine, handles ship physics
# (rotation, thrust, inertia, screen wrap), renders asteroids
# and bullets, detects collisions.
# ============================================================
extends Node2D

const AsteroidsFSM = preload("res://scripts/asteroids.gd")

# --- Court / display ---
@export var court_size: Vector2 = Vector2(800, 600)

# --- Ship tunables ---
@export var ship_thrust: float = 240.0       # acceleration per second while thrusting
@export var ship_rotation_speed: float = 4.0  # radians per second
@export var ship_max_speed: float = 320.0
@export var ship_drag: float = 0.5            # fraction of velocity lost per second
@export var ship_shot_cooldown: float = 0.25
@export var ship_size: float = 14.0

# --- Bullet tunables ---
@export var bullet_speed: float = 500.0
@export var bullet_lifetime: float = 1.2
@export var bullet_size: float = 2.0

# --- Difficulty: 1=easy, 2=normal, 3=hard ---
@export var difficulty: int = 2

# --- Runtime state ---
var fsm
var ship_pos: Vector2
var ship_vel: Vector2
var ship_angle: float = -PI * 0.5      # pointing up
var ship_shot_timer: float = 0.0
var bullets: Array = []                # each: { pos: Vector2, vel: Vector2, life: float }
var _p_was_down: bool = false
var _h_was_down: bool = false
var _last_ship_state: String = "alive"

# --- UI ---
var label_hud: Label
var label_center: Label

# ============================================================
func _ready() -> void:
    fsm = AsteroidsFSM.new(difficulty)
    _build_ui()
    _reset_ship()

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_hud = Label.new()
    label_hud.add_theme_font_size_override("font_size", 18)
    label_hud.position = Vector2(10, 6)
    label_hud.size = Vector2(court_size.x - 20, 28)
    canvas.add_child(label_hud)

    label_center = Label.new()
    label_center.add_theme_font_size_override("font_size", 28)
    label_center.position = Vector2(0, court_size.y * 0.4)
    label_center.size = Vector2(court_size.x, 120)
    label_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    canvas.add_child(label_center)

# ============================================================
func _physics_process(delta: float) -> void:
    _handle_input(delta)

    var state: String = fsm.get_state()

    if not fsm.is_paused() and state != "attract" and state != "game_over":
        fsm.tick(delta, court_size)

        # Ship physics — integrate velocity, wrap screen
        _update_ship(delta)
        _update_bullets(delta)

        _check_collisions()

    _update_labels()
    queue_redraw()

# ============================================================
func _handle_input(delta: float) -> void:
    var state: String = fsm.get_state()

    if state == "attract":
        if Input.is_anything_pressed():
            fsm.start()
            _reset_ship()
            bullets.clear()
        return

    if state == "game_over":
        if Input.is_key_pressed(KEY_R):
            fsm.restart()
        return

    # Pause toggle (edge-detected)
    if Input.is_key_pressed(KEY_P) and not _p_was_down:
        _p_was_down = true
        if fsm.is_paused():
            fsm.resume()
        else:
            fsm.pause()
    elif not Input.is_key_pressed(KEY_P):
        _p_was_down = false

    if fsm.is_paused():
        return

    # Ship controls only work when ship can do things
    if not fsm.ship.is_visible():
        return

    # Rotation
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        ship_angle -= ship_rotation_speed * delta
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        ship_angle += ship_rotation_speed * delta

    # Thrust
    if fsm.ship.get_state() == "alive" or fsm.ship.get_state() == "respawning":
        if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
            ship_vel += Vector2(cos(ship_angle), sin(ship_angle)) * ship_thrust * delta
            # Cap speed
            if ship_vel.length() > ship_max_speed:
                ship_vel = ship_vel.normalized() * ship_max_speed

    # Fire
    ship_shot_timer = max(0.0, ship_shot_timer - delta)
    if fsm.ship.can_fire():
        if Input.is_key_pressed(KEY_SPACE):
            _try_fire()

    # Hyperspace (edge-detected to avoid repeated triggers)
    if Input.is_key_pressed(KEY_H) and not _h_was_down:
        _h_was_down = true
        fsm.ship_hyperspace()
    elif not Input.is_key_pressed(KEY_H):
        _h_was_down = false

# ============================================================
func _update_ship(delta: float) -> void:
    if not fsm.ship.is_visible():
        return

    # Drag
    ship_vel *= (1.0 - ship_drag * delta)

    # Integrate
    ship_pos += ship_vel * delta

    # Wrap
    if ship_pos.x < 0.0:           ship_pos.x += court_size.x
    if ship_pos.x > court_size.x:  ship_pos.x -= court_size.x
    if ship_pos.y < 0.0:           ship_pos.y += court_size.y
    if ship_pos.y > court_size.y:  ship_pos.y -= court_size.y

    # If we just came back from hyperspace, teleport to a random spot.
    # We detect that by checking if the ship is $Alive but its previous
    # state was InHyperspace. Since we don't expose "just popped" from
    # the Frame system, we fake it: pushing hyperspace stashes current
    # ship_pos; when ship is $Alive again and _last_ship_state ==
    # hyperspace, we randomize. See notes in the chapter README about
    # how this could be cleaner.
    var current_state: String = fsm.ship.get_state()
    if _last_ship_state == "hyperspace" and current_state == "alive":
        ship_pos = Vector2(randf() * court_size.x, randf() * court_size.y)
        ship_vel = Vector2.ZERO
    _last_ship_state = current_state

func _reset_ship() -> void:
    ship_pos = court_size * 0.5
    ship_vel = Vector2.ZERO
    ship_angle = -PI * 0.5
    ship_shot_timer = 0.0
    _last_ship_state = "alive"

# ============================================================
func _try_fire() -> void:
    if ship_shot_timer > 0.0:
        return
    # Classic Asteroids: 4 bullets max on screen
    if bullets.size() >= 4:
        return
    var dir := Vector2(cos(ship_angle), sin(ship_angle))
    var muzzle := ship_pos + dir * ship_size
    bullets.append({
        "pos": muzzle,
        "vel": dir * bullet_speed + ship_vel,
        "life": 0.0,
    })
    ship_shot_timer = ship_shot_cooldown

func _update_bullets(delta: float) -> void:
    var i: int = bullets.size() - 1
    while i >= 0:
        var b: Dictionary = bullets[i]
        b.pos = b.pos + b.vel * delta
        b.life = b.life + delta
        # Wrap bullets too, for satisfying feel
        if b.pos.x < 0.0:           b.pos.x += court_size.x
        if b.pos.x > court_size.x:  b.pos.x -= court_size.x
        if b.pos.y < 0.0:           b.pos.y += court_size.y
        if b.pos.y > court_size.y:  b.pos.y -= court_size.y
        bullets[i] = b
        if b.life >= bullet_lifetime:
            bullets.remove_at(i)
        i -= 1

# ============================================================
func _check_collisions() -> void:
    var total: int = fsm.field.count()

    # Bullets vs. asteroids
    var bi: int = bullets.size() - 1
    while bi >= 0:
        var hit: int = -1
        var i: int = 0
        while i < total:
            if fsm.field.is_alive(i):
                var ap: Vector2 = fsm.field.position(i)
                var ar: float = fsm.field.radius_of(i)
                if ap.distance_to(bullets[bi].pos) < ar:
                    hit = i
                    break
            i += 1
        if hit >= 0:
            fsm.bullet_hit_asteroid(hit)
            bullets.remove_at(bi)
        bi -= 1

    # Ship vs. asteroids
    if fsm.ship.can_be_hit():
        var i: int = 0
        while i < total:
            if fsm.field.is_alive(i):
                var ap: Vector2 = fsm.field.position(i)
                var ar: float = fsm.field.radius_of(i)
                if ap.distance_to(ship_pos) < ar + ship_size * 0.6:
                    fsm.ship_hit_asteroid(i)
                    break
            i += 1

# ============================================================
func _update_labels() -> void:
    label_hud.text = "SCORE  %05d     LIVES  %d     WAVE  %d     DIFF  %d" % [
        fsm.get_score(), fsm.get_lives(), fsm.get_wave(), fsm.get_difficulty()]

    match fsm.get_state():
        "attract":
            label_center.text = "A S T E R O I D S\n\nPress any key to start\n(H = hyperspace, P = pause)"
        "playing":
            label_center.text = ""
        "ship_dying":
            label_center.text = ""
        "wave_clear":
            label_center.text = "WAVE CLEAR"
        "paused":
            label_center.text = "PAUSED"
        "game_over":
            label_center.text = "GAME OVER\n\nPress R to restart"
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    var white := Color(1, 1, 1)
    var dim := Color(0.7, 0.7, 0.7)
    var state: String = fsm.get_state()

    # Asteroids
    var total: int = fsm.field.count()
    var i: int = 0
    while i < total:
        if fsm.field.is_alive(i):
            var pos: Vector2 = fsm.field.position(i)
            var radius: float = fsm.field.radius_of(i)
            _draw_asteroid(pos, radius)
        i += 1

    # Bullets
    for b in bullets:
        draw_circle(b.pos, bullet_size, white)

    # Ship
    if state != "attract" and state != "game_over" and fsm.ship.is_visible():
        var ship_state: String = fsm.ship.get_state()
        if ship_state == "exploding":
            _draw_explosion(ship_pos)
        else:
            # Blink while respawning to signal invuln
            var visible: bool = true
            if ship_state == "respawning":
                visible = int(Time.get_ticks_msec() / 100) % 2 == 0
            if visible:
                _draw_ship(ship_pos, ship_angle)

func _draw_ship(at: Vector2, angle: float) -> void:
    # Classic triangle ship
    var white := Color(1, 1, 1)
    var nose: Vector2 = at + Vector2(cos(angle), sin(angle)) * ship_size
    var left: Vector2 = at + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * ship_size
    var right: Vector2 = at + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * ship_size
    draw_line(nose, left, white, 1.5)
    draw_line(left, right, white, 1.5)
    draw_line(right, nose, white, 1.5)

    # Thruster flame while thrusting
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
        if fsm.ship.get_state() == "alive" or fsm.ship.get_state() == "respawning":
            var tail_base: Vector2 = (left + right) * 0.5
            var tail_tip: Vector2 = at - Vector2(cos(angle), sin(angle)) * ship_size * 1.4
            draw_line(tail_base, tail_tip, Color(1, 0.6, 0.2), 1.5)

func _draw_asteroid(at: Vector2, radius: float) -> void:
    # Simple jagged polygon — 8 points with randomized radii
    var white := Color(1, 1, 1)
    var points := PackedVector2Array()
    var n: int = 10
    var i: int = 0
    # Stable hash from position so the shape doesn't flicker
    var seed_h: int = int(at.x * 100) + int(at.y * 100) * 31
    while i < n:
        var t: float = (float(i) / float(n)) * TAU
        var jitter: float = 0.75 + _hash01(seed_h + i) * 0.35
        var p: Vector2 = at + Vector2(cos(t), sin(t)) * radius * jitter
        points.append(p)
        i += 1
    # Close the shape
    i = 0
    while i < n:
        var p1: Vector2 = points[i]
        var p2: Vector2 = points[(i + 1) % n]
        draw_line(p1, p2, white, 1.5)
        i += 1

func _hash01(k: int) -> float:
    # Cheap deterministic hash to [0, 1)
    var x: int = (k * 2654435761) & 0xffffffff
    x = ((x >> 16) ^ x) * 0x45d9f3b
    x = x & 0xffffffff
    return float(x & 0xffff) / 65536.0

func _draw_explosion(at: Vector2) -> void:
    var col := Color(1, 0.7, 0.3)
    # Radiating lines
    var i: int = 0
    while i < 8:
        var t: float = float(i) / 8.0 * TAU
        var p1: Vector2 = at + Vector2(cos(t), sin(t)) * 4.0
        var p2: Vector2 = at + Vector2(cos(t), sin(t)) * 14.0
        draw_line(p1, p2, col, 2.0)
        i += 1
