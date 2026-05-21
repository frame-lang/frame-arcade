# ============================================================
# Pac-Man Ghost AI — Godot driver (main.gd)
# ============================================================
# Demo of the ghost state machine. An open arena (no maze),
# Pac-Man moved by arrow keys, four ghosts running the full
# state machine (chase / scatter / frightened / eaten /
# in-pen), four power pellets in the corners.
#
# Pac-Man can't die in this demo — the point is seeing the
# ghost AI, not the full game.
# ============================================================
extends Node2D

const PacManFSM = preload("res://scripts/pacman.gd")

# --- Court ---
@export var court_size: Vector2 = Vector2(800, 600)

# --- Pac-Man ---
@export var pacman_speed: float = 180.0
@export var pacman_radius: float = 12.0

# --- Ghosts ---
@export var ghost_radius: float = 12.0
@export var ghost_speed_normal: float = 150.0
@export var ghost_speed_frightened: float = 95.0
@export var ghost_speed_eaten: float = 260.0

# --- Pen ---
@export var pen_size: Vector2 = Vector2(120, 80)

# --- Power pellets ---
@export var pellet_radius: float = 8.0
@export var pellet_inset: float = 40.0

# --- Runtime ---
var fsm
var pacman_pos: Vector2
var pacman_dir: Vector2 = Vector2.RIGHT
var ghost_positions: Array = []       # parallel to fsm.ghosts
var pellets: Array = []               # each: { pos: Vector2, alive: bool }
var pen_center: Vector2

# --- UI ---
var label_hud: Label
var label_center: Label
var label_leave_prompt: Label

# Leave-game overlay. Esc opens the prompt; while open, physics
# freezes and Enter returns to the menu / Esc resumes.
var _leave_prompt_active: bool = false

# ============================================================
func _ready() -> void:
    fsm = PacManFSM.new()

    # Pen lives in the middle of the arena.
    pen_center = court_size * 0.5

    # Create the four ghosts with their parameters.
    # target_kind: 0=direct, 1=ahead4, 2=mixed, 3=shy
    var GhostClass = PacManFSM.Ghost
    var b = GhostClass._create("blinky", Vector2(court_size.x - 24, 24), 0)
    var p = GhostClass._create("pinky",  Vector2(24, 24), 1)
    var i = GhostClass._create("inky",   Vector2(court_size.x - 24, court_size.y - 24), 2)
    var c = GhostClass._create("clyde",  Vector2(24, court_size.y - 24), 3)
    fsm.add_ghost(b)
    fsm.add_ghost(p)
    fsm.add_ghost(i)
    fsm.add_ghost(c)

    # Mirror positions in the driver (all start in the pen).
    ghost_positions = [pen_center, pen_center, pen_center, pen_center]

    _reset_pellets()
    _build_ui()

    pacman_pos = Vector2(court_size.x * 0.5, court_size.y * 0.75)

    # Auto-start for the demo — no attract screen.
    fsm.start()

func _reset_pellets() -> void:
    pellets = [
        { "pos": Vector2(pellet_inset, pellet_inset), "alive": true },
        { "pos": Vector2(court_size.x - pellet_inset, pellet_inset), "alive": true },
        { "pos": Vector2(pellet_inset, court_size.y - pellet_inset), "alive": true },
        { "pos": Vector2(court_size.x - pellet_inset, court_size.y - pellet_inset), "alive": true },
    ]

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_hud = Label.new()
    label_hud.add_theme_font_size_override("font_size", 18)
    label_hud.position = Vector2(10, 6)
    label_hud.size = Vector2(court_size.x - 20, 28)
    canvas.add_child(label_hud)

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

# ============================================================
func _physics_process(delta: float) -> void:
    if _leave_prompt_active:
        return
    _handle_input()

    fsm.tick(delta)

    _update_pacman(delta)
    _update_ghosts(delta)
    _check_pellets()
    _check_ghost_collisions()

    _update_labels()
    queue_redraw()

# ============================================================
func _handle_input() -> void:
    # R resets pellets so you can eat them again.
    if Input.is_key_pressed(KEY_R):
        _reset_pellets()

    var dir := Vector2.ZERO
    if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
    if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1.0
    if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1.0
    if dir.length_squared() > 0.01:
        pacman_dir = dir.normalized()

