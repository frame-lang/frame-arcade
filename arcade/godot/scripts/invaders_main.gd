# ============================================================
# Space Invaders — Godot driver (main.gd)
# ============================================================
# Owns an Invaders state machine and drives it with physics,
# input, and rendering. The Invaders system owns Player and
# Fleet sub-systems internally.
# ============================================================
extends Node2D

const InvadersFSM = preload("res://scripts/invaders.gd")

# --- Court / display ---
@export var court_size: Vector2 = Vector2(800, 600)

# --- Player ---
@export var player_size: Vector2 = Vector2(36, 12)
@export var player_y: float = 560.0
@export var player_speed: float = 260.0
@export var player_shot_cooldown: float = 0.4
@export var player_bullet_speed: float = 500.0
@export var player_bullet_size: Vector2 = Vector2(2, 10)

# --- Invaders (must match domain defaults in Frame source) ---
@export var fleet_rows: int = 5
@export var fleet_cols: int = 11
@export var invader_size: Vector2 = Vector2(28, 20)
@export var invader_spacing: Vector2 = Vector2(44, 32)
@export var fleet_origin: Vector2 = Vector2(60, 80)
@export var fleet_horizontal_step: float = 12.0
@export var fleet_vertical_step: float = 20.0

# --- Alien bullets ---
@export var alien_bullet_speed: float = 220.0
@export var alien_bullet_size: Vector2 = Vector2(3, 10)
@export var alien_fire_chance_per_sec: float = 0.9

# --- Runtime state ---
var fsm
var player_x: float
var player_shot_timer: float = 0.0
var fleet_offset: Vector2 = Vector2.ZERO
var player_bullets: Array = []       # each: Vector2 position
var alien_bullets: Array = []        # each: Vector2 position
var rng := RandomNumberGenerator.new()
var _p_was_down: bool = false

# --- Visual state ---
# Starfield: pre-generated points with varying brightness. Dim
# layer drifts slowly downward to suggest depth without needing
# parallax math. Bright layer is static (foreground stars).
var _stars_dim: Array = []        # each: Vector2
var _stars_bright: Array = []     # each: Vector2
const STAR_DRIFT_SPEED: float = 12.0   # px/sec for the dim layer

# Alien animation: phase 0 or 1, toggles every ~0.45s. Used to
# render alternating "feet" so the fleet visibly marches.
var _alien_anim_phase: int = 0
var _alien_anim_timer: float = 0.0
const ALIEN_FRAME_DURATION: float = 0.45

# Cabinet integration: post final score to Scoreboard once per
# session on the rising edge of game_over.
var _last_top_state: String = ""

# --- UI ---
var label_hud: Label
var label_center: Label
var label_leave_prompt: Label

# Leave-game overlay. Esc opens the prompt; while open, physics
# freezes and Enter returns to the menu / Esc resumes.
var _leave_prompt_active: bool = false

# ============================================================
func _ready() -> void:
    rng.randomize()
    fsm = InvadersFSM.new()
    fsm.fleet_rows = fleet_rows
    fsm.fleet_cols = fleet_cols
    _seed_starfield()

    _build_ui()
    _reset_player()
    _reset_fleet_offset()

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
    label_center.position = Vector2(0, court_size.y * 0.45)
    label_center.size = Vector2(court_size.x, 100)
    label_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    canvas.add_child(label_center)

    label_leave_prompt = Label.new()
    label_leave_prompt.add_theme_font_size_override("font_size", 24)
    label_leave_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
    label_leave_prompt.position = Vector2(0, court_size.y * 0.45)
    label_leave_prompt.size = Vector2(court_size.x, 100)
    label_leave_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_leave_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label_leave_prompt.text = "LEAVE GAME?\n\n[Enter] Return to menu    [Esc] Resume"
    label_leave_prompt.visible = false
    canvas.add_child(label_leave_prompt)

