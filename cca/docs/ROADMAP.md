# CCA Roadmap

Forward-looking work, ordered by ROI. Pre-existing pending items
live in [`../TODO.md`](../TODO.md); this doc covers the
testing-infrastructure track started by RFC-0001.

## In flight

### Phase C verb-effects expansion + audits (in progress)

Closing the four follow-on tasks identified end-of-Phase-C:

- ✅ **Death-path systematic coverage** — landed
  `test_cca_death_paths.gd`. Surfaced 1 driver bug (death-prose
  silently lost on death-room arrivals).
- 🔄 **Score-system audit** — in progress. Already surfaced 1
  driver bug (final-score uses `total_score()` instead of
  `score()`); investigating 1 candidate FSM bug (hint costs
  hardcoded `-2` rather than canon section-11 per-hint).
- ⏳ **Verb-effects expansion** — 14 entries → ~40, drawn from
  `advent.for` STMT tables.
- ⏳ **Hint-system tests** — 6 hints × trigger conditions.

ETA: 1 day to complete.

## Queued — RFC-0002: Multi-canonical-paths as testing spine

See [`rfcs/rfc-0002.md`](rfcs/rfc-0002.md). Architectural shift
that promotes the single `canonical_journey.fgd` to a catalog of
journeys (`canonical_paths/`) whose milestone snapshots become
the seeding pool for both the Phase B probe (Go-Explore
demonstration seeds) and Phase C verb-effects setup.

Concrete deliverables:

1. `cca/frame/canonical_paths/` directory with relocated
   existing canonical_journey + 2–4 new variants.
2. `MilestoneRegistry` global for snapshot export.
3. Probe extension to consume `seed_journeys` config.
4. Phase C migration of tightly-coupled setups (notably the
   abandoned bear-bridge-collapse entry).
5. TESTING.md documentation of the gap-closure workflow.

Implementation: 1–2 days for the foundational pieces (1-3);
content (4-6) accumulates incrementally as probe runs identify
gaps.

ETA: ~2 working days once started.

## Future / unscoped

### Writeup / case study

Translate `probe-evolution.md` into an external-facing blog post
positioning Frame as the substrate that makes white-box adventure-
game testing tractable. Materials are in place; just needs the
writing. Estimated weekend's work.

Plausible venues:
- Long-form blog post → HN / r/programming
- Lambda Days / DDD Europe / BOB / Curry On talk
- Onward! Essays submission (peer-reviewed but accepts
  thoughtful programming-essays without novelty requirements)

### Coverage-report HTML dashboard

Render the probe's coverage data as a navigable HTML page —
clickable room map, per-room action coverage, spec violations,
canon-conditional-row audit status. Would make the testing story
tangible to outsiders and could be embedded in a Frame showcase.
Estimated 1–2 days.

### Active-learning extension to passive automata learning

The world graph (`world_graph.gd`) is built passively from probe
observations. Active learning (L\* membership + equivalence
queries) would let us actively probe for unobserved transitions
rather than wait for stochastic exploration to find them.
Theoretically interesting but probably overkill — the probe's
random + Go-Explore already finds most transitions, and the
gap-closure workflow proposed in RFC-0002 fills the rest more
ergonomically.

### Frame-DSL improvements surfaced by CCA

Items that would improve the Frame-as-substrate story:
- Better tooling for `@@[persist]` round-trip verification
  (currently each project rolls its own check).
- A canonical-paths language primitive in Frame itself (the
  pattern in RFC-0002 is implementable today as plain FSMs, but
  language sugar would make it discoverable).
- Improved cross-FSM event tracing for debugging compound
  state machines like CCA's aspect-machines architecture.

These belong in the upstream framec project, not CCA. Cross-
reference whenever motivated by concrete CCA pain points.

## Done — recent infrastructure phases

For completeness, the testing-infrastructure track to date:

- [`rfc-0001.md`](rfcs/rfc-0001.md) — deterministic state-space
  search. ✅ Implemented.
- Phase B coverage probe (LFU + Go-Explore archive + BFS-routed
  storm). ✅ See `cca/godot/scripts/probe.gd`.
- Phase B passive automata learning + topology audit. ✅ See
  `cca/godot/scripts/world_graph.gd`.
- Phase C Layer 2 — item placement spec. ✅
- Phase C Layer 3 — NPC anchoring spec. ✅
- Phase C Layer 4 — verb-effect spec table (14 entries). ✅
- Phase C treasure-value cross-check. ✅
- Canon section-3 conditional-row gap closed (62/62). ✅ See
  `cca/canon/audit/conditional_audit.py`.

The journey log for these phases lives in
[`probe-evolution.md`](probe-evolution.md).