# ============================================================
func _update_pacman(delta: float) -> void:
    var dir := Vector2.ZERO
    if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
    if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1.0
    if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1.0
    if dir.length_squared() > 0.01:
        dir = dir.normalized()
        pacman_pos += dir * pacman_speed * delta
        pacman_dir = dir

    pacman_pos.x = clamp(pacman_pos.x, pacman_radius, court_size.x - pacman_radius)
    pacman_pos.y = clamp(pacman_pos.y, pacman_radius, court_size.y - pacman_radius)

# ============================================================
func _update_ghosts(delta: float) -> void:
    var n: int = fsm.ghost_count()
    var i: int = 0
    while i < n:
        var state: String = fsm.ghost_state(i)
        var speed: float = ghost_speed_normal
        var target: Vector2 = ghost_positions[i]

        if state == "in_pen":
            # Hover above the pen center, waiting for release
            target = pen_center
            speed = 0.0    # don't actually move
        elif state == "chase":
            target = _chase_target(i)
        elif state == "scatter":
            target = fsm.ghost_home_corner(i)
        elif state == "frightened":
            target = _flee_target(i)
            speed = ghost_speed_frightened
        elif state == "eaten":
            target = pen_center
            speed = ghost_speed_eaten

        # Steer toward target
        if speed > 0.0:
            var to_target: Vector2 = target - ghost_positions[i]
            if to_target.length() > 1.0:
                ghost_positions[i] += to_target.normalized() * speed * delta
            ghost_positions[i].x = clamp(ghost_positions[i].x, ghost_radius, court_size.x - ghost_radius)
            ghost_positions[i].y = clamp(ghost_positions[i].y, ghost_radius, court_size.y - ghost_radius)

        # Arrival notifications
        if state == "eaten":
            if ghost_positions[i].distance_to(pen_center) < ghost_radius:
                fsm.ghost_arrived_at_pen(i)

        i += 1

# Per-ghost chase targeting using target_kind
func _chase_target(ghost_index: int) -> Vector2:
    var kind: int = fsm.ghost_target_kind(ghost_index)
    match kind:
        0:  # Blinky: direct
            return pacman_pos
        1:  # Pinky: 4 units ahead of Pac-Man
            return pacman_pos + pacman_dir * 80.0
        2:  # Inky: project around Blinky (we approximate by mirroring around pac)
            var blinky_pos: Vector2 = ghost_positions[0]
            var ahead: Vector2 = pacman_pos + pacman_dir * 40.0
            return ahead + (ahead - blinky_pos)
        3:  # Clyde: chase when far, scatter when close
            if ghost_positions[ghost_index].distance_to(pacman_pos) > 160.0:
                return pacman_pos
            return fsm.ghost_home_corner(ghost_index)
        _:
            return pacman_pos

func _flee_target(ghost_index: int) -> Vector2:
    # Head to the corner farthest from Pac-Man
    var corners := [
        Vector2(pellet_inset, pellet_inset),
        Vector2(court_size.x - pellet_inset, pellet_inset),
        Vector2(pellet_inset, court_size.y - pellet_inset),
        Vector2(court_size.x - pellet_inset, court_size.y - pellet_inset),
    ]
    var best_d: float = 0.0
    var best: Vector2 = corners[0]
    for c in corners:
        var d: float = c.distance_to(pacman_pos)
        if d > best_d:
            best_d = d
            best = c
    return best

# ============================================================
func _check_pellets() -> void:
    for p in pellets:
        if not p.alive:
            continue
        if pacman_pos.distance_to(p.pos) < pacman_radius + pellet_radius:
            p.alive = false
            fsm.power_pellet_picked_up()

func _check_ghost_collisions() -> void:
    var n: int = fsm.ghost_count()
    var i: int = 0
    while i < n:
        if fsm.ghost_state(i) == "eaten" or fsm.ghost_state(i) == "in_pen":
            i += 1
            continue
        var d: float = pacman_pos.distance_to(ghost_positions[i])
        if d < pacman_radius + ghost_radius:
            # If ghost is edible, eat it. Otherwise, Pac-Man would die
            # in the full game — here we just ignore it.
            if fsm.ghost_is_edible(i):
                fsm.ghost_caught(i)
        i += 1

