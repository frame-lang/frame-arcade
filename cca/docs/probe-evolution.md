# Probe Evolution: Building a Coverage-Testing Stack for CCA

A journey log of how the `probe.gd` / `world_graph.gd` testing
infrastructure came together. This document captures what we
tried, what failed, and how each dead end shaped the next attempt.
It's both a project-internal record and source material for an
eventual writeup positioning Frame as the substrate that makes
this kind of testing tractable.

The current state is summarised at the end. The middle is the
interesting part — the sequence of "this didn't work, here's why,
here's what we tried next."

---

## The starting gap

The pre-probe CCA test suite (see [TESTING.md](TESTING.md)) was
three layers:

- **Layer 1** — ~60 FSM-direct unit tests, each driving a specific
  mechanic from a teleported start state.
- **Layer 2** — One canonical-journey test, walking the happy path
  end-to-end through the real Driver.
- **Layer 3** — Drift/structural checks (topology audit,
  pre-commit drift detector).

Together they answered "do specific mechanics work?" and "does the
canonical happy path still reach victory?" Both yes.

What no layer answered:

- Is there *any* sequence of player commands from any reachable
  state that leaves the game inconsistent?
- Do verb-dispatch paths work for combinations no test hand-wrote
  (e.g. `wave food`, `attack chest`, `examine bird`)?
- When we say "67 tests pass," what does *coverage* actually mean?
  Mechanic-by-mechanic? Or just the specific scenarios we thought
  to test?

The literature term for what we lacked is *state-space coverage* —
the model-checking sense, not the line-coverage sense. We had
strong **scenario** coverage but no measure of how much of the
reachable behavior space the tests actually exercised.

---

## Attempt 1: deterministic BFS over the state space

**Filed as RFC-0001 ([docs/rfcs/rfc-0001.md](rfcs/rfc-0001.md)).**

The idea: use `Adventure.save_state()` / `restore_state()` (the
Frame `@@[persist]` infrastructure) to do exhaustive BFS over the
reachable state graph. At each node, snapshot the FSM, try every
action, assert invariants, record any divergence.

**Implementation:** `cca/godot/scripts/state_space.gd` plus
`cca/tests/test_cca_state_space.gd` running three "sweeps" from
different start states (canonical surface; well-house with starter
items; debris room with rod).

**What worked:**

- The save/restore round-trip held everywhere — no divergence
  between "save then immediately restore" and "the original
  state" across 836 visited states.
- It surfaced a real bug: **player-death didn't drop inventory
  items.** The Player FSM transitioned to `$Dead` but the
  individual item FSMs (keys, lamp, food, etc.) stayed in
  `$Carried`. Two views disagreed: `player.carrying(KEYS_ID)`
  was false while `keys_item.is_carried()` was true. The fix
  was a `_drop_inventory_at_death_room` helper that iterates
  the inventory and calls `try_drop()` on each.

**What didn't scale:**

The BFS only covered ~836 distinct states across all three sweeps
combined. The full reachable space is much larger — projected
5,600–100,000 nodes per the RFC's estimate. To actually run the
full search would take hours of CPU.

More importantly, **BFS finds the wrong kind of coverage for our
goal.** It guarantees "every reachable state was visited at least
once" — which is too strong. What we actually wanted was "every
(room, action) pair was exercised at least once," which is a
coverage problem, not a reachability one. BFS gives us both, but
spends most of its budget enumerating state combinations that are
equivalent for coverage purposes (two different inventory
orderings, same room, same action → BFS sees two nodes; coverage
sees one entry).

The BFS work isn't wasted — it's still in-tree, runs in the test
suite, asserts invariants — but it stopped being the headline
strategy at this point.

---

## Attempt 2: introspection + count-based exploration (the LFU walker)

The user proposed: *"Can we add introspection so the room is
queryable for what can be done there, and have a prober that
queries and tries things, logging counts per location and action,
and randomly choosing from actions that are tied at being the
lowest-actuated?"*

