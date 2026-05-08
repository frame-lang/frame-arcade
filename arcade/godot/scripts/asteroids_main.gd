# ============================================================
# Asteroids — Cabinet driver (main.gd, with save/resume)
# ============================================================
# Owns an Asteroids Frame state machine, handles ship physics
# (rotation, thrust, inertia, screen wrap), renders asteroids
# and bullets, detects collisions.
#
# Cabinet additions on top of the chapter version:
#
#   1. Pause menu. Esc (or P) opens an in-game menu with three
#      options — Resume / Save & exit / Exit without saving —
#      navigated with ↑/↓ and confirmed with Enter. Esc from
#      inside the menu resumes (it's a natural cancel).
#
#   2. Save & resume across cabinet sessions. The "Save &
#      exit" option writes the FSM and driver-physics state
#      to user://asteroids.save. On the next launch, if a
#      save file is present, _ready() restores everything and
#      drops the player back into $Paused — the same pause
#      menu they left, with asteroids frozen in their last
#      positions. Picking Resume returns control to the
#      pushed sub-state via -> pop$.
#
#      The Frame side does the heavy lifting: a single call
#      to fsm.save_state() round-trips the entire FSM tree
#      (Asteroids, Ship, AsteroidField, plus the pushed
#      compartment under $Paused). The driver only bundles
#      its own non-FSM state — ship_pos/vel/angle, bullets —
#      alongside the FSM bytes.
#
#   3. Game over deletes the save. The run is over; nothing
#      to resume.
#
#   4. Esc routing. In a saved-game-aware cabinet, Esc has
#      different jobs in different states:
#        attract     → return to cabinet menu
#        playing/etc → open pause menu
#        paused      → resume (cancel)
#        game_over   → return to cabinet menu
#      See _input() at the bottom.
# ============================================================
extends Node2D

const AsteroidsFSM = preload("res://scripts/asteroids.gd")

# Save format. Versioned so a future format change can detect
# and discard incompatible saves rather than crash on load.
# The path is owned by the Arcade autoload (so the cabinet
# menu's has_save / delete_save and this driver agree on a
# single location) — see arcade/godot/scripts/arcade.gd's
# save_path() helper.
@onready var SAVE_PATH: String = Arcade.save_path("asteroids")
const SAVE_VERSION: int = 1

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
# fsm: the Frame Asteroids system. Contains Ship, AsteroidField,
# and all the gameplay state machine logic. The driver delegates
# every game-rule decision to it.
var fsm

# Driver-owned ship physics. These ride the Frame system's mode
# (the FSM decides whether the ship can be hit or fire) but the
# physics integration runs here in Godot's _physics_process so
# we can use Godot input and Vector2 math directly.
var ship_pos: Vector2
var ship_vel: Vector2
var ship_angle: float = -PI * 0.5      # pointing up
var ship_shot_timer: float = 0.0
var bullets: Array = []                # each: { pos: Vector2, vel: Vector2, life: float }

# Edge-detected key state. Several keys (P for pause, H for
# hyperspace, ↑↓Enter for pause menu) need to fire once per
# press, not once per frame held.
var _p_was_down: bool = false
var _h_was_down: bool = false

# Ship-state edge detector for the hyperspace teleport. When
# the ship transitions from "hyperspace" to "alive", we randomize
# the ship position. Watching the previous state is the cleanest
# way to detect the pop without changing the Frame interface.
# (The chapter README discusses this trade-off in detail.)
var _last_ship_state: String = "alive"

# Cabinet integration: post the final score to the persistent
# Scoreboard once per game-over. _last_top_state is the rising-
# edge detector so we don't post repeatedly while sitting on the
# game-over screen.
var _last_top_state: String = ""

# --- Pause menu ---
# Selection cursor and the option labels. _pause_selection is a
# UI concern — the FSM is in $Paused regardless of which option
# is highlighted.
const _PAUSE_OPTIONS: Array = [
    "Resume",
    "Save & exit to menu",
    "Exit without saving",
]
var _pause_selection: int = 0