# ============================================================
func _update_labels() -> void:
    label_hud.text = "SCORE  %05d     PHASE  %s     FRIGHTEN  %.1fs" % [
        fsm.get_score(),
        fsm.get_phase().to_upper(),
        fsm.frighten_seconds_left()]

    match fsm.get_phase():
        "frightened":
            label_center.text = "FRIGHTENED"
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    # Ghost pen (visual only)
    var pen_rect := Rect2(pen_center - pen_size * 0.5, pen_size)
    draw_rect(pen_rect, Color(0.2, 0.2, 0.4), false, 2.0)

    # Power pellets
    for p in pellets:
        if p.alive:
            draw_circle(p.pos, pellet_radius, Color(1, 0.95, 0.6))

    # Ghosts
    var n: int = fsm.ghost_count()
    var i: int = 0
    while i < n:
        _draw_ghost(i)
        i += 1

    # Pac-Man
    _draw_pacman()

func _draw_ghost(index: int) -> void:
    var pos: Vector2 = ghost_positions[index]
    var state: String = fsm.ghost_state(index)

    var body_color: Color
    match index:
        0: body_color = Color(1.0, 0.25, 0.25)     # blinky = red
        1: body_color = Color(1.0, 0.70, 0.85)     # pinky = pink
        2: body_color = Color(0.30, 0.85, 1.0)     # inky = cyan
        _: body_color = Color(1.0, 0.65, 0.30)     # clyde = orange

    if state == "frightened":
        # Blink white-blue when frighten is about to expire
        var rem: float = fsm.frighten_seconds_left()
        if rem < 1.5 and int(Time.get_ticks_msec() / 200) % 2 == 0:
            body_color = Color(1, 1, 1)
        else:
            body_color = Color(0.2, 0.3, 1.0)

    if state == "eaten":
        # Just eyes — draw two small whites
        draw_circle(pos + Vector2(-4, -2), 3.0, Color(1, 1, 1))
        draw_circle(pos + Vector2(+4, -2), 3.0, Color(1, 1, 1))
        return

    if state == "in_pen":
        body_color = body_color.darkened(0.4)

    # Body (half circle + rectangle for the classic ghost shape)
    draw_circle(pos + Vector2(0, -2), ghost_radius, body_color)
    draw_rect(Rect2(pos + Vector2(-ghost_radius, -2),
                    Vector2(ghost_radius * 2, ghost_radius * 0.9)),
              body_color)

    # Eyes
    var eye_col: Color = Color(1, 1, 1)
    draw_circle(pos + Vector2(-4, -4), 2.5, eye_col)
    draw_circle(pos + Vector2(+4, -4), 2.5, eye_col)

func _draw_pacman() -> void:
    # Simple yellow circle with a mouth wedge
    var col := Color(1, 0.95, 0.2)
    draw_circle(pacman_pos, pacman_radius, col)
    # Mouth
    var mouth_open: float = (sin(Time.get_ticks_msec() / 120.0) + 1.0) * 0.5  # 0..1
    var angle: float = atan2(pacman_dir.y, pacman_dir.x)
    var opening: float = mouth_open * 0.6
    # Skip the wedge when the mouth is essentially shut: a zero
    # opening collapses p2/p3 into a degenerate triangle, which the
    # GL-compatibility (web) renderer rejects with a per-frame
    # "triangulation failed" log. A closed mouth draws nothing
    # anyway, so guarding here is both correct and quieter.
    if opening > 0.01:
        var p1: Vector2 = pacman_pos
        var p2: Vector2 = pacman_pos + Vector2(cos(angle + opening), sin(angle + opening)) * pacman_radius * 1.1
        var p3: Vector2 = pacman_pos + Vector2(cos(angle - opening), sin(angle - opening)) * pacman_radius * 1.1
        var pts := PackedVector2Array([p1, p2, p3])
        draw_polygon(pts, PackedColorArray([Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)]))

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
