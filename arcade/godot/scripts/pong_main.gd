# ============================================================
# Pong — Godot driver (main.gd)
# ============================================================
# This is the "body" to Frame's "brain". It:
#   - owns a Pong state machine instance
#   - reads player input and tells the machine about it
#   - runs the ball and paddle physics
#   - queries the machine each frame to know what to render
# ============================================================
extends Node2D

# The generated Frame state machine.
# framec produces ../generated/pong.gd — it's symlinked (or copied)
# into scripts/pong.gd so Godot can find it.
const PongFSM = preload("res://scripts/pong.gd")

# --- Tunables (edit freely) ---
@export var court_size: Vector2 = Vector2(800, 600)
@export var paddle_size: Vector2 = Vector2(10, 60)
@export var ball_size: float = 8.0
@export var paddle_speed: float = 280.0
@export var ball_speed_initial: float = 240.0
@export var ball_speed_max: float = 480.0
@export var ai_reaction: float = 0.85        # 1.0 = perfect, lower = sloppier

# --- Runtime state (the "view model") ---
var fsm                                       # Pong state machine instance
var ball_pos: Vector2
var ball_vel: Vector2
var paddle_left_y: float
var paddle_right_y: float
var ball_speed_current: float
var ball_trail: Array = []                    # recent ball positions for the motion trail
const BALL_TRAIL_LEN: int = 10
var flash_timer: float = 0.0
var _serve_armed: bool = false                # becomes true one frame after
                                               # entering Serving, so the keypress
                                               # that started the game doesn't
                                               # instantly launch the ball.
# Leave-game overlay. Esc opens the prompt; while open, physics
# freezes and Enter returns to the menu / Esc resumes. Same
# shape as the home-screen quit prompt and CCA's ExitDialog —
# stray Esc no longer drops an in-progress run.
var _leave_prompt_active: bool = false

# --- Rendering nodes (created in _ready) ---
var label_score: Label
var label_center: Label
var label_leave_prompt: Label

# ------------------------------------------------------------
func _ready() -> void:
    fsm = PongFSM.new()

    # Build minimal UI programmatically so the scene file stays tiny.
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_score = Label.new()
    label_score.add_theme_font_size_override("font_size", 48)
    label_score.position = Vector2(court_size.x * 0.5 - 60, 10)
    label_score.size = Vector2(120, 60)
    label_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_score)

    label_center = Label.new()
    label_center.add_theme_font_size_override("font_size", 24)
    label_center.position = Vector2(0, court_size.y * 0.5 - 40)
    label_center.size = Vector2(court_size.x, 80)
    label_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    canvas.add_child(label_center)

    label_leave_prompt = Label.new()
    label_leave_prompt.add_theme_font_size_override("font_size", 24)
    label_leave_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
    label_leave_prompt.position = Vector2(0, court_size.y * 0.5 - 40)
    label_leave_prompt.size = Vector2(court_size.x, 80)
    label_leave_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_leave_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label_leave_prompt.text = "LEAVE GAME?\n\n[Enter] Return to menu    [Esc] Resume"
    label_leave_prompt.visible = false
    canvas.add_child(label_leave_prompt)

    _reset_paddles()
    _park_ball_on_serve()

# ------------------------------------------------------------
func _physics_process(delta: float) -> void:
    if _leave_prompt_active:
        return
    _handle_input()

    # Paddle motion is allowed in every state except attract.
    var state: String = fsm.get_state()
    if state != "attract":
        _update_paddles(delta)

    # Ball physics only integrates when the machine says we're playing.
    if fsm.is_playing():
        _update_ball(delta)
        _check_scoring()

    if state == "serving":
        _park_ball_on_serve()

    # Update the ball trail. We sample once per physics tick so
    # the trail length is constant regardless of frame rate.
    if state == "in_play":
        ball_trail.append(ball_pos)
        if ball_trail.size() > BALL_TRAIL_LEN:
            ball_trail.pop_front()
    else:
        ball_trail.clear()

    flash_timer += delta
    queue_redraw()
    _update_labels()