# Pause-state rising edge: when we transition from not-paused
# to paused, we (re)seed the menu defaults. This fires both for
# fresh pauses (player hit Esc/P during play) and for restored-
# from-disk launches (where the FSM is already in $Paused on
# the first frame).
var _was_paused: bool = false

# Edge-detected pause-menu navigation keys. Separate from the
# in-game key edge detectors because in-game and pause-menu use
# the same keys for different actions, and we want clean edges
# at the moment of transition.
var _pause_up_was_down: bool = false
var _pause_down_was_down: bool = false
var _pause_enter_was_down: bool = false

# --- UI ---
# Two labels stacked on the same canvas:
#
#   label_hud    — top bar, always visible (score/lives/wave/diff)
#   label_center — short messages: "PAUSED", "WAVE CLEAR",
#                  "GAME OVER", attract-screen blurb. One line.
#   label_pause  — multi-line pause menu, only visible while
#                  fsm.is_paused().
#
# Splitting the brief center text from the multi-line pause menu
# keeps each label's font size, position, and alignment tuned for
# its purpose without conditional resizing.
var label_hud: Label
var label_center: Label
var label_pause: Label

# ============================================================
func _ready() -> void:
    fsm = AsteroidsFSM.new(difficulty)
    _build_ui()
    _reset_ship()

    # If a saved run exists, restore both the FSM and our local
    # physics state. This must run AFTER _reset_ship() so the
    # restored values overwrite the defaults.
    if FileAccess.file_exists(SAVE_PATH):
        _load_run()

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

    label_pause = Label.new()
    label_pause.add_theme_font_size_override("font_size", 22)
    label_pause.position = Vector2(0, court_size.y * 0.30)
    label_pause.size = Vector2(court_size.x, court_size.y * 0.55)
    label_pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_pause.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    label_pause.visible = false
    canvas.add_child(label_pause)

# ============================================================
func _physics_process(delta: float) -> void:
    # Detect pause rising edge so we can seed the menu's default
    # selection and edge-detector state. This handles both
    # paths into $Paused: (a) the player pressed Esc/P during
    # play, (b) the scene was just loaded from disk into a
    # saved $Paused state.
    var paused_now: bool = fsm.is_paused()
    if paused_now and not _was_paused:
        _enter_pause_menu()
    _was_paused = paused_now

    _handle_input(delta)

    var state: String = fsm.get_state()

    if not paused_now and state != "attract" and state != "game_over":
        fsm.tick(delta, court_size)

        # Ship physics — integrate velocity, wrap screen, etc.
        # All of this is deliberately driver-side: see the chapter
        # README's "Honest Quirk of the Driver" section.
        _update_ship(delta)
        _update_bullets(delta)

        _check_collisions()

    _update_labels()
    queue_redraw()
    _post_score_if_needed()

# ============================================================
func _post_score_if_needed() -> void:
    var s: String = fsm.get_state()
    if s == "game_over" and _last_top_state != "game_over":
        Arcade.record_score("asteroids", fsm.get_score())
        # The run is finished; there's nothing meaningful left
        # to resume. Delete the save so the next launch sees a
        # clean slate (and the cabinet menu won't offer to
        # "continue" a game that just ended).
        _delete_save()
    _last_top_state = s

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

    # Paused: input drives the pause menu, no game input
    # processed. _handle_pause_menu_input also handles the P
    # key (toggles back to playing) so P stays consistent with
    # its in-game behavior.
    if fsm.is_paused():
        _handle_pause_menu_input()
        return

    # Pause toggle (edge-detected). When pressed during play,
    # transitions the FSM to $Paused and the next frame's
    # rising-edge detector will seed the pause menu defaults.
    if Input.is_key_pressed(KEY_P) and not _p_was_down:
        _p_was_down = true
        fsm.pause()
        return
    elif not Input.is_key_pressed(KEY_P):
        _p_was_down = false

    # Ship controls only work when the ship is visible (not
    # mid-hyperspace, not on game over, etc.).
    if not fsm.ship.is_visible():
        return

    # Rotation
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        ship_angle -= ship_rotation_speed * delta
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        ship_angle += ship_rotation_speed * delta

    # Thrust — only when alive or invuln (during respawn).
    if fsm.ship.get_state() == "alive" or fsm.ship.get_state() == "respawning":
        if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
            ship_vel += Vector2(cos(ship_angle), sin(ship_angle)) * ship_thrust * delta
            if ship_vel.length() > ship_max_speed:
                ship_vel = ship_vel.normalized() * ship_max_speed

    # Fire
    ship_shot_timer = max(0.0, ship_shot_timer - delta)
    if fsm.ship.can_fire():
        if Input.is_key_pressed(KEY_SPACE):
            _try_fire()

    # Hyperspace (edge-detected to prevent repeated triggers
    # on a long press).
    if Input.is_key_pressed(KEY_H) and not _h_was_down:
        _h_was_down = true
        fsm.ship_hyperspace()
    elif not Input.is_key_pressed(KEY_H):
        _h_was_down = false

