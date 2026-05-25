# ============================================================
# Platformer — Godot driver (main.gd)
# ============================================================
# Owns a Player FSM, applies gravity and AABB platform
# collision, reads the FSM's velocity wishes each frame.
# ============================================================
extends Node2D

const PlatformerFSM = preload("res://scripts/platformer.gd")

# --- Court ---
@export var court_size: Vector2 = Vector2(800, 480)

# --- Player ---
@export var player_width: float = 24.0
@export var jump_impulse: float = 540.0
@export var jump_cut_multiplier: float = 0.4   # how much vy is cut on early jump release

# --- Physics ---
@export var gravity: float = 900.0
@export var terminal_velocity: float = 600.0

# --- Pickups ---
@export var mushroom_size: Vector2 = Vector2(18, 18)
@export var flower_size: Vector2 = Vector2(18, 20)

# --- Runtime ---
var fsm
var player_pos: Vector2
var player_vel: Vector2 = Vector2.ZERO
var was_grounded: bool = false
var platforms: Array = []    # each: Rect2 (static world geometry)
var mushroom: Dictionary = {}    # { pos: Vector2, alive: bool }
var flower: Dictionary = {}

# --- Edge-detected input flags ---
var _left_down: bool = false
var _right_down: bool = false
var _sprint_down: bool = false
var _jump_down: bool = false
var _p_was_down: bool = false

# --- UI ---
var label_hud: Label
var label_help: Label

# ============================================================
func _ready() -> void:
    fsm = PlatformerFSM.new()
    _build_level()
    _build_ui()
    _spawn_player()

func _build_level() -> void:
    # Simple static platforms. Each is an AABB (Rect2).
    platforms = [
        # Floor
        Rect2(0, court_size.y - 32, court_size.x, 32),
        # Three platforms
        Rect2(120, court_size.y - 140, 140, 20),
        Rect2(340, court_size.y - 220, 140, 20),
        Rect2(560, court_size.y - 140, 140, 20),
        # A high ledge
        Rect2(40, court_size.y - 300, 100, 20),
    ]

    # Pickups
    mushroom = { "pos": Vector2(400, court_size.y - 240), "alive": true }
    flower   = { "pos": Vector2(80, court_size.y - 320),  "alive": true }

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_hud = Label.new()
    label_hud.add_theme_font_size_override("font_size", 18)
    label_hud.position = Vector2(10, 6)
    label_hud.size = Vector2(court_size.x - 20, 28)
    canvas.add_child(label_hud)

    label_help = Label.new()
    label_help.add_theme_font_size_override("font_size", 14)
    label_help.position = Vector2(10, court_size.y - 28)
    label_help.size = Vector2(court_size.x - 20, 24)
    canvas.add_child(label_help)
    label_help.text = "Arrows/WASD = move, Shift = run, Space = jump, P = pause, R = reset pickups"

func _spawn_player() -> void:
    player_pos = Vector2(60, court_size.y - 80)
    player_vel = Vector2.ZERO
    was_grounded = true

# ============================================================
func _physics_process(delta: float) -> void:
    # Pause toggle (P), edge-detected. While paused the FSM sits in
    # $Paused; we skip input, tick, and physics entirely so both
    # sub-FSMs and the body freeze, and just render the held frame.
    var p_now: bool = Input.is_key_pressed(KEY_P)
    if p_now and not _p_was_down:
        if fsm.is_paused():
            fsm.resume()
        else:
            fsm.pause()
    _p_was_down = p_now

    if fsm.is_paused():
        _update_labels()
        queue_redraw()
        return

    _handle_input()

    # Tick the FSM so jumping's $.jump_held_time advances,
    # landing's timer advances, etc.
    fsm.tick(delta)

    _apply_jump_impulse()
    _apply_horizontal_velocity()
    _apply_gravity(delta)
    _integrate_and_collide(delta)
    _update_grounded_notifications()
    _check_pickups()
    _handle_reset_key()

    _update_labels()
    queue_redraw()