# ============================================================
func _physics_process(delta: float) -> void:
    if _leave_prompt_active:
        return
    _handle_input()

    var state: String = fsm.get_state()

    # The FSM's tick handlers run the player + fleet sub-FSMs,
    # but we always want to call it when in-game (even paused?
    # no — pause means freeze). So we only tick when not paused.
    if not fsm.is_paused() and state != "attract" and state != "game_over":
        fsm.tick(delta)

        # While the fleet is marching and its timer has expired,
        # execute one march step (driver moves the offset).
        if fsm.get_state() == "playing" or fsm.get_state() == "player_dying":
            _advance_fleet_if_ready()

        _update_player(delta)
        _update_bullets(delta)
        _maybe_alien_fire(delta)
        _check_collisions()

    # Alien march animation phase — toggle on a fixed cadence,
    # independent of the fleet's speed-up. This is purely visual;
    # the FSM has no concept of marching frames.
    _alien_anim_timer += delta
    if _alien_anim_timer >= ALIEN_FRAME_DURATION:
        _alien_anim_timer = 0.0
        _alien_anim_phase = 1 - _alien_anim_phase

    _update_labels()
    queue_redraw()
    _post_score_if_needed()

# ============================================================
func _post_score_if_needed() -> void:
    var s: String = fsm.get_state()
    if s == "game_over" and _last_top_state != "game_over":
        Arcade.record_score("invaders", fsm.get_score())
    _last_top_state = s

# ============================================================
func _handle_input() -> void:
    var state: String = fsm.get_state()

    if state == "attract":
        if Input.is_anything_pressed():
            fsm.start()
            _reset_player()
            _reset_fleet_offset()
            player_bullets.clear()
            alien_bullets.clear()
        return

    if state == "game_over":
        if Input.is_key_pressed(KEY_R):
            fsm.restart()
        return

    # P toggles pause in-game.
    if Input.is_key_pressed(KEY_P) and not _p_was_down:
        _p_was_down = true
        if fsm.is_paused():
            fsm.resume()
        else:
            fsm.pause()
    elif not Input.is_key_pressed(KEY_P):
        _p_was_down = false

    # Space / up-arrow: fire
    if state == "playing":
        if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP):
            _try_fire()

# ============================================================
func _update_player(delta: float) -> void:
    player_shot_timer = max(0.0, player_shot_timer - delta)

    if not _player_can_move():
        return

    var dir := 0.0
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        dir -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        dir += 1.0
    player_x += dir * player_speed * delta
    player_x = clamp(player_x, 0.0, court_size.x - player_size.x)

func _player_can_move() -> bool:
    return not fsm.is_paused() and fsm.get_state() == "playing"

func _reset_player() -> void:
    player_x = (court_size.x - player_size.x) * 0.5
    player_shot_timer = 0.0

func _try_fire() -> void:
    if player_shot_timer > 0.0:
        return
    if not fsm.get_state() == "playing":
        return
    # Only one player bullet at a time (classic Invaders rule)
    if player_bullets.size() >= 1:
        return
    var muzzle := Vector2(player_x + player_size.x * 0.5,
                          player_y - player_bullet_size.y)
    player_bullets.append(muzzle)
    player_shot_timer = player_shot_cooldown

# ============================================================
func _update_bullets(delta: float) -> void:
    # Player bullets travel upward
    var i: int = player_bullets.size() - 1
    while i >= 0:
        player_bullets[i] += Vector2(0, -player_bullet_speed * delta)
        if player_bullets[i].y < 0:
            player_bullets.remove_at(i)
        i -= 1

    # Alien bullets travel downward
    i = alien_bullets.size() - 1
    while i >= 0:
        alien_bullets[i] += Vector2(0, alien_bullet_speed * delta)
        if alien_bullets[i].y > court_size.y:
            alien_bullets.remove_at(i)
        i -= 1

# ============================================================
func _maybe_alien_fire(delta: float) -> void:
    if fsm.get_state() != "playing":
        return
    # Probability check scaled by delta
    if rng.randf() > alien_fire_chance_per_sec * delta:
        return
    # Pick a random column; find its bottom-most alive invader
    var col: int = rng.randi_range(0, fleet_cols - 1)
    var row: int = fleet_rows - 1
    while row >= 0:
        var idx: int = row * fleet_cols + col
        if fsm.fleet.is_alive(idx):
            var inv_pos := _invader_rect(idx).position
            alien_bullets.append(Vector2(
                inv_pos.x + invader_size.x * 0.5,
                inv_pos.y + invader_size.y))
            return
        row -= 1