# ------------------------------------------------------------
# Pause menu navigation
# ------------------------------------------------------------
func _enter_pause_menu() -> void:
    # Reset the cursor to "Resume" — that's the friendly default;
    # players are unlikely to want to discard their run by reflex.
    _pause_selection = 0

    # Seed the edge detectors from the current key state so a
    # held key from the moment of pause doesn't immediately move
    # the selection. Specifically: if the player held Down to dive
    # away from an asteroid and slammed Esc on the same frame,
    # we don't want the menu's first frame to interpret that
    # held Down as "move selection".
    _pause_up_was_down = Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
    _pause_down_was_down = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
    _pause_enter_was_down = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)
    # _p_was_down is shared with in-game pause toggle and seeded
    # whenever P state changes; no special handling needed here.

func _handle_pause_menu_input() -> void:
    var up: bool = Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
    var down: bool = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
    var enter: bool = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)
    var p: bool = Input.is_key_pressed(KEY_P)

    if up and not _pause_up_was_down:
        _pause_selection = (_pause_selection - 1 + _PAUSE_OPTIONS.size()) % _PAUSE_OPTIONS.size()
    if down and not _pause_down_was_down:
        _pause_selection = (_pause_selection + 1) % _PAUSE_OPTIONS.size()
    if enter and not _pause_enter_was_down:
        _confirm_pause_selection()
    if p and not _p_was_down:
        # P toggles pause both ways for symmetry with the in-game
        # behavior — the player's muscle memory says "P = the
        # pause key", whether currently paused or not.
        fsm.resume()

    _pause_up_was_down = up
    _pause_down_was_down = down
    _pause_enter_was_down = enter
    _p_was_down = p

func _confirm_pause_selection() -> void:
    match _pause_selection:
        0:
            # Resume — the FSM's pop$ takes us back to the pushed
            # compartment ($Playing, $ShipDying, or $WaveClear)
            # with every state variable restored.
            fsm.resume()
        1:
            # Save the entire run, then leave the scene. The save
            # write is synchronous and small (few KB), so doing it
            # before the scene change keeps the flow simple.
            _save_run()
            Arcade.return_to_menu()
        2:
            # Exit without touching the save file. If a previous
            # save exists, it survives unchanged; the player can
            # re-launch and continue from that older point.
            Arcade.return_to_menu()

