# CCA-in-Frame: an honest evaluation

**Question:** Does Frame help build CCA, or is it the wrong tool
for adventure-game shape?

**TL;DR:** Frame is **a measured win** for CCA — bigger than I
estimated mid-session, smaller than the arcade chapters. Three
specific Frame features (composition + `@@[persist]`, multi-stage
HSMs, parameterized parallel instances) earn their keep cleanly.
Three other systems (Snake, Troll, Dragon) are small enough that
plain GDScript would have been roughly equivalent. The aspect-bus
pattern *layered over* Frame is where the architectural payoff
actually lands.

This document scores each system honestly so the chapter
prose, when it gets written, can pitch Frame correctly.

---

## What was built

15 commits of CCA work, organized into:

**Reusable infrastructure**
- `AspectBus` — priority-ordered FSM-interceptor registry
- 4 aspects on the bus: `DarknessGate`, `BackpackLimit`,
  `MagicWordTeleport`, `ScoreLedger`
- 4 verdict types exercised: consume, transform, observe, pass

**World entities (composed under `Adventure`)**
- `Lamp` (HSM with battery)
- `Player` (alive/dead/permadead)
- `Bird`, `Snake` (cross-FSM coordination)
- `Bear` (5-state HSM with hazard branch)
- `Troll` (3-state, bear-scared cross-FSM)
- `Dwarf` × 5 (parameterized × N with deterministic PRNG)
- `Endgame` (multi-stage HSM with timer)
- `Hint` × 3 (parallel parameterized small FSMs)
- `Dragon` (multi-turn parser dialog as state)

**Total Frame source:** ~2150 lines including comments
**Generated GDScript:** ~7000 lines
**Smoke tests:** 8 files, ~200 checks across them, all PASS

---

## Per-system Frame value scoring

Five-point scale where:

- **5** = Frame transformatively helps; plain GDScript would
        be much worse
- **4** = Frame is a clear win
- **3** = Frame is a wash (about equivalent to plain GDScript)
- **2** = Frame is mild ceremony for marginal benefit
- **1** = Frame is pure ceremony; plain GDScript would be
        smaller and clearer

| System | Score | Why |
|---|---|---|
| `AspectBus` | **4** | $Idle/$Dispatching encodes queue-during-dispatch correctly. The two-state semantic is real; the alternative (a `_dispatching: bool` flag with conditional logic) is the same complexity but hides intent. |
| `Lamp` | **4** | HSM with parent `$On` and three children ($Bright/$Dim/$Out) plus threshold transitions and battery countdown. `is_lit()` and `last_warning` overrides per child are exactly the HSM-inheritance idiom. |
| `Player` | **3** | Three states with simple transitions. Plain GDScript with an enum + a few methods would be ~30 lines vs Frame's 100+. The death-cycle is legible either way. |
| `Bird` | **3** | Four states; the room-dependent transition logic is interesting but small. The save/restore round-trip on $Caged with location=-1 is a real win. |
| `Snake` | **2** | Two states. Morally a boolean. Frame ceremony for ~50 generated GDScript lines. |
| `Bear` | **5** | Five states with a branching hazard ($Hungry × take_chain → $Attacking) and a linear progression that's exactly what state machines are for. The "feed before unchaining" rule is encoded as state and is impossible to forget. |
| `Troll` | **2** | Three states but mostly boolean ("blocking? yes/no/no-because-paid"). Frame doesn't earn much. |
| `Dwarf` × 5 | **4** | Parameterized-with-multiple-instances is a real Frame feature. Per-dwarf seed for deterministic PRNG round-trips through `@@[persist]` cleanly. The if-ladder in `_dispatch_to` is the only blemish. |
| `Endgame` | **5** | Four-state phase machine with a state-variable timer that survives `@@[persist]`. The `$.timer` round-trip on save/restore-mid-$Closing is the headline persistence test in CCA. Hardest to express well in plain GDScript. |
| `Hint` × 3 | **4** | Parallel parameterized small FSMs. Each hint advances independently; observe(true)/observe(false) streak-and-reset is a clean shape; per-hint state survives serialization without thinking about it. |
| `Dragon` | **4** | Multi-turn parser dialog as state. $Asked encodes "we're mid-question." The alternative — a boolean "awaiting_yes_no" flag — works but is the same flag-on-base smell that motivated the aspect bus pattern. |
| `DarknessGate` | **2** | Single state; Frame is ceremony around a function with a counter. |
| `BackpackLimit` | **3** | Single state but with non-trivial counter state, and the consume-verdict pattern is enabled by being on the bus. The bus is what earns its keep here, not the FSM. |
| `MagicWordTeleport` | **3** | Single state; the room-pair table makes it a legitimate small system, but the FSM scaffolding doesn't help. |
| `ScoreLedger` | **2** | Single state. Telemetry counter dressed as a state machine. |

