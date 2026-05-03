# ============================================================
# Stealth — Godot driver (main.gd)
# ============================================================
# Owns a Stealth Frame system, draws a tile-grid maze, the
# player, three guards, and three vision cones. Reports
# perception (which guards can see the player this frame) to
# the Frame side as spot_player events; the Frame side
# decides what to do.
#
# Architecture mirrors the chapter 4 (Asteroids) split:
#   • Frame owns: state machines, decisions, memory
#     (last_known, patrol cursor, timers).
#   • Driver owns: positions of player and guards, facings,
#     maze geometry, line-of-sight, collision, rendering.
#
# The chapter README walks through the comparison with
# behavior trees in detail. The short version is here as
# inline comments where they're easiest to spot.
# ============================================================
extends Node2D

const StealthFSM = preload("res://scripts/stealth.gd")

# ------------------------------------------------------------
# Maze
# ------------------------------------------------------------
# 16 columns × 12 rows of 50-pixel tiles → 800×600 court.
# '#' = wall, '.' = floor, 'S' = player start, 'E' = exit.
# The driver scans this once at _ready() and converts to:
#   - `walls[row][col]: bool` for collision and LOS
#   - `player_start: Vector2` from S
#   - `exit_pos: Vector2` from E
#
# Designed by hand so each guard's patrol route stays in one
# region of the maze and so corridors give the player real
# spatial choices (loop around a wall to break LOS, wait at
# a corner to time a guard's pass, etc).
# ------------------------------------------------------------
const TILE_SIZE: int = 50
# Hand-designed for the chapter:
#   - Start (S) sits in the top-left "antechamber" — three open
#     rows so the first arrow press always produces visible
#     motion regardless of which direction the player tries.
#   - Three patrol zones (top, middle, bottom) separated by
#     half-walls with single gaps, so the guards' patrol cones
#     genuinely block routes the player has to time crossings
#     against.
#   - Exit (E) is bottom-right, on the opposite diagonal from S,
#     forcing traversal of all three zones.
const MAZE: Array = [
    "################",
    "#..............#",
    "#..S...........#",
    "#..............#",
    "####.######.####",
    "#..............#",
    "#.######..######",
    "#..............#",
    "######.######..#",
    "#..............#",
    "#.............E#",
    "################",
]
const COLS: int = 16
const ROWS: int = 12

# ------------------------------------------------------------
# Display / tunables
# ------------------------------------------------------------
@export var court_size: Vector2 = Vector2(COLS * TILE_SIZE, ROWS * TILE_SIZE)
@export var player_speed: float = 140.0
@export var player_radius: float = 9.0
@export var guard_radius: float = 11.0
@export var catch_radius: float = 18.0

# Vision cone shape. half_angle is in radians (the cone is
# 2× this wide); range is in pixels.
@export var vision_half_angle: float = deg_to_rad(28.0)
@export var vision_range: float = 180.0

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var fsm

# Maze data, parsed from MAZE in _ready.
var walls: Array = []         # walls[row][col] : bool
var player_start: Vector2 = Vector2.ZERO
var exit_pos: Vector2 = Vector2.ZERO

# Player
var player_pos: Vector2

# Per-guard driver-owned facing (radians). Frame owns the
# guard's mode and its target; the driver computes and
# remembers facing because it's a continuous geometric value
# closer to "how the guard renders" than "what mode the
# guard is in."
var guard_pos: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var guard_facing: Array = [0.0, 0.0, 0.0]

# Edge-detected restart key
var _r_was_down: bool = false

# Player rendering state. Kept driver-side because they're
# purely visual concerns — direction the figure is facing for
# rendering, the leg-swing phase for the running animation, and
# whether we should animate this frame at all. The Frame side
# doesn't model the player as a state machine; it just observes
# perception facts.
var _player_facing: float = -PI / 2.0
var _player_anim_phase: float = 0.0
var _player_is_moving: bool = false

# UI
var label_hud: Label
var label_center: Label