# ============================================================
func _check_collisions() -> void:
    # Player bullets vs. invaders
    var i: int = player_bullets.size() - 1
    while i >= 0:
        var b: Vector2 = player_bullets[i]
        var hit_index: int = _find_invader_hit(b)
        if hit_index >= 0:
            fsm.player_killed_invader(hit_index)
            player_bullets.remove_at(i)
        i -= 1

    # Alien bullets vs. player
    var player_rect := Rect2(Vector2(player_x, player_y), player_size)
    i = alien_bullets.size() - 1
    while i >= 0:
        if player_rect.has_point(alien_bullets[i]):
            fsm.player_hit()
            alien_bullets.remove_at(i)
        i -= 1

    # Fleet vs. player
    if _fleet_reached_bottom():
        fsm.fleet_reached_bottom()

func _find_invader_hit(point: Vector2) -> int:
    var total: int = fleet_rows * fleet_cols
    var i: int = 0
    while i < total:
        if fsm.fleet.is_alive(i):
            if _invader_rect(i).has_point(point):
                return i
        i += 1
    return -1

# ============================================================
# Fleet rendering and motion
# ============================================================
func _invader_rect(index: int) -> Rect2:
    var col: int = index % fleet_cols
    var row: int = index / fleet_cols
    var base := fleet_origin + Vector2(
        col * invader_spacing.x,
        row * invader_spacing.y)
    return Rect2(base + fleet_offset, invader_size)

func _reset_fleet_offset() -> void:
    fleet_offset = Vector2.ZERO

func _advance_fleet_if_ready() -> void:
    if not fsm.fleet.consume_step():
        return

    # A step is due. Decide: horizontal or vertical?
    var dir: int = fsm.fleet.get_direction()

    # Check if a horizontal step would push any invader off the edge.
    var would_overshoot := false
    var total: int = fleet_rows * fleet_cols
    var i: int = 0
    while i < total:
        if fsm.fleet.is_alive(i):
            var r := _invader_rect(i)
            var next_x: float = r.position.x + dir * fleet_horizontal_step
            if next_x < 0.0 or next_x + r.size.x > court_size.x:
                would_overshoot = true
                break
        i += 1

    if would_overshoot:
        # Drop down and reverse. Tell the FSM, then apply the vertical shift.
        fleet_offset.y += fleet_vertical_step
        fsm.fleet_reached_edge()
        # The FSM's $Stepping state flips direction on its own $>.
    else:
        fleet_offset.x += dir * fleet_horizontal_step

func _fleet_reached_bottom() -> bool:
    var low: int = fsm.fleet.lowest_row()
    if low < 0:
        return false
    # Bottom of the lowest alive row
    var y: float = fleet_origin.y + low * invader_spacing.y + invader_size.y + fleet_offset.y
    return y >= player_y

# ============================================================
func _update_labels() -> void:
    label_hud.text = "SCORE  %05d     LIVES  %d     WAVE  %d" % [
        fsm.get_score(), fsm.get_lives(), fsm.get_wave()]

    match fsm.get_state():
        "attract":
            label_center.text = "S P A C E   I N V A D E R S\n\nPress any key"
        "playing":
            label_center.text = ""
        "player_dying":
            label_center.text = ""
        "wave_complete":
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
    var green := Color(0.4, 1.0, 0.4)
    var cyan := Color(0.4, 0.9, 1.0)
    var state: String = fsm.get_state()

    # Starfield first — dim drifters then bright statics.
    _draw_starfield()

    # Invaders
    if state != "attract" and state != "game_over":
        var total: int = fleet_rows * fleet_cols
        var i: int = 0
        while i < total:
            if fsm.fleet.is_alive(i):
                var r := _invader_rect(i)
                var row: int = i / fleet_cols
                # Top rows more valuable → differentiate with colour
                var col_top: Color = cyan if row == 0 else (white if row < 3 else green)
                _draw_invader(r, col_top)
            i += 1

    # Player bullets — bright core with a soft trailing glow.
    for b in player_bullets:
        var p: Vector2 = b
        draw_rect(Rect2(p - player_bullet_size * 0.5 + Vector2(0, 4),
                        Vector2(player_bullet_size.x, player_bullet_size.y)),
                  Color(1, 1, 0.6, 0.35))
        draw_rect(Rect2(p - player_bullet_size * 0.5, player_bullet_size), white)

    # Alien bullets — slight zigzag silhouette via two stacked rects.
    for b in alien_bullets:
        var p: Vector2 = b
        var col := Color(1.0, 0.55, 0.55)
        draw_rect(Rect2(p - alien_bullet_size * 0.5, alien_bullet_size), col)
        draw_rect(Rect2(p - Vector2(2, 2), Vector2(2, 2)), col.lightened(0.3))

    # Player ship
    if state != "attract" and state != "game_over":
        var player_state: String = fsm.get_state()
        if player_state == "player_dying":
            # Radiating particle explosion centered on the ship.
            var center: Vector2 = Vector2(player_x, player_y) + player_size * 0.5
            var ex := Color(1.0, 0.8, 0.3)
            for k in range(10):
                var t: float = float(k) / 10.0 * TAU
                var p1: Vector2 = center + Vector2(cos(t), sin(t)) * 6.0
                var p2: Vector2 = center + Vector2(cos(t), sin(t)) * 22.0
                draw_line(p1, p2, ex, 2.0)
            draw_circle(center, 4.0, ex.lightened(0.4))
        else:
            # Triangular cannon body — base + cockpit notch + barrel.
            draw_rect(Rect2(Vector2(player_x, player_y + 4),
                            Vector2(player_size.x, player_size.y - 4)), green)
            draw_rect(Rect2(Vector2(player_x + 6, player_y),
                            Vector2(player_size.x - 12, 8)), green)
            draw_rect(Rect2(
                Vector2(player_x + player_size.x * 0.5 - 1.5, player_y - 6),
                Vector2(3, 6)), green.lightened(0.2))

