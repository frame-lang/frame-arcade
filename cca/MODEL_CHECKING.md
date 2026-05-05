# Model-checking nearly free: what `@@[persist]` unlocks

**Question:** Frame's `@@[persist]` annotation gives every
`@@system` a `save_state()` / `restore_state()` pair. That's
sold as a save-game feature. Does it also buy anything for
*testing*?

**TL;DR:** Yes. The same byte-array that lets a player save and
reload becomes a teleport primitive for two real testing tools:
a state-space explorer that BFS-validates small FSMs against
their canonical shape, and a runtime monkey fuzzer that walks
the full system at ~1000 commands/second and asserts coverage
floors. Together they catch a class of bugs scenario-based
smoke tests don't — drift between docs and generated code,
soft-locks introduced by an FSM refactor, transition crashes
on unusual orderings.

Neither tool found a bug in CCA at the time of writing. That
**is** the result: 21 tests including 10000 random commands
across 64 rooms, 0 crashes, 0 soft-lock candidates. The tools
are forward-looking — their value compounds with every future
FSM change.

---

## What got built

Two files in `cca/godot/scripts/` and two tests:

- `state_explorer.gd` — BFS the (state × event) graph of any
  `@@[persist]` system. Uses `save_state` / `restore_state` to
  teleport between visited states rather than replaying paths.
  Cost is `O(states × events)` regardless of graph diameter.
- `monkey.gd` — random-walk fuzzer of the full Adventure
  world. Hashes a coarse world-fingerprint to detect "did
  anything change," memoizes (fingerprint, command) pairs to
  skip wasted work on deterministic FSMs, auto-revives on
  death so the walk doesn't terminate.
- `tests/test_cca_state_exploration.gd` — runs the explorer on
  six small FSMs (Bear, Lamp, Plant, CrystalBridge, Grate,
  VendingMachine) and validates each against an expected
  canonical shape (states + dead-ends). 1ms each.
- `tests/test_cca_monkey.gd` — runs the monkey for 10000 steps
  on a fixed seed (42) and asserts coverage thresholds. ~8s
  wall time.

---

## Tool 1: state explorer

The explorer treats every `@@[persist]` system as a finite
graph to be enumerated. Pseudocode:

    queue       = [initial_state]
    saves       = {initial_state: factory().save_state()}
    transitions = []

    while queue not empty:
        current = queue.pop()
        for (event_name, args) in events:
            inst = factory()
            inst.restore_state(saves[current])
            inst.callv(event_name, args)
            new_state = inst.get_state()
            transitions.append((current, event_name, args, new_state))
            if new_state not in saves:
                saves[new_state] = inst.save_state()
                queue.push(new_state)

The teleport is the trick. A naive walker would have to replay
each path from the initial state to retry an event from a
visited state, paying O(diameter) every time. With save/restore
the cost collapses to O(states × events).

Output for Bear:

    === Bear ===
    Initial: hungry
    Discovered states (5):
      - hungry, tame, attacking, following, released
    Transitions (15):
      hungry    -- feed         --> tame
      hungry    -- take_chain   --> attacking
      tame      -- take_chain   --> following
      following -- drop_chain   --> released
      ... (self-loops marked "no change")
    Dead-end states (no event leaves them): attacking, released

The test asserts the discovered state set and dead-end set
against an expected canonical shape. If a future Bear refactor
accidentally adds a state, drops a dead-end, or makes a state
unreachable, the test fails immediately — and the failure
message names the specific divergence.

What it can't reach: threshold-driven transitions. Lamp's
`$Bright → $Dim → $Out` happens via battery drain over many
ticks; one `light` event won't get there. The test explicitly
carves these out as "lifecycle only" and leaves the
threshold path to the existing `test_cca_lamp.gd`. Honest
labelling beats false coverage.

**Coverage:** 6 small FSMs, 17 states total, 36 transitions,
4 expected dead-ends, all validated structurally.

---

## Tool 2: the monkey

The state explorer doesn't scale to the full Adventure. The
joint state space of (Player × Bear × Bird × Snake × Troll ×
... × Dragon × Pirate × Endgame × ScoreLedger × world map)
is astronomical. But the *command vocabulary* is finite —
canonical CCA verbs and nouns total maybe 60 entries.

The monkey:

1. Builds a fresh Adventure with all aspects wired.
2. Each step, picks a random `(verb, noun)` from a fixed
   vocabulary. Directional moves resolve against the room
   topology table — we don't fabricate room IDs.
