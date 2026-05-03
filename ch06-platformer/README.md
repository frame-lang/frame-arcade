# Chapter 6 — Platformer

Six chapters in. You've seen flat FSMs (Pong), composed FSMs
(Breakout, Invaders), HSM (Invaders, Pac-Man), the state stack
(Asteroids, Pac-Man), and parameterized systems (Asteroids,
Pac-Man). The toolkit is complete. This chapter isn't about
learning new Frame features — it's about **making the right
design choice among them**.

A Mario-style platformer character has two kinds of state that
need tracking:

- **Locomotion:** idle, walking, running, jumping, falling, landing.
  Changes several times per second based on input and physics.
- **Form:** small, big, fiery. Changes rarely, only on mushroom
  pickup or damage.

The naive instinct is: "Both are states, so put them in one
state machine." With HSM we could even do it without state
explosion — six locomotion states as children of three form
states, or vice versa.

**That would be wrong.** And the chapter is about why.

## What This Chapter Teaches

- The **orthogonal-state problem** — when two kinds of state
  vary independently, they should be two state machines, not
  one hierarchical one
- Composition as the *default* tool, HSM as a specialization
  for shared-behavior cases
- A meaty, genuinely-modal Locomotion FSM — the real workhorse
  of a platformer character
- Variable jump height via **state variables on `$Jumping`**
- The "pending jump impulse" one-shot signal pattern

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| ← / → (or A / D) | Walk |
| Shift (held) | Run |
| Space / ↑ / W | Jump (hold for higher) |
| R | Reset pickups |

There's a mushroom floating on the middle platform and a fire
flower on the high ledge. Pick them up and watch the player's
form change. Take damage is wired in the FSM but not yet in the
driver — no enemies in this demo. Exercise 3 adds them.

## The Two Designs

### Design A: One HSM combining everything

Here's what the "combine it all into one HSM" approach looks
like in Frame:

```frame
$Small {
    pickup_mushroom() { -> $Big }
    ...
}

$Small_Idle => $Small { ... }
$Small_Walking => $Small { ... }
$Small_Running => $Small { ... }
$Small_Jumping => $Small { ... }
$Small_Falling => $Small { ... }
$Small_Landing => $Small { ... }

$Big {
    pickup_flower() { -> $Fiery }
    take_damage() { -> $Small_Idle }   // which locomotion?!
    ...
}

$Big_Idle => $Big { ... }
$Big_Walking => $Big { ... }
// ... 6 more child states ...

$Fiery { ... }
$Fiery_Idle => $Fiery { ... }
// ... 6 more child states ...
```

Eighteen child states. That's not fundamentally terrible; HSM
means you don't write eighteen copies of the same logic. But
look at `$Big.take_damage()`. When you get hit as Big Mario, you
transition to... Small. But which Small? If you were running,
you should presumably land in Small-Running. If you were jumping,
Small-Jumping. Now the damage handler needs to *query* its
current locomotion child to know which sibling to go to.

The deeper problem: **the transitions are crossing dimensions.**
Form events need to preserve locomotion. Locomotion events need
to preserve form. Every cross-cutting transition is a
"remember-what-you-were-doing-and-recreate-it-under-the-new-umbrella"
operation, and that's awkward to express.

You can solve this — exit handlers that record the old locomotion,
enter handlers that restore it, a domain variable stashing the
last known locomotion state. But each of those mechanisms exists
to work around the fundamental mismatch: you're trying to put
orthogonal state into one tree.

### Design B: Two separate FSMs

Open [`frame/platformer.fgd`](./frame/platformer.fgd) and see how
we actually built it:

```frame
@@system Locomotion : RefCounted {
    // 6 states: Idle, Walking, Running, Jumping, Falling, Landing
    // 10-ish events: press_left, press_jump, ground_contact, etc.
}

@@system PowerUp : RefCounted {
    // 3 states: Small, Big, Fiery
    // events: pickup_mushroom, pickup_flower, take_damage
}

@@system Player : RefCounted {
    // Single-state orchestrator
    domain:
        loco = @@Locomotion()
        power = @@PowerUp()
}
```

Two independent FSMs. `take_damage()` goes to `PowerUp`, doesn't
touch `Locomotion`. Jumping events go to `Locomotion`, don't
touch `PowerUp`. **No cross-dimensional entanglement.**

The state count is 6 + 3 = 9, not 6 × 3 = 18. More importantly,
each dimension can evolve independently:

- Add a new locomotion state (`$Swimming`)? Just extends
  Locomotion. PowerUp is untouched.
- Add a new form (`$Invincible` after a star)? Just extends
  PowerUp. Locomotion is untouched.

In the HSM version, adding `$Swimming` would mean adding
`$Small_Swimming`, `$Big_Swimming`, `$Fiery_Swimming` — three
new states for every new locomotion kind times every form.

## The Rule

**When two kinds of state vary independently, use two FSMs.**

