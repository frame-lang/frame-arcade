# Platformer: an honest evaluation

**Question:** When a character has *two* independent modal
dimensions (motion mode + power-up form), is HSM the right
answer, or does composition (two FSMs side-by-side) win?

**TL;DR:** Frame is **a 4/5 win for Platformer** — and the
chapter's key insight is "use composition, not HSM." A Mario-style
character has motion mode (idle/walk/run/jump/fall) and power-up
form (small/big/fiery) as *orthogonal* state dimensions. An HSM
representation would be 5×3 = 15 leaf states with massive
duplication. Two parallel FSMs (`Locomotion` + `PowerUp`)
composed under `Player` is 5+3 = 8 states with zero duplication.

The chapter is the book's clearest argument for "lift state into
sub-systems when dimensions are independent." Pong, Breakout,
and Asteroids use composition for unrelated sub-systems
(Ball+BrickField, Ship+AsteroidField). Platformer uses
composition because the *character itself* has multiple
orthogonal state machines.

---

## What was built

- `Locomotion` — 6 states (idle, walking, running, jumping,
  falling, landing) with `$.timer` on jumping.
- `PowerUp` — 3 states (small, big, fiery) with damage decay.
- `Player` — single-state composer that routes events to both
  sub-systems.

**Frame source:** ~500 lines
**Generated GDScript:** ~2000 lines
**Driver:** ~880 lines (physics, jump-height variability, render)
**Smoke tests:** 40 checks covering Locomotion, PowerUp, Player
composition.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Locomotion` | **4** | Six states with clear transitions. Press right → walking; press sprint while walking → running; press jump → jumping with `pending_jump` flag the driver consumes for the impulse; left_ground → falling. The "consume_jump_impulse" pattern is small and clean — the FSM holds *that we want to jump*, the driver applies the actual impulse and clears the flag. |
| `PowerUp` | **5** | Three states, perfect monotone-then-decay shape: pickup_mushroom upgrades, pickup_flower upgrades, take_damage decays one tier, take_damage in $Small returns false (player died). The hit_box_height query (24/48/48) is consumed by the driver to swap collision shapes. The shoot/no-shoot ability (only $Fiery) is queried by the driver to decide whether to allow fire input. **The cleanest small example of "queries for boolean abilities + queries for derived data" in the book.** |
| `Player` | **3** | Single-state composer. Routes events 1:1 to sub-systems (press_left → loco.press_left; pickup_mushroom → power.pickup_mushroom). Composition over inheritance, applied at the character level. The "single state" makes the FSM scaffolding look ceremonial, but the chapter's whole point is *the two sub-FSMs are the state* — Player itself doesn't need modes. |

---

## What Frame demonstrably did well

### 1. Orthogonal state without state explosion

Mario can be (Idle, Small) or (Running, Fiery) or (Jumping, Big).
That's 6 × 3 = 18 combinations. An HSM would either:

- Have 18 leaf states (terrible), or
- Have 6 motion states with 3-way conditional behavior in each
  (also terrible), or
- Use orthogonal regions (Frame doesn't support these directly,
  and they're a niche feature in UML/StateChart land anyway).

The composition answer is 6 + 3 = 9 states, zero
duplication. The chapter argues this is usually the right call.

### 2. Damage as a return-value transition

`take_damage(): bool` returns true if the player survives,
false if they died. `$Small.take_damage` returns false (no
state change — driver kills the player). `$Big.take_damage`
returns true and transitions to $Small. The decision and the
transition are inseparable; the return tells the driver what to
do next.

### 3. Independent state save/restore

Saving the game would just save Locomotion's state and
PowerUp's state independently. No coordination needed because
the two FSMs don't interact. This chapter doesn't actually use
@@[persist] (it's a behavior demo, not a scoring game), but the
pattern is correct for it.

---

## What Frame demonstrably *didn't* help with

### 1. Jump physics

Variable jump height (longer hold = higher jump), gravity,
horizontal momentum at the top of the arc, coyote time — all
driver-side. The FSM tells the driver "I want to jump" and the
driver implements the physics.

### 2. Animation blending

The driver picks the right sprite based on `locomotion_state()`
and `form()`, but the actual sprite-blend math (or whatever
animation system) is engine-specific.

### 3. Collision response

The driver detects ground/wall/enemy collisions and feeds them
to the FSM as events (`ground_contact`, `take_damage`). The
FSM responds with state transitions; the driver applies the
mechanics.

---

## Comparison: hypothetical Platformer in plain GDScript

The composition pattern works fine in plain GDScript:

```gdscript
class Locomotion:
    var state: int  # enum
    func press_left(): ...

class PowerUp:
    var form: int   # enum
    func pickup_mushroom(): ...

var loco = Locomotion.new()
var power = PowerUp.new()
```

Equivalent in size, slightly less self-documenting. The Frame
version's `$Idle.press_left() -> $Walking` reads more like a
state diagram than the GDScript version's `if state == IDLE: state
= WALKING`.

**Net:** Frame is a clear legibility win, equivalent in LOC. The
chapter's pedagogical point — "composition beats HSM when
dimensions are independent" — is the right frame for thinking
about this design choice in any engine.

---

## When to reach for Frame for a Platformer-class game

**Use Frame when:**
- A character has 2+ orthogonal modal dimensions (motion +
  form, motion + status-effects, etc.).
- Each dimension has 3+ distinct modes.
- You'd otherwise be tempted to write 15+ leaf states or a
  match ladder with conditionals on multiple variables.

**Don't reach for Frame when:**
- The character has one modal dimension.
- The "second dimension" is a single boolean (alive/dead, etc.).

For Platformer: yes — the chapter's value is the architectural
lesson, not the size of the win.