3. Snapshots a coarse world-fingerprint before and after:

   ```
   fp = "r%d|s%d|t%d|p%s|l%s|e%s|g%s|b%s" % [
       fsm.player_room(),
       fsm.score(),
       fsm.treasures_deposited(),
       fsm.player_state(),
       fsm.get_lamp_state(),
       fsm.endgame_state(),
       "L" if fsm.grate_locked() else "U",
       "B" if fsm.bridge_built() else "_",
   ]
   ```

4. Memoizes `(fp_before, verb, noun) → fp_after`. Frame FSMs
   are deterministic; retrying the same command from the same
   fingerprint tells us nothing.
5. Tracks a no-op streak per fingerprint. If 200 consecutive
   commands all bump (no fingerprint change), the fingerprint
   is flagged a soft-lock candidate.
6. Auto-revives on death so the walk continues. Permadeath
   recreates the world and continues with the same memo
   tables.

The fixed seed makes any failure reproducible: hand the seed
and step count back, walk the same path bit-for-bit.

**Baseline at 10000 steps, seed 42, ~8s wall time:**

| Metric | Value |
|---|---|
| Rooms reached | 64 / ~140 |
| Distinct world fingerprints | 974 |
| State-changing commands | 4324 |
| No-op commands | 5676 |
| Max score | 53 |
| Resurrections | varies (~30) |
| Soft-lock candidates | **0** |
| Crashes | **0** |

Scaling is approximately linear in step budget. 20k steps
reaches 68 rooms / 1341 fingerprints — diminishing returns,
because the random walker can't reliably solve gated puzzles
(plant beanstalk, crystal bridge, troll bribe). That's a Phase
2 concern.

---

## What the tools don't do

Honest list, in order of size:

1. **Deep semantic bugs.** The monkey can't tell that "take
   bottle" worked when inventory printer claims it didn't (a
   real bug we shipped earlier — the fix was outside the
   FSM). The fingerprint matched because aspects didn't see
   the inventory string.

2. **Threshold-driven transitions.** Already covered above.
   Lamp battery, endgame timer, hint observation streaks —
   all need many ticks to fire, the explorer fires events
   once per state.

3. **Gated puzzles.** Random walks don't solve "wave rod at
   fissure to build crystal bridge then cross east to scorched
   cavern then attack dragon with bare hands." The monkey
   gets there ~5% of seeds. Solving puzzles needs directed
   search with goals — Phase 2 / 3 territory.

4. **Sequencing logic.** "A then B" vs "B then A" is only
   distinguished when it produces a different fingerprint.
   Subtle ordering bugs that don't surface in the
   fingerprint slip through.

5. **Inter-FSM interactions outside the fingerprint hash.**
   The fingerprint is 8 fields. Pirate stalking state, dwarf
   counts, exact treasure inventory — all invisible. Bugs
   that need those to surface won't be caught.

6. **Argument value spaces.** For events with bool args
   (`unlock(true/false)`, `insert(true/false)`) the explorer
   enumerates manually. Continuous or large arg domains are
   not swept.

The tools find shallow bugs and assert structural shape.
That's the contract.

---

## Why this is a Frame thing specifically

Other FSM ecosystems handle this poorly:

- **Unity Animator / state machines** don't have a generic
  save/restore. You'd have to write your own, per-machine,
  per-version. Drift inevitable.
- **Unreal Behavior Trees** have a tree-walk runtime;
  "current state" is a stack of node pointers, not a value
  you can serialize and replay. Save/restore is a feature
  you add manually.
- **Hand-rolled FSMs** in any language: save/restore is what
  you build last, after the FSM works, after the integrations,
  after shipping. By then there are already states that don't
  serialize cleanly, and adding `@persist`-equivalent
  retroactively is a refactor.

Frame's `@@[persist]` is upstream of all this. The
serialisation comes for free with the annotation; every
`@@system` you write with that flag is teleport-able from
day one. The tools above are downstream of that single
property.

The article isn't "every game dev needs a monkey." It's
"Frame gives you the substrate where building one is a
weekend, not a quarter."

---

## What we tried for Phase 2 — and why it didn't ship

The plan after Phase 1 was a richer monkey: instrument hot
FSMs with a `Recorder` side-channel so the driver could see
internal observations (`Player.take(item)`, `Pirate.steal()`,
aspect verdicts) the public interface doesn't expose. Use
those observations to bias exploration toward "interesting"
fingerprints, with periodic teleport via save/restore.

What actually happened across the build:

1. **The Recorder turned out to be unnecessary.** Reviewing
   Adventure's public surface — `*_state()` per sub-FSM,
   `darkness_consumed_count()` / `backpack_blocked_count()` /
   `magic_transforms_count()` for aspect verdicts, the score
   and treasure-deposit counters, plus `inventory_size()` /
   `bottle_has_water()` / `plant_is_tall()` and similar — we
   already had ~25 observable signals. Phase 2's premise
   ("the public interface isn't enough") was wrong. The
   Frame source stays clean of test-only instrumentation.

2. **Richer fingerprint helped a little.** Going from 8
   fields to 18 fields lifted distinct fingerprint count
   ~17% (974 → 1142 average over 5 seeds at 10k steps).
   Real but modest signal.

3. **Novelty-biased teleport didn't pay off on CCA.**
   Periodic teleport (10% every step) hurt forward progress:
   directed walker reached *fewer* rooms than random on
   3-of-5 seeds, max score collapsed (53 → 29), wall time
   doubled. Switching to "only teleport when stuck" never
   actually fired — the random walker on CCA is never stuck
   long enough to trigger. The walker isn't stuck; it's
   inefficient. Different problem.

The honest finding: **for the CCA shape (140-room graph,
turn-based parser, gated puzzles), the random walker's real
failure mode is wasted commands, not local minima**. Random
draws spend 60% of budget on no-ops. Fixing that needs
goal-directed action selection ("that take just got blocked
— drop something first" / "this command sequence is
canonical for the dragon") which is planning over the FSM
graph, not save/restore teleport.

That's Phase 3 territory: LLM-prompted goal selection or a
learned policy. The headline architectural lesson stands —
`@@[persist]` enables both the state explorer (which works
beautifully) and the directed monkey (which we built and
shelved) — but the monkey heuristic doesn't cross the
threshold where it earns its complexity.

The directed monkey code lived briefly in
`cca/godot/scripts/monkey_directed.gd` + an A/B test, then
was deleted as study residue. The result is in this section
instead.

### Addendum — constrained-vocabulary monkey also lost

A second heuristic was tried after this writeup landed:
pre-filter the command vocabulary to only include legal
actions per turn (move only through real exits, take only
items in the player's room, drop only items currently
carried). Hypothesis: cutting the random walker's ~60%
no-op rate would convert wasted draws into exploration.

What happened across 5 seeds at 10k steps each:

| Metric | Random | Constrained | Δ |
|---|---|---|---|
| Rooms reached | 59.0 | 52.6 | **-6.4** |
| Fingerprints | 974 | 794 | **-180** |
| Max score | 48.2 | 43.0 | -5.2 |
| No-op draws | 5635 | 1460 | -4175 |

The no-op rate dropped 75% — but rooms went *down*. The
diagnosis: random's no-ops were acting as an effective rate
limiter on inventory churn. The constrained walker greedily
takes every visible item, fills inventory, hits
BackpackLimit, drops something, takes the next item — burning
the "saved" budget on loops in already-visited regions
rather than on movement.

That makes the random monkey a surprisingly strong baseline
for the CCA graph shape. Two heuristic improvements
(novelty-biased teleport, legal-only vocabulary) both
failed to beat it. The next honest path is goal-directed
search (Phase 3 — LLM-prompted action selection or learned
policy), which is a different framework, not a tuning
twiddle on this one.

---

## What landed (final)

- **State explorer** — `cca/godot/scripts/state_explorer.gd`
  with `tests/test_cca_state_exploration.gd`. Six small FSMs
  exhaustively validated against canonical shape. Real
  forward-looking regression bound.
- **Random monkey** — `cca/godot/scripts/monkey.gd` with
  `tests/test_cca_monkey.gd`. 10k random commands, fingerprint
  diff, soft-lock detection. Cheap insurance: 0 crashes,
  0 soft-lock candidates against the current build.
- **Topology extracted** — `cca/godot/scripts/topology.gd`.
  Room map and gates as pure data so non-UI consumers
  (monkey, future visualisers) can reason about the graph
  without instantiating the driver Control.

For *bug coverage*, scripted scenario tests
(`test_cca_full.gd`, `test_cca_dragon.gd`, etc.) do the
heavy lifting. The model-checking work above is *insurance*
on top of that — it asserts structural shape and survives
random fuzzing, but it doesn't replace knowing the canonical
paths.

The pitch hasn't changed: **Frame's `@@[persist]` is what
makes building these tools cheap**. The state explorer is
the most defensible demonstration of that. The monkey is a
bonus.

Phase 1 commits: `13f9584` (state explorer), `e4e657f`
(monkey + topology), `d553b84` (this writeup, original
version). Phase 2 ablation absorbed into this section
without a new commit — the experiment didn't earn one.
21 tests green.
