<!-- ============================================================ -->
<!-- TEMPORARY REVIEW DOC — DELETE BEFORE COMMITTING.             -->
<!-- The clean article lives in article-gamedev-draft.md.         -->
<!-- This file = critique + fixes applied + the full revised text -->
<!-- in one place for review. Not intended for the repo history.  -->
<!-- ============================================================ -->

# Review: "Catching Softlocks Before Your Players Do"

## Verdict

Stronger of the two articles for its audience. The softlock hook is
visceral where the model-extraction framing isn't; it drops "Kripke
structure" entirely, leads with pain, and lands the value prop where a
game dev feels it. The "what this catches that ordinary tests don't"
section is the best paragraph in either piece. Pacing is good, the
limits section has integrity, the "three currencies" close is clean.
Ship-worthy after the one real fix below.

## Fixes applied (in article-gamedev-draft.md)

1. **persist / Bug-1 contradiction (the important one).** The primer
   originally said `save_state()` captures "owned sub-systems, the
   lot," which a careful reader would find contradicted forty lines
   later by Bug 1 (a held machine that was NOT captured). Rewrote the
   `@@[persist]` bullet to: captures "the sub-systems composed onto its
   persistence envelope. The qualifier matters: a machine the game
   holds *outside* that envelope won't be captured by the save. Hold
   that thought — it's the first bug." Now the primer *sets up* Bug 1
   instead of contradicting it.

2. **Frame URL inconsistency.** Early inline link was
   `github.com/frame-lang/framec`; Further-reading said `frame-lang.org`.
   Reconciled: kept the inline framec link, and rewrote the
   Further-reading entry to name both without contradiction — "Project
   home: frame-lang.org; the framepiler (compiler) lives at
   github.com/frame-lang/framec."

3. **"Every save slot is winnable" overclaim.** Bolded bullet now reads
   "Every save state the search reaches is winnable," with a
   parenthetical that we run it from a curated milestone set, not
   literally every slot. The follow-on "headline" sentence reworded
   from "*Every save slot is winnable*" to "*Is this save winnable?*"
   so the bold claim matches the work. The limits section already
   hedged it; this aligns the early framing.

4. **Cosmetic.** "State machines, briefly" numbered list was `1./1./1.`
   — changed to explicit `1./2./3.`

## Open items for you to confirm (NOT changed — need your knowledge)

- **Cookbook specifics.** "111 recipes" and the references to
  "state-stack and HSM examples" — I kept your "111-recipe" figure but
  *dropped* the specific "pattern 29 (Game Level Manager)" claim from
  the Further-reading section because I can't verify the recipe's
  number/name. If pattern 29 is real, add it back — it's a credible,
  concrete pointer. If unsure, the generic "state-stack and HSM
  examples" phrasing I left is safe.
- **frame-lang.org** — confirm it's live. If it isn't yet, drop it and
  use only the framec repo URL.
- **"every room is reachable"** in the close still elides the 134-by-
  search + 6-transient-prose split. Left as-is (acceptable
  simplification for this audience, and the limits section covers
  "with these milestones"). Flag if you want it hedged.

## What I deliberately did NOT touch

- The market-flavored lines ("worst Steam reviews," "ten days") — right
  register for this audience; wrong for the researcher sibling.
- The simplified aspect-bus diagram (annotations, no consume/transform
  arrows) — correct call for game devs.
- Dropping the formal Kripke tuple — correct.

---
---

# REVISED ARTICLE TEXT (clean copy is article-gamedev-draft.md)

# Catching Softlocks Before Your Players Do

*How writing your game as composable state machines lets a small
amount of generic code walk the whole reachable game and tell you
where it can get stuck. A worked example on a port of the 1977
Colossal Cave Adventure.*

-----

## The bug class

Every nontrivial adventure or puzzle game ships with at least one
of these:

- A door you can lock with the only key on the other side.
- A potion you can drink in a room you needed it to leave.
- A bridge that collapses before you've fetched the item on the
  far side.
- A save slot at minute 47 of a 50-minute sequence where, it
  turns out, the boss can't actually be defeated without an item
  you can no longer get.

The technical name is a **softlock**: the game keeps running, the
player keeps having input, but the win condition is unreachable.
There is no crash to put in a stack trace. The QA report is a
two-thousand-word forum post titled "stuck after [spoiler]" and
the verdict from the lead designer is some variant of *I have
no idea how they got there.*