# ============================================================
func _ready() -> void:
    _parse_maze()

    fsm = StealthFSM.new()

    # Each guard starts near the middle of its patrol zone in the
    # new maze. Cells must be open (verified against MAZE) — a
    # guard placed in a wall cell would be wedged from frame 1
    # because driver collision would refuse to move it anywhere.
    guard_pos = [
        _cell_center(5, 2),    # top zone (rows 1-3 are open)
        _cell_center(8, 5),    # middle, row 5
        _cell_center(8, 10),   # bottom zone (rows 9-10)
    ]
    guard_facing = [0.0, PI, 0.0]
    player_pos = player_start

    _build_ui()

func _parse_maze() -> void:
    walls.clear()
    for row in range(ROWS):
        var row_walls: Array = []
        var line: String = MAZE[row]
        for col in range(COLS):
            var c: String = line.substr(col, 1)
            row_walls.append(c == "#")
            if c == "S":
                player_start = _cell_center(col, row)
            elif c == "E":
                exit_pos = _cell_center(col, row)
        walls.append(row_walls)

func _cell_center(col: int, row: int) -> Vector2:
    return Vector2((col + 0.5) * TILE_SIZE, (row + 0.5) * TILE_SIZE)

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    label_hud = Label.new()
    label_hud.add_theme_font_size_override("font_size", 16)
    label_hud.position = Vector2(10, 6)
    label_hud.size = Vector2(court_size.x - 20, 24)
    canvas.add_child(label_hud)

    label_center = Label.new()
    label_center.add_theme_font_size_override("font_size", 26)
    label_center.position = Vector2(0, court_size.y * 0.40)
    label_center.size = Vector2(court_size.x, 140)
    label_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    canvas.add_child(label_center)

# ============================================================
# Patrol routes — one Array of cell-centers per guard. Each
# guard walks its own loop. Routes are designed by eye to:
#   - Stay inside corridors (no waypoint inside a wall)
#   - Cover the corner each guard "owns" so the player has
#     to time crossings between zones
#   - Force at least one direction-change per loop (so the
#     guard's facing rotates and vision cone sweeps the area)
#
# Living in the driver, not in Frame, because the maze is
# the driver's concern. Frame just receives the route at
# init() time as opaque Vector2 list.
# ============================================================
func _patrol_for(guard_index: int) -> Array:
    # Each guard's loop must consist entirely of straight-line
    # segments through open cells — guards walk straight toward
    # their next waypoint, with simple slide-against-wall
    # collision but no pathfinding. A waypoint behind a wall, or
    # a segment that crosses a wall, would wedge the guard.
    #
    # The new maze has three open horizontal "rooms" connected
    # by narrow gates. We give each guard a loop that stays
    # inside one room.
    match guard_index:
        0:
            # Top zone — rows 1-3 are wide-open. Triangle loop.
            return [
                _cell_center(2, 1),
                _cell_center(13, 1),
                _cell_center(7, 3),
            ]
        1:
            # Middle — patrol along row 5, which is the long
            # connecting corridor. Guard sweeps left-mid-right.
            return [
                _cell_center(3, 5),
                _cell_center(8, 5),
                _cell_center(12, 5),
            ]
        2:
            # Bottom — rows 9-10 are open. Loop covers the exit
            # area so reaching E is the climactic crossing.
            return [
                _cell_center(2, 9),
                _cell_center(13, 9),
                _cell_center(13, 10),
                _cell_center(2, 10),
            ]
        _:
            return []

