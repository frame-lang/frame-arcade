# Frame Arcade Cabinet

A single Godot app that hosts all nine Frame Arcade games behind one
menu — eight classic-arcade chapters plus a full text-adventure
capstone. One project, one window, nine state-machine-driven games.

Every game's logic is a [Frame](https://github.com/frame-lang/frame_transpiler)
state machine compiled to GDScript. The cabinet is the *playable*
deliverable; the per-chapter projects under `ch01-pong/` … `ch08-stealth/`
and `cca/` remain the canonical, self-contained references for the
book's prose — each can be cloned and run on its own.

## The games

Each game is the worked example for one Frame concept. The linked
chapter README contains an ASCII state-transition diagram of that
game's FSM plus an annotated walkthrough of its `.fgd` source.

| # | Game | Frame concept it teaches | FSM docs |
|---|------|--------------------------|----------|
| 1 | Pong | Core FSM — states, enter/exit handlers, domain variables | [ch01-pong](../ch01-pong/README.md) |
| 2 | Breakout | Multi-system composition, state variables | [ch02-breakout](../ch02-breakout/README.md) |
| 3 | Space Invaders | Hierarchical state machines, parent inheritance | [ch03-invaders](../ch03-invaders/README.md) |
| 4 | Asteroids | State stack (`push$` / `-> pop$`), parameterized systems | [ch04-asteroids](../ch04-asteroids/README.md) |
| 5 | Ghost Maze | Deep HSM, two-stack coordination — maze-chase ghost AI | [ch05-pacman](../ch05-pacman/README.md) |
| 6 | Platformer | Orthogonal-state problem — HSM vs composition | [ch06-platformer](../ch06-platformer/README.md) |
| 7 | Side-Scrolling Shooter | Capstone — boss HSM, parameterized enemies | [ch07-shooter](../ch07-shooter/README.md) |
| 8 | Stealth | Agent AI — Frame as an alternative to behaviour trees | [ch08-stealth](../ch08-stealth/README.md) |
| 9 | Colossal Cave Adventure | Capstone — 24 FSMs, 140 rooms, an aspect bus, cross-FSM orchestration | [cca](../cca/README.md), [cca/ARCHITECTURE.md](../cca/ARCHITECTURE.md) |

The Frame source for each game lives in `frame/<game>.fgd` (the
cabinet build pulls from the chapter sources; the `.fgd` *is* the
state machine).

## Play

The cabinet ships to **itch.io** as a browser (HTML5) build — zero
install. A macOS native build is also produced. See
[DIST.md](DIST.md) for the full build-and-upload procedure.

To run a local web build for testing:

```sh
cd arcade
./dist.sh web
python3 dist/serve_web.py     # then open http://localhost:8000
```

## Build & run (from source)

```sh
# From the arcade/ directory:
./build.sh
godot --path godot/ scenes/menu.tscn
```

If your `framec` is not on `$PATH`, set it explicitly:

```sh
FRAMEC=/Users/you/projects/framepiler/target/release/framec ./build.sh
```

`build.sh` compiles each chapter's Frame source and copies the
generated GDScript into `godot/scripts/`. The cabinet's per-game
driver scripts (e.g. `pong_main.gd`) preload these by their bare
name.

> **framec version note.** The cabinet-only sources
> `frame/scoreboard.fgd` and `frame/asteroids.fgd` use the
> `@@[save]` / `@@[load]` operation attributes that drive
> `@@[persist]`. These were added after the framec 4.0.0 release
> on cargo (Apr 2026), so `cargo install framec` of that release
> fails to parse them. Use a current framepiler build
> (`cargo build --release` in the framepiler repo) and point
> `FRAMEC` at it.

## Controls

The cabinet shares a small unified keymap on top of each game's own
controls. Two principles:

1. **`Esc` is always reversible** — it opens an overlay; nothing
   destructive happens until you confirm.
