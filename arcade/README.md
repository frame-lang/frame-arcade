# Frame Arcade Cabinet

A unified Godot app that hosts all seven chapters of the Frame Arcade
book behind a menu. One project, one window, seven games.

This directory is **separate from the per-chapter projects** under
`ch01-pong/`, `ch02-breakout/`, etc. Those still exist as the
canonical reference for the book's prose — each chapter is
self-contained so a reader can clone it and run that one game
in isolation. The cabinet is an *additional* deliverable that
points at the same Frame source.

## Build & run

```bash
# From the arcade/ directory:
./build.sh
godot --path godot/ scenes/menu.tscn
```

If your `framec` is not on `$PATH`, set it explicitly:

```bash
FRAMEC=/Users/you/projects/framepiler/target/release/framec ./build.sh
```

`build.sh` compiles each chapter's Frame source and copies the
generated GDScript into `godot/scripts/`. The cabinet's per-game
driver scripts (e.g. `pong_main.gd`) preload these by their bare
name.

> **framec version note.** The cabinet-only sources
> `frame/scoreboard.fgd` and `frame/asteroids.fgd` use the
> `@@[save]` / `@@[load]` operation attributes that drive
> `@@[persist]`. These were added after the framec 4.0.0
> released on cargo (Apr 2026), so a `cargo install framec` of
> that release fails to parse them. Use a current framepiler
> build (`cargo build --release` in the framepiler repo) and
> point `FRAMEC` at it. Once the cargo release catches up, this
> override won't be needed.

## Controls

The cabinet shares a small unified keymap on top of each chapter's
own controls. Two principles: `Esc` is always reversible (opens an
overlay, never destroys work directly), and `Enter` in any overlay
is the safe default (preserve, not discard).

**Home screen:**

- ↑ / ↓ — select a game
- Enter / Space — launch the highlighted game
- 1–9 — jump straight to that game
- Esc — open *Quit cabinet?* confirmation (Enter quits, Esc cancels)

If a chapter has a save and you launch it again, the home screen
shows a *Continue / New game* prompt. Up/Down to choose, Enter to
confirm, Esc to back out to the game list.

**In-game (most chapters):**

- Esc — return to the home screen

**Colossal Cave Adventure** (save-aware):

- Esc — open *Leaving the cave?* dialog
  - Enter / Space — Save and quit (default — preserves your run)
  - Q — Quit without saving
  - Esc — Cancel back to the game
- F5 — quick save (no overlay)
- F9 — quick load (resume from last save)
- Up / Down — recall previously typed commands at the prompt
- PgUp / PgDn — page the scrollback log
- The classic typed verbs `SAVE`, `LOAD`, and `QUIT` still work too.

**Asteroids** (save-aware):

- Esc / P — pause menu (Resume / Save & exit to menu / Exit without saving)
- The pause menu is the leave-game overlay — there's no separate
  "Esc means leave" path, since the menu already covers it.

Any chapter that doesn't save (Pong, Breakout, Invaders, Pacman,
Platformer, Shooter, Stealth) returns straight to the home screen
on Esc — no confirmation prompt, since there's no run state to
lose.

## Architecture

```
arcade/
├── build.sh                       (compiles all 7 Frame files)
├── README.md                      (this file)
└── godot/
    ├── project.godot              (autoload: arcade.gd)
    ├── scenes/
    │   ├── menu.tscn              (cabinet menu)
    │   └── games/
    │       ├── pong.tscn
    │       ├── breakout.tscn
    │       ├── invaders.tscn
    │       ├── asteroids.tscn
    │       ├── pacman.tscn
    │       ├── platformer.tscn
    │       └── shooter.tscn
    └── scripts/
        ├── arcade.gd              (autoload — scene navigation)
        ├── menu.gd                (cabinet menu logic)
        ├── pong_main.gd           (= ch01 main.gd, adapted)
        ├── pong.gd                (Frame-generated, by build.sh)
        ├── breakout_main.gd
        ├── breakout.gd
        └── ...
```

The cabinet uses Godot's autoload feature: `Arcade` is a singleton
that holds the game registry and exposes `launch_game(index)` and
`return_to_menu()`. Each adapted driver has a small `_unhandled_input`
handler appended that catches Esc and calls `Arcade.return_to_menu()`.

## How games were adapted

Each chapter's `main.gd` is copied here as `<game>_main.gd` with two
small changes:

1. **`court_size` default changed to 800×600** so every game fills
   the cabinet window. The originals used per-game sizes (Pong was
   640×360, Pac-Man was 640×600, etc.). All driver code already
   referenced `court_size` for layout, so changing the default is
   sufficient.
2. **Esc handler appended** — calls `Arcade.return_to_menu()`.

Apart from those, the driver code is byte-identical to the chapter
versions. The Frame state machines themselves are 100% untouched —
the cabinet uses the exact same compiled `.gd` files the book chapters
use.

## Why a separate cabinet directory

Could the cabinet have been *the* Frame Arcade project, with the
chapters folded into it? Yes — but that would couple the book's
pedagogy to the cabinet's design. Each chapter teaches Frame
incrementally, and a reader who wants to study one chapter shouldn't
have to learn the cabinet's autoload + scene-navigation pattern first.

So the chapters stay self-contained. The cabinet wraps them.

The flip side: the cabinet **duplicates** each chapter's `main.gd`.
A bug fix in `ch03-invaders/godot/scripts/main.gd` won't propagate to
`arcade/godot/scripts/invaders_main.gd` automatically. Re-running
`build.sh` doesn't help — it only re-compiles Frame source. Driver
script changes have to be re-copied manually.

In practice this is fine because the chapter drivers are nearly
finished and changes are rare. If you do edit a chapter driver,
re-run `arcade/build.sh` *and* manually copy the updated `main.gd`
into the cabinet's scripts folder, preserving the appended Esc
handler.

A future improvement would be a `sync.sh` script that re-derives
each `<game>_main.gd` from the chapter source automatically. For
now this is left as an exercise.
