# The Model-Extraction Gap, and a Program Born Without It

*On what you get for nearly free when your program is already a
labeled transition system. Worked example: a port of the 1977
Colossal Cave Adventure, built from composable Frame state
machines.*

-----

## The gap nobody talks about

Software model checking is one of the genuine triumphs of
computer science. Give a model checker a finite-state system and
a temporal-logic property, and it will either prove the property
holds on every execution or hand you a concrete counterexample
trace. Clarke, Emerson, and Sifakis shared the 2007 Turing Award
for it. SPIN has been verifying protocols since the late
'80s. The theory — Lamport's safety and liveness (1977), Clarke
and Emerson's CTL (1981), Milner's and Park's bisimulation
(1980-81) — is settled and beautiful.

And almost nobody runs it on their application code.

The reason isn't ignorance. It's that the hard part of software
model checking isn't the checking — it's getting from a pile of
imperative code to the **finite-state model** the checker needs.
That step is *model extraction*, and it is brutal. SLAM, BLAST,
and CBMC are entire research programs built around extracting
checkable models from C, using predicate abstraction (Ball &
Rajamani), lazy abstraction (Henzinger et al.), bounded
unrolling (Clarke, Kroening, Lerda), and counterexample-guided
abstraction refinement (Clarke, Grumberg, Jha, Lu, Veith, 2000)
to claw a tractable Kripke structure out of code that was never
written to expose one. Abstract interpretation (Cousot & Cousot,
1977) is the foundation, and it is *the* cost center. The
checking is cheap once you have the model. You almost never
have the model.

This is a story about a class of program that **hands you the
model for free** — because it was written as a transition system
in the first place — and what becomes possible once the
extraction gap is gone.

-----

## A brief detour: what Frame is

The system under test is written in [Frame], a small notation
for declaring explicit state machines that compile to ordinary
classes in 17 target languages (we use GDScript for Godot here).
Frame lives inside host source files; a `@@system` block declares
states and event handlers, and the framepiler expands it into a
plain class with no runtime dependency. A minimal example:

```frame
@@[target("python_3")]
@@system TrafficLight {
    interface:
        next()
    machine:
        $Green  { next() { -> $Yellow } }
        $Yellow { next() { -> $Red    } }
        $Red    { next() { -> $Green  } }
}
```

The relevant Frame feature for what follows is `@@[persist]`,
which adds two methods to the generated class — `save_state()`
returning an opaque blob, and `restore_state(blob)` mutating self
back to the saved configuration. Persistence serializes the
**compartment**: current state, state stack, state variables,
state args, enter/exit args, and domain variables. It explicitly
does *not* serialize transient call-time state (the context
stack, in-flight transitions). Saves are required to happen
between events, not mid-handler.

For a full introduction see the Frame docs: `frame_getting_started.md`,
`frame_quickstart.md`, `frame_runtime.md`, and the 111-recipe
`frame_cookbook.md`. The remainder of this article assumes only
"a Frame system is a state machine with a serializable
configuration."

-----

## Adventure as a bus of aspects

