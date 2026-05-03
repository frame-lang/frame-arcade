# ============================================================
# menu.gd — Frame Arcade cabinet menu
# ============================================================
# Up/Down to select, Enter to launch, Escape to quit.
# Drawn entirely in code with a CanvasLayer + Labels.
#
# Each game row has TWO labels — title on the left, high-score
# on the right. The score is read from `Arcade.get_high_score`
# (backed by the persisted Scoreboard system). Unscored games
# (Pac-Man, Platformer) leave the score column blank because
# they're behavior demos rather than scoring games.
# ============================================================
extends Node2D

const COURT_SIZE: Vector2 = Vector2(800, 600)

# Card area for the game list. Title labels left-align inside
# this band, score labels right-align. The band is centered
# horizontally regardless of court size.
const CARD_LEFT: float = 170.0
const CARD_RIGHT: float = 630.0
const TITLE_WIDTH: float = 320.0
const SCORE_WIDTH: float = 140.0

var selected_index: int = 0

var label_title: Label
var label_subtitle: Label
var game_labels: Array = []          # one Label per game (title)
var score_labels: Array = []         # one Label per game (high-score)
var label_blurb: Label
var label_help: Label

# Edge-detected input
var _up_was_down: bool = false
var _down_was_down: bool = false
var _enter_was_down: bool = false
var _escape_was_down: bool = false

# ============================================================
func _ready() -> void:
    _build_ui()
    _refresh_selection()
    _refresh_scores()
    # Seed edge-detector state from the actual key state on entry. If we
    # arrive here from a game scene with Esc still held (the user pressed
    # Esc in a game to come back to the menu), this prevents the menu's
    # first frame from interpreting the held key as a fresh press and
    # quitting the cabinet.
    _up_was_down = Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
    _down_was_down = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
    _enter_was_down = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)
    _escape_was_down = Input.is_key_pressed(KEY_ESCAPE)

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)

    # Title
    label_title = Label.new()
    label_title.text = "F R A M E   A R C A D E"
    label_title.add_theme_font_size_override("font_size", 36)
    label_title.position = Vector2(0, 60)
    label_title.size = Vector2(COURT_SIZE.x, 50)
    label_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_title)

    # Subtitle
    label_subtitle = Label.new()
    label_subtitle.text = "seven classic arcade games as Frame state machines"
    label_subtitle.add_theme_font_size_override("font_size", 14)
    label_subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
    label_subtitle.position = Vector2(0, 110)
    label_subtitle.size = Vector2(COURT_SIZE.x, 24)
    label_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_subtitle)

    # Game list — two labels per row (title left, score right).
    var games: Array = Arcade.GAMES
    var list_top: float = 170.0
    var row_height: float = 36.0
    for i in range(games.size()):
        var row_y: float = list_top + i * row_height

        var title_lbl := Label.new()
        title_lbl.add_theme_font_size_override("font_size", 22)
        title_lbl.position = Vector2(CARD_LEFT, row_y)
        title_lbl.size = Vector2(TITLE_WIDTH, row_height)
        title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        canvas.add_child(title_lbl)
        game_labels.append(title_lbl)

        var score_lbl := Label.new()
        score_lbl.add_theme_font_size_override("font_size", 18)
        score_lbl.position = Vector2(CARD_RIGHT - SCORE_WIDTH, row_y + 4)
        score_lbl.size = Vector2(SCORE_WIDTH, row_height)
        score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        score_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
        canvas.add_child(score_lbl)
        score_labels.append(score_lbl)

    # Blurb (description of selected game)
    label_blurb = Label.new()
    label_blurb.add_theme_font_size_override("font_size", 14)
    label_blurb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
    label_blurb.position = Vector2(0, list_top + games.size() * row_height + 30)
    label_blurb.size = Vector2(COURT_SIZE.x, 24)
    label_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_blurb)

    # Help footer
    label_help = Label.new()
    label_help.text = "↑/↓ select    Enter launch    Esc quit"
    label_help.add_theme_font_size_override("font_size", 13)
    label_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
    label_help.position = Vector2(0, COURT_SIZE.y - 36)
    label_help.size = Vector2(COURT_SIZE.x, 20)
    label_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_help)

# ============================================================
func _process(_delta: float) -> void:
    var up: bool = Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
    var down: bool = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
    var enter: bool = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)

    if up and not _up_was_down:
        selected_index = (selected_index - 1 + game_labels.size()) % game_labels.size()
        _refresh_selection()
    if down and not _down_was_down:
        selected_index = (selected_index + 1) % game_labels.size()
        _refresh_selection()
    if enter and not _enter_was_down:
        Arcade.launch_game(selected_index)

    var escape: bool = Input.is_key_pressed(KEY_ESCAPE)
    if escape and not _escape_was_down:
        get_tree().quit()

    _up_was_down = up
    _down_was_down = down
    _enter_was_down = enter
    _escape_was_down = escape

func _refresh_selection() -> void:
    for i in range(game_labels.size()):
        var entry: Dictionary = Arcade.GAMES[i]
        if i == selected_index:
            game_labels[i].text = "▸  " + entry.title
            game_labels[i].add_theme_color_override("font_color", Color(1.0, 0.95, 0.2))
        else:
            game_labels[i].text = "    " + entry.title
            game_labels[i].add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
    label_blurb.text = Arcade.GAMES[selected_index].blurb

func _refresh_scores() -> void:
    # Called once after the menu loads. Scores don't change while the
    # menu is on screen — they only change when a game ends — so a
    # one-shot read is enough. (If we add a "you set a new high score!"
    # animation on return-from-game, this can be re-called from
    # `_ready()` to pick up the latest values.)
    for i in range(score_labels.size()):
        var entry: Dictionary = Arcade.GAMES[i]
        if not entry.scored:
            score_labels[i].text = ""
            continue
        var best: int = Arcade.get_high_score(entry.name)
        if best == 0:
            score_labels[i].text = "best  —"
        else:
            score_labels[i].text = "best  " + str(best)