# ============================================================
func _update_ship(delta: float) -> void:
    if not fsm.ship.is_visible():
        return

    # Drag
    ship_vel *= (1.0 - ship_drag * delta)

    # Integrate
    ship_pos += ship_vel * delta

    # Screen wrap
    if ship_pos.x < 0.0:           ship_pos.x += court_size.x
    if ship_pos.x > court_size.x:  ship_pos.x -= court_size.x
    if ship_pos.y < 0.0:           ship_pos.y += court_size.y
    if ship_pos.y > court_size.y:  ship_pos.y -= court_size.y

    # If we just popped from hyperspace, teleport. The Frame
    # system handles the mode change; the visible "appear at a
    # random spot" effect lives here. The chapter README's
    # "Honest Quirk of the Driver" section discusses why.
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
    # Classic Asteroids: 4 bullets max on screen.
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

    if fsm.is_paused():
        # Multi-line pause menu via label_pause. label_center is
        # hidden so we don't render a second "PAUSED" on top.
        var lines := PackedStringArray()
        lines.append("PAUSED")
        lines.append("")
        for i in range(_PAUSE_OPTIONS.size()):
            var prefix: String = ">  " if i == _pause_selection else "    "
            lines.append(prefix + _PAUSE_OPTIONS[i])
        lines.append("")
        lines.append("↑/↓ select    Enter confirm    Esc resume")
        label_pause.text = "\n".join(lines)
        label_pause.visible = true
        label_center.visible = false
        return

    # Not paused — restore label_center visibility and pick
    # the brief message for the current state.
    label_pause.visible = false
    label_center.visible = true
    match fsm.get_state():
        "attract":
            label_center.text = "A S T E R O I D S\n\nPress any key to start\n(H = hyperspace, P = pause)"
        "playing":
            label_center.text = ""
        "ship_dying":
            label_center.text = ""
        "wave_clear":
            label_center.text = "WAVE CLEAR"
        "game_over":
            label_center.text = "GAME OVER\n\nPress R to restart"
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    var white := Color(1, 1, 1)
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
            # Blink while respawning to signal invulnerability.
            var visible: bool = true
            if ship_state == "respawning":
                visible = int(Time.get_ticks_msec() / 100) % 2 == 0
            if visible:
                _draw_ship(ship_pos, ship_angle)

func _draw_ship(at: Vector2, angle: float) -> void:
    # Classic triangle ship.
    var white := Color(1, 1, 1)
    var nose: Vector2 = at + Vector2(cos(angle), sin(angle)) * ship_size
    var left: Vector2 = at + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * ship_size
    var right: Vector2 = at + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * ship_size
    draw_line(nose, left, white, 1.5)
    draw_line(left, right, white, 1.5)
    draw_line(right, nose, white, 1.5)

    # Thruster flame while thrusting.
    if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
        if fsm.ship.get_state() == "alive" or fsm.ship.get_state() == "respawning":
            var tail_base: Vector2 = (left + right) * 0.5
            var tail_tip: Vector2 = at - Vector2(cos(angle), sin(angle)) * ship_size * 1.4
            draw_line(tail_base, tail_tip, Color(1, 0.6, 0.2), 1.5)

func _draw_asteroid(at: Vector2, radius: float) -> void:
    # Simple jagged polygon — 10 points with a deterministic
    # per-position hash for the radius jitter so the shape
    # doesn't shimmer between frames.
    var white := Color(1, 1, 1)
    var points := PackedVector2Array()
    var n: int = 10
    var i: int = 0
    var seed_h: int = int(at.x * 100) + int(at.y * 100) * 31
    while i < n:
        var t: float = (float(i) / float(n)) * TAU
        var jitter: float = 0.75 + _hash01(seed_h + i) * 0.35
        var p: Vector2 = at + Vector2(cos(t), sin(t)) * radius * jitter
        points.append(p)
        i += 1
    i = 0
    while i < n:
        var p1: Vector2 = points[i]
        var p2: Vector2 = points[(i + 1) % n]
        draw_line(p1, p2, white, 1.5)
        i += 1

func _hash01(k: int) -> float:
    # Cheap deterministic hash to [0, 1).
    var x: int = (k * 2654435761) & 0xffffffff
    x = ((x >> 16) ^ x) * 0x45d9f3b
    x = x & 0xffffffff
    return float(x & 0xffff) / 65536.0

func _draw_explosion(at: Vector2) -> void:
    var col := Color(1, 0.7, 0.3)
    var i: int = 0
    while i < 8:
        var t: float = float(i) / 8.0 * TAU
        var p1: Vector2 = at + Vector2(cos(t), sin(t)) * 4.0
        var p2: Vector2 = at + Vector2(cos(t), sin(t)) * 14.0
        draw_line(p1, p2, col, 2.0)
        i += 1

