# Chapter 1 — Pong

The first video game most people recognize on sight, and the first one
we'll build with Frame. Pong is an ideal starter because the gameplay
is almost entirely state-driven: the ball is either bouncing or it's
not, the court is either waiting for a serve or it isn't, someone has
either won or the game is still in progress. There's barely any
"gameplay logic" in the traditional sense — what looks like game logic
is actually mode-switching, and mode-switching is exactly what state
machines are for.

By the end of this chapter you'll have a complete playable Pong in
Godot 4, driven by a Frame state machine that you can read in one
sitting. You'll also understand the architectural pattern that every
later chapter builds on: **Frame is the brain, Godot is the body.**

## What This Chapter Teaches

- Writing your first non-trivial Frame system
- Enter handlers (`$>`) for one-shot setup work
- Domain variables for data that persists across state changes
- The **brain/body split** between Frame and the game engine
- How to drive a Frame system from a Godot `_physics_process` loop
- Building and running a generated GDScript class inside Godot

Concepts deliberately *not* used here — we'll get to them later:

- Hierarchical state machines (chapter 2 starts using HSM)
- Multiple cooperating Frame systems (chapter 2)
- State variables (`$.foo`) (chapter 3)
- The state stack / `push$` / `pop$` (chapter 4)

## Running It

```bash
# From this chapter's directory:
./build.sh                          # runs framec, produces godot/scripts/pong.gd
godot --path godot/ scenes/main.tscn
```

Or open `godot/` as a project in the Godot 4 editor and hit F5.

**Controls:**

| Key | Action |
|-----|--------|
| W / S | Move left paddle up/down |
| Space | Serve |
| R | Restart after game over |
| Any key | Start from attract mode |

The right paddle is played by a simple AI that tracks the ball with
adjustable reaction dampening (the `ai_reaction` export in `main.gd`).
Set it to `1.0` for perfect play (unbeatable), lower for a weaker opponent.

## The Game as a State Machine

Before writing any code, let's draw the game. Pong moves through five
distinct situations, with events that cause transitions between them:

```
┌────────────┐   start    ┌─────────┐   launch   ┌─────────┐
│AttractMode │───────────▶│ Serving │───────────▶│ InPlay  │
└────────────┘            └─────────┘            └─────────┘
      ▲                        ▲                      │
      │                        │                      │ ball_out_left
      │                        │                      │ ball_out_right
      │                        │                      ▼
      │     restart      ┌──────────┐           ┌─────────────┐
      └──────────────────│ GameOver │◀──────────│ PointScored │
                         └──────────┘ (winner)  └─────────────┘
                                                  │ (not winner)
                                                  └──▶ Serving
```

Every box is a state. Every arrow is an event that causes a
transition. Nothing else happens — no player input is processed
except what's labeled here, no game logic runs except what's triggered
by these events.

The key insight: **this diagram is the whole game.** Everything else
is rendering and physics.

## The Frame Source, Piece by Piece

Open [`frame/pong.fgd`](./frame/pong.fgd) and read along.

### The Header

```frame
@@target gdscript

@@system Pong {
    ...
}
```

`@@target gdscript` tells the framepiler to generate GDScript.
`@@system Pong` declares a state machine named `Pong`. When compiled,
this becomes a GDScript class that Godot loads like any other script.

### The Interface

```frame
interface:
    start()
    restart()
    launch()
    tick()
    ball_out_left()
    ball_out_right()
    get_state(): String
    get_score_left(): int
    get_score_right(): int
    get_serve_direction(): int
    get_winner(): String
    is_playing(): bool
```

These are the public methods the Godot driver calls. They split
naturally into two groups:

**Events** — `start`, `launch`, `tick`, `ball_out_left`, etc. These
cause the machine to do things (often transition states).

**Queries** — anything starting with `get_` or `is_`. These just
return data. They never change state. They're how the Godot driver
asks "what should I draw?"

A good heuristic: events are verbs, queries are noun phrases.

### The Machine

The `machine:` block is the heart of the file. Each state is a named
block:

```frame
$AttractMode {
    $>() {
        self.score_left = 0
        self.score_right = 0
        self.winner = ""
    }

    start() {
        -> $Serving
    }

    get_state(): String             { @@:("attract") }
    is_playing(): bool              { @@:(false) }
    // ... other queries ...
}
```

Three things to notice:

**1. `$>()` is the enter handler.** It runs when the state is entered.
In `$AttractMode`, the enter handler zeros the scores and clears the
winner. This is exactly when you want that to happen — once, on entry
to the attract screen. If you put this in `_ready()` on the Godot
side, you'd have to remember to call it again when restarting. The
state machine makes "what happens on entry to this mode" a structural
property of the mode itself.

**2. Event handlers transition.** `start()` inside `$AttractMode` does
nothing but `-> $Serving`. That's the entire logic for the "start the
game" button: go to the serving state. No flags to flip, no booleans
to reset, no if-ladders. Mode change.

**3. Queries return values.** `get_state(): String { @@:("attract") }`
reads "when I'm in attract mode and asked for my state, return the
string 'attract'". The `@@:(expr)` syntax sets the interface method's
return value. Every state defines its own answer.

### The Interesting State: `$PointScored`

Most states in Pong are simple. `$PointScored` earns its place because
its enter handler does real work:

```frame
$PointScored {
    $>() {
        if self.last_scorer == "left":
            self.serving_to = 1
        else:
            self.serving_to = -1

        if self.score_left >= self.winning_score:
            self.winner = "left"
            -> $GameOver
        elif self.score_right >= self.winning_score:
            self.winner = "right"
            -> $GameOver
        else:
            -> $Serving
    }
    ...
}
```

