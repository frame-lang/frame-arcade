# Every Tool We Built to Measure the Game Found a Bug

*Draft — an engineering write-up on testing a port of the 1977
Colossal Cave Adventure to completion.*

---

## The setup

Colossal Cave Adventure — Crowther and Woods, 1977 — is 140 rooms,
15 treasures, a handful of NPCs (a snake, a dragon, a bear, a
troll, five dwarves, a pirate), and a fistful of cruel little
puzzles. We ported it to a Frame-generated state-machine
architecture running under Godot. The port had a test suite that
was, by any normal standard, thorough: ~65 tests, all green,
covering every puzzle, every NPC state transition, every canon
message.

It was also quietly broken in ways no green test could see.

This is the story of the layers of test infrastructure we built
on top of that suite, and a pattern that held with uncomfortable
consistency: **every time we built a new tool to measure the
system, the tool found a bug the existing suite was tolerating.**
Until, eventually, they didn't — and learning to recognize *that*
inflection turned out to be as important as any single bug.

---

## Three kinds of question

You can ask three fundamentally different questions about a
finite adventure game:

1. **Reachability** — can the player get to room X / state X?
2. **Safety** — does any reachable state violate an invariant
   (negative score, room out of range, an item in two places at
   once)?
3. **Liveness** — from state X, can the player still *win*?

The original 65-test suite answered none of these at the level of
the *whole reachable state space*. It answered "does this specific
mechanic behave correctly when I set it up by hand," which is
valuable but local. It walked exactly one path through the game —
the canonical happy path — and checked specific puzzles from
teleported start states. Neither asks "is there *any* sequence of
commands from the start that breaks an invariant?"

That gap is where the work began.

---

## Arc 1 — Reachability and safety: state-space BFS

The first idea was a breadth-first search over the reachable state
graph. Start at the canonical opening, enumerate every reachable
state by feeding real commands through the real parser and
dispatcher, and assert invariants at each one: room in [1,140],
score above a sanity floor, lamp battery in range, deposit count
consistent, every "carried" item agreeing between the player's
inventory and the item's own state machine.

The first run found a bug immediately — an inventory inconsistency
on death, where the player's carried-items list and the item state
machines disagreed after a fatal pit-fall. The BFS had proved the
gap was real on its first outing.

But the cold-start BFS hit a wall: it could only reach **16 of 140
rooms**. Most of the cave sits behind a chain of prerequisites —
unlock the grate, light the lamp, navigate a nontrivial maze — that
breadth-first action ordering can't punch through within any
reasonable state cap. The search was sound but shallow.

---

## Arc 2 — Seeding the search: milestone snapshots

If BFS can't *reach* the deep cave from a cold start, give it a
running start. Walk the canonical journey to a milestone — "lamp
lit, past the grate" — snapshot the full FSM state, and run the
BFS *from that snapshot*. Coverage at the LampLit milestone jumped
to 30 rooms; at deeper milestones (snake gone, dragon dead, bear
released) it kept climbing.

This arc is also where the test infrastructure started biting
*itself*. Six of the milestone-seeded test harnesses called
`wake_dwarves()` during setup — which woke the dwarves from turn
one, so they actively blocked the very commands the journey was
trying to execute. The snapshots were captured at the wrong
states. The fix was a one-line flag (`dwarves_auto_woken = true`,
which short-circuits the auto-wake counter rather than triggering
it). The bug was in the *measurement*, not the game — a theme that
would recur.

---

## Arc 3 — The convergence loop

The deep insight of the third arc: BFS coverage is *asymptotic*.
A single seed, no matter how deep, can't penetrate every gated
region within a sane cap — the search fans out and exhausts its
budget before threading every needle. Raising the cap is
exponentially expensive for linear coverage gains.

So instead of pushing one search harder, we built a **tree of
journeys**. A journey is a named, fixed sequence of player
commands — a DFA path — that bridges from a parent milestone *to*
a new milestone, deliberately threading a specific barrier. From
each milestone's snapshot, a cheap local BFS explores the
newly-opened region. The *union* across all snapshots is the
coverage measurement.

