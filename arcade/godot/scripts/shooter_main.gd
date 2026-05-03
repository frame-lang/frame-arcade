# ============================================================
# Side-Scrolling Shooter — Godot driver (main.gd)
# ============================================================
# Owns a Shooter state machine. Drives player, spawns enemies
# on the Shooter FSM's request, handles bullet physics,
# collision detection, and all rendering.
# ============================================================
extends Node2D

const ShooterFSM = preload("res://scripts/shooter.gd")

# --- Court ---
@export var court_size: Vector2 = Vector2(800, 600)

# --- Player ---
@export var player_size: Vector2 = Vector2(28, 14)
@export var player_speed: float = 260.0
@export var player_shot_cooldown: float = 0.18
@export var player_bullet_speed: float = 600.0
@export var player_bullet_size: Vector2 = Vector2(8, 3)

# --- Enemy visuals ---
@export var enemy_size: Vector2 = Vector2(24, 18)
@export var enemy_bullet_speed: float = 260.0
@export var enemy_bullet_size: Vector2 = Vector2(5, 5)

# --- Boss ---
@export var boss_size: Vector2 = Vector2(80, 80)
@export var boss_bullet_speed: float = 280.0

# --- Runtime ---
var fsm
var player_pos: Vector2
var player_shot_timer: float = 0.0

# Per-enemy rendering data, keyed by the Enemy instance itself.
# Using the instance as a dict key is safe because Enemy extends
# RefCounted — Godot keeps the object alive as long as it's
# referenced somewhere (which it is, from fsm.enemies). When the
# FSM removes an enemy from its array AND we remove it from this
# dict, it's freed.
#
# Each entry is { pos: Vector2, vel: Vector2, spawn_time: float }.
#
# This replaces the earlier "parallel arrays indexed by enemy index"
# approach, which broke when mid-array enemies were removed.
var enemy_data: Dictionary = {}

var player_bullets: Array = []  # each: Vector2 position
var enemy_bullets: Array = []   # each: { pos: Vector2, vel: Vector2 }

var boss_pos: Vector2 = Vector2.ZERO
var boss_vy: float = 60.0      # vertical oscillation
var boss_visible: bool = false

var rng := RandomNumberGenerator.new()

# Cabinet integration: post final score to Scoreboard once per
# session. Both `game_over` (death) and `victory` (boss killed)
# end the session — record either.
var _last_top_state: String = ""

# --- UI ---
var label_hud: Label
var label_center: Label

# ============================================================
func _ready() -> void:
    rng.randomize()
    fsm = ShooterFSM.new()

    boss_pos = Vector2(court_size.x - 100, court_size.y * 0.5)

    _build_ui()
    _reset_player()

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

func _reset_player() -> void:
    player_pos = Vector2(80, court_size.y * 0.5)

# ============================================================
func _physics_process(delta: float) -> void:
    _handle_input()

    var state: String = fsm.get_state()
    if state == "playing" or state == "boss_fight":
        fsm.tick(delta)

        _update_player(delta)
        _maybe_spawn_wave()
        _update_enemies(delta)
        _update_boss(delta)
        _update_bullets(delta)
        _check_collisions()
        fsm.clear_dead_enemies()
        _cleanup_enemy_data()

    _update_labels()
    queue_redraw()
    _post_score_if_needed()

# ============================================================
func _post_score_if_needed() -> void:
    var s: String = fsm.get_state()
    var ended: bool = (s == "game_over" or s == "victory")
    var was_ended: bool = (_last_top_state == "game_over" or _last_top_state == "victory")
    if ended and not was_ended:
        Arcade.record_score("shooter", fsm.get_score())
    _last_top_state = s

# ============================================================
func _handle_input() -> void:
    var state: String = fsm.get_state()

    if state == "attract":
        if Input.is_anything_pressed():
            fsm.start()
            _reset_player()
            player_bullets.clear()
            enemy_bullets.clear()
            enemy_data.clear()
            boss_visible = false
        return

    if state == "game_over" or state == "victory":
        if Input.is_key_pressed(KEY_R):
            fsm.restart()
        return

