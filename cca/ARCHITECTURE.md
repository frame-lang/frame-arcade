# CCA — architecture and testing

This document describes how the Frame-Arcade port of *Colossal Cave
Adventure* is structured, how every test exercises some slice of it,
and how to find the canonical truth for any room or mechanic.

The companion file [`CANON_LOCATIONS.md`](CANON_LOCATIONS.md) is the
authoritative per-room reference — every canon location 1..140 with
its travel-table rows decoded against
[`canon/advent.for`](canon/advent.for) (the original PDP-10
FORTRAN-IV interpreter).

The credit for *Colossal Cave Adventure* belongs to **Will Crowther
and Don Woods, 1976-77**. This port re-implements their game in
Frame state machines on top of Godot — every gameplay decision is
either traced to the canon or explicitly documented as a port-local
choice.

---

## 1. Source-code layout

```
cca/
├── ARCHITECTURE.md         ← this file
├── CANON_DELTAS.md         ← inventory of port-vs-canon differences
├── CANON_LOCATIONS.md      ← auto-generated per-room canon reference
├── EVALUATION.md           ← session-by-session evaluation notes
├── MODEL_CHECKING.md       ← Frame-side model-checking notes
├── README.md               ← quick start
├── TODO.md                 ← short-list of pending non-canon work
├── build.sh                ← framec compile pipeline (Frame → GDScript)
├── run_tests.sh            ← headless Godot test runner
│
├── canon/                  ← 1977 Crowther/Woods canon, public domain
│   ├── advent.dat          ← canonical 1808-line data file
│   ├── advent.for          ← canonical PDP-10 FORTRAN-IV interpreter
│   ├── advent.mic          ← TOPS-20 build script
│   ├── advent.readme       ← Don Woods' release notes
│   ├── README.md           ← provenance + credits
│   ├── gen_locations.py    ← regenerates CANON_LOCATIONS.md
│   ├── rooms.txt           ← extracted: room id → first-line desc
│   ├── objects.txt         ← extracted: object id → name
│   ├── score_tiers.txt     ← extracted: 9 score-rating tiers
│   └── hints.txt           ← extracted: 6 canon hints
│
├── frame/                  ← Frame source (.fgd, hand-authored)
│   ├── aspects.fgd         ← AspectBus prototype + minimal demo
│   └── cca.fgd             ← every CCA system (~5K lines)
│
├── generated/              ← framec output (gitignored)
│   ├── aspects.gd
│   └── cca.gd
│
├── godot/                  ← Godot 4 project
│   ├── project.godot
│   ├── scenes/             ← .tscn UI scenes (one per dialog)
│   └── scripts/
│       ├── aspects.gd      ← copied from generated/ (gitignored)
│       ├── cca.gd          ← copied from generated/ (gitignored)
│       ├── topology.gd     ← maze data: ROOMS dict + GATES dict
│       ├── monkey.gd       ← random-walk fuzzer for the FSM
│       └── driver.gd       ← UI + parser + cross-FSM choreography
│
└── tests/                  ← 30 SceneTree-based smoke tests
```

---

## 2. The Frame state-machine layer (`frame/cca.fgd`)

CCA is a state-machine-heavy game. Everything that has memorable
state across player turns is modelled as a Frame `@@system`:

