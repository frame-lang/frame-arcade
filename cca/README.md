# Colossal Cave Adventure (Frame port)

> **Status:** full canonical scope. **125 rooms with canonical
> Crowther+Woods 1977 numbering**, 15 treasures, 6 NPCs (bird,
> snake, dragon, bear, troll, pirate, plus 5 dwarves), 4 cross-
> cutting aspects on the bus, full CCA scoring breakdown
> (treasure / visits / hints / endgame), rod + crystal-bridge
> fissure puzzle, FEE/FIE/FOE/FOO eggs incantation, fragile
> vase, bear/dwarf player attacks, resurrection cycle with
> permadeath, pirate stash + retrieval, both mazes, Witt's End,
> the Vending Machine Room, and the canonical surface forest
> grid with descent through the slit and grate. Save/restore
> round-trips the entire world. See [EVALUATION.md](./EVALUATION.md)
> for an honest per-system score on Frame's value-add.

Frame port of Crowther/Woods *Colossal Cave Adventure*. Built on
the **aspect machines** pattern — small FSM interceptors on a
priority-ordered bus in front of the world state machine — to
decompose CCA's cross-cutting concerns (darkness, inventory
limits, magic-word teleports, score tracking) cleanly without
the flag-on-the-base-machine smell.

## Playing

```bash
cd cca
FRAMEC=/path/to/framepiler/target/release/framec ./build.sh
godot --path godot/ scenes/main.tscn
```

Type `HELP` once you're in for the verb list. The canonical
solve path:

```
LIGHT
XYZZY              (teleports to debris room)
TAKE GOLD
XYZZY              (back to surface)
NORTH              (well house)
DROP GOLD          (deposits — score!)
SOUTH              (back outside)
PLUGH              (teleports to Y2)
DOWN               (bird chamber)
TAKE BIRD
UP                 (back to Y2)
EAST               (snake passage)
RELEASE BIRD       (snake flees)
EAST               (dragon cavern)
ATTACK DRAGON      (game asks "with what?")
YES                (dragon dies)
TAKE DIAMONDS
NORTH              (bear chamber)
FEED BEAR          (food not actually required in this prototype)
TAKE CHAIN         (bear follows)
EAST               (troll bridge)
DROP CHAIN         (bear scares troll)
EAST               (beyond bridge)
TAKE JEWELRY
... and so on, depositing each treasure back at the well house.
```

`SAVE` and `LOAD` round-trip the entire game state. `SCORE`
shows current treasure-deposit progress.

## What's in this directory

```
frame/aspects.fgd         AspectBus + sample aspects + Conductor demo
                          (smoke-test fixture, not the game)
frame/cca.fgd             real CCA — 20 @@system declarations
generated/                framec output (gitignored)
godot/scripts/driver.gd   text-adventure UI + parser + maze topology
godot/scenes/main.tscn    Godot scene wiring driver to a Control node
EVALUATION.md             honest per-system Frame value-add scoring
```

## Frame system catalog

**Reusable infrastructure**

- `AspectBus` — priority-ordered FSM-interceptor registry
  (`$Idle` / `$Dispatching` for queue-during-dispatch)

**Aspects on the bus** (4 verdict types covered)

- `DarknessGate` (consume) — gates `look`/`examine` in dark rooms
- `BackpackLimit` (consume) — blocks `take` at 7-item carry cap
- `MagicWordTeleport` (transform) — XYZZY/PLUGH/PLOVER → MOVE
- `ScoreLedger` (observe) — counts events; per-rule scoring stub

**World entities** (composed under `Adventure`)

