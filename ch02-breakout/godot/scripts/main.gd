# ============================================================
# Breakout — Godot driver (main.gd)
# ============================================================
# Owns a Breakout state machine and drives it with physics and
# input. The Breakout system owns a Ball and BrickField
# internally — the driver never talks to them directly.
# ============================================================
extends Node2D

const BreakoutFSM = preload("res://scripts/breakout.gd")

# --- Tunables ---
@export var court_size: Vector2 = Vector2(640, 480)
@export var paddle_size: Vector2 = Vector2(80, 10)
@export var paddle_y: float = 440.0
@export var paddle_speed: float = 420.0
@export var ball_size: float = 8.0
@export var ball_speed_initial: float = 260.0
@export var ball_speed_max: float = 520.0

# --- Brick layout ---
@export var brick_cols: int = 8
@export var brick_rows: int = 5
@export var brick_size: Vector2 = Vector2(72, 16)
@export var brick_origin: Vector2 = Vector2(32, 60)
@export var brick_gap: Vector2 = Vector2(4, 4)

# --- Runtime ---
var fsm
var _pause_down: bool = false                 # rising-edge latch for the P key
var paddle_x: float
var ball_pos: Vector2
var ball_speed_current: float

# Rendering helpers
var label_score: Label
var label_status: Label
var brick_colors: Array = []

# ============================================================
func _ready() -> void:
    fsm = BreakoutFSM.new()
    fsm.brick_count = brick_cols * brick_rows

    # Paint each row a different colour, Breakout-style.
    brick_colors = [
        Color(0.95, 0.27, 0.27),    # red
        Color(0.95, 0.62, 0.23),    # orange
        Color(0.95, 0.85, 0.25),    # yellow
        Color(0.35, 0.78, 0.35),    # green
        Color(0.28, 0.52, 0.90),    # blue
    ]

    _build_ui()
    _reset_paddle()
    _park_ball_on_paddle()

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_score = Label.new()
    label_score.add_theme_font_size_override("font_size", 20)
    label_score.position = Vector2(10, 10)
    label_score.size = Vector2(300, 30)
    canvas.add_child(label_score)

    label_status = Label.new()
    label_status.add_theme_font_size_override("font_size", 32)
    label_status.position = Vector2(0, court_size.y * 0.5 - 40)
    label_status.size = Vector2(court_size.x, 80)
    label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    canvas.add_child(label_status)

# ============================================================
func _physics_process(delta: float) -> void:
    _handle_input()

    var state: String = fsm.get_state()
    if state == "playing":
        _update_paddle(delta)
        _update_ball(delta)
    elif state == "level_clear":
        # Let player move paddle during pause
        _update_paddle(delta)
        _park_ball_on_paddle()

    queue_redraw()
    _update_labels()

# ============================================================
func _handle_input() -> void:
    var state: String = fsm.get_state()

    # P toggles pause (rising-edge). pause() from playing pushes the
    # current state; resume() from paused pops back to it.
    var p_now: bool = Input.is_key_pressed(KEY_P)
    if p_now and not _pause_down:
        if state == "playing":
            fsm.pause()
        elif state == "paused":
            fsm.resume()
    _pause_down = p_now
    if fsm.get_state() == "paused":
        return

    if state == "attract":
        if Input.is_anything_pressed():
            fsm.start()
            _park_ball_on_paddle()
        return

    if state == "playing":
        # Launch ball if attached
        if fsm.ball_state() == "attached":
            if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE):
                var vy: float = -ball_speed_initial * 0.8
                var vx: float = ball_speed_initial * 0.3 * (1.0 if randf() > 0.5 else -1.0)
                fsm.launch_ball(vx, vy)
                ball_speed_current = ball_speed_initial

    if state == "level_clear":
        if Input.is_anything_pressed():
            fsm.start()     # re-uses start() to advance to next level
            _park_ball_on_paddle()

    if state == "game_over":
        if Input.is_key_pressed(KEY_R):
            fsm.restart()

# ============================================================
func _update_paddle(delta: float) -> void:
    var dir := 0.0
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        dir -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        dir += 1.0
    paddle_x += dir * paddle_speed * delta
    paddle_x = clamp(paddle_x, 0.0, court_size.x - paddle_size.x)

func _reset_paddle() -> void:
    paddle_x = (court_size.x - paddle_size.x) * 0.5