That's a textbook description of **count-based exploration**
(Bellemare et al., *Unifying Count-Based Exploration and
Intrinsic Motivation*, NeurIPS 2016). The user independently
re-derived a real and well-cited idea.

**Implementation:**

1. Added `list_actions_here()` to `driver.gd`. The method
   enumerates currently-plausible (verb, noun) combos by querying
   the live FSM: every room exit, every visible item's `take`,
   every carried item's `drop`, plus state-changing verbs whose
   preconditions are met (light lamp if carrying it, unlock grate
   if at room 8 with keys, etc.).
2. Wrote `cca/godot/scripts/probe.gd` — a walker that asks the
   Driver "what can the player do here?", picks the action with
   the lowest accumulated count at that room (random tiebreak),
   feeds it through `Driver._process_input` exactly as a player's
   keyboard input would, and increments the counter.
3. Walks terminate on permadeath, victory, or step cap.
4. Auto-revive on death so a single death doesn't end a walk.

**What worked immediately:**

The probe found a real bug on its first non-trivial run: a
`SCRIPT ERROR: Invalid call. Nonexistent function 'is_carried' in
base 'RefCounted (Treasure)'`. The death-drop helper from
Attempt 1 was calling `is_carried()` on both `_item` FSMs and
Treasure FSMs, but Treasure exposes `get_state() == "carried"`
instead — the two FSM families had taken slightly different
shapes during the V1.2 split. Fixed in one line.

**What broke down: the forest-cycling problem.**

After 50 walks the report looked like:

```
   685 × 5:move:east
   685 × 5:move:west
   685 × 5:move:south
   685 × 5:move:down
   685 × 5:look
   670 × 5:drop:axe
```

Room 5 (the forest) has 7 movement exits, most of which loop back
to room 5. The walker kept returning, the in-room counts kept
incrementing in lockstep, and the LFU "tiebreak random among
minimums" picked from the same saturated set every visit. Rooms
that needed item prerequisites (keys → grate → cave) never got
reached because the walker never accumulated the prerequisites in
the right order.

This is the classic failure mode of count-based exploration on
hard-exploration domains. The literature calls it "local LFU
starvation" — the bonus for under-visited actions only
differentiates *within the current state*, so the agent never
preferentially leaves a saturated region.

---

## What the literature recommends (and where we landed)

Four families of fixes exist for this failure mode:

1. **UCB1-style bonuses** (Auer 2002) — replace pure min-count
   selection with a softer `√(ln N(s) / n(s,a))` term. Long-ignored
   actions eventually win.
2. **Curiosity / RND** (Pathak 2017, Burda 2019) — reward states
   where a learned model has high prediction error. Overkill for
   discrete state spaces.
3. **Archive + return** (Ecoffet 2019, *Go-Explore*) — save
   promising states to an archive, sample one at walk start, restore
   to it, *then* explore. The single insight that cracked
   Montezuma's Revenge.
4. **Active automata learning** (Angluin 1987, *L\**) — build an
   explicit model of the world from observations, plan over the
   model.

We layered approaches 3 and 4 over the LFU base. Both turned out to
be cheap because of Frame's primitives.

---

## Attempt 3: passive automata learning (the world graph)

**Implementation:** `cca/godot/scripts/world_graph.gd`.

L\* in its original form needs an equivalence oracle — for our
setting, the passive variant (RPNI, Oncina & García 1992) suffices.
The probe emits one `(from_state, action, to_state)` triple per
step, and the graph accumulates them into an explicit transition
table. State hash is `(room, sorted inventory, NPC states)`; this
folds many concrete states into the same graph node, which is the
Hopcroft-style minimisation we want.

Queries the graph supports:

- `shortest_path(from, to)` — BFS over learned edges. The artifact
  that later enabled targeted routing.
- `reachable_from(start)` — all observed-reachable states. Lets us
  flag "graph cells observed as targets but never explored from"
  (the L\* dangling-state signal).