- `Lamp` — `$Off` / `$On.{$Bright/$Dim/$Out}`, battery countdown
- `Player` — `$Alive` / `$Dead` / `$Permadead`, inventory, deaths
- `Bird` — 4 states; release-at-snake or release-at-dragon
- `Snake` — 2 states; bird drives off
- `Bear` — 5 states; feed→tame→follow→release; hazard branch
- `Troll` — 3 states; bridge gate; bear scares
- `Dragon` — multi-turn parser dialog as state
- `Dwarf × 5` — parameterized probabilistic encounter
- `Pirate` — probabilistic threshold-activated encounter
- `Treasure × 15` — parameterized; deposit→endgame chain;
  fragile flag for the vase (`$Broken` shatter state)
- `Endgame` — multi-stage HSM with state-variable timer
- `Hint × 3` — parallel parameterized small FSMs
- `EggsIncantation` — 4-state chant FSM (FEE/FIE/FOE/FOO);
  Adventure observes completion and summons eggs back
- `CrystalBridge` — 2-state toggle FSM gating the fissure;
  `wave()` only fires from Adventure when player has the rod

**Total**: 20 `@@system` declarations, ~3600 lines of Frame
source, ~10000 lines of generated GDScript. Sixteen smoke
test files, ~300 individual checks, all PASS.

## Driver layer

The driver (`godot/scripts/driver.gd`) is one ~730-line file:

- Maze topology (125 rooms with canonical Crowther+Woods 1977
  numbering, named exits, gated passages including snake/troll/
  crystal-bridge gates)
- Verb-noun parser with synonym table + article stripping
- UI verbs (HELP, SCORE, INVENTORY, HINT, SAVE, LOAD, QUIT)
  routed driver-side
- Game verbs routed to `Adventure.do_command(verb, noun)`
- Per-turn upkeep: lamp warnings, endgame phase transitions
  (with closing-warning crescendo), pirate steal events,
  dwarf-axe surfacing, resurrection prompt on player death,
  room re-print on movement

The driver doesn't use Frame — it's deliberately plain GDScript
that bridges the player to the FSM. The "Frame is the brain,
the driver is the body" pattern from every other project
chapter.

## Smoke tests

```bash
# The aspect-bus prototype (toy demo)
godot --headless --path godot/ --script /tmp/test_aspect_bus.gd

# CCA Frame system tests
godot --headless --path godot/ --script /tmp/test_cca_lamp.gd
godot --headless --path godot/ --script /tmp/test_cca_dark.gd
godot --headless --path godot/ --script /tmp/test_cca_aspects.gd
godot --headless --path godot/ --script /tmp/test_cca_score.gd
godot --headless --path godot/ --script /tmp/test_cca_bird_snake.gd
godot --headless --path godot/ --script /tmp/test_cca_bear.gd
godot --headless --path godot/ --script /tmp/test_cca_troll.gd
godot --headless --path godot/ --script /tmp/test_cca_dwarves.gd
godot --headless --path godot/ --script /tmp/test_cca_endgame.gd
godot --headless --path godot/ --script /tmp/test_cca_hints.gd
godot --headless --path godot/ --script /tmp/test_cca_dragon.gd
godot --headless --path godot/ --script /tmp/test_cca_mechanics.gd
godot --headless --path godot/ --script /tmp/test_cca_bridge.gd

# End-to-end playthrough wiring
godot --headless --path godot/ --script /tmp/test_cca_playthrough.gd
godot --headless --path godot/ --script /tmp/test_cca_full.gd
```

The playthrough test exercises the canonical solve path
through `Adventure.do_command`, confirming every verb routes
through the bus + base handler correctly and that mid-game
save/restore preserves NPC states.

## Honest evaluation

See [EVALUATION.md](./EVALUATION.md) for per-system Frame
value scoring (5/5 for Bear/Endgame/Dragon down to 2/5 for
single-state aspects), the comparison to hypothetical plain
GDScript, and the "when to reach for Frame in adventure
games" heuristic.

Bottom line: Frame is a **measured win** for CCA — bigger
than expected mid-build, smaller than for arcade games. The
aspect-bus pattern layered over Frame is the genuine
architectural payoff for IF specifically.