| FSM                | States                                         | Owns                                |
|--------------------|------------------------------------------------|-------------------------------------|
| `Adventure`        | `$Playing` → `$InRepository` → `$Won`/`$Lost` | The orchestrator: room, score, all the cross-FSM choreography. |
| `Player`           | `$Alive` → `$Dead` → ... → `$Permadead`        | Player room, inventory, deaths.     |
| `Lamp`             | `$Off` → `$On` → `$Dim` → `$Dead`              | Battery countdown.                  |
| `Bird`             | `$Free` → `$Caged` → `$Released` → `$Dead`     | Bird location + capture state.      |
| `Snake`            | `$Blocking` → `$Gone`                          | Whether the canyon exits at 19 are open. |
| `Bear`             | `$Hungry` → `$Tame` → `$Following` → `$Released` / `$Attacking` | Bear's behaviour at canon 130/117. |
| `Troll`            | `$Demanding` → `$TollPaid` → `$Vanished`       | Whether the bridge crossing is open. |
| `Plant`            | `$Tiny` → `$Tall` → `$Huge`                    | Beanstalk growth.                   |
| `Dragon`           | `$Alive` → `$Dead`                             | Dragon + rug under it.              |
| `Grate`            | `$Locked` → `$Unlocked`                        | Cave-entry grate at canon 8.        |
| `RustyDoor`        | `$Rusty` → `$Oiled`                            | Treasury access at canon 94.        |
| `CrystalBridge`    | `$NotBuilt` → `$Built`                         | Fissure crossing 17 ↔ 27.           |
| `EggsIncantation`  | `$Idle` → `$Fee` → `$Fie` → `$Foe` → `$Foo`   | The four-word recall sequence.      |
| `MagicWordTeleport`| (aspect, not @@system)                         | XYZZY/PLUGH/PLOVER verb interception.|
| `DarknessGate`     | (aspect)                                       | Look/examine consumed in dark rooms. |
| `Pirate`           | `$Hidden` → `$Stalking` → `$Stolen`            | Random-encounter timing + chest spawn. |
| `Dwarf` × 5        | `$Hidden` → `$Stalking` → `$Slain`             | Five identical instances, different seeds. |
| `Bottle`           | `$Empty` → `$Water` / `$Oil`                   | Liquid contents (separate from carry-state). |
| `Treasure` × 15    | `$InRoom` → `$Carried` → `$Deposited` / `$Vanished` / `$Broken` | One parameterized FSM per treasure. |
| `Item` × ~12       | `$InRoom` → `$Carried` → `$Consumed`           | Generic carryables (rod, keys, food, pillow, ...). |
| `Hints`            | `$Idle` → `$Eligible` → `$Asked`               | Six canon hints with turn-threshold + cost. |
| `EndgameTimer`     | timer → `$Closing` → `$Closed`                 | Cave-closing teleport sequence.     |

### 2.1 Aspects (cross-cutting interceptors)

Two aspects sit on a bus that wraps every `do_command`. The bus
gives an aspect a chance to consume or transform a verb before it
reaches Adventure's base handler:

- **`DarknessGate`** consumes `look` / `examine` in dark rooms with
  the canon "It is pitch dark. You can't see a thing." prose.
- **`MagicWordTeleport`** intercepts `xyzzy` / `plugh` / `plover`,
  rewrites the verb to `move` with a destination room id baked in
  by the aspect (so the FSM never sees the magic word — it sees
  the resulting move).

Aspects deliberately don't reach into FSM state. Their pre-condition
is a single domain query (`room_is_dark`, `room_eligible_for_xyzzy`)
exposed by Adventure. This keeps the bus dispatch composable —
adding a new aspect doesn't require teaching the verb dispatcher
about it.

### 2.2 Cross-FSM choreography

The `Adventure` orchestrator brokers the cross-cutting work that
doesn't fit cleanly inside a single FSM:

- `_verb_pour` at canon 25 calls `plant.water()`; at canon 94 calls
  `rusty_door.oil()`.
- `_verb_break` at the Shell Room calls `clam.consume()` and
  `oyster.place(here)` and spawns the pearl.
- Bear-and-chain release at canon 117 transitions the troll to
  `$Vanished` via `bear.release()` followed by `troll.scared_off()`.
- The pirate's first steal moves the chest to canon 18.

The pattern: each system owns its own slice (FSM stays small and
testable in isolation), and `Adventure` is the only place where two
slices touch.

### 2.3 Persistence (`@@[persist]`)

Every `@@system` in `cca.fgd` carries
`@@[persist(PackedByteArray)] @@[save(save_state)] @@[load(restore_state)]`
header annotations (RFC-0015 syntax, May 2026). framec generates a
serialiser for the entire compartment chain — the current state
plus any pushed parents — and `Adventure.save_state()` is just a
top-level dispatch that round-trips every owned FSM.

The canonical test [`test_cca_canonical.gd`](tests/test_cca_canonical.gd)
exploits this: it runs each stage from a checkpoint by calling
`adv.restore_state(bytes)` at the start, so a 52-stage playthrough
doesn't have to re-walk the cave from `init` for every assertion.