# ============================================================
func _update_player(delta: float) -> void:
    player_shot_timer = max(0.0, player_shot_timer - delta)

    if not fsm.player.is_visible():
        return

    var dir := Vector2.ZERO
    if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1.0
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
    if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1.0
    if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1.0
    if dir.length_squared() > 0.01:
        dir = dir.normalized()
    player_pos += dir * player_speed * delta
    player_pos.x = clamp(player_pos.x, 0.0, court_size.x - player_size.x)
    player_pos.y = clamp(player_pos.y, 0.0, court_size.y - player_size.y)

    # Fire
    if fsm.player.can_fire() and Input.is_key_pressed(KEY_SPACE):
        if player_shot_timer <= 0.0:
            var muzzle := Vector2(player_pos.x + player_size.x,
                                  player_pos.y + player_size.y * 0.5)
            player_bullets.append(muzzle)
            player_shot_timer = player_shot_cooldown

# ============================================================
func _maybe_spawn_wave() -> void:
    if not fsm.should_spawn_wave():
        return
    # Spawn 3 enemies of a random kind.
    var kind: int = rng.randi_range(0, 2)
    var i: int = 0
    while i < 3:
        _spawn_enemy(kind, Vector2(
            court_size.x + 30 + i * 40.0,
            60.0 + rng.randf() * (court_size.y - 120.0)))
        i += 1
    fsm.consume_wave()

func _spawn_enemy(kind: int, at: Vector2) -> void:
    var hp: int = 1
    var rate: float = 0.0
    var points: int = 50
    match kind:
        0:
            hp = 1;  rate = 1.5;  points = 50    # straight
        1:
            hp = 1;  rate = 2.0;  points = 80    # sine
        _:
            hp = 2;  rate = 2.5;  points = 150   # swoop

    var EnemyClass = ShooterFSM.Enemy
    var enemy = EnemyClass.new(kind, hp, rate, points)
    fsm.add_enemy(enemy)

    enemy_data[enemy] = {
        "pos": at,
        "vel": Vector2(-140.0, 0.0),
        "spawn_time": Time.get_ticks_msec() / 1000.0,
    }

# ============================================================
func _update_enemies(delta: float) -> void:
    # Iterate fsm.enemies by reference — positions are stored in
    # enemy_data keyed by the enemy instance itself, so indices
    # shifting (due to mid-array removal) doesn't matter.
    for enemy in fsm.enemies:
        if not enemy_data.has(enemy):
            continue
        _update_one_enemy(enemy, delta)
        _maybe_enemy_fire(enemy)

func _update_one_enemy(enemy, delta: float) -> void:
    if not enemy.is_alive():
        return

    var data: Dictionary = enemy_data[enemy]
    var kind: int = enemy.get_kind()
    var pos: Vector2 = data.pos

    match kind:
        0:  # straight
            pos += data.vel * delta
        1:  # sine
            var t: float = Time.get_ticks_msec() / 1000.0 - data.spawn_time
            pos.x += data.vel.x * delta
            pos.y = pos.y + sin(t * 3.0) * 60.0 * delta
        _:  # swoop
            var t2: float = Time.get_ticks_msec() / 1000.0 - data.spawn_time
            pos.x += data.vel.x * delta
            pos.y += sin(t2 * 1.5) * 120.0 * delta

    data.pos = pos

    # Enemies that exit the left side are removed by marking them as dying
    if pos.x < -60.0:
        enemy.hit(9999)    # force death to clean up

func _maybe_enemy_fire(enemy) -> void:
    if not enemy.is_alive():
        return
    if enemy.wants_to_fire():
        var data: Dictionary = enemy_data[enemy]
        var muzzle: Vector2 = data.pos + Vector2(0, enemy_size.y * 0.5)
        enemy_bullets.append({
            "pos": muzzle,
            "vel": Vector2(-enemy_bullet_speed, 0.0),
        })
        enemy.consume_fire()