# ============================================================
func _physics_process(delta: float) -> void:
    var state: String = fsm.get_state()

    if state == "attract":
        if Input.is_anything_pressed():
            _start_run()
        _update_labels()
        queue_redraw()
        return

    if state == "caught" or state == "escaped":
        if Input.is_key_pressed(KEY_R) and not _r_was_down:
            _r_was_down = true
            fsm.restart()
            player_pos = player_start
        elif not Input.is_key_pressed(KEY_R):
            _r_was_down = false
        _update_labels()
        queue_redraw()
        return

    # --- $Playing ---

    _move_player(delta)

    # Move each guard toward the target Frame chose for it,
    # but ONLY if Frame says it should be moving (Idle,
    # Investigating, Searching, Engaged are all stationary).
    # Update facing toward whichever direction "matters" for
    # the current state — see _facing_target_for().
    for i in range(3):
        var guard = _guards()[i]
        if guard.should_move():
            guard_pos[i] = _step_with_collision(
                guard_pos[i], guard.get_target(), guard.speed, delta, guard_radius)
        var look_at: Vector2 = _facing_target_for(i, guard)
        guard_facing[i] = _smooth_face(guard_facing[i], guard_pos[i], look_at, delta)

    # Tick the Frame side, passing each guard's actual current
    # position so the FSM can decide things like "have I
    # reached the waypoint?" or "am I close to last_known?"
    fsm.tick(delta, guard_pos[0], guard_pos[1], guard_pos[2])

    # Perception: for each guard, if vision cone + LOS hits
    # the player, fire spot_player. Otherwise stay quiet (the
    # absence of events is the "lost sight" signal).
    for i in range(3):
        if _can_see_player(i):
            _guards()[i].spot_player(player_pos)

    # Catch and escape detection.
    for i in range(3):
        if guard_pos[i].distance_to(player_pos) < catch_radius:
            fsm.guard_caught_player(i)
            break
    if player_pos.distance_to(exit_pos) < TILE_SIZE * 0.45:
        fsm.player_at_exit()

    _update_labels()
    queue_redraw()

# Sub-system access. After @@[persist] restore_state, the
# guard refs may be new instances; always go through fsm
# rather than caching.
func _guards() -> Array:
    return [fsm.guard1, fsm.guard2, fsm.guard3]

func _start_run() -> void:
    player_pos = player_start
    fsm.start(_patrol_for(0), _patrol_for(1), _patrol_for(2))

# ============================================================
# Player movement — continuous, with simple AABB-vs-grid
# collision. Faster sliding on diagonals because that's how
# the genre feels; classical arcade stealth doesn't bother
# normalizing.
# ============================================================
func _move_player(delta: float) -> void:
    var dir := Vector2.ZERO
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):  dir.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):    dir.y -= 1.0
    if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):  dir.y += 1.0
    if dir.length() == 0.0:
        _player_is_moving = false
        return
    _player_is_moving = true
    _player_facing = dir.normalized().angle()
    _player_anim_phase += delta * 12.0     # leg-swing cycles per second
    var step: Vector2 = dir.normalized() * player_speed * delta
    # Slide axis-by-axis so a wall on one axis doesn't kill
    # motion on the other.
    var nx := player_pos + Vector2(step.x, 0)
    if not _circle_blocked(nx, player_radius):
        player_pos = nx
    var ny := player_pos + Vector2(0, step.y)
    if not _circle_blocked(ny, player_radius):
        player_pos = ny

# ============================================================
# Generic circle-vs-grid collision: take a step toward a
# target at a given speed, with axis-by-axis sliding. Used
# both for guards (toward Frame's get_target) and for the
# player movement above.
# ============================================================
func _step_with_collision(from: Vector2, to: Vector2, speed: float,
                          delta: float, radius: float) -> Vector2:
    var diff: Vector2 = to - from
    var dist: float = diff.length()
    if dist < 0.5:
        return from
    var step_size: float = min(speed * delta, dist)
    var dir: Vector2 = diff / dist
    var step: Vector2 = dir * step_size
    var pos: Vector2 = from
    var nx: Vector2 = pos + Vector2(step.x, 0)
    if not _circle_blocked(nx, radius):
        pos = nx
    var ny: Vector2 = pos + Vector2(0, step.y)
    if not _circle_blocked(ny, radius):
        pos = ny
    return pos

func _circle_blocked(pos: Vector2, radius: float) -> bool:
    # Sample the four cardinal points around the circle. If
    # any is inside a wall cell, block. Cheap and good enough
    # for the small radii we use.
    var samples: Array = [
        pos + Vector2(radius, 0),
        pos + Vector2(-radius, 0),
        pos + Vector2(0, radius),
        pos + Vector2(0, -radius),
    ]
    for s in samples:
        var col: int = int(s.x / TILE_SIZE)
        var row: int = int(s.y / TILE_SIZE)
        if col < 0 or col >= COLS or row < 0 or row >= ROWS:
            return true
        if walls[row][col]:
            return true
    return false