On entry to `$PointScored`, the machine decides two things:

1. **Which direction the next serve goes.** Classic Pong serves to
   whoever lost the point (giving them a chance to recover).
2. **Whether the game is over.** If either score hit the winning
   threshold, go to `$GameOver`. Otherwise, back to `$Serving`.

This is a **transient state** — one that doesn't wait for input, it
just computes and immediately transitions. Transient states are
common. They're a place to put computation that's awkward to locate
anywhere else: it's not setup (that's an enter handler for a
non-transient state), it's not event handling (no external event
triggered it), it's "the moment after a point was scored". A state
gives it a home.

### Domain Variables

At the bottom of the file:

```frame
domain:
    score_left: int = 0
    score_right: int = 0
    winning_score: int = 11
    serving_to: int = 1
    last_scorer: String = ""
    winner: String = ""
```

Domain variables persist across every state transition. They're the
game's memory. `score_left` lives from attract mode through serving
through play through game over — one continuous value. Contrast this
with state variables (introduced in chapter 3), which reset every time
you enter a state.

Rule of thumb: if a value is about the *game* (scores, settings,
progress), it's a domain variable. If it's about the current *mode*
(how many ticks into this state we are, which item is selected on
this particular menu screen), it's a state variable.

## Building and Inspecting the Generated Code

Run `./build.sh` and then look at `generated/pong.gd`. The framepiler
produces a plain GDScript class with:

- A constructor that sets up the domain variables and enters
  `$AttractMode`
- One method per interface event (`start`, `launch`, `tick`, etc.)
- A dispatch function that routes events to the current state's
  handler
- One function per state (`_sPong_AttractMode`, `_sPong_Serving`, etc.)

It's about 200 lines. You can read it end to end. There's no runtime
library, no framework — it's just a class. If you ever decided to
stop using Frame, you could maintain this output directly.

That's a deliberate design choice in Frame: the transpiler disappears
after compilation. The generated code is the deliverable.

## The Godot Side: Brain Meets Body

Open [`godot/scripts/main.gd`](./godot/scripts/main.gd). The Frame
system doesn't know anything about Godot — no Vector2, no
CharacterBody2D, no input events. The Godot script owns all of that.

The key pattern is in `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
    _handle_input()

    var state: String = fsm.get_state()
    if state != "attract":
        _update_paddles(delta)

    if fsm.is_playing():
        _update_ball(delta)
        _check_scoring()

    if state == "serving":
        _park_ball_on_serve()

    queue_redraw()
    _update_labels()
```

Each frame:

1. **Input → FSM.** `_handle_input` reads keys and calls FSM events:
   `fsm.start()`, `fsm.launch()`, `fsm.restart()`.
2. **FSM → physics gating.** The Godot side asks the FSM "should I be
   running physics right now?" via `fsm.is_playing()`. Physics only
   integrates during `$InPlay`. No flag to manage — the FSM is the
   source of truth.
3. **Physics → FSM.** When the ball escapes the court, the Godot side
   tells the FSM: `fsm.ball_out_left()`. The FSM decides what that
   means (score a point, transition to `$PointScored`).
4. **FSM → rendering.** `_update_labels` asks the FSM for its state
   and the current score, and sets the labels accordingly.

No `if state == "foo" and not paused and not flag and not ...`
ladders. The FSM holds the modes; Godot renders them.

## Exercises

These are ordered roughly by difficulty. The point is to touch the
Frame file, not to perfect the game.

**1. Change the winning score.** Edit `winning_score` in the domain
block from `11` to something shorter (like `3`) so you can see the
full game loop quickly. Rebuild and run.

**2. Add a `pause` state.** Add a new state `$Paused` and an interface
event `pause()`. In `$InPlay`, handle `pause()` by transitioning to
`$Paused`. In `$Paused`, handle `pause()` by transitioning back to
`$InPlay`. Bind the P key to `fsm.pause()` in the Godot driver.

Hint: this is the first time you'll want to transition *back* to
where you came from. For now, just hard-code `-> $InPlay`. Chapter 4
will show you the cleaner way using `push$` and `-> pop$`.

**3. Add a "match point" announcement.** When either player reaches
`winning_score - 1`, the center label should display "MATCH POINT"
on serves. You'll need a new query like `is_match_point(): bool` and
to modify `_update_labels` to check it. Notice how the FSM grows
cleanly — no new states needed, just a new query derived from domain
variables.

**4. Make the AI beatable.** The right paddle's `ai_reaction` is
exported at the top of `main.gd`. Experiment with values like `0.4`,
`0.6`, `0.8`. For a real challenge, add an `@export var ai_difficulty`
to the Godot script and interpolate between several tuning parameters
based on it. The FSM doesn't need to change — this is all Godot side.

**5. Two-player mode.** Replace the AI with arrow-key control for the
right paddle. Again, no FSM changes — this is entirely a driver
concern. This exercise is the clearest demonstration of what the
brain/body split buys you: *gameplay* is in Frame, *interaction style*
is in Godot.

## What's Next

Chapter 2 is Breakout. The jump in complexity is significant: instead
of one state machine, you'll have three — a Paddle, a Ball, and a
BrickField — each with its own states, composed together. You'll see
Frame's **multi-system composition** pattern, which is how Frame
scales up to larger games without becoming a tangle.