```
canonical_journey (the original linear playthrough)
    ├─ PlantUnlock      (branches off "bear released")
    │     grows the beanstalk → opens the chamber above
    └─ RustyDoorUnlock  (branches off PlantUnlock)
          oils the rusty door → opens the magnificent cavern
```

Each journey is ~15-40 commands. Adding one to bridge a barrier is
*dramatically* cheaper than raising the global BFS cap to brute-
force through it. This is the convergence loop: identify an
unreached region, write a short journey that bridges to it, let
local BFS fan out, repeat.

Building the first extension journey (PlantUnlock) immediately
surfaced another bug — and this one was a real canon-fidelity
defect, not a test artifact. The affordance enumerator (the code
that tells the search "here's what you can do in this room")
advertised that you could fill your bottle at room 23. The game's
own water-source predicate disagreed: room 23 isn't a water
source. So the search wasted turns trying to fill the bottle
where it couldn't, and — worse — *never tried* to fill it at the
eight rooms that actually are water sources, because they weren't
advertised. The journey to grow the plant failed silently until
we traced it.

---

## The big one: a bug hiding inside the test harness

The journey-tree audit reported it could reach **53 of 140
rooms** and called it a pass. The number was a lie.

The BFS reuses a single driver object across thousands of search
branches, rolling the game's FSM back to each branch point with a
save/restore. But the driver has state that lives *outside* the
FSM's save-state: a modal prompt dispatcher — the little state
machine that handles "are you sure? (y/n)" interactions, including
the death-and-revive prompt.

When any branch of the search killed the player, that dispatcher
entered its "awaiting revive answer" state. The save/restore rolled
the *FSM* back — but not the dispatcher. So every subsequent
branch inherited a stuck revive prompt, and the modal handler ate
every command that wasn't "yes" or "no." The search couldn't move.
It reported 53 rooms not because 53 was the truth, but because a
leaked prompt had silently broken navigation across most of the
search tree.

We found it by instrumenting a single suspicious transition — at
the Hall of Mountain King, with the snake gone, going south
bounced the player back instead of advancing. The snake was gone.
The lamp was lit. The player was alive. And yet: `prompts.current
== "revive"`, inherited from some sibling branch that had died
turns ago.

The fix was one line — reset the dispatcher after each restore,
mirroring the architect's documented contract that modal state
doesn't survive a save/restore boundary. Coverage jumped from **53
to 104 rooms** instantly. The bug had been masking nearly half the
cave.

This is the bug that reframed the whole effort. It wasn't a bug in
the game. It was a bug in the *tool we built to measure the game*,
and it had been confidently reporting a false number. A test that
says "PASS — 53 of 140 rooms" with no second opinion is worse than
no test: it's a number you trust that's wrong.

---

## Closing the gap to 140

With the leak fixed, the convergence loop did its job. A handful of
moves got us to full coverage:

- Raising the BFS cap from 5,000 to 15,000 states reached 122
  rooms. A probe at 30,000 proved the remaining "blocked" rooms
  weren't blocked at all — they were just queued and never
  popped before the cap. (The audit's gap classifier had been
  too coarse, flagging cap-budget as if it were a real barrier.
  Refining it to evaluate each gate's *runtime* status — is the
  snake actually here right now? — fixed the misdiagnosis.)
- The PlantUnlock and RustyDoorUnlock journeys bridged the two
  genuinely-gated clusters (+7 rooms).
- A multi-seed union audit combined snapshots from before the
  dragon kill (which opens canyon rooms the post-kill state
  redirects away from) and from the endgame repository.
- Six rooms turned out to have no topology source at all —
  they're transient message rooms ("the dome is unclimbable,"
  "you can't get by the snake") that the engine uses as prose
  targets, never as places you stand. A separate test verifies
  each fires its canon prose from its canon trigger.

The tally: **134 rooms reached as state-graph nodes, 6 verified by
canon-prose trigger, 140 total.**

---

## The third question: can you still win?

Reachability and safety were now nailed. But we'd never asked the
third question — **liveness**. Every proof that the game was
winnable used the single scripted happy path. Could you save
mid-game and still finish? Was any reachable state a *softlock* — a
point from which victory has quietly become impossible (a treasure
lost past a one-way gate, the lamp dead before the endgame, a
required item consumed)?