# ------------------------------------------------------------
func _handle_input() -> void:
    var state: String = fsm.get_state()

    # Any key starts the game from attract mode.
    if state == "attract":
        if Input.is_anything_pressed():
            fsm.start()
            _serve_armed = false
        return

    # Space/Enter launches the ball when serving — but only after the key
    # that started the game has been released once. _serve_armed becomes
    # true after a frame of no input, so the held start-keypress can't
    # also act as the serve.
    if state == "serving":
        if not _serve_armed:
            if not Input.is_anything_pressed():
                _serve_armed = true
        elif Input.is_action_just_pressed("ui_accept"):
            _launch_ball()
            fsm.launch()

    # R restarts from game over.
    if state == "game_over":
        if Input.is_key_pressed(KEY_R):
            fsm.restart()

# ------------------------------------------------------------
func _update_paddles(delta: float) -> void:
    # Left paddle: ↑/↓ or W/S
    var left_dir := 0.0
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
        left_dir -= 1.0
    if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
        left_dir += 1.0
    paddle_left_y += left_dir * paddle_speed * delta

    # Right paddle: simple AI that tracks the ball with reaction dampening
    var target_y: float = ball_pos.y - paddle_size.y * 0.5
    var diff: float = target_y - paddle_right_y
    paddle_right_y += clamp(diff * ai_reaction, -paddle_speed * delta, paddle_speed * delta)

    # Clamp both paddles to the court.
    paddle_left_y  = clamp(paddle_left_y,  0.0, court_size.y - paddle_size.y)
    paddle_right_y = clamp(paddle_right_y, 0.0, court_size.y - paddle_size.y)

# ------------------------------------------------------------
func _update_ball(delta: float) -> void:
    ball_pos += ball_vel * delta

    # Top/bottom wall bounce
    if ball_pos.y < 0.0 and ball_vel.y < 0.0:
        ball_vel.y = -ball_vel.y
    if ball_pos.y > court_size.y and ball_vel.y > 0.0:
        ball_vel.y = -ball_vel.y

    # Paddle collisions
    var left_paddle_rect := Rect2(
        Vector2(20.0, paddle_left_y),
        paddle_size)
    var right_paddle_rect := Rect2(
        Vector2(court_size.x - 20.0 - paddle_size.x, paddle_right_y),
        paddle_size)

    if left_paddle_rect.has_point(ball_pos) and ball_vel.x < 0.0:
        _paddle_hit(left_paddle_rect, +1.0)
    elif right_paddle_rect.has_point(ball_pos) and ball_vel.x > 0.0:
        _paddle_hit(right_paddle_rect, -1.0)

func _paddle_hit(paddle_rect: Rect2, x_dir: float) -> void:
    # Add a bit of english based on where the ball hit the paddle.
    var offset: float = (ball_pos.y - paddle_rect.position.y) / paddle_rect.size.y - 0.5
    var angle: float = offset * 0.6                    # radians
    ball_speed_current = min(ball_speed_current * 1.04, ball_speed_max)
    ball_vel = Vector2(x_dir * cos(angle), sin(angle)) * ball_speed_current

# ------------------------------------------------------------
func _check_scoring() -> void:
    if ball_pos.x < 0.0:
        fsm.ball_out_left()
    elif ball_pos.x > court_size.x:
        fsm.ball_out_right()

# ------------------------------------------------------------
func _park_ball_on_serve() -> void:
    # Put the ball on the serving paddle.
    var dir: int = fsm.get_serve_direction()
    if dir > 0:
        # Serve from the left paddle toward the right.
        ball_pos = Vector2(30.0, paddle_left_y + paddle_size.y * 0.5)
    else:
        # Serve from the right paddle toward the left.
        ball_pos = Vector2(court_size.x - 30.0, paddle_right_y + paddle_size.y * 0.5)
    ball_vel = Vector2.ZERO
    ball_speed_current = ball_speed_initial

