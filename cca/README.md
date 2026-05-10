# Colossal Cave Adventure — Frame port

> *YOU ARE STANDING AT THE END OF A ROAD BEFORE A SMALL BRICK*
> *BUILDING. AROUND YOU IS A FOREST. A SMALL STREAM FLOWS OUT OF*
> *THE BUILDING AND DOWN A GULLY.*

In the mid-1970s, **Will Crowther** — a programmer at BBN who had
spent years mapping the real Mammoth-Bedquilt-Colossal cave system in
Kentucky with the Cave Research Foundation — wrote a small text
adventure on a PDP-10 to share with his daughters. In 1976/77, **Don
Woods** at Stanford got hold of a copy, asked Crowther's permission,
and substantially expanded it: more rooms, the dragon, the troll, the
endgame, the score-and-treasure structure that would shape every text
adventure to follow.

What Crowther and Woods made together is the genre's seed crystal.
Anyone who's typed `XYZZY` on a real terminal knows the feeling. This
port is one more attempt to do that 50-year-old game justice in a new
substrate — not to remix it, not to modernize it, but to render it as
faithfully as we can in a different language.

## Goal — canon-fidelity to 1977

The target is the **Crowther + Woods 1976/77** version, exactly as it
shipped, with [`canon/advent.for`](./canon/advent.for) (the original
PDP-10 FORTRAN-IV interpreter) and [`canon/advent.dat`](./canon/advent.dat)
(its 1808-line data file) treated as ground truth. Both files are
included verbatim in this repository. Every room number, every
message, every NPC behavior, every score boundary should match the
canon — and where it doesn't, the divergence should be deliberate
and documented.

Whether we've reached that goal is, honestly, **still TBD**. We have:

- [`CANON_FULL_AUDIT.md`](./CANON_FULL_AUDIT.md) — the per-feature
  audit driving toward zero open items.
- [`CANON_DELTAS.md`](./CANON_DELTAS.md) — the inventory of deliberate
  port-local divergences (UX softening, save/restore mechanics, a
  handful of conditional rows that don't have port equivalents).
- [`CANON_LOCATIONS.md`](./CANON_LOCATIONS.md) — the auto-generated
  per-room reference covering all 140 canonical locations, derived
  directly from `advent.for`'s travel table.
- A 62-file headless test suite (`./run_tests.sh`) that asserts canon
  messages, canon room numbers, canon probabilities, and end-to-end
  playthroughs against the live state machines.

Corrections welcome — open an issue or a PR with the
`advent.for` / `advent.dat` line numbers and we'll chase it.

## Playing

```bash
cd cca
FRAMEC=/path/to/framepiler/target/release/framec ./build.sh
godot --path godot/ scenes/main.tscn
```

Type `HELP` once you're in for the verb list. `SAVE` / `LOAD`
round-trip the entire world. `XYZZY` and `PLUGH` work the way you
remember.

## How it's built

The implementation is a study in **state machines for interactive
fiction**. Every entity that holds memorable cross-turn state — the
bear, the troll, the dragon, the lamp battery, the plant beanstalk,
the fragile vase, the player herself — is its own
[Frame](https://github.com/frame-lang/frame_transpiler) FSM,
composed under an `Adventure` orchestrator. Cross-cutting concerns
(darkness, inventory limits, magic-word teleports, score tracking)
ride a priority-ordered **aspect bus** in front of the world FSM —
the architectural payoff specific to this port.

For the full story — the Frame system catalogue, the aspect-bus
pattern, the driver layer, save/restore, the test architecture — see
[`ARCHITECTURE.md`](./ARCHITECTURE.md).

For honest per-system Frame value-add scoring (and a candid take on
where Frame helped vs. where it added ceremony), see
[`EVALUATION.md`](./EVALUATION.md).

## Credits

*Colossal Cave Adventure* — © Will Crowther 1976, expanded by Don
Woods 1977. Public domain. The canonical sources in
[`canon/`](./canon/) are preserved unmodified, with provenance and
attribution in [`canon/README.md`](./canon/README.md).

This Frame port is part of the [frame-arcade](../README.md) project.