The system under test is a port of Colossal Cave Adventure (CCA):
140 rooms, ~190-word vocabulary, fifteen treasures, a snake, a
dragon, a bear, a troll, five dwarves, a pirate, the original's
catalogue of cruel little puzzles. It is built as a bus of
priority-ordered FSM "aspects" — Snake, Bear, Troll, Bottle,
CrystalBridge, Endgame, and so on — each an independent Frame
system, composed under one persistence envelope.

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
```

The priority order is load-bearing: `darkness` sits above `magic`
so XYZZY (one of the original game's magic words) can't silently
teleport you in a room you can't see; `score` sits at the bottom
so it records the *transformed* event ("you moved") rather than
the raw verb ("you typed XYZZY"). This is essentially a Mealy
chain: the dispatcher's output depends on both the state of each
aspect and the input event, and aspects further down the chain
see inputs already rewritten by aspects above.

-----

## A Frame program is a Kripke structure

Here is the observation the whole effort turns on.

A **Kripke structure** — the object a model checker consumes —
is, in informal terms, a labeled graph: nodes are program states,
edges are transitions caused by inputs, each node carries a tag
listing which atomic propositions are true there, and one node
(or a small set) is marked as the initial state. Formally
(Kripke, 1963), it is a tuple `(S, S₀, R, AP, L)`: a set of
states `S`, initial state(s) `S₀`, a transition relation `R ⊆ S × S`, a set of atomic propositions `AP`, and a labeling function
`L : S → 2^AP`. CTL and LTL formulas are interpreted over such
structures; a model checker is a decision procedure for "does
this structure satisfy this formula?"

A Frame program already *is* that tuple, concretely, at runtime:

|Kripke structure        |Frame program                                                                          |
|------------------------|---------------------------------------------------------------------------------------|
|state `s ∈ S`           |the composed FSM configuration                                                         |
|state vector            |`save_state()` → `PackedByteArray`                                                     |
|transition relation `R` |`process_input(command)`                                                               |
|enabled actions in `s`  |the affordance enumerator the game already has                                         |
|atomic propositions `AP`|the FSMs' own query methods (`player_room()`, `endgame_state()`, `snake.is_blocking()`)|
|labeling `L(s)`         |reading those query methods after restoring `s`                                        |
|initial state `s₀`      |the freshly-constructed root system                                                    |

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
*abstraction* of the state — it is the state, serialized, because
the Frame framework already needs serialization for save/load.
The transition relation isn't recovered by static analysis — it's
the dispatcher you ship. The atomic propositions aren't invented
by the verification engineer — they're the query methods the game
already exposes.

That collapses the model-extraction gap to nearly nothing. What's
left is a small, *domain-agnostic* engine and a thin per-domain
adapter.

-----

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
counterexample path. (Ours: a player carrying an item whose own
state machine thinks it's on the floor — caught on the first
run.)

**Liveness.** `reachable_satisfying(φ)` answers the CTL query
**EF φ** — "does some reachable state satisfy φ?" — and returns a
witness path. Point it at φ = *won* and it answers "can the
player still win from here?", which is the game-design property
of **softlock-freedom**. From every reachable save-point, the
strengthening **AG EF won** ("from anywhere reachable, victory
is still reachable") is the textbook non-deadlock /
reset-reachable formula. We compute bounded approximations of
both.

**Restore soundness.** `restore_soundness()` checks that
restoring to a state produces behavior indistinguishable from a
fresh instance at that state. Strictly speaking this is a
single-trace approximation of trace equivalence, not Milner/Park
bisimulation — bisimulation is a coinductive relation over all
transitions, and we sample one. But a mismatch on a single trace
falsifies the property loudly, which is what we need from a
soundness guard. The closely related literature on bisimulation
gives the right vocabulary for what the failure mode is when this
check fires: the state vector isn't a bisimulation quotient of
the underlying system.

The adapter for CCA is the punchline: ten methods, every one a
thin delegate. `save` is the FSM's own `save_state`.
`enumerate_actions` is the affordance list the game already
computes for its in-game prober. `state_hash` reads query
methods. Binding a 140-room adventure to a model checker took an
afternoon — *because the per-domain modeling work, which
dominates the literature, had been amortized into writing the
game as composable state machines in the first place.*

We cross-validated the generic engine against the hand-written,
CCA-specific search it replaced: identical reachable-room count,
identical zero violations, at the same bound and seed. The
generality cost nothing in fidelity.

-----

## Two bugs, and the theory that names them

The interesting part of building a verifier is the moments it
lies to you. Both of ours map exactly onto known failure modes.

### The incomplete state vector

The reachability search reported it could reach **53 of 140
rooms** and called that a pass. The number was false.

The search reuses one driver object across thousands of
branches, rolling the FSM back at each branch point with
save/restore. But the driver carries one piece of state
*outside* the FSM's save-state: a modal prompt dispatcher — the
little machine that handles "are you sure? (y/n)", including the
death-and-revive prompt. It was deliberately not composed onto
the game's persistence envelope (a documented design choice:
transient modal interaction state shouldn't survive a save/load
boundary).

So when any branch killed the player, the dispatcher entered
"awaiting revive answer." Save/restore rolled the *FSM* back —
but not the dispatcher. Every subsequent branch inherited a
stuck prompt, and the modal handler ate every command that
wasn't "yes" or "no." Navigation silently broke across most of
the search tree. The "53" was an artifact of a leaked prompt,
not a fact about the game.

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

This is, precisely, the **incomplete-state-vector** failure
that model-checking theory warns about: *a search is only sound
if its state vector captures all transition-relevant state.* The
dispatcher influenced transitions (it intercepted commands) but
wasn't in the vector. In abstraction terms, the state
abstraction wasn't a bisimulation — it didn't preserve the
transition relation — so the explored graph was a fiction.

The remedy is the standard one: re-derive the out-of-vector
state from the world after every restore, exactly as a fresh
session would. One method (`reset_session`). Coverage jumped
from 53 to 104 instantly. And the lesson became a *test*: the
restore-soundness check above exists specifically so this class
of bug fails loudly the moment it appears, instead of hiding
behind a confident wrong number.

### The abstraction that didn't preserve the proposition

The liveness query failed the first time we ran it — and the
failure is a small classic.

`state_hash` — the dedup key, our state vector for BFS — was
room + inventory + NPC states. Deliberately *not* including
score, lamp battery, turn count: those are invariant-checked, and
folding them in would explode the graph without adding reachable
rooms. A good engineering call for reachability.

But winning is the transition `in_repository → won`, fired by
BLAST in the repository. It changes no room, no inventory, no NPC
state. So the *won* state hashed **identically** to the
pre-BLAST state. Breadth-first dedup saw the hash, declared the
state already visited, and never enqueued it. The goal was
invisible. `EF won` returned false not because you can't win,
but because the search couldn't *see* winning.

The principle: **a state abstraction adequate for one property
is not automatically adequate for another.** Our vector
distinguished the states that matter for *reachability* (where
can you stand?) but collapsed the states that matter for
*liveness* (have you won?). The fix is to make the vector
distinguish the proposition you're checking — add endgame phase
to the hash. Crucially, that *doesn't* change the reachability
result (endgame is uniformly "active" during normal play, so no
new states appear), which the cross-validation confirms. One
abstraction, refined just enough to preserve both propositions.

After the fix: `EF won` returns in six states with the witness
path `["blast"]` — the model checker handing back the winning
move.

-----

## What we can and can't claim

This is **bounded, directed, RNG-sampled testing, not
exhaustive verification.** We approximate the formulas; we do
not discharge them.

- **Bounded.** A state cap means the search can stop short of
  the full frontier. We never enumerate the entire reachable
  set; we enumerate a large bounded prefix. This is bounded
  model checking (Biere et al.), with the usual caveat: absence
  of a counterexample within the bound is evidence, not proof.
- **Directed.** Breadth-first from a cold start reached only 16
  rooms — most of the cave sits behind a prerequisite chain the
  search can't thread within budget. We seed the search from
  deep milestone snapshots reached by scripted play, then
  explore locally. That's directed model checking (Edelkamp) and,
  in the RL idiom, exactly Go-Explore (Ecoffet et al., *Nature*
  2021): archive interesting states, return, explore. We did not
  invent this; we applied it.

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
  checker (PRISM; Kwiatkowska et al.) — which would be the
  principled answer and which we don't use. We swept seven seeds
  and the game stayed winnable under each: strong evidence, not
  a theorem.

And one structural honesty: a Frame program is not finite-state
in general — it carries data (inventories, counters). The
reachable space can be large. We get away with *concrete*
exploration (no abstraction at all) precisely because the game's
reachable space is modest and we direct the search. A system
with a genuinely enormous concrete state space would still need
the abstraction machinery we were lucky enough to skip. The
Frame dividend is real but it is not magic: it removes the
*extraction* cost, not the *state-explosion* cost.

-----

## Sizing the artifact, and prior art

The natural comparison for CCA-as-Frame is to other text
adventures handled by model checkers. To our knowledge the
closest prior work is Lester's *Solving Interactive Fiction Games
via Partial Evaluation and Bounded Model Checking* (arXiv
2012.15365, 2020), which uses CBMC on Scott Adams adventures
from the late 1970s — Adventureland and a few others, each
roughly 30 rooms with a small entity model. Lester's central
finding is that "off-the-shelf model-checking tools are unable
to handle the games in their original form" and that
substantial program transformation (partial evaluation across
the games' scripting interpreter) is required to recover a
checkable model. That is exactly the model-extraction work this
article doesn't do — because the modeling investment was paid
when the game was authored as a composition of explicit Frame
machines rather than as imperative C.

Hasegawa & Yokogawa's *Formal Verification for Node-Based Visual
Scripts Using Symbolic Model Checking* (arXiv 2103.11618, 2021)
makes a kindred point in a different setting: Final Fantasy XV's
visual scripts are essentially state machines, and translating
them into NuSMV's input language found bugs at production scale.
Same thesis as ours — state-machine-shaped game logic is
naturally amenable to symbolic verification — different
language, different game, different tooling.

By the rooms-and-vocabulary measure, CCA is larger than the
games Lester handled (140 rooms versus ~30; ~190-word vocabulary
versus ~120; six autonomous NPC machines versus one or two).
The longest prerequisite chain (lamp → bird → snake → … →
endgame) is roughly 20 puzzle steps deep. By raw lines-of-code
measure the artifact is smaller than the protocol-stack and
scientific-code targets typical of the broader software model
checking literature (e.g., BLAST on ~30 KLOC of C, the BlobFlow
case study on ~10 KLOC of MPI). What CCA exercises is
prerequisite-chain depth and entity coupling, not LOC bulk.

-----

## The dividend, and what it costs

Strip away the adventure game and the claim generalizes to any
Frame-native system in a particular regime:

> If your domain is composed of persistable Frame state machines
> over a discrete, bounded event space, you get a model checker
> almost for free. The framework already provides the state
> vector (`save_state`), the transition relation (the
> dispatcher), and the atomic propositions (query methods). A
> ~150-line generic engine plus a ~10-method adapter gives you
> bounded reachability, safety-invariant checking, CTL
> goal-reachability with witnesses, and a sampling-based
> restore-soundness check — the apparatus that, on ordinary
> code, costs a research program to even set up.

Scope conditions matter. This dividend pays for: discrete-event
interactive systems with bounded reachable state, written as
composed state machines, with serializable configuration. It
does not, at least not without further work, pay for: real-time
properties, deep arithmetic constraints, large continuous state,
or genuinely distributed/concurrent systems. The Frame envelope
is a particular architectural commitment, and the verification
dividend is the payoff for that commitment — not a universal
fact about state machines.

The price is paid up front, in architecture: you have to write
your program as explicit, composable, persistable state machines.
Most code isn't written that way, which is exactly why the
extraction gap exists.

The result we can stand behind, with the caveats above: across
this cave, every room is reachable, every reachable state is
invariant-clean, and the game is winnable from every save-point
under every roll of the dice we sampled. We can say that with
evidence and witnesses. Forty-some commits ago, with a suite
that was merely all-green, we couldn't say it at all — and one
of the things hiding under the green was a verifier confidently
reporting a number that a leaked prompt had made a lie.

**The program is its own formal model.** That is the architecture
bet Frame is making, and the verification dividend is one
consequence of that bet.

-----

## References

- Alpern, B., & Schneider, F. B. (1985). Defining liveness.
  *Information Processing Letters*, 21(4), 181–185.
- Biere, A., Cimatti, A., Clarke, E., & Zhu, Y. (1999).
  Symbolic model checking without BDDs. *TACAS*.
- Clarke, E., & Emerson, E. A. (1981). Design and synthesis of
  synchronization skeletons using branching-time temporal logic.
  *Workshop on Logic of Programs*.
- Clarke, E., Grumberg, O., Jha, S., Lu, Y., & Veith, H. (2000).
  Counterexample-guided abstraction refinement. *CAV*.
- Cousot, P., & Cousot, R. (1977). Abstract interpretation: A
  unified lattice model for static analysis of programs by
  construction or approximation of fixpoints. *POPL*.
- Ecoffet, A., Huizinga, J., Lehman, J., Stanley, K., & Clune, J.
  (2021). First return, then explore. *Nature*, 590, 580–586.
- Edelkamp, S., et al. *Directed model checking* (survey and
  monograph literature).
- Hasegawa, I., & Yokogawa, T. (2021). Formal verification for
  node-based visual scripts using symbolic model checking. arXiv
  2103.11618.
- Henzinger, T. A., Jhala, R., Majumdar, R., & Sutre, G.
  (2002). Lazy abstraction. *POPL*. (BLAST.)
- Holzmann, G. J. (2003). *The SPIN Model Checker: Primer and
  Reference Manual.*
- Kripke, S. A. (1963). Semantical considerations on modal logic.
  *Acta Philosophica Fennica*, 16, 83–94.
- Kwiatkowska, M., Norman, G., & Parker, D. (2011). PRISM 4.0:
  Verification of probabilistic real-time systems. *CAV*.
- Lamport, L. (1977). Proving the correctness of multiprocess
  programs. *IEEE Trans. Software Engineering*, SE-3(2),
  125–143.
- Lester, M. M. (2020). Solving interactive fiction games via
  partial evaluation and bounded model checking. arXiv
  2012.15365.
- Milner, R. (1980). *A Calculus of Communicating Systems.*
  Springer LNCS 92.
- Park, D. (1981). Concurrency and automata on infinite
  sequences. *5th GI-Conference on Theoretical Computer Science.*
- (CBMC) Clarke, E., Kroening, D., & Lerda, F. (2004). A tool
  for checking ANSI-C programs. *TACAS*.
- (SLAM) Ball, T., & Rajamani, S. K. (2002). The SLAM project:
  Debugging system software via static analysis. *POPL*.

[Frame]: https://github.com/frame-lang/framec — state-machine
notation; for documentation see the `frame_getting_started`,
`frame_language`, `frame_quickstart`, `frame_runtime`, and
`frame_cookbook` documents in the project.
