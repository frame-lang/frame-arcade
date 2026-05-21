# The Model-Extraction Gap, and a Program Born Without It

*Draft — on what you get for nearly free when your program is
already a labeled transition system. Worked example: a port of
the 1977 Colossal Cave Adventure, built from composable Frame
state machines.*

---

## The gap nobody talks about

Model checking is one of the genuine triumphs of computer
science. Give a model checker a finite-state system and a
temporal-logic property, and it will either prove the property
holds on every execution or hand you a concrete counterexample
trace. Clarke, Emerson, and Sifakis shared the 2007 Turing Award
for it. SPIN has been verifying protocols since the late '80s.
The theory — Lamport's safety and liveness (1977), Clarke and
Emerson's CTL (1981), Milner's and Park's bisimulation (1980-81)
— is settled and beautiful.

And almost nobody runs it on their application code.

The reason isn't ignorance. It's that the hard part of software
model checking isn't the checking — it's getting from a pile of
imperative code to the **finite-state model** the checker needs.
That step is *model extraction*, and it is brutal. SLAM, BLAST,
and CBMC are entire research programs built around extracting
checkable models from C, using predicate abstraction (Ball &
Rajamani), lazy abstraction (Henzinger et al.), bounded unrolling
(Clarke, Kroening, Lerda), and counterexample-guided abstraction
refinement (Clarke, Grumberg, Jha, Lu, Veith, 2000) to claw a
tractable Kripke structure out of code that was never written to
expose one. Abstract interpretation (Cousot & Cousot, 1977) is
the foundation, and it is *the* cost center. The checking is
cheap once you have the model. You almost never have the model.

This is a story about a class of program that **hands you the
model for free** — because it was written as a transition system
in the first place — and what becomes possible once the
extraction gap is gone.

---

## A Frame program is a Kripke structure

The system under test is a port of Colossal Cave Adventure: 140
rooms, 15 treasures, a snake, a dragon, a bear, a troll, five
dwarves, a pirate, and the original's catalogue of cruel little
puzzles. It is built in [Frame], a notation for explicit state
machines that compile to (in our case) GDScript. The whole game
is a bus of priority-ordered FSM "aspects" — Snake, Bear, Troll,
Bottle, CrystalBridge, Endgame, and so on — composed under one
persistence envelope.

Every player command is dispatched down that bus. Each aspect, in
priority order, returns one of three verdicts: **consume** (handle
it, stop the chain), **transform** (rewrite the event, keep
going), or pass. Only if nothing consumes does the command reach
the base verb handling:

```text
 player types:  "xyzzy"
                   │
                   ▼
   ┌──────────────────────────────────────────────────┐
   │ Adventure.do_command(verb, noun)                  │
   │ event = {verb, noun, room, is_dark, lamp_lit, …}  │
   └──────────────────────────────────────────────────┘
                   │  bus.begin_dispatch()
   priority        ▼
    700  ──►  ┌──────────┐  pass        gate info verbs in the dark;
              │ darkness │ ───────┐     consume if you can't see
              └──────────┘        │
    500  ──►  ┌──────────┐  TRANSFORM   "xyzzy" → "move 33"
              │  magic   │ ───────┤     (event rewritten, chain continues)
              └──────────┘        │
    400  ──►  ┌──────────┐  pass        consume "take" when the
              │ backpack │ ───────┤     pack is full
              └──────────┘        │
    100  ──►  ┌──────────┐  observe     records "player moved"
              │  score   │             (sees the post-transform event)
              └──────────┘        │
                   │  nothing consumed → fall through
                   ▼
   ┌──────────────────────────────────────────────────┐
   │ base FSM verb handling (_verb_move, _verb_take…)  │
   └──────────────────────────────────────────────────┘

   verdicts:  consume   stop the chain, return its message
              transform rewrite the event, continue downward
              pass      hand to the next aspect
```

The priority order is load-bearing: `darkness` sits above `magic`
so XYZZY can't silently teleport you in a room you can't see;
`score` sits at the bottom so it records the *transformed* event
("you moved") rather than the raw verb ("you typed XYZZY").

Here is the observation the whole effort turns on. A Kripke
structure (Kripke, 1963), the object a model checker consumes, is
a tuple: a set of states, a transition relation, and a labeling
of states with atomic propositions. A Frame program already *is*
that tuple, concretely, at runtime:

| Kripke structure | Frame program |
|---|---|
| state | the composed FSM configuration |
| state vector | `save_state()` → `PackedByteArray` |
| transition relation | `process_input(command)` |
| enabled actions | the affordance enumerator the game already has |
| atomic propositions | the FSMs' own query methods (`player_room()`, `endgame_state()`, `snake.is_blocking()`) |

Drawn as the gap it closes:

```text
  FORMAL OBJECT                RUNTIME ARTIFACT (already ships)
  ─────────────                ───────────────────────────────
  state  s ∈ S          ◄────  composed FSM configuration
  state vector          ◄────  save_state() : PackedByteArray
  transition  s ─a→ s'  ◄────  restore(s); process_input(a)
  enabled(s)            ◄────  list_actions_here()
  labeling  L(s)        ◄────  query methods: player_room(),
                                endgame_state(), snake.is_blocking()

  ORDINARY CODE                       FRAME-NATIVE CODE
  ─────────────                       ─────────────────
  source  ──extraction──►  model      source ════════►  model
          (SLAM/BLAST/CBMC:           (the program already
           predicate abstraction,     IS the transition system;
           CEGAR, unrolling …)        save_state() is the vector)
                ✗ the cost center            ✓ no extraction step
```

There is no extraction step. `save_state()` is not an
*abstraction* of the state — it is the state, serialized,
because the Frame framework already needs serialization for
save/load. The transition relation isn't recovered by static
analysis — it's the dispatcher you ship. The atomic propositions
aren't invented by the verification engineer — they're the query
methods the game already exposes.

That collapses the model-extraction gap to nearly nothing. What's
left is a small, *domain-agnostic* engine and a thin per-domain
adapter.

---

## What falls out

We built `FrameStateChecker`: about 150 lines, no knowledge of
adventure games. It talks to any Frame domain through a
ten-method adapter (`make_root`, `save`, `restore`,
`enumerate_actions`, `apply`, `state_hash`, `invariants`,
`observe`, plus two optional). Bind a domain and the classical
properties drop out, each a direct instance of a named result:

**Reachability + safety.** `explore()` is breadth-first
explicit-state search — the SPIN/Holzmann technique, bounded in
the manner of Biere et al.'s bounded model checking (1999) via a
state cap. At every reached state it evaluates the domain's
invariants. An invariant is a **safety property** in the precise
Lamport (1977) / Alpern–Schneider (1985) sense: refutable by a
finite prefix. A violation comes back as a concrete
counterexample path. (Ours: a player carrying an item the item's
own state machine thinks is on the floor — caught on the first
run.)