---

## 3. Topology and gates (`godot/scripts/topology.gd`)

The maze is data, not Frame state — a 140-entry `ROOMS` dictionary
keyed by canonical room id, each value being a dict of
`direction → destination_room_id`:

```gdscript
const ROOMS: Dictionary = {
    1: {"hill": 2, "north": 5, "south": 4, "east": 3, ... },
    ...
    140: {"north": 112, "out": 112},
}
```

Every room and every direction-to-destination pair has been verified
against [`canon/advent.dat`](canon/advent.dat) section 3 — see the
per-room reference at [`CANON_LOCATIONS.md`](CANON_LOCATIONS.md).

### 3.1 The `GATES` dict — conditional motions

Plain ROOMS entries are unconditional. Conditional motions (snake
blocks the canyon exits, troll bars the bridge, fissure too wide
without bridge, grate locked, etc.) live in `GATES`:

```gdscript
const GATES: Dictionary = {
    "8:down":      {"check": "grate",     "msg": "The grate is locked..."},
    "19:north":    {"check": "snake",     "msg": "The snake glares..."},
    "117:over":    {"check": "troll",     "msg": "The troll bars..."},
    "94:north":    {"check": "rusty",     "msg": "The door is extremely rusty..."},
    "17:over":     {"check": "bridge",    "msg": "The fissure is too wide..."},
    "25:climb":    {"check": "plant_huge","msg": "The plant is too feeble..."},
    "100:west":    {"check": "plover_squeeze", "msg": "..."},
    "17:jump":     {"check": "always",    "msg": "The fissure is too wide."},
    ...
}
```

The `check` field is a string that the driver knows about. Each
`check` value resolves to a method on `Adventure`:
`snake.is_blocking()`, `troll.is_blocking_bridge()`, `bridge_built()`,
`grate_locked()`, `plant_is_tall()`, `plant_is_huge()`,
`plover_squeeze_blocked()`, `rusty_door_oiled()`. The `always` check
is a port-side bumper (canon prose for verbs that hit no exit).

### 3.2 Why two dicts and not one

ROOMS is the unconditional-motion truth. GATES is the
conditional-motion truth. The split is deliberate: the per-room
canon audit (`tests/test_cca_topology.gd`) checks every ROOMS entry
against `advent.dat` section 3's plain rows; the conditional dashboard
(`tests/test_cca_conditional.gd`) checks the special-handler rows
(those with `M ≥ 1` per the `Y = M*1000 + N` encoding) against GATES.
A single dict would force every audit to thread the condition logic
through itself.

---

## 4. The driver (`godot/scripts/driver.gd`)

The driver is the only file with a UI dependency. It hosts the
RichTextLabel scrolling log + LineEdit input, and bridges typed
commands to Frame events:

```
Player types into LineEdit
    ↓
_process_input(text)
    ↓ parse to (verb, noun)
    ↓ resolve direction → room id (via Topology.ROOMS / GATES)
    ↓ handle UI verbs (inventory, score, save, load, hint, quit)
    ↓ otherwise:
fsm.do_command(verb, noun)        ← FSM side
    returns String response (driver prints)
    ↓
fsm.tick()                        ← FSM side
    advances lamp battery, endgame timer, hint observation,
    pirate threshold, ...
    ↓ render:
_print_room()
    ↓ check post-turn consequences:
_check_pirate_steal(); _check_lamp_warnings(); _check_player_death();
_check_endgame_phase_change();
```

The driver also implements a few interactive-only mechanics that
don't belong in the pure FSM:

- **Bumper-key dispatch** — for non-direction motion verbs (JUMP,
  SLIT, STREAM, FORWARD, PIT, DOME, ...) it consults `GATES` to
  emit the canon bumper prose without going through the FSM.
- **Dark-room pit-fall hazard** — Crowther/Woods canon's "warn on
  first attempt, 35% chance of pit-fall on subsequent attempts."
  Tracks `_dark_warned_room` per session.
- **Resurrection prompt** — the only place that converts `yes`/`no`
  into `player.revive()` after death.
- **Save / load** — UI verbs that round-trip Adventure's state.