The reason softlocks are nasty isn't that they're hard to fix
once found. It's that **finding** them is hard. You can't test
for "the win condition is reachable from this state" with a
fixture that calls one function. You have to *get to* the state,
and then *try* to win, and then know that you failed because the
state was bad and not because you played badly. Multiply by every
state a player can save in, and you have a search problem.

This article is about doing that search automatically. Not as an
exotic verification project — as a regression test that runs in
CI. The trick is that we got it for cheap, because the game was
already written as a set of state machines, and a state machine
is exactly the object an automated search wants.

We'll build the idea up in stages: what a state machine is, what
makes one "checkable," what Frame is doing to keep the game in
that shape, what the search algorithm looks like, what bugs it
caught us in, and what its limits are.

-----

## State machines, briefly

A **state machine** (or **finite-state machine**, FSM) is the
simplest computational model that's still interesting enough to
hold a game in. It's three things:

1. A finite set of named **states** — `Idle`, `Walking`,
   `Jumping`, `InDialogue`, whatever your game cares about.
2. A set of **events** that can happen — player input, timer
   ticks, NPC interactions.
3. A **transition table** that says, for each state, what each
   event does — sometimes it changes the state, sometimes it
   triggers a side effect, sometimes it's ignored.

Game programmers reinvent this constantly. The character
controller with `if (state == "jumping") return;` scattered
through it is a state machine. The dialogue tree with a giant
switch on the current node is a state machine. The save-load
system that has to know whether you're in a cutscene is dealing
with state-machine semantics.

The technical observation that drives everything below is this:
*if your code is a state machine, an automated tool can walk
every state and event combination and tell you things you
couldn't possibly know by hand.* The catch is that most
production code isn't a state machine — it's a tangle of
conditionals where the state machine is *implicit*. The states
are encoded in scattered booleans; the transitions are buried in
function bodies. There's a state machine in there, but you can't
get a tool to read it.

