# Colossal Cave Adventure (Frame port)

> **Status:** prototype. The aspect-bus foundation is here and verified;
> the actual CCA world (rooms, NPCs, parser, treasures) hasn't been built
> yet.

Frame port of Crowther/Woods *Colossal Cave Adventure*. Uses the
[aspect machines](https://example.invalid/aspect-machines) pattern —
small FSM interceptors on a priority-ordered bus in front of the world
state machine — to decompose CCA's many cross-cutting concerns
(darkness, inventory limits, dwarf harassment, pirate theft, magic-word
teleports, hint tracking, endgame countdown, etc.).

## What's currently in this directory

```
frame/aspects.fgd         AspectBus + sample aspects + Conductor demo
generated/aspects.gd      framec output (gitignored)
godot/                    minimal harness (no scene; tests run headless)
```

The `aspects.fgd` file contains a working end-to-end demo of the
pattern:

- **`AspectBus`** — reusable. `$Idle` / `$Dispatching` states, holds
  `(name, priority)` metadata, queues mid-dispatch register/unregister
  calls.
- **`LoudAspect`** — example transform aspect. Has its own `$On`/`$Off`
  internal mode.
- **`MuteAspect`** — example consume aspect. Counts what it muted.
- **`LogAspect`** — example observe aspect. Counts and remembers events.
- **`Conductor`** — orchestrator. Holds the bus + aspects, routes
  `publish(name, data)` through the verdict ladder, falls through to a
  base handler.

The `try_handle(event) -> {verdict, event}` interface is the contract
every aspect implements.

## Running the smoke test

```bash
cd cca
FRAMEC=/path/to/framepiler/target/release/framec ./build.sh
godot --headless --path godot/ --script /tmp/test_aspect_bus.gd
```

Verifies registration, dispatch order, the four verdicts, internal
aspect state changes, and `@@[persist]` round-trip.

## What's next

1. Real CCA aspects (DarknessGate, BackpackLimit, DwarfHarass,
   PirateSkulk, EndgameClosing, MagicWordTeleport, HintTracker,
   ScoreLedger, AutoTimer, …).
2. World composition: Player + Lamp + Bird + Snake + Dragon + Bear +
   Troll + parameterized Dwarf×5 + Treasure×N + Endgame.
3. Parser + room/object/vocabulary data tables (driver-side).
4. Text I/O harness.

See the project memory note `project_aspect_machines.md` for the
architectural decision context.