# ============================================================
func _update_boss(delta: float) -> void:
    if not fsm.should_spawn_boss() and not boss_visible:
        return
    if fsm.should_spawn_boss():
        boss_visible = true
        boss_pos = Vector2(court_size.x - 120, court_size.y * 0.5)
        fsm.consume_boss_spawn()

    if not boss_visible:
        return
    if fsm.boss.is_gone():
        boss_visible = false
        return

    # Simple vertical oscillation
    boss_pos.y += boss_vy * delta
    if boss_pos.y < 80.0:
        boss_pos.y = 80.0
        boss_vy = abs(boss_vy)
    elif boss_pos.y + boss_size.y > court_size.y - 20.0:
        boss_pos.y = court_size.y - 20.0 - boss_size.y
        boss_vy = -abs(boss_vy)

    # Phase-specific firing
    if fsm.boss.wants_to_fire_single():
        _boss_fire_single()
        fsm.boss.consume_fire()
    elif fsm.boss.wants_to_fire_spread():
        _boss_fire_spread()
        fsm.boss.consume_fire()
    elif fsm.boss.wants_to_fire_spray():
        _boss_fire_spray()
        fsm.boss.consume_fire()

func _boss_fire_single() -> void:
    var muzzle: Vector2 = boss_pos + Vector2(0, boss_size.y * 0.5)
    enemy_bullets.append({
        "pos": muzzle,
        "vel": Vector2(-boss_bullet_speed, 0.0),
    })

func _boss_fire_spread() -> void:
    var muzzle: Vector2 = boss_pos + Vector2(0, boss_size.y * 0.5)
    var angles: Array = [-0.3, 0.0, 0.3]
    for a in angles:
        enemy_bullets.append({
            "pos": muzzle,
            "vel": Vector2(-boss_bullet_speed, 0.0).rotated(a),
        })

func _boss_fire_spray() -> void:
    var muzzle: Vector2 = boss_pos + Vector2(0, boss_size.y * 0.5)
    var angle: float = rng.randf_range(-0.6, 0.6)
    enemy_bullets.append({
        "pos": muzzle,
        "vel": Vector2(-boss_bullet_speed * 1.1, 0.0).rotated(angle),
    })

# ============================================================
func _update_bullets(delta: float) -> void:
    var i: int = player_bullets.size() - 1
    while i >= 0:
        player_bullets[i] += Vector2(player_bullet_speed * delta, 0)
        if player_bullets[i].x > court_size.x + 20.0:
            player_bullets.remove_at(i)
        i -= 1

    i = enemy_bullets.size() - 1
    while i >= 0:
        enemy_bullets[i].pos += enemy_bullets[i].vel * delta
        if enemy_bullets[i].pos.x < -20.0 or enemy_bullets[i].pos.x > court_size.x + 20.0:
            enemy_bullets.remove_at(i)
        elif enemy_bullets[i].pos.y < -20.0 or enemy_bullets[i].pos.y > court_size.y + 20.0:
            enemy_bullets.remove_at(i)
        i -= 1

# ============================================================
func _check_collisions() -> void:
    _check_player_bullets_vs_enemies()
    _check_player_bullets_vs_boss()
    _check_enemy_bullets_vs_player()
    _check_enemies_vs_player()

func _check_player_bullets_vs_enemies() -> void:
    # Iterate over bullets, find the first enemy each one hits, then
    # translate the enemy reference to its current FSM index for the
    # enemy_hit call (the Shooter FSM interface is index-based).
    var bullet_bounds: Vector2 = Vector2(3, 3)   # small bullet hit-radius
    var i: int = player_bullets.size() - 1
    while i >= 0:
        var b_rect := Rect2(player_bullets[i] - bullet_bounds * 0.5,
                            bullet_bounds)
        var hit_idx: int = -1
        var j: int = 0
        for enemy in fsm.enemies:
            if enemy.is_alive() and enemy_data.has(enemy):
                var r := Rect2(enemy_data[enemy].pos, enemy_size)
                if r.intersects(b_rect):
                    hit_idx = j
                    break
            j += 1
        if hit_idx >= 0:
            fsm.enemy_hit(hit_idx, 1)
            player_bullets.remove_at(i)
        i -= 1