HSM is for when child states share *event handling* with a
parent — when the parent's job is "handle these cross-cutting
events for all my children." Pac-Man's `$OutOfPen` is a good
example: all children in that hierarchy should respond to
`power_pellet_eaten()` the same way. The event is orthogonal
to the children's own differences, but it cuts across them in
a way HSM expresses cleanly.

When there's no shared event handling to factor out — when the
two dimensions just coexist — HSM buys you nothing but scaffolding.
Use composition.

A mnemonic: **HSM is inheritance. Composition is composition. The
same preference for composition over inheritance that applies to
OO class design applies to state machine design.**

## The Locomotion FSM, Walked Through

Now the interesting bit: the Locomotion state machine itself. It
has real modal logic with all the classic platformer gotchas.

### The state structure

```
                    ground_contact / (start)
                         ↓
              ┌────────  $Idle  ──────┐
              │           │           │
      press_left/right    │      press_jump
              ↓           │           ↓
           $Walking ──press_jump──→ $Jumping
              │                        │ ground_contact
           press_sprint                 ↓
              ↓                    $Landing
           $Running ──press_jump───↑   │
                                       ↓ (after brief timer)
                                     $Idle / $Walking
                    left_ground
              ↑        ↓
           $Jumping → $Falling
                        ↓ ground_contact
                     $Landing
```

Six states. Event handlers are scattered appropriately: events
that only matter on the ground live in ground states; events
that only matter in the air live in air states.

### The `$Jumping` state and variable jump height

This is the showcase for **state variables**. Mario's jump height
depends on how long you hold the button. Release it early, jump
short. Hold it all the way, jump high. In Frame:

```frame
$Jumping {
    $.jump_held_time: float = 0.0
    $.jump_released: bool = false

    tick(dt: float) {
        if not $.jump_released:
            $.jump_held_time = $.jump_held_time + dt
        if $.jump_held_time >= 0.35:
            -> $Falling
    }

    release_jump() {
        $.jump_released = true
    }
    ...
}
```

`$.jump_held_time` is a state variable — it exists only while
the player is in `$Jumping`. Every time you enter `$Jumping`
(which is every jump), it resets to zero. Its lifetime matches
its meaning.

`$.jump_released` is the early-release flag. Once it's true,
`jump_held_time` stops accumulating, so `0.35s` becomes an
unreachable ceiling — the state transitions to `$Falling` based
on the physics-driven velocity instead (handled elsewhere). The
driver also sees `_jump_down` becoming false and applies a
jump-cut velocity multiplier.

Variable jump height is the textbook platformer feature that's
awkward to express in imperative code — you end up with
`is_jumping`, `jump_held_time`, `has_released_jump_this_jump`,
`jump_was_cut` flags strewn across the character controller. In
Frame, the state-scoped variables colocate with the state that
uses them. No flags across frames.

### The "pending impulse" pattern

When Space is pressed and we transition from `$Idle` to `$Jumping`,
the player needs a sudden upward velocity. The FSM doesn't touch
the Godot character body directly — that'd break the brain/body
split. Instead:

```frame
$Idle {
    press_jump() {
        self.pending_jump = true
        -> $Jumping
    }
    ...
    wants_jump_impulse(): bool  { @@:(self.pending_jump) }
    consume_jump_impulse()      { self.pending_jump = false }
}
```

Each frame the driver asks:

```gdscript
if fsm.wants_jump_impulse():
    player_vel.y = -jump_impulse
    fsm.consume_jump_impulse()
```

A one-shot signal: the FSM flags "I want an impulse," the driver
applies it and tells the FSM it's done. The FSM never computes
velocity in pixels/second — that's the driver's job. The FSM
just says "I want an impulse" and lets the driver translate that
to its own physics units.

Same pattern works for sound effect triggers, screen shake
events, camera focus changes — anywhere the FSM needs to flag a
"one-time thing just happened" to the driver.

### Why `$Landing` is its own state

`$Landing` is only ~80ms long. Could we just go straight from
`$Falling` to `$Idle` on ground contact?

The reason it's a state is that it **suppresses immediate
re-jumping** — the enter handler clears `pending_jump`:

```frame
$Landing {
    $>() {
        self.pending_jump = false
    }
    ...
}
```

Without this, spamming Space during a fall would cause the
player to immediately re-jump the instant they touched the
ground, before the frame where they actually landed registered.
The `$Landing` state gives us a defined place to consume the
stale input.

It's a small thing, but it's the kind of small thing a FSM
encodes cleanly. A boolean like `just_landed = true` that gets
flipped by physics and consumed in the next input tick is the
alternative — and it's worse because nothing reminds you to
actually check it.

## The PowerUp FSM

Compare the weight of the two systems. Locomotion has six states,
a dozen events, state variables. PowerUp is much simpler:

```frame
@@system PowerUp : RefCounted {
    interface:
        pickup_mushroom()
        pickup_flower()
        take_damage(): bool         // false = died
        ...

    machine:
        $Small {
            pickup_mushroom() { -> $Big }
            pickup_flower()   { -> $Fiery }
            take_damage(): bool { @@:(false) }
        }
        $Big {
            pickup_flower()   { -> $Fiery }
            take_damage(): bool { @@:(true)  -> $Small }
        }
        $Fiery {
            take_damage(): bool { @@:(true)  -> $Big }
        }
}
```

Three states. Clean, linear, no fuss. Notice:

- Neither state knows about the other's existence except for
  the transitions. No inheritance needed.
- `take_damage()` returns a boolean: "are you still alive?"
  `$Small` returns false when hit. The driver can react
  accordingly (respawn animation, life decrement, etc.).
- Events that don't apply are silently ignored. `pickup_mushroom`
  in `$Big` does nothing — you're already powered up. Frame's
  "unhandled events are ignored" default makes this implicit.

This is the fifty-line state machine. Not every FSM needs to
be elaborate. PowerUp exists because the character's form is
legitimately modal — it affects rendering, hit box size, and
capability (only `$Fiery` can shoot). Making it a state machine
makes those dependencies structural rather than conventional.

## The Player Orchestrator

Player holds both sub-systems and delegates:

```frame
@@system Player : RefCounted {
    machine:
        $Playing {
            press_left()        { self.loco.press_left() }
            press_right()       { self.loco.press_right() }
            press_jump()        { self.loco.press_jump() }
            pickup_mushroom()   { self.power.pickup_mushroom() }
            take_damage(): bool { @@:(self.power.take_damage()) }
            ...
            locomotion_state(): String  { @@:(self.loco.get_state()) }
            form(): String              { @@:(self.power.get_form()) }
        }
    domain:
        loco = @@Locomotion()
        power = @@PowerUp()
}
```

Player has *one state*. Every event is just a forwarding call
to the appropriate sub-system.

So why have Player at all? Why not have the driver just create
a Locomotion and a PowerUp directly and call each?

Two reasons:

1. **Encapsulation.** The driver shouldn't need to know there
   are two sub-FSMs. It knows about a Player. If we later
   decide to split Locomotion further (separate Jump FSM from
   ground movement FSM, say), the driver doesn't change.
2. **Composite operations.** Some events involve both
   sub-systems. Resurrecting the player after a death might
   reset both Locomotion and PowerUp. That logic belongs on
   Player, not on the driver.

Player is **thin by design**. When the composite operations grow
(death handling, checkpointing, power-up-timer expiration), they'll
live in Player. Right now it's just a pass-through.

## Things This Chapter Doesn't Cover

- **Enemies.** No enemies in the demo, so `take_damage()` is
  wired up but can't fire. Add some and watch the PowerUp FSM
  do its thing.
- **Coyote time** (the brief grace period after walking off a
  ledge during which you can still jump). A great state-stack
  candidate — push $Walking, enter $CoyoteGrace with a short
  timer, pop back or fall through to $Falling. Exercise 5.
- **Wall sliding / wall jumping.** Several more locomotion
  states. Clean to add once you've seen how the existing ones
  compose.
- **Scrolling camera, tilemaps, level editor.** All standard
  Godot work, orthogonal to Frame.

## Exercises

**1. Add a `$Crouching` state to Locomotion.** Handle press_down/
release_down events. In `$Crouching`, jump should cancel crouch
and jump. Running into a space too low to stand up in should
force `$Crouching` and prevent release_down from taking effect
until there's headroom. (The headroom check belongs in the
driver — it queries collisions and sends a `blocked_above()`
event to the FSM to keep it crouched.)

**2. Make PowerUp drive rendering.** Currently the driver reads
`form()` from the FSM and picks colors. Generalize: have the
PowerUp system expose `get_render_layer(): String` returning a
layer name the driver uses to pick a sprite. This pushes more
rendering decisions into the FSM — the driver becomes dumber.
Discuss: is that better, worse, or situational?

**3. Add a simple enemy that hurts on contact.** On contact,
call `fsm.take_damage()`. Check the return value. If it's
false, respawn the player at the start. If it's true, trigger
a brief invulnerability window (see Pong and Invaders for the
pattern) before allowing more damage.

**4. Coyote time.** Implement the state-stack solution described
above. Compare it to a "timer variable in $Falling" approach.
Which reads more clearly?

**5. Variable jump height tuning.** The jump-cut multiplier is
`0.4` in the driver. Play with values between 0.2 and 0.6 and
decide what feels best. Notice that none of this tuning requires
touching the Frame source — it's all driver-side feel. That's
the clean brain/body split at its best: gameplay logic in Frame,
game feel in the driver.

## What's Next

Chapter 7 is the finale — a **side-scrolling shooter**
(R-Type / Gradius style). It will pull together everything:
multiple cooperating systems, HSM, state stacks, parameterized
enemies. The boss itself will be a multi-phase state machine
worth seeing. It's also the chapter where we finally let
ourselves use Frame systems for individual entities — because
shooter enemies really do have modal behavior — and where we
see how parameterized systems scale to dozens of instances.
