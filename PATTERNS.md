# Frame Arcade — Patterns and Practices

This is the long-form companion to the [Patterns section in the
README](./README.md#patterns-and-practices). Each of the nine
patterns gets:

- the rationale (one paragraph)
- a Frame-source code sample drawn from this repo
- a "where to find it" pointer with file paths
- when to reach for it (and when not to)

If you're reading the book chapters in order, expect to meet
each pattern as it's introduced, then watch it deepen across
later chapters. If you're skimming the source after reading an
article, this document is the index.

---

## 1. Frame is the brain, Godot is the body

The whole arcade rests on one decision: **the Frame system holds
state; the Godot node holds rendering**. The Frame system never
imports a Godot type. The Godot driver never reaches into the
FSM's internals — it talks through the FSM's interface methods.
The driver reads input, calls into the FSM, and queries the FSM
for what to render.

This means you can:

- Test the FSM under headless Godot without ever touching a
  scene tree (every smoke test in `cca/tests/` does exactly
  this).
- Swap the renderer (the [arcade cabinet](./arcade/) reuses
  the chapters' FSMs unmodified).
- Port to a different engine by rewriting only the driver
  script — the `.fgd` file ships across.

**Code sketch** (driver-side, `_physics_process` shape):

```gdscript
func _physics_process(delta: float) -> void:
    # 1. Input → FSM
    if Input.is_action_pressed("paddle_up"):
        fsm.paddle_up()
    if Input.is_action_pressed("paddle_down"):
        fsm.paddle_down()

    # 2. FSM advances
    fsm.tick(delta)

    # 3. FSM → render
    paddle.position.y = fsm.paddle_y()
    score_label.text = str(fsm.score())
    if fsm.is_game_over():
        $GameOverPanel.visible = true
```

The FSM doesn't know `paddle.position.y` is a thing. It just
exposes `paddle_y(): float`.

**Where:** every chapter. Cleanest small example:
[`ch01-pong/godot/scripts/main.gd`](./ch01-pong/godot/scripts/main.gd).

**When to use:** always. This is the load-bearing pattern;
everything else assumes it.

---

## 2. Hierarchical state machines (HSM)

A parent state defines shared entry/exit handlers, shared
queries, shared transitions. Children override selectively.
Frame's `=> $^` dispatches an event up to the parent. The HSM
is what makes "ghost is in $Frightened *and* $Tunnel"
expressible without an exponential matrix of leaf states.

**Code sample** (Lamp from CCA — the cleanest small HSM):

```frame
machine:

    $Off {
        light() {
            if self.battery <= 0:
                -> $Out
            else:
                -> $Bright
        }
        is_lit(): bool        { @@:(false) }
        battery_left(): int   { @@:(self.battery) }
    }

    $On {
        # Parent: per-tick drain, extinguish behavior, default
        # is_lit is true. Children override only what differs.
        extinguish()  { -> $Off }
        tick()        { self.battery = self.battery - 1 }
        is_lit(): bool  { @@:(true) }
    }

    $Bright => $On {
        tick() {
            self.battery = self.battery - 1
            if self.battery <= self.DIM_THRESHOLD:
                -> $Dim
        }
    }

    $Dim => $On {
        tick() {
            self.battery = self.battery - 1
            if self.battery <= 0:
                -> $Out
        }
    }

    $Out => $On {
        is_lit(): bool { @@:(false) }   # override parent
        tick() {}                       # no further drain
    }
```

`$Bright`, `$Dim`, and `$Out` all inherit from `$On`, so
`extinguish()` works in all of them via parent dispatch. Each
overrides only its own threshold transition.

**Where:**

- [`ch03-invaders/frame/invaders.fgd`](./ch03-invaders/frame/invaders.fgd) — pacing HSM (introduces the pattern)
- [`ch05-pacman/frame/pacman.fgd`](./ch05-pacman/frame/pacman.fgd) — `$Scatter`/`$Chase` under `$Active`/`$Frightened`
- [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) — `Lamp` ($On.$Bright/$Dim/$Out) and `Endgame` (multi-phase HSM with state-variable timer)

**When to use:** when you find yourself writing the same
transition or query in two leaf states. Lift it to a parent.

**When NOT to use:** if your states are all genuinely different
shapes (no shared behavior), HSM adds ceremony for nothing. A
flat machine is fine.

---

## 3. State stack (push$/pop$)

Suspend the current state, run a sub-state, then pop back to
where you were — with all your domain variables intact. The
classic "hyperspace, then resume normal flight" shape. Frame's
compartment serialization round-trips pushed states through
`@@[persist]` for free, so a save/load mid-hyperspace just
works.

**Code sample** (Asteroids hyperspace):

```frame
$Flying {
    hyperspace() {
        push$ $Hyperspace
    }
    tick() {
        # Normal physics
    }
}

$Hyperspace {
    $>() {
        # Entry: hide the ship, start fade-in timer
        self.hyperspace_timer = 1.0
    }
    tick() {
        self.hyperspace_timer = self.hyperspace_timer - 0.016
        if self.hyperspace_timer <= 0:
            # Random new position, then pop back to $Flying
            self.x = rand_range(0, 800)
            self.y = rand_range(0, 600)
            pop$
    }
}
```

When the player hits hyperspace, `$Flying` pushes; the ship's
position, velocity, score — all preserved on the stack. After
the brief teleport, `pop$` returns to `$Flying` exactly as it
was, except now at a new (x, y).

**Where:**

- [`ch04-asteroids/frame/asteroids.fgd`](./ch04-asteroids/frame/asteroids.fgd) — hyperspace (introduces the pattern)
- [`ch05-pacman/frame/pacman.fgd`](./ch05-pacman/frame/pacman.fgd) — frightened mode (timed sub-state per ghost)

**When to use:** any time the game enters a temporary
"different rules apply" state and needs to return cleanly to
where it was. Hyperspace, frightened, paused, mid-dialog,
mid-cutscene.

---

## 4. Parameterized systems × N

A single `@@system Foo(seed: int)` declaration with multiple
named instances, each with its own configuration. Frame's
`@@[persist]` auto-traverses named domain fields, so adding a
fifth instance is one line. The trade-off is an if-ladder in
the orchestrator to dispatch by-name instead of by-index.

**Code sample** (Dwarves from CCA — five instances of one FSM):

```frame
@@[persist]
@@system Dwarf(seed: int) : RefCounted {
    interface:
        wake_up(at_room: int)
        attack(): String
        try_throw_axe(): bool

    machine:
        $Hidden {
            wake_up(at_room: int) {
                self.location_room = at_room
                -> $Stalking
            }
        }
        $Stalking {
            attack(): String {
                # Probabilistic outcome, deterministic per seed
                self.step = self.step + 1
                var x = self.seed * 1664525 + self.step * 1013904223
                if (x % 100) < 70:
                    -> $Dead
                    @@:return("You killed it.")
                @@:("Your axe missed.")
            }
        }
        $Dead {}

    domain:
        seed: int = seed     # constructor parameter
        step: int = 0
        location_room: int = -1
}

# In Adventure's domain:
dwarf1 = @@Dwarf(1)
dwarf2 = @@Dwarf(2)
dwarf3 = @@Dwarf(3)
dwarf4 = @@Dwarf(4)
dwarf5 = @@Dwarf(5)
```

Each dwarf carries its own seed and step, so they roll
divergent outcomes from identical starting conditions. Save/
restore round-trips all five through `@@[persist]` because they
live in named domain fields.

**Where:**

- [`ch04-asteroids/frame/asteroids.fgd`](./ch04-asteroids/frame/asteroids.fgd) — difficulty-tier asteroids (introduces)
- [`ch05-pacman/frame/pacman.fgd`](./ch05-pacman/frame/pacman.fgd) — four ghosts, shared FSM, divergent AI personalities (the showpiece)
- [`ch07-shooter/frame/shooter.fgd`](./ch07-shooter/frame/shooter.fgd) — enemy wave instances
- [`ch08-stealth/frame/stealth.fgd`](./ch08-stealth/frame/stealth.fgd) — three guards in a maze
- [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) — `Dwarf × 5`, `Hint × 3`, `Treasure × 15`

**When to use:** any time you'd otherwise duplicate an FSM
class three or four times with minor parameter tweaks.

**When NOT to use:** if instances really do need different
*behavior*, not just different *parameters*, lift the differing
behavior into the parent class via HSM and use parameterized
children for the rest. Don't paper over genuinely different
designs with constructor flags.

---

## 5. Cross-FSM orchestration

Each FSM owns its own state; a parent "World" / "Adventure" /
"Conductor" system brokers cross-cuts. Releasing the bird
shouldn't be a thing the bird FSM knows about the snake; it's
a thing the orchestrator observes the bird doing and forwards
to the snake. This keeps every subsystem unit-testable in
isolation.

**Code sample** (CCA's bird → snake choreography):

```frame
# Bird only knows its own transitions:
@@system Bird {
    machine:
        $Caged {
            release(at_room: int) {
                self.location_room = at_room
                if at_room == self.SNAKE_ROOM:
                    -> $Released   # bird drove off the snake
                elif at_room == self.DRAGON_ROOM:
                    -> $Dead       # dragon ate the bird
                else:
                    -> $Free
            }
        }
}

# Adventure brokers the cross-cut:
_verb_release(noun: String): String {
    if noun == "bird":
        var room: int = self.player.get_room()
        var was_caged: bool = (self.bird.get_state() == "caged")
        self.bird.release(room)
        # Cross-FSM: if the bird just landed in the snake room,
        # tell the snake about it. The bird itself doesn't know
        # the snake exists; Adventure is the broker.
        if was_caged and room == self.SNAKE_ROOM:
            self.snake.bird_released_here()
            return "The bird attacks the snake; the snake flees!"
        ...
}
```

The bird transitions to `$Released` regardless. Adventure
*observes* that transition and forwards an event to the snake,
which transitions to `$Gone`. The two FSMs never reference each
other.

**Where:**

- [`ch02-breakout/frame/breakout.fgd`](./ch02-breakout/frame/breakout.fgd) — ball / paddle / bricks orchestrator (introduces)
- [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) — `Adventure` brokers bird→snake, bear→troll, pirate→treasure, vending→lamp, eggs-incantation→eggs-reappear, dragon-attack→player (the showpiece)

**When to use:** any time one FSM's transition needs to trigger
a transition in another FSM. The orchestrator pattern keeps
each FSM unit-testable in isolation; the cross-cut tests only
need to test the orchestrator.

**When NOT to use:** if the two FSMs are actually one concept
(e.g., a "Player" FSM that contains health, ammo, position),
make them children of one parent FSM rather than peers with
an orchestrator.

---

## 6. Aspect machines: priority-ordered FSM interceptors on a bus

When cross-cutting concerns (darkness, inventory limits, magic
words, scoring) start growing into the base machine as
flag-checks, lift them onto an `AspectBus`. Each aspect is
itself an FSM with a priority and a verdict (consume /
transform / observe / pass). Higher-priority aspects fire
first; consume short-circuits the chain.

**Code sample** (CCA's `DarknessGate` aspect):

```frame
@@[persist]
@@system DarknessGate : RefCounted {
    interface:
        try_handle(event: Dictionary): Dictionary

    machine:
        $Active {
            try_handle(event: Dictionary): Dictionary {
                var verb: String = event.get("verb", "")
                var room: int = event.get("room", -1)
                # Only gate look/examine/read in dark rooms
                var gated = (verb == "look" or verb == "examine"
                             or verb == "read")
                if gated and self._is_dark(room):
                    self.consumed = self.consumed + 1
                    @@:return({
                        "verdict": "consume",
                        "message": "It is pitch dark."
                    })
                @@:({"verdict": "pass", "event": event})
            }
        }
}

# AspectBus dispatches in priority order:
# - DarknessGate (priority 700, consume) fires first.
# - If it consumes, downstream aspects don't run.
# - MagicWordTeleport (500, transform) rewrites the event.
# - BackpackLimit (400, consume) blocks at full inventory.
# - ScoreLedger (100, observe) counts every event.
```

Each aspect is independent. Adding a fifth one (say, a
"DwarvesAttackOnEntry" aspect) is one new `@@system` and one
`bus.register("dwarves", 600)` call.

**Where:**

- [`cca/frame/aspects.fgd`](./cca/frame/aspects.fgd) — the AspectBus + sample aspects + Conductor demo (smoke-test fixture)
- [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) — four production aspects: `DarknessGate`, `BackpackLimit`, `MagicWordTeleport`, `ScoreLedger`

**When to use:** when cross-cutting concerns (darkness, sound,
fog-of-war, scoring) are growing into the base machine as
boolean flags. Lift them onto a bus.

**When NOT to use:** if you only have one or two cross-cuts,
the bus is over-engineered. Plain orchestrator-side checks are
fine. The bus earns its keep when you're at three+ aspects.

---

## 7. Persistence via `@@[persist]`

One annotation on the world system; framepiler auto-traverses
every named domain field, including nested `@@system`
instances, including pushed compartments, including
state-variable timers. `save_state(): PackedByteArray` and
`restore_state(bytes)` round-trip the entire game in one call.

**Code sample** (Adventure's save/load surface):

```frame
@@[persist]
@@system Adventure : RefCounted {
    operations:
        @@[save]
        save_state(): PackedByteArray {}

        @@[load]
        restore_state(data: PackedByteArray) {}

    domain:
        # Every field below is auto-traversed on save/load.
        bus       = @@AspectBus()
        lamp      = @@Lamp()
        player    = @@Player()
        bird      = @@Bird()
        snake     = @@Snake()
        bear      = @@Bear()
        dragon    = @@Dragon()
        endgame   = @@Endgame()
        dwarf1    = @@Dwarf(1)
        dwarf2    = @@Dwarf(2)
        # ... fifteen more nested @@systems ...
        gold      = @@Treasure(11, 5)
        # ... fourteen more treasures ...
        rooms_visited: Array = []
        score_treasures: int = 0
}
```

Saving the game:

```gdscript
var bytes: PackedByteArray = fsm.save_state()
FileAccess.open("user://save.dat", FileAccess.WRITE).store_buffer(bytes)
```

Loading:

```gdscript
var bytes = FileAccess.open("user://save.dat", FileAccess.READ).get_buffer(...)
fsm.restore_state(bytes)
# Every @@system instance, every push$ compartment, every
# state-variable, every domain field — all restored.
```

The single biggest LOC win Frame ships in this book — and the
reason mid-game save/restore is just *there* in every chapter.

**Where:** every chapter that has save/load. Showpiece in
[`cca/frame/cca.fgd`](./cca/frame/cca.fgd) (24 nested FSMs +
state-variable timer + push compartments — all round-trip in
one `save_state()` call).

**When to use:** always, on the world / Adventure system.

**Caveat:** the field has to be a *named* domain field, not an
`Array<@@system>`. That's why CCA names `dwarf1` through
`dwarf5` instead of an array.

---

## 8. Multi-turn parser dialog as state

When the game asks the player a question and waits for the
answer, *that's a state*, not an `awaiting_yes_no: bool` flag
on the base machine. Push into `$Asked`, accept yes/no,
transition based on the answer, pop back. The dialog context
*is* the state.

**Code sample** (Dragon's "with what?" prompt from CCA):

```frame
$Alive {
    attack_dragon(): String {
        push$ $Asked
        @@:return("With what? Your bare hands?")
    }
}

$Asked {
    yes(): String {
        # Bare-handed kill (canonical CCA bug we replicate)
        -> $Dead
        @@:return("Congratulations! You have just vanquished a dragon with your bare hands! Unbelievable!")
    }
    no(): String {
        pop$
        @@:return("You decide not to fight the dragon.")
    }
    # Anything else: "answer yes or no."
}

$Dead {
    is_alive(): bool { @@:(false) }
}
```

The "yes" answer arrives many turns later; the FSM is still in
`$Asked` waiting for it. No flag-on-base-machine; the dialog
context lives in the state machine itself, where it can be
saved/restored along with everything else.

**Where:**

- [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) — Dragon's "attack with what?" prompt, plus the resurrection prompt after death

**When to use:** any "are you sure?" / "with what?" / yes-no
mid-game prompt. Including in the arcade games — a "really
quit?" dialog is the same shape.

---

## 9. Per-frame overlay rendering

The renderer asks the FSM "what's in this room / on this screen
right now?" and the FSM stitches together a base description
plus per-NPC, per-item, per-state overlays. The FSM never holds
rendering state; the renderer never holds game state. You add
a new pickup or NPC by adding one query to the FSM and one
overlay branch in the renderer.

**Code sample** (CCA's `_verb_look` — the canonical overlay
shape):

```frame
_verb_look(): String {
    var r: int = self.player.get_room()
    var base: String = ""

    # Base text: per-room description
    if r == 1:
        base = "You are at the end of a road..."
    elif r == 3:
        base = "You are inside a building, a well house..."
    # ... 138 more rooms ...

    # NPC overlays — render only if NPC is here right now
    if r == self.bird.get_location() and self.bird.get_state() == "free":
        base = base + " A small bird flutters nearby."
    if r == self.SNAKE_ROOM and self.snake.is_blocking():
        base = base + " A huge green snake bars further passage."
    if r == self.BEAR_HOME_ROOM and self.bear.get_state() == "hungry":
        base = base + " A large bear is chained to the wall, glaring hungrily."
    # ... troll, dragon ...

    # Treasure overlays — only visible when in_room (not carried, not deposited)
    if self.gold.get_location() == r and self.gold.get_state() == "in_room":
        base = base + " There's a gleam of gold here."
    # ... fourteen more treasures ...

    # Dynamic-state overlays
    if r == self.GRATE_ROOM:
        if self.grate.is_locked():
            base = base + " The grate is locked."
        else:
            base = base + " The grate is unlocked and swung open."

    return base
}
```

The Godot driver just calls `fsm.do_command("look", "")` and
prints the result. Adding the rod / keys / bottle puzzles
required one new query each plus one new overlay branch — the
driver was untouched.

**Where:**

- Implicitly in every chapter (e.g., Pong's scoreboard query)
- Formalized in CCA's `_verb_look` (room base text + bird/snake/bear/dragon overlays + each treasure, rod, keys, grate state)

**When to use:** any time the renderer needs to compose
multiple game-state facts into one display surface.

---

## Bonus: Consume-an-item-as-side-effect (CCA only)

The vending machine in CCA removes the player's coins from
play *and* triggers a cross-FSM lamp refresh in a single
transition. It's a small enough shape that it doesn't earn its
own chapter, but it's worth seeing once if you're modeling
trade puzzles.

**Code sketch:**

```frame
# VendingMachine FSM:
$Loaded {
    insert(have_coins: bool): String {
        if have_coins:
            -> $Empty
            @@:return("The vending machine clanks twice and dispenses fresh batteries.")
        @@:("You don't have coins.")
    }
}
$Empty { }   # terminal

# Adventure brokers item-consumption + cross-FSM:
_verb_insert(noun: String): String {
    if noun != "coins":
        return "You can't insert that."
    if self.player.get_room() != self.VENDING_ROOM:
        return "There's nothing here to insert into."
    var was_loaded: bool = self.vending.is_loaded()
    var has_coins:  bool = self.player.carrying(self.COINS_ID)
    var msg: String = self.vending.insert(has_coins)
    if was_loaded and has_coins and not self.vending.is_loaded():
        # Successful trade. Consume the coins out-of-bounds and
        # refresh the lamp. Both side effects are atomic with
        # the vending FSM transition.
        self.player.drop(self.COINS_ID)
        self.coins.reappear(0)        # relocate to non-existent room
        self.lamp.refresh()           # cross-FSM trigger
    return msg
}
```

Where: [`cca/frame/cca.fgd`](./cca/frame/cca.fgd) (`VendingMachine`).

---

## How to use this document in articles

If you're writing a Frame article and want to link to a
canonical example of pattern N, link to:

- The **README's Patterns section** for a one-paragraph hook.
- This **PATTERNS.md** for the worked example.
- The **chapter source** (linked in each pattern) for the full
  context.

Articles can be small without losing access to the full
demonstration — readers click through.