func _check_player_bullets_vs_boss() -> void:
    if not boss_visible or not fsm.boss.is_alive():
        return
    var boss_rect := Rect2(boss_pos, boss_size)
    var i: int = player_bullets.size() - 1
    while i >= 0:
        if boss_rect.has_point(player_bullets[i]):
            fsm.boss_hit(1)
            player_bullets.remove_at(i)
        i -= 1

func _check_enemy_bullets_vs_player() -> void:
    if not fsm.player.can_be_hit():
        return
    var p_rect := Rect2(player_pos, player_size)
    var i: int = enemy_bullets.size() - 1
    while i >= 0:
        if p_rect.has_point(enemy_bullets[i].pos):
            fsm.player_hit()
            enemy_bullets.remove_at(i)
            return
        i -= 1

func _check_enemies_vs_player() -> void:
    if not fsm.player.can_be_hit():
        return
    var p_rect := Rect2(player_pos, player_size)
    var j: int = 0
    for enemy in fsm.enemies:
        if enemy.is_alive() and enemy_data.has(enemy):
            var r := Rect2(enemy_data[enemy].pos, enemy_size)
            if r.intersects(p_rect):
                fsm.player_hit()
                fsm.enemy_hit(j, 9999)
                return
        j += 1

# ============================================================
func _cleanup_enemy_data() -> void:
    # After fsm.clear_dead_enemies runs, the FSM removes $Gone
    # enemies from its array. We mirror that by removing any
    # dict entries whose enemy is no longer in fsm.enemies.
    var still_alive: Dictionary = {}
    for enemy in fsm.enemies:
        if enemy_data.has(enemy):
            still_alive[enemy] = enemy_data[enemy]
    enemy_data = still_alive

# ============================================================
func _update_labels() -> void:
    var phase_str: String = ""
    if fsm.get_state() == "boss_fight" and boss_visible:
        phase_str = "  BOSS P%d  HP %d%%" % [
            fsm.boss.get_phase(),
            int(fsm.boss.get_hp_fraction() * 100.0)]

    label_hud.text = "SCORE  %05d     LIVES  %d     ENEMIES  %d%s" % [
        fsm.get_score(), fsm.get_lives(), fsm.enemy_count(), phase_str]

    match fsm.get_state():
        "attract":
            label_center.text = "S H O O T E R\n\nPress any key to start"
        "boss_fight":
            if fsm.boss.is_dying():
                label_center.text = "B O S S   D E F E A T E D"
            elif fsm.boss.get_phase() == 3:
                label_center.text = ""
            else:
                label_center.text = ""
        "victory":
            label_center.text = "VICTORY!\n\nPress R to play again"
        "game_over":
            label_center.text = "GAME OVER\n\nPress R to restart"
        _:
            label_center.text = ""

# ============================================================
func _draw() -> void:
    # Starfield (decorative)
    _draw_starfield()

    # Player
    if fsm.player.is_visible():
        _draw_player()

    # Enemies — iterate the FSM's enemies and look up each by
    # reference in the enemy_data dict. No index alignment issues.
    for enemy in fsm.enemies:
        if not enemy_data.has(enemy):
            continue
        var state: String = enemy.get_state()
        var pos: Vector2 = enemy_data[enemy].pos
        if state == "active" or state == "spawning":
            _draw_enemy(pos, enemy.get_kind(), state == "spawning")
        elif state == "dying":
            _draw_explosion(pos + enemy_size * 0.5)

    # Boss
    if boss_visible and not fsm.boss.is_gone():
        _draw_boss()

    # Bullets
    for b in player_bullets:
        draw_rect(Rect2(b - player_bullet_size * 0.5, player_bullet_size), Color(1, 1, 0.3))
    for b in enemy_bullets:
        draw_rect(Rect2(b.pos - enemy_bullet_size * 0.5, enemy_bullet_size), Color(1, 0.4, 0.4))