- `audit_topology()` — for every observed `(room, direction)`
  movement, compare the learned destination to `topology.gd::ROOMS`.
  Three categories: matched (silent), gate-conditional (expected),
  divergent (suspect).

**What the audit immediately surfaced: the 5-char-truncation gap.**

Canon CCA's parser examines only the first 5 characters of each
verb (Don Woods 1977 banner). Our driver mirrors that via a
`_verb_synonyms_5` table. The table missed four canonical motion
aliases:

| Canon verb | After truncation | In synonyms_5? |
|---|---|---|
| `forest` | `fores` | **no** |
| `broken` | `broke` | **no** |
| `canyon` | `canyo` | **no** |
| `debris` | `debri` | **no** |

So at every room where `topology.gd` listed these as valid exits,
typing them produced... nothing. The player just stood still.

The audit found this because the topology table said
`Topology.ROOMS[1]["forest"] = 5` (well-house has a forest exit to
room 5), but the learned graph showed 154 walks typing "forest" at
room 1 and ending up at room 1. Adding "forest", "broken", "canyon",
"debris" to the canonical-restore list fixed the bug; room coverage
jumped 48 → 58 in the next run and `unreachable from root` dropped
from 22 → 0 (the graph is fully connected from canonical now).

**What we learned:** the audit's value isn't finding wildly-wrong
movement destinations (we never saw any "wrong-destination" rows).
It's finding *silently-broken* paths the topology table claims work
but the driver doesn't honor. These are invisible to unit tests
unless someone happens to write one for that specific verb at that
specific room.

---

## Attempt 4: multi-seed sweeps (handling probabilism)

CCA has probabilistic mechanics — Witt's End 95/5 bounce-back,
dark-pit 35%, dwarf walks, pirate stalking, Y2 hollow-voice 25%,
the maze decoration probability rows. Under a single RNG seed all
of these collapse to one rolled outcome per turn; a bug in the 5%
branch could go unobserved forever.

**Implementation:** added a `seeds: Array` field to the probe.
Each seed runs a sweep of `walk_count` walks; coverage and the
world graph pool across sweeps. Default: 4 seeds × N walks.

**What worked:** coverage cells +11%, states observed +11%, max
score 38 → 50. Probabilistic branches that one seed missed got
unfolded by another.

**What didn't help much:** room count only went 58 → 59. The
room-coverage bottleneck isn't probabilistic — it's
prerequisite-chain (need keys → unlock grate → descend → lit lamp
→ ...). Probabilistic seeds don't help reach new rooms because the
gates aren't random.

The trade-off was real and intentional: multi-seed widened the
state/action coverage but didn't expand room breadth. It went into
the default config anyway because the cost is linear and the
coverage gain isn't zero.

---

## Attempt 5: wild verb × visible noun emission

User question: *"Why aren't you randomly picking things up and
using them?"*

The introspection was too polite. It only emitted actions whose
canon preconditions were met (`light lamp` only when carrying the
lamp, `wave rod` only at the fissure). That meant the parser
paths for *unexpected* verb-noun combos (`attack chest`,
`wave food`, `examine snake`) never got exercised, and any
verb-dispatch bug that only surfaced on a weird combo was
invisible.

**Implementation:** added a "wild" pass to `list_actions_here()`.
A fixed vocabulary of 18 generic verbs (`examine, attack, kill,
wave, throw, hurl, eat, drink, light, extinguish, feed, release,
read, break, pour, fill, rub, find`) crossed with every noun
currently in scope (carried items + visible-in-room items + NPCs
present). Per-state action count went from ~30 to ~150.

**What worked:** coverage cells jumped from 499 → 2273 in
comparable runs (+356%). Many (room, action_key) pairs that the
canon-correct emission would never have tried got exercised.
Most produce canon rebuff prose ("you can't be serious!") rather
than state changes, but **every rebuff is a parser code path we
hadn't been testing**.

