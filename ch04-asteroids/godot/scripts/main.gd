# ============================================================
# Asteroids — Godot driver (main.gd)
# ============================================================
# Owns an Asteroids state machine, handles ship physics
# (rotation, thrust, inertia, screen wrap), renders asteroids
# and bullets, detects collisions.
# ============================================================
extends Node2D

const AsteroidsFSM = preload("res://scripts/asteroids.gd")

# Palette matched to the JS (Phaser) build so both runtimes look the same.
# JS hex values: bg #0b0e14, ship 0x8ab4f8, asteroid stroke 0x9aa4b8.
const COL_BG     := Color(0, 0, 0, 1)
const COL_SHIP   := Color(0x8a / 255.0, 0xb4 / 255.0, 0xf8 / 255.0)
const COL_ROCK   := Color(0x9a / 255.0, 0xa4 / 255.0, 0xb8 / 255.0)
const COL_BULLET := Color(1, 1, 1)
const COL_FLAME  := Color(1, 0.68, 0.26)

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

# --- UI ---
var label_hud: Label
var label_center: Label

# ============================================================
func _ready() -> void:
    # Parameterized Frame systems pass args via the static _create factory —
    # `_init` itself takes no args. Calling `.new(difficulty)` throws "too
    # many args for '_init'" at scene load, crashes _ready silently, and the
    # Godot web export then shows nothing but the canvas clear color (a
    # grey box). Stick with _create.
    # `self` is the ship_host. Ship's $> / <$ handlers will call back into
    # the public methods below (spawn_explosion / reset_ship / warp_out /
    # warp_in). The .fjs and .fgd Ship bodies are identical; only the host
    # implementations differ per renderer.
    fsm = AsteroidsFSM._create(difficulty, self)
    # Match the JS (Phaser) build's near-black background instead of Godot's
    # default grey. RenderingServer applies it once for the whole project.
    RenderingServer.set_default_clear_color(COL_BG)
    _build_ui()
    reset_ship()

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

    var state: String = fsm.get_current_state_name()

    if not fsm.is_paused() and state != "Attract" and state != "GameOver":
        fsm.tick(delta, court_size)

        # Ship physics — integrate velocity, wrap screen
        _update_ship(delta)
        _update_bullets(delta)

        _check_collisions()

    _update_labels()
    queue_redraw()

# ============================================================
func _handle_input(delta: float) -> void:
    var state: String = fsm.get_current_state_name()

    if state == "Attract":
        if Input.is_anything_pressed():
            # start() → $Playing → ship.respawn() → $Alive (or transitively
            # via $Respawning). Whichever Ship state we land in, the FSM
            # is now the authority for the sprite — bullets are still
            # ours to clear because the orchestrator doesn't know about
            # them.
            fsm.start()
            bullets.clear()
        return

    if state == "GameOver":
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
    if fsm.ship.get_current_state_name() == "Alive" or fsm.ship.get_current_state_name() == "Respawning":
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
    # Movement is pure pull: read is_visible(), drag, integrate, wrap. The
    # InHyperspace -> Alive transition no longer needs detecting here —
    # $InHyperspace.$>() in the Frame source calls warp_out() directly,
    # which moves the sprite at the moment the FSM enters that state.
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

# ============================================================
# ShipHost surface — Frame's Ship system calls these from its $> / <$
# handlers via the `host` parameter wired in _ready(). Each is a one-shot
# moment at a state boundary, NOT a per-frame predicate.

# Ship.$Respawning.$>() — centre the ship, zero its velocity, clear bullets.
# Also the boot-time setup (called from _ready before any FSM event).
func reset_ship() -> void:
    ship_pos = court_size * 0.5
    ship_vel = Vector2.ZERO
    ship_angle = -PI * 0.5
    ship_shot_timer = 0.0
    bullets.clear()

# Ship.$InHyperspace.$>() — pick a fresh location for the re-emergence.
func warp_out() -> void:
    ship_pos = Vector2(randf() * court_size.x, randf() * court_size.y)
    ship_vel = Vector2.ZERO

# Ship.$InHyperspace.<$() — reserved hook for a re-entry flash. The
# visible blink-in is already covered by is_visible() flipping true on
# the next frame, so nothing to do here yet.
func warp_in() -> void:
    pass

# Ship.$Exploding.$>() — the explosion burst is drawn from state
# (state == "Exploding" → _draw_explosion), so this is just a hook for
# audio / camera-shake if we add them later. Keeping the method so the
# .fjs/.fgd handler always has a real target.
func spawn_explosion() -> void:
    pass

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

    match fsm.get_current_state_name():
        "Attract":
            label_center.text = "A S T E R O I D S\n\nPress any key to start\n(H = hyperspace, P = pause)"
        "Playing":
            label_center.text = ""
        "ShipDying":
            label_center.text = ""
        "WaveClear":
            label_center.text = "WAVE CLEAR"
        "Paused":
            label_center.text = "PAUSED"
        "GameOver":
            label_center.text = "GAME OVER\n\nPress R to restart"
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    var state: String = fsm.get_current_state_name()

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
        draw_circle(b.pos, bullet_size, COL_BULLET)

    # Ship
    if state != "Attract" and state != "GameOver" and fsm.ship.is_visible():
        var ship_state: String = fsm.ship.get_current_state_name()
        if ship_state == "Exploding":
            _draw_explosion(ship_pos)
        else:
            # Blink while respawning to signal invuln
            var visible: bool = true
            if ship_state == "Respawning":
                visible = int(Time.get_ticks_msec() / 100) % 2 == 0
            if visible:
                _draw_ship(ship_pos, ship_angle)

func _draw_ship(at: Vector2, angle: float) -> void:
    # Classic triangle ship, filled in the accent blue used by Phaser
    # (Phaser.GameObjects.Triangle is filled by default; matching that).
    var nose: Vector2 = at + Vector2(cos(angle), sin(angle)) * ship_size
    var left: Vector2 = at + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * ship_size
    var right: Vector2 = at + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * ship_size
    draw_colored_polygon(PackedVector2Array([nose, left, right]), COL_SHIP)

    # Thruster flame while thrusting
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
        if fsm.ship.get_current_state_name() == "Alive" or fsm.ship.get_current_state_name() == "Respawning":
            var tail_base: Vector2 = (left + right) * 0.5
            var tail_tip: Vector2 = at - Vector2(cos(angle), sin(angle)) * ship_size * 1.4
            draw_line(tail_base, tail_tip, COL_FLAME, 1.5)

func _draw_asteroid(at: Vector2, radius: float) -> void:
    # Plain outlined circle — matches the JS build (Phaser.Arc with
    # setStrokeStyle(2, 0x9aa4b8)). draw_arc traces the full circumference
    # without filling, leaving the dark background visible inside.
    draw_arc(at, radius, 0.0, TAU, 32, COL_ROCK, 2.0)

func _draw_explosion(at: Vector2) -> void:
    # Radiating lines in the ship color, matching the JS debris fragments.
    var i: int = 0
    while i < 8:
        var t: float = float(i) / 8.0 * TAU
        var p1: Vector2 = at + Vector2(cos(t), sin(t)) * 4.0
        var p2: Vector2 = at + Vector2(cos(t), sin(t)) * 14.0
        draw_line(p1, p2, COL_SHIP, 2.0)
        i += 1
