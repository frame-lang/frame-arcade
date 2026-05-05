# Canonical reference data — 1977 Crowther+Woods 350-point Adventure

This directory holds extracted reference data from Don Woods' 1977
PDP-10 Fortran release of *Adventure*, the canonical 350-point
version. The source is in the public domain (per `advent.readme`).

## Files

- `advent.dat` — full 1808-line canonical data file (rooms + objects
  + vocabulary + travel table + hints + scoring tiers + arbitrary
  messages + class messages). Reference only; the port does not
  parse this file at runtime.
- `advent.readme` — Don Woods' release notes.
- `rooms.txt` — extracted: 140 canonical rooms with first-line
  descriptions. Format: `room_number|description`.
- `objects.txt` — extracted: 64 canonical objects (1-40 = movable
  + fixtures, 50-64 = treasures). Format: `object_id|name`. Names
  prefixed with `*` indicate immobile fixtures.
- `score_tiers.txt` — 9 canonical score-rating tiers (Rank Amateur
  → Grandmaster). Format: `score_threshold TAB rating_text`.
- `hints.txt` — 6 canonical hints. Format: `hint_# turn_threshold
  cost question_msg# answer_msg#`.

## Source

Retrieved from
[https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz](https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz)
on 2026-05-05. SHA hashes per `advent.readme`:

```
advent.dat   md5  9f12da0c3e129b7fe5a1d91bbfebe02f
advent.for   md5  ce54256f8e732b4a5e570bc64dd8536f
```

This data is the authoritative canon target for the port. The
delta inventory at [`../CANON_DELTAS.md`](../CANON_DELTAS.md)
catalogues every place the port differs and ranks fixes by
priority.

## How the port uses this

The port's source files (`cca/frame/cca.fgd`, `cca/godot/scripts/topology.gd`)
must agree with the canonical data here for behavioral fidelity.
When a delta is closed, the corresponding row in `CANON_DELTAS.md`
is removed. When all rows are closed, the port is canon-faithful.