**What broke down:** room coverage dropped from 59 → 49. With 5×
more actions per state, the LFU walker spent more turns exhausting
each room before leaving. The trade-off is wider per-state
coverage at the cost of fewer rooms.

---

## Attempt 6: Go-Explore archive (for autonomous completion)

User goal: *"I would like it to conclude the gameplay as fast as
possible."*

**Implementation:** added an archive `Dictionary[state_hash →
{bytes, trajectory, score, visit_count, room}]` to the probe.
At walk start, with probability `archive_return_prob = 0.8`,
sample a cell from the archive and `restore_state()` to it. The
walker skips the boring exploration prefix and spends its budget
exploring from the frontier. State hash widened to include
`treasures_deposited` and `endgame_state` so "well-house with
empty inventory and 0 deposits" doesn't collapse with "well-house
with empty inventory and 14 deposits."

**First sampling scheme: weighted by score.** Each archive cell's
weight ∝ `score_weight × normalized_score + 1.0`. **This failed.**
With 189 score-0 cells and 1 score-30 cell, the score-0 cells
totaled 97% of sample mass even at high score weight. The walker
kept restoring to "at well-house, no items" instead of "in deep
cave, lots of progress."

**Fix: top-K sampling.** With probability 0.7, sample uniformly
from the top 20% of cells by score. With probability 0.3, sample
uniformly anywhere. This is the Go-Explore "prioritised sampling"
recipe (Ecoffet §3.2) adapted for a discrete-score domain.
Fixed the failure.

**Movement-preferred LFU tiebreak.** When multiple actions tied at
minimum count, the wild-verb emission produced enough non-movement
ties to slow traversal. Added a tiebreak rule: among tied actions
at the minimum, prefer `kind == "move"` over `kind == "verb"` or
`kind == "wild"`. Walker traverses rooms faster.

**What worked:** max score 28 → 37 in 60 walks. Archive
accumulated 256 cells.

**What didn't:** the walker still didn't *win the game*. Pure
Go-Explore on CCA-class problems (the literature equates them with
Montezuma's Revenge) typically takes millions of frames; we have
hundreds of walks. Path 3 of "tune Go-Explore further / add graph
routing / seed from canonical journey" was undecided.

---

## The reframe that mattered

User clarification: *"The goal is testing coverage and not
wayfinding. Any tools that help us permute the testing coverage is
the goal."*

This reframed the whole stack. We weren't trying to *complete the
game autonomously* — we were trying to *exercise testing coverage
permutation*. A* / Go-Explore / graph routing are useful as
**navigation primitives** to reach interesting test points, not as
goal-seekers.

This changed what the next attempt should be: not "smarter
exploration toward victory" but "use the graph to reach
under-tested cells, then permute heavily once there."

---

## Attempt 7: graph-routed targeting + action storm (current state)

**Implementation:**

1. **Target-cell picker** — chooses an under-tested archive cell.
   Priority: (a) cells dangling in the graph (observed as targets
   but never explored from), (b) cells with fewest distinct
   outgoing edges, (c) cells with lowest visit count.
2. **Routed walk** — `world_graph.shortest_path(current, target)`
   returns an action sequence. The probe replays it.
3. **Action storm at the target** — once at the target state,
   `save_state` once, then iterate the available actions in
   shuffled order, executing each and `restore_state`-ing back to
   the anchor between actions. Each storm action exercises a
   distinct (state, action) parser path; the rewind ensures we
   exercise N action paths from a single anchor.

The storm is the unique-to-us piece. Black-box exploration agents
(the entire Jericho 2020 tradition) literally cannot do this —
they can't atomically rewind FSM state. Frame's `@@[persist]`
gives it to us for free.

**Numbers at default config (4 seeds × 12 walks, 500-step cap,
~70s wall time):**

- 1700–2300 coverage cells
- 200–256 archive cells
- 15–22 routed walks per run
- 225–309 storm actions per run
- 34–46 rooms visited
- Zero wrong-destination topology divergences
- Max score 25–37

The test pass criterion was reworked: either rooms ≥ 30 *or*
coverage cells ≥ 1500. The dual threshold lets routed/storm runs
(narrow-but-deep) pass without requiring the same room breadth as
pure-LFU runs.

---

## The full stack

After seven attempts the probe is composed of these pieces, each
addressing a specific failure mode:

| Layer | Failure mode it addresses | Lineage |
|---|---|---|
| Affordance enumeration | Coverage measures only what was tried | — |
| LFU action selection | Repeated visits don't add coverage | Bellemare 2016 |
| Multi-seed sweeps | Probabilistic mechanics under-explored | Standard stochastic testing |
| Wild verb × noun emission | Parser paths for unexpected combos untested | Coverage-guided fuzzing |
| Passive automata learning | No model of reachable transitions | Angluin 1987, Oncina/García 1992 |
| Topology audit | Silent driver/topology divergences | Model-based testing |
| Go-Explore archive | LFU saturates locally, can't reach prerequisites | Ecoffet 2019 |
| Top-K archive sampling | Weighted sums starve in long-tail score domain | Ecoffet §3.2 |
| Movement-preferred tiebreak | Wild verbs slow traversal | Heuristic — local |
| Graph-routed targeting | Random LFU can't reach under-tested cells | BFS over learned graph |
| Action storm with save/restore | Exercise N actions from one anchor | Unique to white-box FSM access |

**Bugs surfaced so far:**

1. Death didn't drop inventory items (`is_carried` mismatch
   between Player FSM and item FSMs). Found by state-space BFS.