# ============================================================
# Facing — what direction should the guard be looking?
# Patrolling: toward the next waypoint (so the cone leads
# the walk). Investigating/Searching/Alerted: toward
# last_known (we want to scan the suspicious area). _smooth_face
# rotates gradually so the cone doesn't snap.
# ============================================================
func _facing_target_for(_index: int, guard) -> Vector2:
    match guard.get_state():
        "patrolling", "idle":
            return guard.get_target()
        _:
            return guard.get_last_known()

func _smooth_face(current: float, from: Vector2, to: Vector2, delta: float) -> float:
    if from.distance_to(to) < 1.0:
        return current
    var desired: float = (to - from).angle()
    return rotate_toward(current, desired, 4.0 * delta)

# ============================================================
# Vision: cone test + line-of-sight on the maze grid. Cheap
# and obviously correct.
# ============================================================
func _can_see_player(guard_index: int) -> bool:
    var gp: Vector2 = guard_pos[guard_index]
    var to_player: Vector2 = player_pos - gp
    var d: float = to_player.length()
    if d > vision_range or d < 0.5:
        return d < 0.5     # right on top of player counts as seen
    var angle_to_player: float = to_player.angle()
    var diff: float = wrapf(angle_to_player - guard_facing[guard_index], -PI, PI)
    if abs(diff) > vision_half_angle:
        return false
    return _los_clear(gp, player_pos)

func _los_clear(from: Vector2, to: Vector2) -> bool:
    # March in fixed steps along the line, checking the cell
    # at each sample. Step of 6 px is fine-grained enough that
    # a 50-px wall is never "stepped over."
    var step_px: float = 6.0
    var diff: Vector2 = to - from
    var d: float = diff.length()
    if d == 0.0:
        return true
    var n: int = int(ceil(d / step_px))
    var step: Vector2 = diff / float(n)
    var p: Vector2 = from
    for i in range(n):
        p = p + step
        var col: int = int(p.x / TILE_SIZE)
        var row: int = int(p.y / TILE_SIZE)
        if col < 0 or col >= COLS or row < 0 or row >= ROWS:
            return false
        if walls[row][col]:
            return false
    return true

# ============================================================
func _update_labels() -> void:
    var elapsed: float = fsm.get_elapsed()
    label_hud.text = "TIME  %5.1fs    Reach the exit (E) without being seen" % elapsed
    match fsm.get_state():
        "attract":
            label_center.text = "S T E A L T H\n\nReach E without entering a guard's vision cone\n\n↑↓←→ move    Press any key to start"
        "playing":
            label_center.text = ""
        "caught":
            label_center.text = "CAUGHT BY GUARD %d\n\n%5.1fs survived    Press R to restart" % [
                fsm.get_caught_by() + 1, elapsed]
        "escaped":
            label_center.text = "ESCAPED IN %5.1fs\n\nPress R for another run" % elapsed
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    # Maze
    var wall_col := Color(0.18, 0.20, 0.28)
    var floor_col := Color(0.07, 0.08, 0.11)
    draw_rect(Rect2(Vector2.ZERO, court_size), floor_col)
    for row in range(ROWS):
        for col in range(COLS):
            if walls[row][col]:
                draw_rect(Rect2(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE), wall_col)

    # Exit
    var exit_pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 220.0)
    draw_rect(Rect2(exit_pos - Vector2(TILE_SIZE, TILE_SIZE) * 0.45,
                    Vector2(TILE_SIZE, TILE_SIZE) * 0.9),
              Color(0.2, 0.95, 0.5, exit_pulse))

    var state: String = fsm.get_state()

    # Vision cones
    for i in range(3):
        _draw_vision_cone(i)

    # Guards
    for i in range(3):
        _draw_guard(i)

    # Player — only while playing or attract; hide on caught
    # so the explosion-of-the-cone effect isn't muddled.
    if state != "caught":
        _draw_player()