2. **`Enter` in any overlay is the safe default** — it preserves
   progress (or, where there's nothing to lose, simply proceeds).

**Home screen:**

- ↑ / ↓ — select a game
- Enter / Space — launch the highlighted game
- 1–9 — jump straight to that game
- Esc — open *Quit cabinet?* confirmation (Enter quits, Esc cancels)

If a game has a save and you launch it again, the home screen shows a
*Continue / New game* prompt (↑/↓ choose, Enter confirm, Esc back out).

**In-game — games without a save** (Pong, Breakout, Invaders,
Pac-Man, Platformer, Shooter, Stealth):

- Esc — open *LEAVE GAME?* overlay
  - Enter — Return to menu
  - Esc — Resume

**Colossal Cave Adventure** (save-aware):

- Esc — open *Leaving the cave?* dialog
  - Enter / Space — Save and quit (default — preserves your run)
  - Q — Quit without saving
  - Esc — Cancel back to the game
- F5 — quick save (no overlay)
- F9 — quick load (resume from last save)
- ↑ / ↓ — recall previously typed commands at the prompt
- PgUp / PgDn — page the scrollback log
- The classic typed verbs `SAVE`, `LOAD`, `QUIT` still work too.

**Asteroids** (save-aware):

- Esc — open the save/quit overlay (freezes the action)
  - Enter — Save and quit (default)
  - Q — Quit without saving
  - Esc — Resume
- P — plain pause in place; from a P pause, Esc escalates to the
  save/quit overlay.

## Architecture

```
arcade/
├── build.sh                  (transpiles all Frame sources → GDScript)
├── dist.sh                   (exports web + mac builds)
├── README.md                 (this file)
├── DIST.md                   (itch.io build & upload guide)
└── godot/
    ├── project.godot         (autoload: arcade.gd; default font: DejaVu Sans)
    ├── export_presets.cfg     (Web + macOS presets — committed)
    ├── fonts/
    │   ├── DejaVuSans.ttf     (UI font — covers arrow glyphs; see LICENSE)
    │   └── DejaVuSans-LICENSE.txt
    ├── scenes/
    │   ├── menu.tscn
    │   └── games/            (pong … stealth, cca — one scene each)
    └── scripts/
        ├── arcade.gd          (autoload — game registry + scene navigation)
        ├── menu.gd            (cabinet menu)
        ├── <game>_main.gd     (per-game driver, adapted from the chapter)
        └── <game>.gd          (Frame-generated by build.sh)
```

`Arcade` is an autoload singleton holding the game registry
(`GAMES` in `arcade.gd`) and exposing `launch_game(index)`,
`return_to_menu()`, and the persistent high-score `Scoreboard`.

The UI font is **DejaVu Sans**, bundled and set as the project
default. Godot's built-in font lacks arrow glyphs (`↑ ↓ ← →`),
which on-screen hints use; DejaVu covers them and is redistributable
(Bitstream Vera + Arev license — see the bundled license file).

## How games were adapted for the cabinet

Each chapter's `main.gd` is copied here as `<game>_main.gd`. The
Frame **state machines are 100% untouched** — the cabinet compiles
and uses the exact same `.fgd` sources the chapters do. The driver
scripts gain cabinet-specific behaviour:

1. **`court_size` default → 800×600** so every game fills the cabinet
   window. (The chapter originals used per-game sizes.)
2. **A leave-game overlay on Esc**, routed through
   `Arcade.return_to_menu()` instead of ever calling
   `get_tree().quit()` from inside a game.
3. **Save/resume for the save-aware games** (CCA, Asteroids):
   `user://<game>.save`, surfaced through the home-screen
   *Continue / New* prompt and an in-game save/quit overlay.
4. **Score posting** to the shared persistent Scoreboard for the
   scored games.

Because the cabinet **duplicates** each chapter's `main.gd`, a driver
fix in a `ch0x-*/` project does not propagate automatically — re-run
`build.sh` (for Frame changes) and re-copy the driver if you edit a
chapter version.

## Why a separate cabinet directory

The chapters teach Frame incrementally and stay self-contained, so a
reader studying one chapter needn't first learn the cabinet's
autoload + scene-navigation pattern. The cabinet wraps them as an
additional, publishable deliverable pointing at the same Frame source.
