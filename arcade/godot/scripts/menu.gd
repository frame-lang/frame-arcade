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

# --- Saved-run prompt ---------------------------------------
#
# When the player presses Enter on a game with a saved run,
# the menu enters a "save prompt" sub-mode that asks
# Continue / New game. The game list is hidden and a centered
# prompt label takes over input. Esc cancels back to the list.
const _SAVE_PROMPT_OPTIONS: Array = [
    "Continue saved run",
    "New game (deletes saved run)",
]
var _save_prompt_active: bool = false
var _save_prompt_game_index: int = -1
var _save_prompt_selection: int = 0
var label_prompt: Label

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
    label_subtitle.text = "eight arcade games + a colossal cave adventure, all as Frame state machines"
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
    label_help.text = "↑/↓ select    Enter launch    1-9 jump    Esc quit"
    label_help.add_theme_font_size_override("font_size", 13)
    label_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
    label_help.position = Vector2(0, COURT_SIZE.y - 36)
    label_help.size = Vector2(COURT_SIZE.x, 20)
    label_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(label_help)

    # Save-prompt overlay (hidden until activated). Same canvas
    # so it draws on top of the game list naturally; we toggle
    # visibility on the list rather than the overlay.
    label_prompt = Label.new()
    label_prompt.add_theme_font_size_override("font_size", 22)
    label_prompt.position = Vector2(0, 200)
    label_prompt.size = Vector2(COURT_SIZE.x, COURT_SIZE.y - 240)
    label_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_prompt.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    label_prompt.visible = false
    canvas.add_child(label_prompt)

# ============================================================
func _process(_delta: float) -> void:
    var up: bool = Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
    var down: bool = Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
    var enter: bool = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)
    var escape: bool = Input.is_key_pressed(KEY_ESCAPE)

    if _save_prompt_active:
        # Sub-mode: navigate Continue / New game.
        if up and not _up_was_down:
            _save_prompt_selection = (_save_prompt_selection - 1 + _SAVE_PROMPT_OPTIONS.size()) % _SAVE_PROMPT_OPTIONS.size()
            _refresh_save_prompt()
        if down and not _down_was_down:
            _save_prompt_selection = (_save_prompt_selection + 1) % _SAVE_PROMPT_OPTIONS.size()
            _refresh_save_prompt()
        if enter and not _enter_was_down:
            _confirm_save_prompt()
        if escape and not _escape_was_down:
            _hide_save_prompt()
    else:
        # Main game-list navigation.
        if up and not _up_was_down:
            selected_index = (selected_index - 1 + game_labels.size()) % game_labels.size()
            _refresh_selection()
        if down and not _down_was_down:
            selected_index = (selected_index + 1) % game_labels.size()
            _refresh_selection()
        if enter and not _enter_was_down:
            _on_game_selected(selected_index)
        if escape and not _escape_was_down:
            get_tree().quit()
        # Number-key shortcuts: 1-9 jump straight to the matching
        # game (1-indexed in the menu, 0-indexed in GAMES). Edge-
        # detected so a held key doesn't fire repeatedly. Goes
        # through _on_game_selected so the Continue/New prompt
        # still appears for games with a saved run.
        _check_number_shortcuts()

    _up_was_down = up
    _down_was_down = down
    _enter_was_down = enter
    _escape_was_down = escape

# Number-key shortcuts. We keep an edge-detector array parallel
# to KEY_1..KEY_9 so each digit press fires once per push.
var _digit_was_down: Array = [false, false, false, false, false, false, false, false, false]

func _check_number_shortcuts() -> void:
    var digit_keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
    var max_index: int = min(digit_keys.size(), Arcade.GAMES.size())
    for i in range(max_index):
        var pressed: bool = Input.is_key_pressed(digit_keys[i])
        if pressed and not _digit_was_down[i]:
            selected_index = i
            _refresh_selection()
            _on_game_selected(i)
        _digit_was_down[i] = pressed

# Called when the player confirms a game from the list. If the
# game has a saved run, switch to the Continue / New prompt;
# otherwise launch directly. The branch keeps the menu silent
# for the common no-save path — players who never save never
# see the prompt.
func _on_game_selected(index: int) -> void:
    var entry: Dictionary = Arcade.GAMES[index]
    if Arcade.has_save(entry.name):
        _show_save_prompt(index)
    else:
        Arcade.launch_game(index)

# --- Save-prompt sub-mode -----------------------------------

func _show_save_prompt(game_index: int) -> void:
    _save_prompt_active = true
    _save_prompt_game_index = game_index
    _save_prompt_selection = 0
    _set_list_visible(false)
    label_prompt.visible = true
    _refresh_save_prompt()

func _hide_save_prompt() -> void:
    _save_prompt_active = false
    _save_prompt_game_index = -1
    label_prompt.visible = false
    _set_list_visible(true)

func _set_list_visible(visible: bool) -> void:
    label_title.visible = visible
    label_subtitle.visible = visible
    for lbl in game_labels:
        lbl.visible = visible
    for lbl in score_labels:
        lbl.visible = visible
    label_blurb.visible = visible
    label_help.visible = visible

func _refresh_save_prompt() -> void:
    var game: Dictionary = Arcade.GAMES[_save_prompt_game_index]
    var lines := PackedStringArray()
    lines.append(game.title.to_upper())
    lines.append("")
    lines.append("A saved run was found.")
    lines.append("")
    for i in range(_SAVE_PROMPT_OPTIONS.size()):
        var prefix: String = "▸  " if i == _save_prompt_selection else "    "
        lines.append(prefix + _SAVE_PROMPT_OPTIONS[i])
    lines.append("")
    lines.append("↑/↓ select    Enter confirm    Esc cancel")
    label_prompt.text = "\n".join(lines)

func _confirm_save_prompt() -> void:
    var idx: int = _save_prompt_game_index
    var entry: Dictionary = Arcade.GAMES[idx]
    if _save_prompt_selection == 1:
        # "New game" — delete the existing save before launching
        # so the driver's _ready() sees no save and starts fresh.
        Arcade.delete_save(entry.name)
    Arcade.launch_game(idx)

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
