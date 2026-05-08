# Canonical reference data — 1977 Crowther+Woods 350-point Adventure

This directory holds extracted reference data from Don Woods' 1977
PDP-10 Fortran release of *Adventure*, the canonical 350-point
version. The source is in the public domain (per `advent.readme`).

## Files

- `advent.dat` — full 1808-line canonical data file (rooms + objects
  + vocabulary + travel table + hints + scoring tiers + arbitrary
  messages + class messages). Reference only; the port does not
  parse this file at runtime.
- `advent.for` — **the original PDP-10 FORTRAN-IV interpreter that
  reads `advent.dat`**. This is the primary source of truth for the
  data file's encoding (the comment block at lines 95-180 specifies
  every section's format and the travel-table conditional encoding
  `Y = M*1000 + N`). Anywhere the port disagrees with this file's
  comments, the port is wrong.
- `advent.mic` — TOPS-20 build script for the FORTRAN source.
- `advent.readme` / `advent-original.readme` — Don Woods' release
  notes and the IF Archive's preservation note.
- `rooms.txt` — extracted: 140 canonical rooms with first-line
  descriptions. Format: `room_number|description`.
- `objects.txt` — extracted: 64 canonical objects (1-40 = movable
  + fixtures, 50-64 = treasures). Format: `object_id|name`. Names
  prefixed with `*` indicate immobile fixtures.
- `score_tiers.txt` — 9 canonical score-rating tiers (Rank Amateur
  → Grandmaster). Format: `score_threshold TAB rating_text`.
- `hints.txt` — 6 canonical hints. Format: `hint_# turn_threshold
  cost question_msg# answer_msg#`.
- `gen_locations.py` — generator script that parses `advent.dat`
  and `topology.gd` to produce `../CANON_LOCATIONS.md`. The
  decoder for travel-table dest values is a direct transcription
  of the spec in `advent.for` lines 105-122 — when the FORTRAN
  comment block says `IF N>500 MESSAGE N-500 FROM SECTION 6 IS
  PRINTED`, the generator emits exactly that. Re-run after any
  topology change to refresh the per-location reference.

## Source and credit

Retrieved from
[https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz](https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz)
on 2026-05-05 (and `advent.for` + `advent.mic` on 2026-05-08).
MD5s per `advent.readme`:

```
advent.dat   9f12da0c3e129b7fe5a1d91bbfebe02f
advent.for   ce54256f8e732b4a5e570bc64dd8536f
```

**This game was originally written by Will Crowther.** Most of the
features of the 350-point version were added by Don Woods (Stanford
AI Lab, 1976-77). Don preserved the source from his backup tape and
released it for historical record (March 1996). It's been freely
redistributed ever since.

This data is the authoritative canon target for the port. The
delta inventory at [`../CANON_DELTAS.md`](../CANON_DELTAS.md)
catalogues every place the port differs and ranks fixes by
priority. The per-location canonical reference at
[`../CANON_LOCATIONS.md`](../CANON_LOCATIONS.md) shows every canon
section-3 travel row decoded against the FORTRAN spec, alongside
the port's current implementation status.

## How the port uses this

The port's source files (`cca/frame/cca.fgd`, `cca/godot/scripts/topology.gd`)
must agree with the canonical data here for behavioral fidelity.
When a delta is closed, the corresponding row in `CANON_DELTAS.md`
is removed. When all rows are closed, the port is canon-faithful.