# ============================================================
func _update_ball(delta: float) -> void:
    if fsm.ball_state() == "attached":
        _park_ball_on_paddle()
        return

    if fsm.ball_state() != "in_flight":
        return

    # Integrate position
    var vx: float = fsm.ball_vx()
    var vy: float = fsm.ball_vy()
    ball_pos.x += vx * delta
    ball_pos.y += vy * delta

    # Wall bounces
    if ball_pos.x < 0.0 and vx < 0.0:
        fsm.wall_bounce_x()
    elif ball_pos.x > court_size.x and vx > 0.0:
        fsm.wall_bounce_x()
    if ball_pos.y < 0.0 and vy < 0.0:
        fsm.wall_bounce_y()

    # Fell off bottom
    if ball_pos.y > court_size.y:
        fsm.ball_fell_off()
        _park_ball_on_paddle()
        return

    # Paddle collision.
    # Use the ball's bounding rect (not just center point) to avoid
    # tunneling when the ball is moving fast — at max speed (~520 px/s
    # at 60fps = ~8.7 px/frame) a single-point test can miss the
    # 10px-thick paddle entirely.
    var paddle_rect := Rect2(Vector2(paddle_x, paddle_y), paddle_size)
    var ball_rect := Rect2(ball_pos - Vector2(ball_size, ball_size) * 0.5,
                           Vector2(ball_size, ball_size))
    if paddle_rect.intersects(ball_rect) and fsm.ball_vy() > 0.0:
        # English based on where on the paddle the ball hit
        var offset: float = (ball_pos.x - paddle_x) / paddle_size.x - 0.5  # -0.5 .. +0.5
        var angle: float = offset * 1.2  # max ~70° off vertical
        ball_speed_current = min(ball_speed_current * 1.02, ball_speed_max)
        var new_vx: float = sin(angle) * ball_speed_current
        var new_vy: float = -cos(angle) * ball_speed_current
        fsm.paddle_hit(new_vx, new_vy)
        # Nudge ball fully above the paddle (center + half-height clears
        # the top edge by 1px).
        ball_pos.y = paddle_y - ball_size * 0.5 - 1.0

    # Brick collision
    _check_brick_collision()

func _park_ball_on_paddle() -> void:
    ball_pos = Vector2(paddle_x + paddle_size.x * 0.5, paddle_y - ball_size)

# ============================================================
func _check_brick_collision() -> void:
    var ball_rect := Rect2(ball_pos - Vector2(ball_size, ball_size) * 0.5,
                           Vector2(ball_size, ball_size))
    var i: int = 0
    var total: int = brick_cols * brick_rows
    while i < total:
        if not fsm.is_brick_broken(i):
            var rect := _brick_rect(i)
            if rect.intersects(ball_rect):
                fsm.brick_hit(i)
                # Only break one brick per frame to keep it simple
                return
        i += 1

func _brick_rect(index: int) -> Rect2:
    var col: int = index % brick_cols
    var row: int = index / brick_cols
    var pos := brick_origin + Vector2(
        col * (brick_size.x + brick_gap.x),
        row * (brick_size.y + brick_gap.y))
    return Rect2(pos, brick_size)

# ============================================================
func _update_labels() -> void:
    label_score.text = "SCORE  %05d     LIVES  %d     LEVEL  %d" % [
        fsm.get_score(), fsm.get_lives(), fsm.get_level()]

    match fsm.get_state():
        "attract":
            label_status.text = "B R E A K O U T\n\nPress any key"
        "playing":
            if fsm.ball_state() == "attached":
                label_status.text = "Press SPACE to launch"
            else:
                label_status.text = ""
        "level_clear":
            label_status.text = "LEVEL CLEAR\n\nPress any key for next level"
        "game_over":
            label_status.text = "GAME OVER\n\nPress R to restart"

# ============================================================
func _draw() -> void:
    var white := Color(1, 1, 1)
    var state: String = fsm.get_state()

    # Bricks
    var i: int = 0
    var total: int = brick_cols * brick_rows
    while i < total:
        if not fsm.is_brick_broken(i):
            var rect := _brick_rect(i)
            var row: int = i / brick_cols
            var col: Color = brick_colors[row % brick_colors.size()]
            draw_rect(rect, col)
            # A subtle inner highlight for that chunky arcade look
            draw_rect(Rect2(rect.position + Vector2(1, 1),
                            rect.size - Vector2(2, 2)),
                      col.lightened(0.15), false, 1.0)
        i += 1

    # Paddle
    if state != "attract":
        draw_rect(Rect2(Vector2(paddle_x, paddle_y), paddle_size), white)

    # Ball
    var show_ball: bool = state == "playing" or state == "level_clear"
    if show_ball and fsm.ball_state() != "lost":
        draw_rect(Rect2(ball_pos - Vector2(ball_size, ball_size) * 0.5,
                        Vector2(ball_size, ball_size)), white)