**Distribution:** 3 systems at 5/5, 4 at 4/5, 5 at 3/5, 4 at 2/5,
0 at 1/5.

The mode is 3 (wash) — Frame neither hurts nor helps for the
median CCA system. The peak is 5 (Bear, Endgame) where the
state semantics are doing real load-bearing work.

---

## What Frame demonstrably did well

### 1. `@@[persist]` across composition is a real win

`Adventure.save_state()` round-trips the entire world tree
(Adventure + Lamp + Player + Bird + Snake + Bear + Troll +
Dwarf×5 + Endgame + Hint×3 + Dragon + AspectBus + 4 aspects)
in **one call**. Hand-rolling that would be ~200 lines of
serialization boilerplate distributed across the systems.

The framepiler dev build's `@@[persist]` codegen is genuinely
production-quality once Issues #1 and #2 (documented in
`FRAMEC_BUGS.md`) were fixed.

### 2. State variables surviving push$/pop$ AND save/restore

The Endgame's `$.timer` and the Bird's pushed-compartment
behavior demonstrated that Frame's state-stack semantics
**compose with persistence**. A saved game in mid-$Closing
restores into the same state with the same timer value — and
the bird-released-then-saved test path verified that pushed
compartments under Adventure's $Playing also round-trip.

This is the single most expensive thing to engineer correctly
by hand and Frame ships it.

### 3. The aspect-bus pattern over Frame

The four-verdict bus (consume / transform / observe / pass) is
a Frame *application* — not a Frame feature, but cleanly
expressible with Frame primitives. It decomposed CCA's cross-
cutting concerns (darkness, inventory limit, magic words,
scoring) cleanly. The bus + aspects together are ~250 lines
of Frame; the alternative would be `if`-ladders woven through
Adventure's verb dispatch and would have grown sprawly fast.

### 4. Cross-FSM coordination through the orchestrator

Bird → Snake (release-bird-kills-snake) and Bear → Troll
(release-bear-scares-troll) are both expressed as: each NPC
owns its state transitions; Adventure observes and reaches
across to call dependent NPCs. This pattern is not unique to
Frame, but Frame's composition (named domain fields with
auto-traversal) made the orchestrator feel natural rather than
bookkeeping-heavy.

---

## What Frame demonstrably *didn't* help with

### 1. Single-state aspects

DarknessGate, MagicWordTeleport, ScoreLedger are each a
single state with a single method. The `@@system` /
`machine:` / `$Active { ... }` envelope adds ~30 lines
of generated dispatch code per aspect for zero semantic value.
A plain GDScript class with one `try_handle()` method would
be 15 lines instead of 50.

The bus *itself* benefits from being an FSM ($Idle/$Dispatching).
The aspects on it mostly don't.

### 2. NPCs with 2-3 trivial states

Snake (2 states), Troll (3 states with mostly boolean queries)
do not benefit meaningfully from Frame. The save-restore
integration is nice but minor. An enum + a few functions
would have been roughly equivalent.

### 3. Adventure's verb dispatch and orchestration code

The `do_command` body is procedural GDScript-flavored Frame:
a while loop walking aspects, branches per verdict, an
if-ladder routing names to systems. Wrapping it in
`$Playing { do_command { ... } }` adds zero clarity. The
algorithm is the same procedural code you'd write outside
Frame. The state-machine envelope around it is dead ceremony.

### 4. Generated code bloat

The `cca.gd` output is ~7000 lines of GDScript for ~1500
lines of hand-written Frame source. The ratio is ~4.7×. Most
of that is dispatcher + compartment + serialization
machinery. For runtime debuggability, you read generated
code; for source-of-truth, you read Frame. The two-language
shadow is real overhead.

---

## Comparison: hypothetical CCA in plain GDScript

What would the same architecture look like without Frame?

