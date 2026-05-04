# Frame Arcade

### Classic Video Games in Frame + Godot

A mini-book of complete, playable classic arcade games, each one driven by a
[Frame](https://github.com/frame-lang/frame_transpiler) state machine
generated to GDScript and dropped into Godot 4.

The games in this book were all originally shipped on hardware with less RAM
than a modern smartphone has L1 cache, by teams of one or two programmers, in
assembly. They got the job done because the games are, deep down, state
machines — and the designers of the era thought in states even when the
language didn't help them. Frame lets you write that structure out loud, and
then generates the dispatch code for you.

The companion book to the [Flight Sim chapter](../frame-flight/) demonstrates
Frame for continuous-control simulation. This one is the opposite end of the
spectrum: small, tight, discrete games where state transitions *are* the
gameplay.

---

## Chapters

| # | Game | Teaches | Status |
|---|------|---------|--------|
| 1 | [Pong](./ch01-pong/) | Core FSM, enter/exit handlers, domain variables, Godot integration pattern | ✅ |
| 2 | [Breakout](./ch02-breakout/) | Multi-system composition, state variables, orchestrator pattern | ✅ |
| 3 | [Space Invaders](./ch03-invaders/) | Hierarchical state machines, parent-state inheritance, emergent pacing | ✅ |
| 4 | [Asteroids](./ch04-asteroids/) | State stack (push$/pop$) for hyperspace, parameterized systems for difficulty | ✅ |
| 5 | [Pac-Man Ghost AI](./ch05-pacman/) | HSM showcase, parameterized ghosts, two-stack coordination | ✅ |
| 6 | [Platformer](./ch06-platformer/) | Orthogonal-state problem, HSM-vs-composition design choice, variable jump height | ✅ |
| 7 | [Side-Scrolling Shooter](./ch07-shooter/) | Multi-phase boss HSM, parameterized enemies at scale, full toolkit | ✅ |
| 8 | [Stealth](./ch08-stealth/) | Agent AI — Frame as an alternative to behavior trees; three guards in a maze | ✅ |

Each chapter is a standalone Godot project. You can open `ch01-pong/godot/`
in Godot 4 and run it immediately — no need to work through earlier chapters
first.

---

## The Cabinet

Want to play all seven games behind a single menu? See
[`arcade/`](./arcade/) for a unified Godot project that hosts every
game in one window.

```bash
cd arcade
./build.sh
godot --path godot/ scenes/menu.tscn
```

The cabinet shares the same Frame state machines as the chapters —
it's a wrapper, not a rewrite. The book chapters remain the canonical
reference for the prose; the cabinet is for actually *playing* the games.

---

## What You'll Need

- [Godot 4.2+](https://godotengine.org/) (GDScript is the target language)
- The Frame transpiler (`framec`):
  ```bash
  cargo install framec
  ```
  If you don't have Rust installed, see [frame-lang.org](https://frame-lang.org)
  for alternative installation options.
- A text editor that doesn't mangle tabs (Godot is picky about GDScript indentation)

To verify:

```bash
framec --version    # should print a version
godot --version     # should print 4.x
```

---

## How the Chapters Are Organized

Each chapter follows the same shape:

```
chNN-gamename/
├── README.md                 # the chapter text of the book
├── frame/                    # Frame source files (.fgd extension)
│   └── game.fgd              # one or more @@system definitions
├── generated/                # framepiler output — do not edit by hand
│   └── game.gd
├── godot/                    # a complete Godot 4 project
│   ├── project.godot
│   ├── scenes/
│   │   └── main.tscn
│   └── scripts/
│       ├── game.gd           # symlink or copy of generated/game.gd
│       └── main.gd           # the Godot scene driver
└── build.sh                  # one-line: framec frame/game.fgd -o generated/game.gd
```

**The Frame file is the source of truth.** You edit `frame/game.fgd`, run the
build script, and the regenerated `generated/game.gd` gets picked up by the
Godot project.

---

## The Pattern: Frame as the Brain, Godot as the Body

This is the core architectural idea that every chapter uses. It's worth
understanding before you read chapter 1.

A Godot game typically has a `_physics_process(delta)` function that runs 60
times per second. Inside that function, you decide what the game should do
next. In a naive implementation, that function grows into a giant `if`-ladder:
*if the ball is past the left paddle and we're in play mode and it's not a
replay, score the point...*

The Frame pattern separates **what state the game is in** from **how it
renders that state**. The Frame system holds the state. The Godot `Node` holds
the rendering. Each physics tick, the Godot node:

1. Reads player input and tells the Frame system about it (calls interface
   methods like `paddle_up()` or `tick()`).
2. The Frame system updates its state (may transition, may fire enter/exit
   handlers, may update domain variables).
3. The Godot node queries the Frame system for the data it needs to render
   the frame (`get_score()`, `get_ball_position()`, `is_playing()`).

The Frame system never touches Godot APIs. It has no idea what a
`CharacterBody2D` is. It just tracks states and numbers. This means you can
test it outside Godot (with a plain GDScript harness), swap the renderer, or
port the game to a different engine by rewriting only the driver script.

You'll see this pattern everywhere in the book. Once it clicks, you'll stop
writing tangled `_physics_process` methods forever.

---

## Reading Order

Chapters are designed to be read in order — each one introduces Frame
features the next one builds on — but each game is self-contained. If you
want to skip ahead to see Pac-Man's HSM ghost AI, nothing in chapter 5
depends on having actually run the earlier games.

The text-adventure capstone in [`cca/`](./cca/) (a 100% canon-complete
Crowther+Woods *Colossal Cave Adventure* port — 24 FSMs, 140 rooms,
every canonical puzzle wired) reuses every Frame technique the eight
arcade chapters introduce, plus a few that only IF asks for. Read it
last — it lands the patterns rather than introducing them.

---

## Patterns and Practices

> **For the long-form companion** — code samples, "where to find it"
> source pointers per chapter, and "when to reach for it / when not"
> guidance — see [PATTERNS.md](./PATTERNS.md).

The arcade returns to the same nine architectural patterns over and over.
Each is introduced in one chapter, recurs in others, and the CCA capstone
is where they all collide. If you remember nothing else from the book,
remember these.

**1. Frame is the brain. Godot is the body.** Every game splits *what
state we're in* (Frame) from *how we render that state* (Godot). The
Frame system never imports a Godot type. The Godot driver never reaches
into Frame internals — it talks through the FSM's interface methods.
This is the load-bearing decision; everything else assumes it.
Introduced in chapter 1; reused literally everywhere else.

**2. Hierarchical state machines.** A parent state defines shared entry/
exit handlers, shared queries, shared transitions. Children override
selectively. Frame's `=> $^` dispatches an event up to the parent. The
HSM is what makes "ghost is in $Frightened *and* $Tunnel" expressible
without an exponential matrix of leaf states.
Introduced in chapter 3 (Space Invaders pacing), peak in chapter 5
(Pac-Man's $Scatter/$Chase under $Active), reused in CCA's `Lamp`
($On.$Bright/$Dim/$Out) and `Endgame` (multi-phase HSM).

**3. State stack (push$/pop$).** Suspend the current state, run a
sub-state, then pop back to where you were — with all your domain
variables intact. The classic "hyperspace, then resume normal flight"
shape. Frame's compartment serialization round-trips pushed states
through `@@[persist]` for free.
Introduced in chapter 4 (Asteroids hyperspace), reused in chapter 5
(Pac-Man frightened mode).

**4. Parameterized systems × N.** A single `@@system Foo(seed: int)`
declaration with multiple named instances, each with its own
configuration. Frame's `@@[persist]` auto-traverses named domain
fields, so adding a fifth dwarf is one line. The trade-off is an
if-ladder in the orchestrator to dispatch by-name instead of by-index.
Introduced in chapter 4 (difficulty-tier asteroids), peak in chapter
5 (four ghosts with shared FSM, divergent personalities), reused in
chapter 7 (enemy waves), chapter 8 (three guards), and CCA (five
dwarves, three hints, fifteen treasures).

**5. Cross-FSM orchestration.** Each FSM owns its own state; a parent
"World" / "Adventure" / "Conductor" system brokers cross-cuts.
Releasing the bird shouldn't be a thing the bird FSM knows about
the snake; it's a thing the orchestrator observes the bird doing
and forwards to the snake. This keeps every subsystem unit-testable
in isolation.
Introduced in chapter 2 (Breakout's ball/paddle/bricks orchestrator),
peak in CCA (`Adventure` brokers bird→snake, bear→troll, pirate→
treasure, vending→lamp, eggs-incantation→eggs-reappear).

**6. Aspect machines: priority-ordered FSM interceptors on a bus.** When
cross-cutting concerns (darkness, inventory limits, magic words,
scoring) start growing into the base machine as flag-checks, lift
them onto an `AspectBus`. Each aspect is itself an FSM with a
priority and a verdict (consume / transform / observe / pass).
Higher-priority aspects fire first; consume short-circuits the chain.
Unique to CCA in this book — but the pattern generalizes to any game
where you'd otherwise grow a flag-on-the-base-machine smell.

**7. Persistence via `@@[persist]`.** One annotation on the world
system; framepiler auto-traverses every named domain field, including
nested `@@system` instances, including pushed compartments, including
state-variable timers. `save_state(): PackedByteArray` and
`restore_state(bytes)` round-trip the entire game in one call. The
single biggest LOC win Frame ships in this book — and the reason
mid-game save/restore is just *there* in every chapter.

**8. Multi-turn parser dialog as state.** When the game asks the
player a question and waits for the answer, *that's a state*, not
an `awaiting_yes_no: bool` flag on the base machine. Push into
`$Asked`, accept yes/no, transition based on the answer, pop back.
The dialog context is the state.
Introduced in CCA (Dragon's "attack with what?" / yes-no, plus the
resurrection prompt), but the shape applies equally to "are you sure?"
quit dialogs in any of the arcade games.

**9. Per-frame overlay rendering.** The renderer asks the FSM "what's
in this room / on this screen right now?" and the FSM stitches together
a base description plus per-NPC, per-item, per-state overlays. The FSM
never holds rendering state; the renderer never holds game state.
You add a new pickup or NPC by adding one query to the FSM and one
overlay branch in the renderer.
Introduced implicitly in chapter 1 (Pong scoreboard), formalized in
CCA's `_verb_look` (room base text + bird/snake/bear/dragon overlays
+ each treasure, rod, keys, grate state).

The capstone CCA port adds one more pattern that the arcade games
don't need: **consume-an-item-as-side-effect** (the vending machine
removes the player's coins from play *and* triggers a cross-FSM
lamp refresh in a single transition). It's a small enough shape that
it doesn't earn its own chapter, but it's worth seeing once.

---

## Contributing

Ports to other engines (Unity/C#, Bevy/Rust, MonoGame/C#) are welcome.
Frame already targets all of those languages, so the Frame specs in this
book can be retargeted without modification — only the engine driver
scripts need to be rewritten. If you build one, open a PR.

---

## License

MIT for the code. CC-BY-4.0 for the prose. Attribute to the
`frame-arcade` repo.