func _draw_starfield() -> void:
    # Deterministic pseudo-random stars so they don't flicker
    var col := Color(0.8, 0.8, 1.0, 0.4)
    var i: int = 0
    while i < 60:
        var x: float = fmod(float(i * 131), court_size.x)
        var y: float = fmod(float(i * 79 + 17), court_size.y)
        draw_rect(Rect2(Vector2(x, y), Vector2(1, 1)), col)
        i += 1

func _draw_player() -> void:
    var col := Color(0.4, 1.0, 0.4)
    if fsm.player.get_state() == "exploding":
        _draw_explosion(player_pos + player_size * 0.5)
        return
    # Blink during invuln
    if fsm.player.get_state() == "invulnerable":
        if int(Time.get_ticks_msec() / 100) % 2 == 0:
            return
    # Arrow shape
    var pts := PackedVector2Array([
        Vector2(player_pos.x, player_pos.y),
        Vector2(player_pos.x, player_pos.y + player_size.y),
        Vector2(player_pos.x + player_size.x, player_pos.y + player_size.y * 0.5),
    ])
    draw_polygon(pts, PackedColorArray([col, col, col]))

func _draw_enemy(at: Vector2, kind: int, spawning: bool) -> void:
    var col: Color
    match kind:
        0: col = Color(1.0, 0.4, 0.4)        # red
        1: col = Color(0.9, 0.7, 0.3)        # orange
        _: col = Color(0.5, 0.7, 1.0)        # blue
    if spawning:
        col = col.lerp(Color(1, 1, 1), 0.5)
    draw_rect(Rect2(at, enemy_size), col)
    # Detail
    draw_rect(Rect2(at + Vector2(4, 4), enemy_size - Vector2(8, 8)), col.darkened(0.3))

func _draw_boss() -> void:
    var col: Color
    match fsm.boss.get_phase():
        1: col = Color(0.7, 0.3, 0.9)    # purple
        2: col = Color(0.9, 0.3, 0.7)    # magenta
        3: col = Color(1.0, 0.2, 0.2)    # red
        _: col = Color(0.4, 0.4, 0.4)

    # Flash when just hit
    draw_rect(Rect2(boss_pos, boss_size), col)
    # Core
    draw_rect(Rect2(boss_pos + Vector2(15, 15), boss_size - Vector2(30, 30)), col.darkened(0.4))

    # HP bar
    var bar_w: float = 200.0
    var bar_x: float = (court_size.x - bar_w) * 0.5
    draw_rect(Rect2(Vector2(bar_x, 36), Vector2(bar_w, 8)), Color(0.2, 0.2, 0.2))
    draw_rect(Rect2(Vector2(bar_x, 36), Vector2(bar_w * fsm.boss.get_hp_fraction(), 8)),
              Color(1, 0.3, 0.3))

func _draw_explosion(at: Vector2) -> void:
    var col := Color(1, 0.7, 0.3)
    var i: int = 0
    while i < 8:
        var t: float = float(i) / 8.0 * TAU
        var p1: Vector2 = at + Vector2(cos(t), sin(t)) * 3.0
        var p2: Vector2 = at + Vector2(cos(t), sin(t)) * 12.0
        draw_line(p1, p2, col, 2.0)
        i += 1

# ------------------------------------------------------------
# Cabinet integration: Esc returns to the menu.
# ------------------------------------------------------------
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        print("[arcade] Esc pressed in ", get_tree().current_scene.scene_file_path, " — returning to menu")
        get_viewport().set_input_as_handled()
        Arcade.return_to_menu()