2. Treasure FSMs don't expose `is_carried()` (they use
   `get_state() == "carried"` instead). Found by probe runtime
   crash.
3. 5-char truncation gap for `forest` / `broken` / `canyon` /
   `debris`. Found by world-graph topology audit.

Three real bugs from a tool whose primary purpose was coverage,
not bug-finding. That's the practical value — coverage tools that
find bugs are doing their job.

---

## What Frame brought to the table

The probe is ~700 lines of GDScript. Most of what makes it small:

- **`@@[persist]` for save/restore.** Every `@@system` in
  `cca/frame/*.fgd` gets `save_state()` / `restore_state()`
  generated automatically. The action-storm primitive — exercise
  N actions from one anchor with rewind — is impossible without
  this, and free with it.
- **FSM event interfaces are inherently introspectable.**
  `list_actions_here()` works by querying live FSM state
  (`fsm.player.carrying(KEYS_ID)`, `fsm.bear.get_state()`).
  No serialisation, no model inference — the language gives us
  the interface.
- **Aspect machines compose independence.** Each puzzle / NPC is
  its own `@@system` with bounded state. The state hash
  enumerates them explicitly. POR-style commutativity isn't
  needed — the architecture is *already* partitioned.
- **The Driver is a thin shell.** The probe types into
  `Driver._process_input` exactly as a player would. No special
  test harness, no parallel input path. What the probe exercises
  is what the player experiences.

This is the substrate argument: the *probe wouldn't be small*
without these primitives. In a black-box game (Jericho-style) the
same coverage workload would need a learned world model, a
neural-net policy, and a serialisation framework. Frame gives all
three by construction.

---

## Phase C — Layer 2 (item-placement spec) landed

**Implementation:** `cca/godot/scripts/world_spec.gd` plus the
dedicated init test `cca/tests/test_cca_world_spec.gd`. Per-walk
in-limbo check wired into the probe.

The spec declares per-item canon expectations: initial room,
treasure value, kind (treasure vs. item), whether it's a dynamic-
spawn (legitimately starts in limbo), and consumable flag. All 28
carriable items are spec'd. Source: canon advent.dat section 7
cross-referenced with the FSM init declarations (`Treasure._create`
/ `Item._create` at the head of `puzzles.fgd`) where the
implementation already cites canon room numbers in comments.