# ------------------------------------------------------------
# Visual helpers
# ------------------------------------------------------------
func _seed_starfield() -> void:
    # ~110 stars total; dim layer drifts and is denser, bright
    # layer is sparser with a few "twinkle"-able anchors.
    _stars_dim.clear()
    _stars_bright.clear()
    for i in range(80):
        _stars_dim.append(Vector2(rng.randf() * court_size.x, rng.randf() * court_size.y))
    for i in range(30):
        _stars_bright.append(Vector2(rng.randf() * court_size.x, rng.randf() * court_size.y))

func _draw_starfield() -> void:
    var dim := Color(0.4, 0.45, 0.6, 0.55)
    var bright := Color(0.9, 0.95, 1.0)
    var t_ms: int = Time.get_ticks_msec()
    # Drift the dim layer downward; wrap when off-screen so we
    # don't have to ever re-seed.
    var drift: float = fmod((t_ms / 1000.0) * STAR_DRIFT_SPEED, court_size.y)
    for s in _stars_dim:
        var y: float = fmod(s.y + drift, court_size.y)
        draw_rect(Rect2(s.x, y, 1, 1), dim)
    # Bright stars twinkle on a per-star phase so they don't all
    # blink in lockstep.
    var i: int = 0
    for s in _stars_bright:
        var twinkle: float = 0.7 + 0.3 * sin((t_ms / 200.0) + float(i) * 1.3)
        draw_rect(Rect2(s.x, s.y, 2, 2), bright * twinkle)
        i += 1

func _draw_invader(r: Rect2, base: Color) -> void:
    # Body (slightly inset top so legs stick out from a "torso").
    var body_rect := Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 6))
    draw_rect(body_rect, base)
    # Eyes — two small dark dots in upper third of the body.
    var eye_y: float = body_rect.position.y + body_rect.size.y * 0.3
    var eye_dx: float = body_rect.size.x * 0.25
    var eye_size := Vector2(3, 3)
    draw_rect(Rect2(Vector2(body_rect.position.x + eye_dx, eye_y), eye_size),
              base.darkened(0.6))
    draw_rect(Rect2(Vector2(body_rect.position.x + body_rect.size.x - eye_dx - eye_size.x, eye_y), eye_size),
              base.darkened(0.6))
    # Legs — two pairs that toggle "in" vs "out" each frame so
    # the fleet visibly marches. Phase 0: legs vertical. Phase 1:
    # legs flared outward.
    var leg_y: float = r.position.y + r.size.y - 4
    var leg_h: float = 4.0
    if _alien_anim_phase == 0:
        draw_rect(Rect2(r.position.x + 4, leg_y, 3, leg_h), base)
        draw_rect(Rect2(r.position.x + r.size.x - 7, leg_y, 3, leg_h), base)
    else:
        draw_rect(Rect2(r.position.x + 1, leg_y, 3, leg_h), base)
        draw_rect(Rect2(r.position.x + r.size.x - 4, leg_y, 3, leg_h), base)
    # A small "antenna" notch on top for personality.
    draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 1, r.position.y, 2, 3), base)

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