func _draw_player() -> void:
    # Top-down stick figure in bright yellow — clearly distinct
    # from the cool-blue/yellow/red guards and the green exit.
    # Shape: head circle, body, two arms, two legs that swing
    # opposite when running. A small triangle nose indicates
    # facing.
    var body_col := Color(1.0, 0.92, 0.20)        # hot yellow
    var limb_col := Color(0.85, 0.65, 0.10)       # darker outline
    var head_col := Color(1.0, 0.85, 0.55)        # skin

    var dir := Vector2(cos(_player_facing), sin(_player_facing))
    var perp := Vector2(-dir.y, dir.x)

    var swing: float = 0.0
    if _player_is_moving:
        swing = sin(_player_anim_phase) * 5.5

    # Legs first so the body covers the hip joint.
    var hip: Vector2 = player_pos - dir * 1.0
    var leg_a: Vector2 = hip - dir * 5.0 + perp * (3.0 + swing)
    var leg_b: Vector2 = hip - dir * 5.0 - perp * (3.0 - swing)
    draw_line(hip, leg_a, limb_col, 2.5)
    draw_line(hip, leg_b, limb_col, 2.5)

    # Arms — swing opposite to legs for a natural gait.
    var shoulder: Vector2 = player_pos + dir * 1.0
    var arm_a: Vector2 = shoulder + dir * 3.0 + perp * (5.0 - swing)
    var arm_b: Vector2 = shoulder + dir * 3.0 - perp * (5.0 + swing)
    draw_line(shoulder, arm_a, limb_col, 2.0)
    draw_line(shoulder, arm_b, limb_col, 2.0)

    # Body — yellow filled circle, slightly larger than guards
    # for legibility.
    draw_circle(player_pos, player_radius + 1.0, body_col)

    # Head — small circle slightly forward of body center.
    draw_circle(player_pos + dir * 2.0, player_radius * 0.55, head_col)

    # Tiny direction nose so the player can confirm facing at
    # a glance without watching a full step cycle.
    var nose: Vector2 = player_pos + dir * (player_radius + 4.0)
    draw_line(player_pos + dir * (player_radius - 2.0), nose, Color(1, 1, 1), 1.5)

func _draw_guard(index: int) -> void:
    var gp: Vector2 = guard_pos[index]
    var aware: bool = _guards()[index].is_alerted()
    var col: Color
    if aware:
        col = Color(0.95, 0.45, 0.45)
    elif _guards()[index].is_aware():
        col = Color(0.95, 0.85, 0.45)
    else:
        col = Color(0.7, 0.75, 0.85)
    draw_circle(gp, guard_radius, col)
    # A small notch indicating facing.
    var nose: Vector2 = gp + Vector2(cos(guard_facing[index]), sin(guard_facing[index])) * (guard_radius + 4)
    draw_line(gp, nose, Color(1, 1, 1, 0.8), 2.0)

func _draw_vision_cone(index: int) -> void:
    var gp: Vector2 = guard_pos[index]
    var facing: float = guard_facing[index]
    # Tint the cone red when the guard is alerted, yellow when
    # aware, dim white otherwise. Lets the player read intent
    # at a glance.
    var fill: Color
    if _guards()[index].is_alerted():
        fill = Color(0.95, 0.45, 0.45, 0.18)
    elif _guards()[index].is_aware():
        fill = Color(0.95, 0.85, 0.45, 0.16)
    else:
        fill = Color(0.85, 0.9, 1.0, 0.10)
    var pts := PackedVector2Array()
    pts.append(gp)
    var n_steps: int = 18
    for i in range(n_steps + 1):
        var t: float = -vision_half_angle + (2.0 * vision_half_angle) * (float(i) / float(n_steps))
        var dir := Vector2(cos(facing + t), sin(facing + t))
        # Walk the ray until LOS breaks or we hit max range.
        var max_d: float = vision_range
        var probe_step: float = 6.0
        var dist: float = 0.0
        var p: Vector2 = gp
        while dist < max_d:
            p = p + dir * probe_step
            dist = dist + probe_step
            var col: int = int(p.x / TILE_SIZE)
            var row: int = int(p.y / TILE_SIZE)
            if col < 0 or col >= COLS or row < 0 or row >= ROWS:
                break
            if walls[row][col]:
                break
        pts.append(p)
    draw_colored_polygon(pts, fill)

# ============================================================
# Esc handling for the standalone chapter project — quit.
# The cabinet driver overrides this with Arcade.return_to_menu.
# ============================================================
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        get_tree().quit()