Two consumers:
- **Init check** (`test_cca_world_spec.gd`) — builds a fresh
  `Cca()` and asserts every spec'd item is at the declared room.
  Smallest possible scope for canon-fidelity verification: a
  fresh world before any commands. Currently passes — implementation
  matches canon for all 28 items.
- **Per-walk in-limbo check** (in `probe._check_spec_violations_at_walk_end`)
  — at each walk's end, scans every item; if any is in location 0
  AND not carried AND not a dynamic-spawn item, flags it as a
  violation. Catches the "item vanishes into nowhere mid-walk"
  bug class.

Current state: **0 spec violations across 34 walk-end checks** at
default probe settings. The Phase C scaffolding is in place; bugs
will surface here when item-handling code drifts away from canon.

### Phase C Layers 3 + 4 + treasure-value all landed

After Layer 2 proved the spec-as-data architecture, the remaining
three Phase C deliverables followed naturally:

**Treasure-value cross-check** (`test_cca_treasure_values.gd`).
For each of the 15 canon treasures: build a fresh FSM, force-take
the treasure (reappear()-ing dynamic spawns like pearl/chest), drop
at the canon DEPOSIT_ROOM, assert the score delta equals the spec's
`value` field. All 15 pass at +14 each (matching canon's 210-point
treasure-score ceiling).

**Layer 3 — NPC anchoring** (`NPC_SPEC` in `world_spec.gd` plus
`test_cca_npc_spec.gd`). Declares each of 7 NPCs' home_room and
initial_state. Found one spec error during development: pirate's
initial state is `dormant`, not `hidden` (the latter is the dwarves'
pre-wake state). Fixed; all 7 NPCs now match canon on fresh init.

**Layer 4 — verb-effect tables** (`VERB_EFFECTS` array plus
`test_cca_verb_effects.gd`). The behavioral half. For each canon
mechanic, declare:
- `setup` — fresh-FSM mutation to land in the pre-condition state.
  Supports `player_room`, `carrying`, `lamp`/`grate` state, plus
  `setup_steps` (a list interleaving `{goto: room}` teleports and
  `{cmd: input}` real driver commands for multi-step setups like
  "go to canon 10, take cage, go to canon 13, take bird").
- `input` — array of typed commands run through real Driver.
- `expect` — post-input predicates verified against the FSM
  (`player_room`, `lamp_lit`, `grate_locked`, `bridge_built`,
  `bear_state`, `snake_blocking`, `dragon_alive`, `clam_consumed`,
  `oyster_exists`, etc.).

Initial set of 14 entries covers magic-word teleports (XYZZY, PLUGH
× both directions), lamp on/off, grate lock/unlock, crystal bridge,
bear taming, snake clearance, dragon slaying, bottle filling, and
clam→oyster transformation. All 14 pass.

The pattern of failures during development was instructive: of 5
initial failures, **all 5 were spec-setup bugs**, not FSM bugs.
Specifically:
1. `unlock_grate_with_keys` setup called `grate.unlock()` without
   the required `have_keys: bool` parameter.
2. `wave_rod_at_fissure`, `feed_bear_tames_it` — the spec's
   `carrying` shortcut force-took items via `try_take(player_room)`,
   but the item wasn't at the player's room. Fixed by extending
   `_force_take` to teleport-take-teleport-back for static-spawn
   items.
3. `release_bird_clears_snake` — the Bird FSM transitions
   `$Free → $Caged` only when "take bird" fires with the cage
   present, so force-take alone left the Bird in `$Free` and
   release-bird short-circuited. Fixed by introducing `setup_steps`
   (interleaved goto/cmd).
4. `break_clam_creates_oyster` — canon requires the clam NOT
   carried (the player must put it down first). Spec was giving
   the player the clam, defeating the canon prerequisite. Fixed
   by leaving the clam in-room.