# ============================================================
func _handle_input() -> void:
    var left_now: bool = Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
    var right_now: bool = Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
    var sprint_now: bool = Input.is_key_pressed(KEY_SHIFT)
    var jump_now: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)

    # Left/right: fire events on direction change, or on release
    if left_now and not _left_down:
        fsm.press_left()
    if right_now and not _right_down:
        fsm.press_right()
    if not left_now and not right_now and (_left_down or _right_down):
        fsm.release_horizontal()
    _left_down = left_now
    _right_down = right_now

    # Sprint
    if sprint_now and not _sprint_down:
        fsm.press_sprint()
    if not sprint_now and _sprint_down:
        fsm.release_sprint()
    _sprint_down = sprint_now

    # Jump (press-edge and release-edge both matter)
    if jump_now and not _jump_down:
        fsm.press_jump()
    if not jump_now and _jump_down:
        fsm.release_jump()
    _jump_down = jump_now

func _handle_reset_key() -> void:
    if Input.is_key_pressed(KEY_R):
        mushroom.alive = true
        flower.alive = true

# ============================================================
func _apply_jump_impulse() -> void:
    # One-shot: if the FSM is flagging a jump, apply the impulse
    # and tell the FSM we've consumed it.
    if fsm.wants_jump_impulse():
        player_vel.y = -jump_impulse
        fsm.consume_jump_impulse()

func _apply_horizontal_velocity() -> void:
    # Read the FSM's preferred horizontal velocity each frame.
    # This is the "brain tells body" pattern: the FSM doesn't set
    # player_vel directly; the driver polls the FSM's preference
    # and applies it. Either would work; polling keeps the FSM
    # pure.
    player_vel.x = fsm.wants_velocity_x()

func _apply_gravity(delta: float) -> void:
    # Cut jump short if the player released the jump button while
    # still ascending. Classic variable-jump-height.
    if not _jump_down and player_vel.y < -80.0 and fsm.is_in_air():
        player_vel.y *= jump_cut_multiplier
        # Prevent multiple cuts per frame
        _jump_down = true

    player_vel.y += gravity * delta
    player_vel.y = min(player_vel.y, terminal_velocity)

# ============================================================
func _integrate_and_collide(delta: float) -> void:
    # Move X, then collide. Then move Y, then collide. The
    # axis-separated approach makes AABB resolution simple.
    var size := _player_size()

    player_pos.x += player_vel.x * delta
    _resolve_x(size)
    player_pos.y += player_vel.y * delta
    _resolve_y(size)

    # Clamp to court
    if player_pos.x < 0.0:
        player_pos.x = 0.0
        player_vel.x = 0.0
    if player_pos.x + size.x > court_size.x:
        player_pos.x = court_size.x - size.x
        player_vel.x = 0.0
    if player_pos.y > court_size.y:
        # Fell off bottom — respawn at start for this demo
        _spawn_player()

func _player_size() -> Vector2:
    return Vector2(player_width, float(fsm.hit_box_height()))

func _player_rect() -> Rect2:
    return Rect2(player_pos, _player_size())

func _resolve_x(size: Vector2) -> void:
    var p_rect := _player_rect()
    for plat in platforms:
        if p_rect.intersects(plat):
            if player_vel.x > 0.0:
                player_pos.x = plat.position.x - size.x
            elif player_vel.x < 0.0:
                player_pos.x = plat.position.x + plat.size.x
            player_vel.x = 0.0
            p_rect = _player_rect()

func _resolve_y(size: Vector2) -> void:
    var p_rect := _player_rect()
    for plat in platforms:
        if p_rect.intersects(plat):
            if player_vel.y > 0.0:
                player_pos.y = plat.position.y - size.y
            elif player_vel.y < 0.0:
                player_pos.y = plat.position.y + plat.size.y
            player_vel.y = 0.0
            p_rect = _player_rect()