func _launch_ball() -> void:
    var dir: int = fsm.get_serve_direction()
    # A small random vertical component keeps serves interesting.
    var vy: float = randf_range(-0.3, 0.3)
    ball_vel = Vector2(float(dir), vy).normalized() * ball_speed_current

func _reset_paddles() -> void:
    paddle_left_y  = (court_size.y - paddle_size.y) * 0.5
    paddle_right_y = (court_size.y - paddle_size.y) * 0.5

# ------------------------------------------------------------
func _update_labels() -> void:
    var state: String = fsm.get_state()
    label_score.text = "%d   %d" % [fsm.get_score_left(), fsm.get_score_right()]

    match state:
        "attract":
            label_center.text = "P O N G\nPress any key" if int(flash_timer * 2) % 2 == 0 else "P O N G"
        "serving":
            label_center.text = "Press SPACE to serve"
        "in_play":
            label_center.text = ""
        "point_scored":
            label_center.text = ""
        "game_over":
            var w: String = fsm.get_winner().to_upper()
            label_center.text = "%s WINS\nPress R to play again" % w
        _:
            label_center.text = ""

# ------------------------------------------------------------
func _draw() -> void:
    var white := Color(1, 1, 1)
    var dim := Color(0.55, 0.6, 0.7)

    # Court borders — top and bottom thin lines so the play area
    # reads as a contained court, not just a black void.
    draw_rect(Rect2(0, 0, court_size.x, 2), dim)
    draw_rect(Rect2(0, court_size.y - 2, court_size.x, 2), dim)

    # Center dashed line
    var dash_h: float = 10.0
    var y: float = 0.0
    while y < court_size.y:
        draw_rect(Rect2(court_size.x * 0.5 - 1.0, y, 2.0, dash_h), dim)
        y += dash_h * 2.0

    # Paddles — draw a slightly darker outer rim around the
    # white core for visual heft.
    var rim := Color(0.7, 0.75, 0.85)
    var pad_l_pos := Vector2(20.0, paddle_left_y)
    var pad_r_pos := Vector2(court_size.x - 20.0 - paddle_size.x, paddle_right_y)
    draw_rect(Rect2(pad_l_pos - Vector2(1, 1), paddle_size + Vector2(2, 2)), rim)
    draw_rect(Rect2(pad_l_pos, paddle_size), white)
    draw_rect(Rect2(pad_r_pos - Vector2(1, 1), paddle_size + Vector2(2, 2)), rim)
    draw_rect(Rect2(pad_r_pos, paddle_size), white)

    # Ball + trail (draw only when it's on the court). Trail
    # renders first, oldest dimmest, so the ball is on top.
    var state: String = fsm.get_state()
    var show_ball: bool = state == "in_play" or state == "serving"
    if show_ball:
        var n: int = ball_trail.size()
        for i in range(n):
            var t: Vector2 = ball_trail[i]
            var alpha: float = (float(i + 1) / float(n + 1)) * 0.5
            var rad: float = ball_size * 0.5 * (0.4 + 0.6 * float(i + 1) / float(n + 1))
            draw_circle(t, rad, Color(1, 1, 1, alpha))
        draw_circle(ball_pos, ball_size * 0.5, white)

# ------------------------------------------------------------
# Cabinet integration: Esc returns to the menu.
# ------------------------------------------------------------
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed):
        return
    if _leave_prompt_active:
        get_viewport().set_input_as_handled()
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            Arcade.return_to_menu()
        elif event.keycode == KEY_ESCAPE:
            _hide_leave_prompt()
        return
    if event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        _show_leave_prompt()

func _show_leave_prompt() -> void:
    _leave_prompt_active = true
    label_leave_prompt.visible = true

func _hide_leave_prompt() -> void:
    _leave_prompt_active = false
    label_leave_prompt.visible = false