**This is the value the spec layer adds.** Every failure surfaced
either a canon-mechanic detail the spec author got wrong (the clam
NOT-carried prerequisite is the kind of thing easy to miss) or a
test-infrastructure gap (the force-take/cage dependency for the
bird). Both are exactly the bugs hand-written unit tests miss
because the test author writes both the setup *and* the canon
expectation from the same flawed mental model. The spec
externalises the canon expectation, so spec author and code author
can disagree visibly.

### Final test count

71 tests pass after Phase C completes:
- 4 new tests added in Phase C
  (`test_cca_world_spec`, `test_cca_treasure_values`,
   `test_cca_npc_spec`, `test_cca_verb_effects`)
- 67 pre-existing tests still pass

The spec database is the artifact. The 4 new tests are
verifications-against-spec at each layer:
- item placement on fresh init
- NPC initial state on fresh init
- treasure deposit values
- verb effects via real driver

## What's next

The probe builds a learned model of CCA's behavior (the world
graph). Phase C inverts the relationship: declare a model of what
canon *should* do, and verify the probe's observations match.

The shape:

- A new module `world_spec.gd` declares per-room expectations
  (which items spawn where, which NPCs anchor where, which
  verb-effects fire on which preconditions). Drawn from canon's
  `advent.dat` / `advent.for` source.
- The probe consults the spec during walks. When `(room, action,
  conditions) → expected_effect` is declared but the observation
  contradicts, flag a `spec_violation` alongside coverage data.
- The audit gains a fourth category: `bug / gate / stayed-put /
  wrong-dest / spec_violation`.

This turns the probe from a coverage tool into a model-based
testing tool. The literature term is **specification-based
testing** (Utting/Pretschner/Legeard 2006); the closest
commercial-grade implementation is Microsoft Research's
SpecExplorer. We have an unusual advantage in that the spec we're
testing against is *canon CCA*, so the spec database is largely
transcription, not invention.

The architecture is documented but not yet built. Layer 2 (item
placements) is the cheapest first cut — maybe a day to write,
gives immediate signal on item-spawn correctness.

---

## Material for an external writeup

This document captures the journey for project-internal record.
The user's stated goal is to use this work to **promote Frame as
a problem-solving technology**, with extensive game-space testing
as the practical case study.

The angle that works for an external audience:

> *"I tried to extensively test a 1977 text adventure with modern
> coverage techniques. Most failed in exactly the ways the
> literature predicts. The ones that worked depended directly on
> Frame DSL primitives — `@@[persist]` for save/restore,
> introspectable FSM events for affordance enumeration, aspect
> machines for independent composition. This is a case study in
> what's possible when state is a first-class language construct
> instead of an ad-hoc data structure."*

Concrete hooks for that writeup:

- **The Jericho 2020 contrast.** Hausknecht et al. established
  that random/RL agents fail on Colossal Cave. With white-box FSM
  access we got 2300 coverage cells in 70 seconds. The comparison
  isn't "we beat them" — they were solving a harder problem (no
  FSM access). The point is that *the architecture of the game
  matters as much as the cleverness of the testing*.
- **The 5-char truncation bug as the lede.** A real bug found by
  a tool whose primary purpose was coverage, surfaced by an
  audit that compared learned behavior against declared topology.
  Concrete, debuggable, fixable in one line.
- **The honest framing.** Don't oversell. The probe doesn't win
  the game autonomously and the literature predicts it shouldn't.
  What it does well — exhaustive coverage of state-action paths
  via save/restore-rewound permutation — is exactly what white-box
  FSM access enables and what black-box approaches can't.

Plausible venues: a long-form blog post syndicated to HN/r/programming,
talks at Lambda Days / DDD Europe / BOB conference / Curry On,
or an Onward! Essays submission at SPLASH if peer review is wanted.
A research paper isn't the right shape — the individual techniques
are all from the literature; the contribution is the synthesis
plus the substrate argument, which is a programming-languages-and-tools
essay rather than an algorithmic one.