**Liveness.** `reachable_satisfying(φ)` answers the CTL query
**EF φ** — "does some reachable state satisfy φ?" — and returns a
witness path. Point it at φ = *won* and it answers "can the
player still win from here?", which is the game-design property
of **softlock-freedom**. From every reachable save-point, the
strengthening **AG EF won** ("from anywhere reachable, victory is
still reachable") is the textbook non-deadlock / reset-reachable
formula. We compute bounded approximations of both.

**Bisimulation.** `restore_soundness()` checks observational
equivalence (Milner 1980, Park 1981): restoring to a state must
produce behavior indistinguishable from a fresh instance at that
state. If a reused checker instance, deliberately corrupted and
then restored, observes differently from a clean one, the restore
(or the state vector) is incomplete. This is the check that
guards the soundness of the whole enterprise — more on why below.

The adapter for CCA is the punchline: ten methods, every one a
thin delegate. `save` is the FSM's own `save_state`.
`enumerate_actions` is the affordance list the game already
computes for its prober. `state_hash` reads query methods.
Binding a 140-room adventure to a model checker took an afternoon,
not a thesis — because the game was born as the structure the
checker wanted.

We cross-validated the generic engine against the hand-written,
CCA-specific search it replaced: identical reachable-room count,
identical zero violations, at the same bound and seed. The
generality cost nothing in fidelity.

---

## Two bugs, and the theory that names them

The interesting part of building a verifier is the moments it
lies to you. Both of ours map exactly onto known failure modes.

### The incomplete state vector

The reachability search reported it could reach **53 of 140
rooms** and called that a pass. The number was false.

The search reuses one driver object across thousands of branches,
rolling the FSM back at each branch point with save/restore. But
the driver carries one piece of state *outside* the FSM's
save-state: a modal prompt dispatcher — the little machine that
handles "are you sure? (y/n)", including the death-and-revive
prompt. It was deliberately not composed onto the game's
persistence envelope (a documented design choice: modal
interaction state shouldn't survive a save/load boundary).

So when any branch killed the player, the dispatcher entered
"awaiting revive answer." Save/restore rolled the *FSM* back — but
not the dispatcher. Every subsequent branch inherited a stuck
prompt, and the modal handler ate every command that wasn't "yes"
or "no." Navigation silently broke across most of the search
tree. The "53" was an artifact of a leaked prompt, not a fact
about the game.

```text
  one reused driver, walking the search tree:

  branch A ── kill player ──►  PromptDispatcher = "awaiting revive"
                                     │
                    save_state() ◄───┘   captures the FSM …
                                         … NOT the dispatcher
                                         (it lives on the host)

  branch B ── restore(snap) ──►  FSM rolled back            ✓
                                 PromptDispatcher STILL          ✗
                                 "awaiting revive"  ◄─ leaked!

  ⇒ every command in branch B is eaten by the y/n handler
    → navigation dead → "53 / 140"   (a confident lie)

  fix: reset_session() re-derives host state from the world
       after every restore   →   "104 / 140"   (the truth)
```

The state vector was incomplete by exactly one machine, and the
search believed a number that machine had quietly falsified.

This is, precisely, the **incomplete-state-vector** failure that
model-checking theory warns about: *a search is only sound if its
state vector captures all transition-relevant state.* The
dispatcher influenced transitions (it intercepted commands) but
wasn't in the vector. In abstraction terms, the state abstraction
wasn't a bisimulation — it didn't preserve the transition
relation — so the explored graph was a fiction.

The remedy is the standard one: re-derive the out-of-vector state
from the world after every restore, exactly as a fresh session
would. One method (`reset_session`). Coverage jumped from 53 to
104 instantly. And the lesson became a *test*: the bisimulation
check above exists specifically so this class of bug fails loudly
the moment it appears, instead of hiding behind a confident wrong
number.

### The abstraction that didn't preserve the proposition

The liveness query failed the first time we ran it — and the
failure is a small classic.

`state_hash` — the dedup key, our state vector — was room +
inventory + NPC states. Deliberately *not* including score, lamp
battery, turn count: those are invariant-checked, and folding
them in would explode the graph without adding reachable rooms.
A good engineering call for reachability.

But winning is the transition `in_repository → won`, fired by
BLAST in the repository. It changes no room, no inventory, no NPC
state. So the *won* state hashed **identically** to the
pre-BLAST state. Breadth-first dedup saw the hash, declared the
state already visited, and never enqueued it. The goal was
invisible. `EF won` returned false not because you can't win, but
because the search couldn't *see* winning.

The principle: **a state abstraction adequate for one property is
not automatically adequate for another.** Our vector distinguished
the states that matter for *reachability* (where can you stand?)
but collapsed the states that matter for *liveness* (have you
won?). The fix is to make the vector distinguish the proposition
you're checking — add endgame phase to the hash. Crucially, that
*doesn't* change the reachability result (endgame is uniformly
"active" during normal play, so no new states appear), which the
cross-validation confirms. One abstraction, refined just enough to
preserve both propositions.

After the fix: `EF won` returns in six states with the witness
path `["blast"]` — the model checker handing back the winning
move.

---

## What we can and can't claim

Intellectual honesty is the price of citing this lineage, so:
this is **bounded, directed, RNG-sampled testing, not exhaustive
verification.** We approximate the formulas; we do not discharge
them.

- **Bounded.** A state cap means the search can stop short of the
  full frontier. We never enumerate the entire reachable set; we
  enumerate a large bounded prefix. This is bounded model checking
  (Biere et al.), with the usual caveat: absence of a
  counterexample within the bound is evidence, not proof.
- **Directed.** Breadth-first from a cold start reached only 16
  rooms — most of the cave sits behind a prerequisite chain the
  search can't thread within budget. We seed the search from deep
  milestone snapshots reached by scripted play, then explore
  locally. That's directed model checking (Edelkamp) and, in the
  RL idiom, exactly Go-Explore (Ecoffet et al., *Nature* 2021):
  archive interesting states, return, explore. We did not invent
  this; we applied it.

  ```text
  canonical_journey  (the scripted winning line — itself a DFA)
   AtRoad → LampLit → SnakeGone → … → BearReleased → … → Won
                                           │
                          ┌────────────────┘ extension journey
                          ▼   (≈15 commands: grow the beanstalk)
                     PlantHugeGrown ● ───► local BFS fan-out
                          │                 ▒ 26 88 92 93 94 ▒
                          │ extension journey
                          ▼   (oil the rusty door)
                     AtCanon91 ● ────────► local BFS fan-out
                                            ▒ 91 95 ▒

   ● a save_state() snapshot the search seeds from
   ▒ rooms the local BFS reaches that the canonical line never visits

   union of all fan-outs = the coverage measurement
  ```

  Each extension journey is a short bridge *through* a gate the
  cold BFS can't thread; from its snapshot the local search fans
  out cheaply. Adding a bridge is far cheaper than raising the
  global bound to brute-force the gate.
- **RNG-sampled.** The game has probabilistic transitions — a
  pirate that steals and relocates treasure, dark-pit rolls,
  probabilistic dispatch. We handle this two ways, both honest
  approximations: fix a seed (explore one resolution), or sweep
  seeds (sample the space). Proving completability under *all*
  luck would mean treating RNG as demonic nondeterminism and
  quantifying universally, or moving to a probabilistic model
  checker (PRISM; Kwiatkowska et al.). We swept seven seeds and
  the game stayed winnable under each — strong evidence,
  not a theorem.

And one structural honesty: a Frame program is not finite-state
in general — it carries data (inventories, counters). The
reachable space can be large. We get away with *concrete*
exploration (no abstraction at all) precisely because the game's
reachable space is modest and we direct the search. A system with
a genuinely enormous concrete state space would still need the
abstraction machinery we were lucky enough to skip. The Frame
dividend is real but it is not magic: it removes the
*extraction* cost, not the *state-explosion* cost.

---

## The dividend, and what it costs

Strip away the adventure game and the claim generalizes to any
Frame-native system:

> If your domain is composed of persistable Frame state machines,
> you get a model checker almost for free. The framework already
> provides the state vector (`save_state`), the transition
> relation (the dispatcher), and the atomic propositions (query
> methods). A ~150-line generic engine plus a ~10-method adapter
> gives you bounded reachability, safety-invariant checking,
> CTL goal-reachability with witnesses, and bisimulation-based
> restore-soundness — the apparatus that, on ordinary code, costs
> a research program to even set up.

The price is paid up front, in architecture: you have to write
your program as explicit, composable, persistable state machines.
Most code isn't written that way, which is exactly why the
extraction gap exists. Frame's bet is that paying that cost buys
you more than testability — it buys you a program that *is* its
own formal model. The verification dividend is one consequence.

The result we can stand behind: across this cave, every room is
reachable, every reachable state is invariant-clean, and the game
is winnable from every save-point under every roll of the dice we
sampled. We can say that with evidence and witnesses. Forty-some
commits ago, with a suite that was merely all-green, we couldn't
say it at all — and one of the things hiding under the green was a
verifier confidently reporting a number that a leaked prompt had
made a lie.

---

## References (for the real write-up)

- Kripke, *Semantical Considerations on Modal Logic*, 1963.
- Lamport, *Proving the Correctness of Multiprocess Programs*,
  1977.
- Cousot & Cousot, *Abstract Interpretation*, 1977.
- Milner, *A Calculus of Communicating Systems*, 1980; Park,
  *Concurrency and Automata on Infinite Sequences*, 1981
  (bisimulation).
- Clarke & Emerson, *Design and Synthesis of Synchronization
  Skeletons Using Branching-Time Temporal Logic*, 1981 (CTL).
- Alpern & Schneider, *Defining Liveness*, 1985.
- Clarke, Grumberg, Jha, Lu, Veith, *Counterexample-Guided
  Abstraction Refinement*, 2000.
- Biere, Cimatti, Clarke, Zhu, *Symbolic Model Checking without
  BDDs* (bounded model checking), 1999.
- Holzmann, *The SPIN Model Checker*, 2003.
- Ball & Rajamani (SLAM); Henzinger et al. (BLAST); Clarke,
  Kroening, Lerda (CBMC) — software model checking via model
  extraction.
- Kwiatkowska, Norman, Parker, *PRISM* (probabilistic model
  checking).
- Ecoffet, Huizinga, Lehman, Stanley, Clune, *First Return, Then
  Explore* (Go-Explore), *Nature*, 2021.

[Frame]: the state-machine notation the game is written in.