# ============================================================
func _update_grounded_notifications() -> void:
    # Detect: are we standing on something? We probe one pixel
    # below the player and check against all platforms.
    var probe := Rect2(player_pos + Vector2(0, 1), _player_size())
    var grounded: bool = false
    for plat in platforms:
        if probe.intersects(plat):
            grounded = true
            break

    if grounded and not was_grounded:
        fsm.ground_contact()
    elif not grounded and was_grounded:
        fsm.left_ground()
    was_grounded = grounded

# ============================================================
func _check_pickups() -> void:
    var p_rect := _player_rect()

    if mushroom.alive:
        var r := Rect2(mushroom.pos, mushroom_size)
        if p_rect.intersects(r):
            fsm.pickup_mushroom()
            mushroom.alive = false

    if flower.alive:
        var r := Rect2(flower.pos, flower_size)
        if p_rect.intersects(r):
            fsm.pickup_flower()
            flower.alive = false

# ============================================================
func _update_labels() -> void:
    var pause_tag: String = "     [PAUSED]" if fsm.is_paused() else ""
    label_hud.text = "STATE  %s     FORM  %s     GROUNDED  %s%s" % [
        fsm.locomotion_state(),
        fsm.form(),
        "yes" if fsm.is_grounded() else "no",
        pause_tag]

# ============================================================
func _draw() -> void:
    # Platforms
    var plat_color := Color(0.45, 0.35, 0.25)
    for plat in platforms:
        draw_rect(plat, plat_color)
        draw_rect(Rect2(plat.position, Vector2(plat.size.x, 3.0)), Color(0.65, 0.55, 0.4))

    # Mushroom
    if mushroom.alive:
        _draw_mushroom(mushroom.pos)
    # Flower
    if flower.alive:
        _draw_flower(flower.pos)

    # Player
    _draw_player()

func _draw_player() -> void:
    var form: String = fsm.form()
    var size := _player_size()
    var col: Color
    match form:
        "small": col = Color(0.9, 0.2, 0.2)
        "big":   col = Color(0.3, 0.7, 0.3)
        _:       col = Color(1.0, 0.55, 0.1)

    draw_rect(Rect2(player_pos, size), col)

    # Eye facing forward
    var eye_x: float
    if fsm.facing() > 0:
        eye_x = player_pos.x + size.x - 8.0
    else:
        eye_x = player_pos.x + 2.0
    draw_rect(Rect2(Vector2(eye_x, player_pos.y + 4.0), Vector2(6, 6)), Color(1, 1, 1))
    draw_rect(Rect2(Vector2(eye_x + 1.0, player_pos.y + 5.0), Vector2(4, 4)), Color(0, 0, 0))

    # A little squish-tell when landing
    if fsm.locomotion_state() == "landing":
        draw_rect(Rect2(player_pos + Vector2(-2, size.y - 4),
                        Vector2(size.x + 4, 4)),
                  col.darkened(0.3))

func _draw_mushroom(at: Vector2) -> void:
    var cap := Color(0.85, 0.25, 0.25)
    var dot := Color(1, 1, 1)
    var stem := Color(0.9, 0.85, 0.75)
    draw_rect(Rect2(at + Vector2(0, 8), Vector2(18, 10)), stem)
    draw_rect(Rect2(at, Vector2(18, 10)), cap)
    draw_rect(Rect2(at + Vector2(3, 2), Vector2(3, 3)), dot)
    draw_rect(Rect2(at + Vector2(11, 4), Vector2(3, 3)), dot)

func _draw_flower(at: Vector2) -> void:
    var petal := Color(1.0, 0.4, 0.1)
    var centre := Color(1.0, 0.85, 0.2)
    var leaf := Color(0.2, 0.7, 0.3)
    # Stem/leaf
    draw_rect(Rect2(at + Vector2(7, 12), Vector2(4, 8)), leaf)
    # Petal ring
    draw_rect(Rect2(at + Vector2(2, 2),  Vector2(14, 10)), petal)
    draw_rect(Rect2(at + Vector2(6, 6),  Vector2(6, 6)), centre)