# ============================================================
# Save / restore
# ============================================================
# The save bundle is a Dictionary serialized via var_to_bytes.
# Layout:
#
#   {
#       "version": int,       # SAVE_VERSION (1)
#       "fsm":     PackedByteArray,   # fsm.save_state()
#       "driver":  Dictionary,
#                   ship_pos, ship_vel, ship_angle,
#                   ship_shot_timer, bullets, last_ship_state
#   }
#
# fsm.save_state() round-trips Asteroids + Ship + AsteroidField
# in one call (framec auto-traverses composed @@[persist]
# sub-systems). We only have to bundle the driver-side physics
# state alongside.
# ============================================================
func _save_run() -> void:
    var bundle: Dictionary = {
        "version": SAVE_VERSION,
        "fsm": fsm.save_state(),
        "driver": {
            "ship_pos": ship_pos,
            "ship_vel": ship_vel,
            "ship_angle": ship_angle,
            "ship_shot_timer": ship_shot_timer,
            "bullets": bullets,
            "last_ship_state": _last_ship_state,
        },
    }
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        push_warning("Asteroids save: could not write " + SAVE_PATH)
        return
    f.store_buffer(var_to_bytes(bundle))
    f.close()

func _load_run() -> void:
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if f == null:
        push_warning("Asteroids load: could not open " + SAVE_PATH)
        return
    var data := f.get_buffer(f.get_length())
    f.close()
    if data.size() == 0:
        return
    var bundle = bytes_to_var(data)
    if typeof(bundle) != TYPE_DICTIONARY:
        push_warning("Asteroids load: corrupt save (root not a Dictionary); ignoring")
        return
    if bundle.get("version", 0) != SAVE_VERSION:
        # A future format change can land here; treat the
        # incompatible save as missing rather than crashing.
        push_warning("Asteroids load: incompatible save version; ignoring")
        return

    # Restore the FSM tree. After this call, fsm.ship and
    # fsm.field are NEW instances (the parent's restore_state
    # allocates them fresh and dispatches their slice of the
    # saved bytes). Don't cache references to fsm.ship/field
    # across restores — always go through fsm.
    var fsm_bytes = bundle.get("fsm", null)
    if fsm_bytes is PackedByteArray and fsm_bytes.size() > 0:
        fsm.restore_state(fsm_bytes)

    # Restore driver-side physics. .get(...) with sensible
    # fallbacks guards against forward-compatible saves that
    # lack a field.
    var d: Dictionary = bundle.get("driver", {})
    ship_pos = d.get("ship_pos", court_size * 0.5)
    ship_vel = d.get("ship_vel", Vector2.ZERO)
    ship_angle = d.get("ship_angle", -PI * 0.5)
    ship_shot_timer = d.get("ship_shot_timer", 0.0)
    bullets = d.get("bullets", [])
    _last_ship_state = d.get("last_ship_state", "alive")

    # Force the next _physics_process to detect a pause rising
    # edge so the menu defaults get seeded. Without this, a
    # restored-into-$Paused launch would leave the cursor at
    # whatever value _pause_selection had at startup (which is
    # 0 anyway, but the edge-detector seeding matters too).
    _was_paused = false

func _delete_save() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# ============================================================
# Esc routing
# ============================================================
# Esc means different things in different states:
#
#   attract     — no run in progress; treat Esc as "back to menu"
#   playing/etc — open the pause menu
#   paused      — resume (Esc as a natural cancel)
#   game_over   — back to menu
#
# Handled in _input rather than _handle_input so we can call
# set_input_as_handled() and stop the event from cascading.
# ============================================================
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        var state: String = fsm.get_state()
        if state == "paused":
            fsm.resume()
        elif state == "attract" or state == "game_over":
            Arcade.return_to_menu()
        else:
            # In-game (playing, ship_dying, wave_clear) — pause.
            fsm.pause()