### 4.1 Arcade build mirror

The arcade-bundled cabinet (`arcade/godot/scripts/cca_main.gd`) is
a self-contained mirror of `topology.gd` + `driver.gd` for the
itch.io distribution. Anything that lands in the `cca/` driver
gets synced to the arcade mirror — the two stay byte-for-byte
equivalent on the topology, GATES, and dispatch logic.

---

## 5. Testing

Every test is a headless `SceneTree` script that prints
`PASS — ...` or `FAIL — ...` and exits with the failure count.
[`run_tests.sh`](run_tests.sh) iterates every `tests/test_cca_*.gd`,
collects failure counts, and exits non-zero if anything fails.

### 5.1 The four dashboards

These are *informational* dashboards — they always exit 0 but
print metrics that surface deviations:

| Dashboard                       | What it tracks                                                                          |
|---------------------------------|-----------------------------------------------------------------------------------------|
| `test_cca_canon.gd`             | 50 architectural probes — treasure homes, NPC rooms, magic-word pairs, mechanism probes (every NPC FSM, every cross-FSM choreography point). Currently 49/50; the open delta is the port-only Witt's End walking corridor. |
| `test_cca_topology.gd`          | Per-room conformance against `advent.dat` section 3 plain rows. 140/140 rooms aligned with 0 deltas. |
| `test_cca_conditional.gd`       | Coverage of canon section 3 *special-handler* rows (those with `M ≥ 1`). 33/62 total covered (4/4 bumper, 10/13 msg500, 19/45 cond). |
| `test_cca_monkey.gd`            | Random-walk fuzzer. 10000 commands, fixed seed (42). Reports rooms visited, fingerprints, moves, soft-locks. Thresholds: ≥18 rooms, ≥50 fps, ≥1000 moves, 0 soft-locks. |

### 5.2 The canonical playthrough — `test_cca_canonical.gd`

The "if this passes, the game works" test. 52 stages, every
navigation a real `do_command("move", str(dest))` (no setter
teleports). Stages chain through `@@[persist]` checkpoints, so each
stage starts from the previous stage's saved state without
re-walking the cave.

The DAG is:
```
init_outside_road → in_well_house → keys_and_bottle_taken →
lamp_lit → outside_grate → grate_unlocked → below_grate →
cobbles_with_cage → debris_room → rod_taken →
gold_taken_back_at_y2 → at_y2 → bird_chamber →
bird_taken_drop_rod_first → at_snake_passage → snake_cleared →
at_dragon → dragon_killed → rug_taken →
diamonds_taken_at_west_bank → deposit_first_haul →
take_silver → deposit_silver → take_pearl_emerald →
deposit_pearl_emerald → plant_watered_to_huge →
eggs_taken_at_giant → at_bear_chamber → bear_tame_chained →
troll_vanished → eggs_recalled_after_toll →
take_jewelry → deposit_jewelry → pillow_to_well_house →
deep_cave_batch_a_takes → deposit_batch_a →
deep_cave_batch_b_takes → deposit_batch_b →
deep_cave_batch_c_takes → deposit_batch_c → in_repository → won
```

Plus eight branch-test stages (dragon-decline, vase-shatter,
bear-maul, resurrection cycle, eggs-summon-back, plant-tall,
dwarves-woken).

### 5.3 Per-system unit tests

Each NPC and puzzle system has its own focused test:

| Test                        | Scope                                                                  |
|-----------------------------|------------------------------------------------------------------------|
| `test_cca_aspects`          | AspectBus dispatch + DarknessGate consume.                            |
| `test_cca_bear`             | Hungry → Tame → Following → Released chain + bear maul.              |
| `test_cca_bird_snake`       | Bird capture, snake-clear via release.                                |
| `test_cca_bridge`           | Wave rod → CrystalBridge.is_built → cross.                            |
| `test_cca_clam_squeeze`     | 103:south refuses with msg #118/#119 carrying CLAM/OYSTER.            |
| `test_cca_dark`             | DarknessGate aspect consume counter + save/restore.                   |
| `test_cca_dark_pit_fall`    | Driver-level pit-fall — five phases including the per-room marker.    |
| `test_cca_death_rooms`      | Routes to canon 20/21 fire `player.die()` with canon prose.           |
| `test_cca_dragon`           | Attack-yes / attack-no / dragon-cancel.                                |
| `test_cca_dwarves`          | Wake threshold, axe throw, dwarf kill.                                |
| `test_cca_endgame`          | Closing → Repository teleport → Won.                                   |
| `test_cca_fragile_vase`     | Drop on pillow vs anywhere else.                                       |
| `test_cca_full`             | Full canon win path (uses `move_to` setters — fast variant of canonical). |
| `test_cca_grate`            | Lock/unlock with keys.                                                 |
| `test_cca_hints`            | Six canon hints, threshold + cost.                                    |
| `test_cca_lamp`             | Battery countdown, vending-batteries refresh, dim warning.            |
| `test_cca_mechanics`        | Combined verb-dispatch and cross-FSM mechanics.                       |
| `test_cca_pirate`           | Stalk threshold, steal, chest spawn at canon 18.                      |
| `test_cca_plant`            | Bottle + plant FSM cross-machinery.                                   |
| `test_cca_playthrough`      | Driver-layer wiring (verb/noun → FSM event).                          |
| `test_cca_rusty_door`       | Pour oil at 94 transitions Rusty → Oiled with msg #114.               |
| `test_cca_score`            | Treasure values + endgame tier ladder.                                 |
| `test_cca_state_exploration`| Frame state-explorer reachability check (catches dead states).         |
| `test_cca_troll`            | Throw-treasure, bear-scare, troll-vanished.                            |
| `test_cca_vending`          | Insert coins → batteries.                                              |

### 5.4 Captured-driver pattern

The driver-only mechanics (dark-pit-fall, bumper-key dispatch) need
a Driver instance to test. Since `Driver extends Control`, it can't
be instantiated headless without UI. The pattern in
`test_cca_dark_pit_fall.gd`:

1. Subclass `Driver` with a captured-output `_println`.
2. Inject a fresh `Cca.new()` as the FSM.
3. Call the driver's helper directly (`d._check_dark_pit_hazard()`)
   and assert against the captured buffer.

This keeps the driver's logic testable without bringing the
SceneTree up.

---

## 6. The build pipeline

```
frame/aspects.fgd  ─┐
frame/cca.fgd       ─┼─→  framec compile  ─→  generated/*.gd  ─→  godot/scripts/*.gd
                                                                    (gitignored)
```

Run `./build.sh` — it compiles every `.fgd` to GDScript via
`framec compile --language gdscript`, then copies the result into
the Godot project's scripts directory.

The generated `.gd` files are gitignored: the `.fgd` is the source
of truth, and committing the generated form would invite hand-edits
that drift from the spec.

framec is at `~/.cargo/bin/framec` (4.0.0); set `FRAMEC=...` to
override.

---

## 7. Where canonical answers live

When a question comes up about "what does CCA do at room X?" or
"what triggers Y?", the order of authority is:

1. **`canon/advent.for`** — the original FORTRAN interpreter. Every
   data-encoding rule and every special-routine behaviour is
   defined here in canonical comments + code. *This is the primary
   source.*
2. **`canon/advent.dat`** — the canonical data file. Every room,
   exit, message, object, score tier, hint.
3. **[`CANON_LOCATIONS.md`](CANON_LOCATIONS.md)** — auto-generated
   per-room reference. Decodes every section-3 row using the spec
   from `advent.for`.
4. **[`CANON_DELTAS.md`](CANON_DELTAS.md)** — what the port does
   differently and why. The "intentional divergence" log.

Modern C ports like Quuxplusone/Advent are *useful* but
*derivative* — Don Woods himself signed off on Quux but it's a
hand-translation. Cross-reference but don't trust as primary.

---

## 8. Per-location canonical reference

See [`CANON_LOCATIONS.md`](CANON_LOCATIONS.md) — 140 rooms, every
canon section-3 row decoded, every entry point listed, every
object/NPC placement noted, and the port's `topology.gd` /
`GATES` status alongside.

To regenerate after a topology change:

```sh
cd cca
python3 canon/gen_locations.py > CANON_LOCATIONS.md
```