**Adventure**: a GDScript class with a `do_command(verb, noun)
-> String` method, a list of `aspect` interceptors (plain
classes implementing `try_handle`), and the same `_verb_look`
/ `_verb_take` / etc. helper methods. Procedural orchestration
code is identical.

**Aspects**: each is `class XAspect: func try_handle(e):
return {...}`. ~15 lines each instead of ~50 in Frame. **4× LOC win.**

**NPCs (Lamp / Player / Bird / Snake / Bear / Troll / Dragon)**:
each is a class with an enum state, methods that switch on
state, and per-class `to_dict()` / `from_dict()` save methods.
Roughly the same total LOC as the Frame versions but with
hand-rolled persistence (~15 lines per class × 8 systems =
**~120 lines of save boilerplate** that Frame eliminates).

**Dwarf × 5**: 5 instances of the same class. Plain GDScript
handles this trivially. The `@@[persist]` auto-traversal of
named domain fields is replaced by a `for d in [d1,d2,d3,d4,d5]:
d.from_dict(...)` loop in `from_dict` — ~10 lines of save
boilerplate. **Modest Frame win.**

**Endgame**: a state-machine-shaped class. With an enum and
a `match self.state` in `tick()`, this is ~80 lines of plain
GDScript, vs Frame's ~120 lines of source. **Wash.** The
state semantics are equally clear in either notation; Frame's
$.timer-survives-push is the differentiator if you save/load
mid-$Closing, which costs ~10 lines to hand-roll.

**Hint × 3**: 3 instances of a small class. Same as Dwarves:
plain GDScript handles this fine; Frame's persistence saves
~30 lines of save boilerplate across the three.

**Bear**: a 5-state machine with a branching hazard. Frame's
`$Hungry { feed: -> $Tame; take_chain: -> $Attacking }` is
genuinely clearer than `match state: HUNGRY: if action == "feed":
state = TAME ...`. **Frame win.**

**Net hand-rolled estimate:** ~1200 lines of plain GDScript
for the same architecture. Frame ships ~1500 lines of source
to express the same thing, but eliminates ~150-200 lines of
serialization boilerplate that the GDScript version would
need. **Roughly a wash on lines of code, with Frame being
clearer in 5-6 hot spots and equivalent or worse in 8-9.**

The framec maturity costs (Issues #1 and #2 hit during this
session, the framepiler-dev-build requirement) are real but
small now that they're documented.

---

## When to use Frame for adventure games

**Reach for Frame when:**

- Your game has multi-stage timed phases (Endgame).
- You have NPCs with 4+ meaningful states and branching
  transitions (Bear).
- You have many parameterized instances of the same system
  (Dwarves × 5, Hints × 3).
- You need save/restore across composition.
- You have multi-turn parser dialogs whose context spans
  commands (Dragon's $Asked).

**Don't reach for Frame when:**

- The system has 1-2 states. Use a boolean.
- The system is a single function with a counter. Use a class.
- The system's only meaningful behavior is data lookup.
  Use a Dictionary.

This is a 60/40 split for CCA, leaning slightly Frame-positive.
For arcade games (Stealth, Asteroids, Pac-Man), the same
heuristic puts ~80% of the systems on the Frame side. CCA is
genuinely a less Frame-shaped genre, but not unfit.

---

## What's still left of CCA (post-evaluation)

Per the original roadmap, what remains:

- **Pirate** (probabilistic encounter, similar to Dwarves) —
  small, ~30 min, would score 3/5 on the Frame value scale.
  Skipping because it doesn't move the architecture story.
- **Treasures × 15** (parameterized data) — large but mostly
  data table. Frame would be a thin wrapper. Score 2/5.
- **Maze data tables** — driver-side data, not Frame.
- **Parser** — algorithm, not Frame.
- **Driver/text I/O harness** — Godot scene + console-style
  text widget, not Frame.

The remaining work is "wire CCA into something actually
playable" — substantial, but no further Frame
demonstration value.

## Recommendation

**Stop adding Frame systems to CCA.** The architecture is
proven, every composition pattern has been exercised, the
evaluation above is the truth-in-advertising about what Frame
gave us. Article-writing material (the user's stated reason
for this project) is in good shape.

**If shipping CCA is the goal**: the next ~4 hours of work is
the parser + maze data + driver wiring, mostly non-Frame.
That's a separate evaluation from this one.

**If the goal is the chapter on Frame for adventure games**:
the chapter writes itself from this document, the smoke tests,
and the existing in-file comments.