So we built a completability check: restore the snapshot at each of
the 32 canonical milestones, replay the remaining journey, assert
it reaches the won state. **All 32 resumed to victory.** Save
anywhere on the canonical path, reload, and you can still win.

Then the sharpest version of the question. Everything we'd proven
about winning used one RNG seed — and the canonical journey
deliberately routes *around* the probabilistic hazards. CCA has
randomness with teeth: the pirate steals a treasure and stashes it
elsewhere. Under a bad seed, could the pirate grab a treasure at a
moment or place that strands it — making the game unwinnable
through no fault of the player?

We ran the full winning playthrough under seven distinct RNG seeds.
Same fixed commands, seven different realizations of pirate
movement, probabilistic dispatch, and dark-pit rolls. **All seven
reached the won state.** The game is RNG-robust to completion — not
merely winnable on a lucky seed. The one mechanic that can
permanently relocate a treasure never, across seven distinct
pirate walks, strands a treasure you need.

---

## The pattern, and knowing when it ends

Count the bugs by how they were found:

- Inventory-on-death — found by the first state-space BFS.
- Dwarf-wake harness bug — found building milestone seeding.
- Affordance/water-source mismatch — found building PlantUnlock.
- The prompts-state-leak — found instrumenting a suspicious BFS
  transition.
- An oil-source list error (a room that wasn't any liquid source
  listed as one; the actual Pool of Oil missing) — found the
  *instant* we wrote a test that checks the affordance list against
  the game's own predicate.

Five bugs. Every one surfaced not by running the existing tests,
but by building a *new instrument* — and the new instrument found
something the green suite had been tolerating. The lesson isn't
"write more tests." It's that **measurement infrastructure needs
invariants on itself**, and that a passing number with no second
opinion is a liability. The prompts-leak hid behind "PASS — 53/140"
for who knows how long.

So we hardened the instruments. Three tests that check the harness,
not the game:

1. **Canonical-journey ⊆ BFS-reached** — when the search exhausts
   its frontier, it must reach every room the scripted journey
   visits. If it drops one, the harness is corrupting its own
   state. This is the cross-check that would have caught the
   prompts-leak the moment it appeared.
2. **Affordance/FSM agreement** — for every action the search is
   told it can take, the game must actually handle it. This caught
   the oil-source bug on its first run.
3. **Restore-path property** — a reused driver restored to a state
   must produce the identical observable behavior as a fresh driver
   restored to that state, regardless of what it did before. This
   pins the prompts-leak fix: disable the reset and all six test
   pairs fail.

And then the pattern broke. The completability checks found
nothing. The seed sweep found nothing. The full suite at full caps
— every BFS test at its real cap, the fuzzer at full length — ran
35 minutes and surfaced **zero violations across 88 tests**.

That silence is itself a result. Early waves hit a rich pool of
bugs because the prompts-leak had been masking so much. The last
several waves crossed from *discovery* into *confirmation* — they
asked genuinely new questions (liveness, RNG-robustness) and got
clean answers. Recognizing that inflection matters: past it,
building more measurement infrastructure is volume without signal.
The bug pool, at this fidelity, is drained — across reachability,
safety, *and* liveness.

---

## Takeaways

- **A green test suite measures what it measures.** Ours was
  thorough and local; it had no opinion on whole-state-space
  soundness, and a real inventory bug lived comfortably underneath
  it.
- **The three questions are different instruments.** Reachability,
  safety, and liveness need different machinery. We had to build
  all three; coverage tools say nothing about whether you can win.
- **Distrust a number with no second opinion.** "PASS — 53/140"
  was wrong for a long time. The cross-check that flags a
  suspicious drop is worth more than the primary number.
- **Test infrastructure is code, and it has bugs.** Two of our five
  finds were bugs in the harness, not the game. Instrument your
  instruments.
- **Know when you've crossed from finding to confirming.** The
  value is in the questions you haven't asked yet, not in re-asking
  the ones you've answered. When new instruments stop finding
  things, that's the signal to stop building instruments.

The game, it turns out, is sound: every room reachable, every
reachable state invariant-clean, and winnable from every save-point
under every roll of the dice. We can say that now with evidence. We
couldn't, forty-some commits ago, with a suite that was all green.
