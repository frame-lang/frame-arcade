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

# Cabinet integration: post final score to Scoreboard once per
# session on the rising edge of game_over.
var _last_top_state: String = ""

# --- UI ---
var label_hud: Label
var label_center: Label

# ============================================================
func _ready() -> void:
    rng.randomize()
    fsm = InvadersFSM.new()
    fsm.fleet_rows = fleet_rows
    fsm.fleet_cols = fleet_cols

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

# ============================================================
func _physics_process(delta: float) -> void:
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
                draw_rect(r, col_top)
                # A little chunky-pixel detail
                draw_rect(Rect2(r.position + Vector2(4, 4),
                                r.size - Vector2(8, 8)),
                          col_top.darkened(0.4))
            i += 1

    # Player bullets
    for b in player_bullets:
        draw_rect(Rect2(b - player_bullet_size * 0.5, player_bullet_size), white)

    # Alien bullets
    for b in alien_bullets:
        draw_rect(Rect2(b - alien_bullet_size * 0.5, alien_bullet_size), Color(1.0, 0.5, 0.5))

    # Player ship
    if state != "attract" and state != "game_over":
        var player_state: String = fsm.get_state()
        # We need to know if the player is exploding / invulnerable.
        # Ideally Invaders would expose player's FSM state. For now,
        # game-state "player_dying" is our signal for the explosion.
        if player_state == "player_dying":
            # Jagged explosion look
            var ex := Color(1.0, 0.8, 0.3)
            draw_rect(Rect2(Vector2(player_x, player_y), player_size), ex)
            draw_rect(Rect2(
                Vector2(player_x - 4, player_y - 4),
                player_size + Vector2(8, 8)),
                ex.darkened(0.3), false, 2.0)
        else:
            draw_rect(Rect2(Vector2(player_x, player_y), player_size), green)
            # Barrel
            draw_rect(Rect2(
                Vector2(player_x + player_size.x * 0.5 - 2, player_y - 6),
                Vector2(4, 6)), green)

# ------------------------------------------------------------
# Cabinet integration: Esc returns to the menu.
# ------------------------------------------------------------
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        print("[arcade] Esc pressed in ", get_tree().current_scene.scene_file_path, " — returning to menu")
        get_viewport().set_input_as_handled()
        Arcade.return_to_menu()