This is the problem [Frame](https://github.com/frame-lang/framec) is built to solve.

-----

## Frame, in one snippet

Frame is a small notation for declaring state machines explicitly.
You write a `@@system` block that lists states and event handlers,
and a tool called the framepiler expands it into ordinary code in
your target language (it supports 17, including GDScript,
TypeScript, C#, Python, and Rust). The generated code is a plain
class with no runtime dependency — you can read it, debug it, ship
it.

The world's smallest example:

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

States are the things prefixed with `$`. `interface:` lists the
events the machine accepts. Each handler optionally does some
work and ends with a transition. The arrow `->` means "go to."
That's it for the core syntax.

There are two Frame features that matter for what follows:

- **Composition.** You can have many systems in one program, and
  a system can hold references to other systems as ordinary
  fields. A 140-room adventure game ends up as a tree of
  systems: the top-level `Adventure`, owning a set of "aspect"
  systems (`Snake`, `Bear`, `Bottle`, `Endgame`, …), each its
  own state machine.
- **`@@[persist]`.** Annotate a system with this and Frame emits
  two methods, `save_state()` and `restore_state(blob)`, that
  serialize and restore its compartment — current state, state
  variables, and the sub-systems composed onto its persistence
  envelope. The qualifier matters: a machine the game holds
  *outside* that envelope won't be captured by the save. Hold
  that thought — it's the first bug. This is the feature
  originally built so games could save and load; it will turn
  out to be exactly what an automated search needs.

For a tour see `frame_getting_started.md` and the 111-recipe
`frame_cookbook.md`. For our purposes you only need: *Frame makes
each state machine an inspectable, copy-able value.*

-----

## Adventure as a bus of aspects

The system under test is a port of Colossal Cave Adventure (CCA),
the 1977 Crowther/Woods original. 140 rooms, ~190 vocabulary
words, fifteen treasures, a snake, a bear, a dragon, a troll,
five dwarves, a pirate. Every cruel puzzle from the original is
in here.

The way the game is organized: every player command goes through
a priority-ordered chain of small state machines, each
responsible for one cross-cutting concern. The chain looks like
this:

```text
 player types:  "xyzzy"
                   │
                   ▼
   ┌──────────────────────────────────────────────────┐
   │ Adventure.do_command(verb, noun)                  │
   │ event = {verb, noun, room, is_dark, lamp_lit, …}  │
   └──────────────────────────────────────────────────┘
                   │
   priority        ▼
    700  ──►  ┌──────────┐  darkness gates info verbs in the dark
              │ darkness │
              └──────────┘
    500  ──►  ┌──────────┐  magic rewrites "xyzzy" → "move 33"
              │  magic   │
              └──────────┘
    400  ──►  ┌──────────┐  backpack blocks "take" when pack is full
              │ backpack │
              └──────────┘
    100  ──►  ┌──────────┐  score observes the resulting motion
              │  score   │
              └──────────┘
                   │
                   ▼
   ┌──────────────────────────────────────────────────┐
   │ base FSM verb handling — _verb_move, _verb_take…  │
   └──────────────────────────────────────────────────┘
```

Each aspect can do one of three things to the command: **consume**
it (handle it, stop the chain), **transform** it (rewrite and
pass down — XYZZY becomes "move 33"), or pass it untouched.

The priority order matters. Darkness sits above Magic so XYZZY
can't teleport you in a room you can't see. Score sits below
everything so it counts the *real* motion, not the typed word.

The whole tree — the top-level `Adventure`, the aspects, the
endgame, the NPCs — is one big composed state machine. Save it
and you've saved the game. Restore it and you're back exactly
where you were.

That last sentence is what makes everything that follows
possible.

-----

## What "checkable" actually means

Here's the move. A game where the entire reachable state is
captured by `save_state()` is a game we can walk.

Imagine the simplest possible search:

```text
visited = { initial_state_hash }
queue   = [ initial_state ]

while queue not empty:
    state = queue.pop()
    for command in legal_commands(state):
        restore(state)
        apply(command)
        new_state = save()
        h = hash(new_state)
        if h not in visited:
            visited.add(h)
            queue.append(new_state)
```

That's breadth-first search over the game's state graph. Every
state we can reach by any sequence of commands ends up in
`visited`, every transition is exercised, every reachable room is
visited.

A few things are quietly load-bearing here:

- `save()` has to capture **everything** that matters for what
  happens next. Anything left out is a state-shaped variable the
  search doesn't see, and the search will silently get the wrong
  answer. (We'll come back to this — it's the first bug.)
- `legal_commands(state)` has to enumerate what a player could
  actually do. The game already needs this (for tab-completion,
  auto-prober, or just hint systems), so we get it for free.
- The hash has to **distinguish states that matter for the
  property you're checking**. A hash too coarse merges states
  that should be different; a hash too fine explodes the
  search. (This is the second bug. Spoiler.)

Once you have this loop, properties of interest become almost
embarrassingly simple to express:

- **Every room is reachable.** Walk the graph; count rooms
  visited.
- **No invariant ever violates.** At each state, evaluate
  predicates like "the inventory matches the world's record of
  what the player is holding" or "the lamp battery is
  non-negative." If any predicate ever fails, dump the path that
  got there.
- **Every save state the search reaches is winnable.** From each
  save-shaped state, attempt a (bounded) search for any state
  where `won == true`. Find one and the slot is safe; fail to,
  and that save is a potential softlock. (In practice we run
  this from a curated set of milestone states rather than
  literally every save slot — see the limits.)

That last one is the headline. *Is this save winnable?* is not a
property you can test with a unit test. It's a property about the
game's graph. And once the game is a state machine you can walk,
it's a property you can test in CI.

-----

## What we built

We wrote a checker — `FrameStateChecker` — that knows nothing
about adventure games. It's about 150 lines of generic search
code talking to a ten-method **adapter** that knows how to
construct, save, restore, enumerate actions, apply commands, and
read a few predicates from any Frame domain. Binding it to CCA
was an afternoon: every adapter method is a thin delegate to
something the game already had.

This isn't research-grade verification — it's a regression test
that catches a class of bug nothing else catches. What it gives
you:

- **Reachability map.** A list of every room the search could
  get to from a given starting state. Compare against the static
  map; rooms missing are either intentionally gated (good) or
  accidentally orphaned (bug).
- **Invariant checker.** Every game logic invariant you can
  write as a predicate gets evaluated at every state the search
  visits. A violation comes back with the exact command sequence
  that produced it.
- **Win-from-here.** Pick any save state, ask "is `won == true`
  still reachable from here?" Within a state budget, you get
  either a witness sequence (commands that win from this state)
  or evidence that no such sequence was found.

This is the workflow that pays off in practice. You ship a patch
that nerfs the bear. Did anything stop being winnable? Run the
checker. You add a one-way door for narrative reasons. Did you
accidentally orphan the room behind it? Run the checker. You
introduce a new endgame puzzle. Does the puzzle have a solution
from every save slot a player can reach it from? Run the checker.

It's not a proof. It's a test that walks more of your game in
ten minutes than a human can play in ten days.

-----

## Two bugs the checker found in itself

Building the checker taught us more about the game than running
it did — because both times we trusted it, it was lying. Both
lies map onto well-known pitfalls in this kind of search.

### Bug 1: The leak

The first reachability run reported **53 of 140 rooms** reachable.
That number was wrong.

The checker reuses one driver object across thousands of search
branches, rolling the FSM back at each branch with save/restore.
That driver carries one thing the FSM doesn't: a small modal
prompt dispatcher — the machine that handles "Are you sure?
(y/n)" and the death-and-revive prompt. It deliberately wasn't
included in the game's persistence envelope, because modal
interaction state shouldn't survive a save/load.

So when a search branch killed the player, the dispatcher
entered "awaiting revive answer." Save/restore rolled the *FSM*
back — but not the dispatcher. The next branch started with a
ghost prompt that ate every command that wasn't "yes" or
"no." Navigation silently broke across most of the search tree.

```text
  one reused driver, walking the search tree:

  branch A ── kill player ──►  PromptDispatcher = "awaiting revive"
                                     │
                    save_state() ◄───┘   captures the FSM …
                                         … NOT the dispatcher

  branch B ── restore(snap) ──►  FSM rolled back            ✓
                                 PromptDispatcher STILL          ✗
                                 "awaiting revive"  ◄─ leaked!

  ⇒ every command in branch B is eaten by the y/n handler
  ⇒ navigation dies → "53 / 140 rooms"   (a confident lie)
```

The lesson generalizes: **if your state vector misses anything
that affects what happens next, your search is enumerating a
fiction.** The fix was a one-line `reset_session()` that
re-derives the host's state from the world after every restore.
Coverage jumped from 53 to 104 instantly.

And we now have a soundness check that runs alongside every
search: take a state, save it, restore it into a fresh checker,
play out a sequence of commands, compare the outputs to the
sequence played on the live checker. If they diverge, the state
vector is incomplete — and now we *know*, instead of having to
trust a number. (Strictly, this is a single-trace sample of
"behavioral equivalence." A full proof of equivalence would mean
checking *all* sequences, which is intractable. But a single
mismatch fails loudly, which is what we need.)

### Bug 2: The hash that hid the win

The win-from-here check failed the first time we ran it. It
shouldn't have — we knew the canonical solve worked, we'd watched
it.

Here's what was happening. The search hash — the key the
breadth-first loop uses to decide "have I seen this state
before?" — was room + inventory + NPC states. We deliberately
left score, lamp battery, and turn count out, because folding
them in would explode the graph without adding any new
reachable *rooms*. For finding rooms, that hash is correct.

But winning is the transition from *in_repository* to *won*,
fired by BLAST in the repository. It doesn't change the room. It
doesn't change inventory. It doesn't change NPC state. So the
*won* state hashed **identically** to the pre-BLAST state — the
search saw the hash, declared the state already visited, and
never enqueued it. The win condition was structurally invisible
to the search.

The fix: add the endgame phase to the hash. Now the search can
tell `pre_blast` from `won` and finds the win in six states.
Adding endgame phase doesn't add new states to the reachability
graph either (endgame is uniformly "active" during normal play),
which we confirmed by cross-checking room counts before and
after.

The lesson, also general: **what you hide in your state hash is
what your checker can't see.** Different properties need
different hashes. A reachability checker can fold lots of stuff
together; a win-condition checker has to keep enough to
distinguish "won" from "not won." There isn't one right answer —
there's an answer per question.

-----

## What this catches that ordinary tests don't

To make the value proposition concrete:

- **A scripted unit test** can verify that one command sequence
  works. It can't tell you the bear puzzle is solvable from
  every save state that reaches it.
- **A playtest** covers what the playtester thinks to do. The
  bug class that ruins playtests is the corner the playtester
  didn't think to walk into — usually because the playtester is
  trying to *win*, not trying to *get stuck*.
- **An exhaustive playthrough** covers one path. The checker
  covers a bounded prefix of the entire tree of paths.
- **A static analyzer** can tell you about type errors and dead
  branches. It can't tell you that an interactive puzzle has no
  solution from a particular world configuration.

The thing the checker catches is the thing that's neither a
crash nor an obvious wrong behavior — it's a **state in which a
correct game has no good move.** That's exactly the bug class
softlocks belong to, and exactly the bug class that's most
expensive to find by hand.

-----

## Honest about the limits

The checker is not a proof. Here's what it does and doesn't tell
you, in plain terms.

- **It's bounded.** We cap the search at some number of states.
  If a softlock exists more than that many moves deep, we won't
  see it. The cap is a tuning knob, not a guarantee.
- **It needs help reaching the deep parts.** A pure
  breadth-first search from the start of CCA only reaches 16
  rooms — most of the cave is gated behind prerequisite chains
  (lamp, bird, snake, …) that the search can't thread within
  budget. We supplement with **scripted journeys** that walk
  the canonical solve up to interesting milestones; from each
  milestone the search fans out locally. This is the
  "Go-Explore" pattern from Ecoffet et al. (2021, *Nature*) —
  archive interesting states, return to them, explore. Works
  beautifully for reaching the corners. Means the coverage
  numbers should be read as "with these milestones, we reach X
  rooms," not "the game reaches X rooms."

  ```text
   canonical solve ──┬──► milestone (snapshot) ──► local BFS
                     ├──► milestone (snapshot) ──► local BFS
                     └──► milestone (snapshot) ──► local BFS

   union of local BFS results = what we report as coverage
  ```
- **It samples randomness.** CCA has a pirate that randomly
  steals treasure and a dark-pit roll. We pick a few RNG seeds
  and sweep them. A real proof would treat the RNG as adversarial
  (the worst luck the player could have); we don't. We swept
  seven seeds and the game stayed winnable under each. That's
  evidence, not a theorem.
- **It needs the game to be in this shape.** If your game isn't
  state-machine-structured — if it's a 6,000-line `tick()`
  function with state stored in twenty booleans — the checker
  doesn't have anything to grab onto. The reason it works on
  this game is that the game was built as composed state
  machines from the start. The verification dividend is the
  payoff for an *architectural* commitment, not a bolt-on.

That last point is the honest answer to "could we use this on
[other game]?" If the answer is yes, you've probably already
written your game with explicit state, explicit transitions, and
serializable configuration — and you have most of what's needed.
If the answer is "we have to refactor the entire input handler
first," the checker isn't going to land cheaply.

-----

## What it's worth

What we can say after running the checker: across this cave,
every room is reachable, every reachable state passes every
invariant we know how to write, and the game is winnable from
every save-point we've reached, under every RNG seed we tried.
That's not a proof. It's substantially more than we could say a
few weeks ago, when our test suite was all-green and one of the
things hiding under the green was a search reporting "53 / 140"
because a stuck prompt had quietly killed half the runs.

The architectural commitment — write the game as composed,
persistable state machines — paid us back in three currencies.
First, the game has a smaller bug surface than the imperative
equivalent would. Second, the save/load system was almost free
because persistence is a framework feature. Third, the checker
was *also* almost free because the framework already serves up
exactly what a state-space search wants.

If you build games that exhibit the softlock bug class — and most
nontrivial games do — and you're not currently doing this kind of
checking, the cost-benefit is unusually good. The "build" cost
is mostly the architectural commitment. The "run" cost is a
small generic engine plus a thin adapter. The payoff is catching
the class of bug that ruins playtests, gets the worst Steam
reviews, and is most painful to debug after the game has shipped.

-----

## Further reading

- **Frame.** The state-machine notation the game is written in.
  Project home: frame-lang.org; the framepiler (compiler) lives
  at github.com/frame-lang/framec. Start with
  `frame_getting_started.md` and `frame_cookbook.md` — the 111
  recipes there are short and runnable; the state-stack and HSM
  examples are directly relevant to game logic.
- **Closest prior work on text adventures.** Lester (2020),
  *Solving Interactive Fiction Games via Partial Evaluation and
  Bounded Model Checking* (arXiv 2012.15365). Uses CBMC on Scott
  Adams adventures from the late 1970s. The contrast is
  instructive: Lester has to do substantial program
  transformation to recover a checkable model from imperative C,
  because the games weren't written as state machines. We didn't
  have to, because ours was.
- **Closest prior work on commercial games.** Hasegawa &
  Yokogawa (2021), *Formal Verification for Node-Based Visual
  Scripts Using Symbolic Model Checking* (arXiv 2103.11618), a
  Square Enix paper on FFXV's visual scripts. Same general
  thesis: state-machine-shaped game logic is checkable.
- **The exploration technique.** Ecoffet et al. (2021), *First
  Return, Then Explore* (Go-Explore), *Nature* 590:580–586. The
  archive-and-fan-out pattern we use to reach deep states.
- **The textbook on the underlying technique.** Clarke,
  Grumberg, Peled — *Model Checking* (MIT Press). If you want
  the formal apparatus the checker is approximating, this is
  the standard reference.
