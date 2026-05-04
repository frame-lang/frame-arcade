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

## What's next: Phase 2

The fingerprint is 8 fields because that's all I could hash
without instrumenting the FSMs. Aspect changes (inventory
gain/loss, score increments, hint penalties) are invisible
to the outside-in view — and that's exactly where the
monkey's coverage plateaus.

Phase 2 adds a `Recorder` side-channel: an autoload object
the FSMs call from their action blocks to report
*observations* the driver couldn't infer from `get_state()`
alone. The driver subscribes between commands and feeds the
extra signal back into the exploration heuristic — biasing
toward fingerprints where novel observations were just
recorded.

This is the labour-broad cost: every Frame source that
contributes interesting observations needs a `recorder.record(...)`
call in its action blocks. It's not free. The judgement
will be: does the richer signal solve the gated-puzzle
plateau, or do we need a different shape (LLM-prompted
goal selection, learned policy) for that to crack?

Phase 1 — the work in this article — landed in commits
`13f9584` (state explorer) and `e4e657f` (monkey + topology
extraction). 21 tests all green.
