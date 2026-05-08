# advent.for — full FORTRAN-IV interpreter inventory

Source file: `cca/canon/advent.for` (~2700 lines, FORTRAN-IV for PDP-10).
Companion to `ADVENT_DAT_INVENTORY.md` (data) — this doc covers the
*interpreter* only.

Don Woods's 1977 release. Primary copy: IF Archive
`if-archive/games/source/advent-original.tar.gz`.

The FORTRAN is mostly straight imperative numbered-statement code with
GOTOs; there are about twenty subroutines and functions at the end.
This document indexes every numbered branch worth a port-side equivalent.

Structure of this inventory:

1. **Common blocks and globals** — every shared variable, what it
   tracks, when it's mutated.
2. **Statement functions** — the `LIQ`, `DARK`, `PCT`, etc. one-liners
   that gate behavior throughout.
3. **Initialization (lines 90-616)** — DB read, mnemonic binding,
   dwarf seeding, treasure tally bootstrap.
4. **Main loop / dwarves / movement** (lines 619-1158).
5. **Death and resurrection** (lines 1158-1204).
6. **Action verb handlers** (1213-1810) — every numbered verb branch.
7. **Hint system** (1812-1852).
8. **Cave closing / endgame / scoring** (1853-2092).
9. **I/O routines** (2098-2305).
10. **Data-structure routines** (2306-2451).
11. **Wizardry (PDP-10 timesharing)** (2452-end).
12. **Magic numbers** — every literal constant that gates behavior.

Line numbers are decimal as printed by `wc -l` and `head -n`. FORTRAN
internal statement numbers (used in `GOTO`s) are written as `STMT N` to
disambiguate.

---

## 1. Common blocks and globals

### `/TXTCOM/ RTEXT, LINES`
- `LINES(9650)`: word-packed message corpus. Each message starts with a
  pointer-word (negative if first line of a multiline message) followed
  by 14 `A5` words of text per line.
- `RTEXT(205)`: section-6 message indexes — `RTEXT(N)` is the index in
  `LINES` where canon msg #N begins.

### `/BLKCOM/ BLKLIN`
- `BLKLIN`: when true, `SPEAK` precedes its message with a blank line.
  Inverted while building `INVENTORY` output to prevent stuttering.

### `/VOCCOM/ KTAB, ATAB, TABSIZ`
- `KTAB(300)`: word-number table. Each entry encodes word type via
  `KTAB(I) / 1000`: 0=motion verb, 1=object, 2=action verb, 3=special.
  Mod 1000 = the ID used downstream.
- `ATAB(300)`: hashed five-letter vocabulary words (`XOR 'PHROG'`).
- `TABSIZ`: 300, the table capacity.

### `/PLACOM/ ATLOC, LINK, PLACE, FIXED, HOLDNG`
- `ATLOC(150)`: head of the linked list of objects at each location
  (room), 0 if none.
- `LINK(200)`: next-object pointer in the same-room chain. Indices 1..100
  are for primary placement, 101..200 for the second placement of
  two-place objects.
- `PLACE(100)`: per-object current room. `-1` means the player is
  carrying it. `0` means destroyed/limbo.
- `FIXED(100)`: per-object immobility / second placement. `-1` =
  immovable, `0` = ordinary, `>0` = second room for two-placed objects.
- `HOLDNG`: count of objects the player carries (excluding fixed-2
  duplicates).

### `/MTXCOM/ MTEXT` and `/PTXCOM/ PTEXT`
- `MTEXT(35)`: section-12 magic-message indexes.
- `PTEXT(100)`: per-object property-message head index in `LINES`.
  Walking the `LINES` chain skips by `PROP(OBJ)` to get the right
  state-keyed description.

### `/ABBCOM/ ABB`
- `ABB(150)`: per-room visit counter. `MOD(ABB(LOC), ABBNUM) == 0`
  triggers a long-form description; otherwise the short form fires.
  `ABBNUM` defaults to 5; `BRIEF` sets it to 10000.

### `/WIZCOM/`
- `WKDAY, WKEND, HOLID`: bitmasks of "prime time" hours (cave closed)
  by day type. PDP-10 timesharing artifact.
- `HBEGIN, HEND, HNAME`: next-holiday window and name.
- `SHORT`: turn limit for demo games.
- `MAGIC, MAGNM`: wizard-mode passphrase + numeric key.
- `LATNCY`: required minutes between save/restore.
- `SAVED, SAVET`: save timestamp.
- `SETUP`: 0=fresh init, 1=measuring DB sizes, 2=warm boot,
  3=running, -1=restoring from save.

### Top-level globals (no common block — held in main routine)
- `LOC, NEWLOC, OLDLOC, OLDLC2`: current/next/prior/two-back room. `OLDLC2`
  is the last *safe* room and is the resurrect target after a death.
- `LIMIT`: lamp battery turns left. Init 330; `1000` if `HINTED(3)`
  (i.e., if the player accepted the verbose-instructions offer).
- `LMWARN`: has the dim-lamp warning fired? (Once-only).
- `WZDARK`: was the *previous* room dark? Used to decide whether to
  print msg #16 and roll the pit-fall.
- `IWEST`: count of times the player typed "WEST" instead of "W".
  At 10, fires msg #17 ("If you prefer, simply type W rather than
  WEST.").
- `KNFLOC`: 0 = no knife here, `>0` = knife in this room (after a
  miss), -1 = "you've been warned about ignoring the knife".
- `DETAIL`: count of "I'll repeat the description" responses; >=3
  suppresses further LOOK help.
- `ABBNUM`: short/long description period (5 default, 10000 after BRIEF).
- `MAXDIE`: max death count (5 in canon — 5 reincarnation message pairs).
- `NUMDIE`: deaths so far.
- `DKILL`: dwarves killed.
- `FOOBAR`: progress index into FEE-FIE-FOE-FOO incantation. Negative
  values mean "missed a step". Resets if a non-incantation verb fires
  in between.
- `BONUS`: 133/134/135 = endgame bonus tier set by BLAST handling.
- `CLOCK1`: turns from "all treasures located" to cave-closing
  warning. Init 30.
- `CLOCK2`: turns from cave-closing warning to closed-flash. Init 50.
- `CLOSNG`: flag — closing phase active.
- `PANIC`: flag — player tried to leave during closing.
- `CLOSED`: flag — fully closed (in repository).
- `GAVEUP`: flag — player typed QUIT.
- `SCORNG`: flag — score command in flight (vs. natural exit).
- `DEMO`: flag — demo-game mode (turn-limited).
- `TURNS`: command counter (excludes yes/no answers).
- `TALLY`: treasures *not yet found*. Initially 15 (per `MAXTRS=79`
  with 50..64 active). Hits 0 → cave closes.
- `TALLY2`: treasures permanently lost (e.g. bird/snake collateral,
  bridge collapse).
- `MAXTRS`: 79 — highest treasure object number.

### Dwarf state arrays
- `DLOC(6)`: each dwarf's current room. Indices 1-5 are dwarves;
  6 is the pirate. Init: 19, 27, 33, 44, 64, 114 (CHLOC).
- `ODLOC(6)`: each dwarf's previous room (so they don't backtrack
  unless forced).
- `DSEEN(6)`: has each dwarf seen the player? Sticky once set, until
  the player leaves loc≥15 zone.
- `DALTLC`: 18 — alternate spawn location if a dwarf would
  otherwise initialise on top of the player.
- `DFLAG`: dwarf system activation level.
  - 0: dormant (player hasn't reached Hall of Mists)
  - 1: armed (player has been in Hall of Mists, but no dwarf
    encounter yet)
  - 2: first-encounter complete; dwarves move and may attack
  - 3: knife thrown (first set always misses)
  - 4..n: throws getting more accurate
  - 20: from-save penalty (impostor mode — dwarves *very* mad)
- `CHLOC = 114`: pirate's chest ultimate stash room (decoded:
  the dead-end-in-second-maze).
- `CHLOC2 = 140`: dead end in the OTHER maze (the message room).

---

## 2. Statement functions (lines 78-88)

Single-expression inline functions, used everywhere:

| Func | Body | Meaning |
|---|---|---|
| `TOTING(OBJ)` | `PLACE(OBJ).EQ.-1` | player carries OBJ |
| `HERE(OBJ)` | `PLACE(OBJ).EQ.LOC.OR.TOTING(OBJ)` | OBJ accessible at LOC |
| `AT(OBJ)` | `PLACE(OBJ).EQ.LOC.OR.FIXED(OBJ).EQ.LOC` | OBJ is in LOC (either of its two-placement slots) |
| `LIQ2(PBOTL)` | `(1-PBOTL)*WATER+(PBOTL/2)*(WATER+OIL)` | given a bottle prop, the contained liquid OBJ-ID (water/oil/none) |
| `LIQ(DUMMY)` | `LIQ2(MAX0(PROP(BOTTLE),-1-PROP(BOTTLE)))` | OBJ-ID of liquid currently in bottle |
| `LIQLOC(LOC)` | `LIQ2(...)` | OBJ-ID of liquid available at LOC (per COND bits 1+2) |
| `BITSET(L,N)` | `COND(L) AND SHIFT(1,N) != 0` | room L has property bit N |
| `FORCED(LOC)` | `COND(LOC).EQ.2` | room is a forced-motion bouncer |
| `DARK(DUMMY)` | `MOD(COND(LOC),2).EQ.0 .AND. (PROP(LAMP).EQ.0 .OR. .NOT.HERE(LAMP))` | LOC currently dark |
| `PCT(N)` | `RAN(100).LT.N` | true `N`% of the time |

**Port equivalents:** `Adventure._room_is_dark`, `Adventure.bottle.has_water/has_oil`, `Topology.gates` carrying-checks, `Cca.player.carrying(...)`. The `LIQLOC` inline function's bit-twiddling decodes COND bits 1 and 2 — bit 2 set with bit 1 off is water source, bit 2 set with bit 1 on is oil source.

---

## 3. Initialization (lines 90-616)

### 3a. DB read and storage (lines 96-366)

`SETUP=0` (cold start) triggers full DB read. Parser dispatches by
section number:

| Section | Stmt # | Routine |
|---|---|---|
| 1 (long descs)   | STMT 1004 → 1008 | `LTEXT(LOC) = LINUSE` |
| 2 (short descs)  | STMT 1004 → fallthrough | `STEXT(LOC) = LINUSE` |
| 3 (travel)       | STMT 1030 | `KEY(LOC), TRAVEL(...)` (negate last per loc) |
| 4 (vocab)        | STMT 1040 | `KTAB(I), ATAB(I) XOR 'PHROG'` |
| 5 (object descs) | STMT 1004 → 1010 | `PTEXT(LOC) = LINUSE` |
| 6 (messages)     | STMT 1004 → 1011 | `RTEXT(LOC) = LINUSE` |
| 7 (placements)   | STMT 1050 | `PLAC(OBJ), FIXD(OBJ)` |
| 8 (action defaults) | STMT 1060 | `ACTSPK(VERB) = J` |
| 9 (COND bits)    | STMT 1070 | for each LOC in TK: `COND(LOC) |= SHIFT(1,K)` |
| 10 (class msgs)  | STMT 1004 → 1012 | `CTEXT(I), CVAL(I)` |
| 11 (hints)       | STMT 1080 | `HINTS(K, 1..4) = TK(1..4)`, `HNTMAX = MAX(...)` |
| 12 (magic msgs)  | STMT 1004 → 1013 | `MTEXT(LOC) = LINUSE` |

Words are 5-char `A5`. The vocabulary hash is `XOR 'PHROG'` to make
the in-core image less browse-able from a debugger.

### 3b. Internal-format finalization (lines 367-433)

After all sections read:
- All `PROP(I) = 0`, `PLACE(I) = 0`, `LINK(I) = 0` (lines 383-387).
- For each room with non-zero KEY, peek at `MOD(IABS(TRAVEL(K)),1000)`:
  if it's 1 (verb=NULL = any-verb), set `COND(I) = 2` (forced-motion).
  This is how rooms 16, 22, 26, 32, 40, 59, 79, 89, 90, 113 become
  bumpers without an explicit data flag.
- `ATLOC` chains are set up by the `DROP` subroutine called from a
  reverse-iteration loop (lines 403-413), so two-placed objects (grate,
  steps, fissure, dragon, troll, chasm) end up at *both* rooms.
- Treasures (50..MAXTRS) get `PROP=-1` (suppress description until
  first observed), `TALLY` accumulates the count.
- Hint state cleared: `HINTED(I)=.FALSE.`, `HINTLC(I)=0`.

### 3c. Mnemonic binding (lines 435-484)

Looks up vocabulary words to bind FORTRAN names to canonical IDs.
This is the *only* coupling between vocabulary and code — every
in-code reference is via these mnemonics:

```
KEYS LAMP GRATE CAGE ROD ROD2 STEPS BIRD DOOR PILLOW SNAKE
FISSUR TABLET CLAM OYSTER MAGZIN DWARF KNIFE FOOD BOTTLE
WATER OIL PLANT PLANT2 AXE MIRROR DRAGON CHASM TROLL TROLL2
BEAR MESSAG VEND BATTER NUGGET COINS CHEST EGGS TRIDNT VASE
EMRALD PYRAM PEARL RUG CHAIN
BACK LOOK CAVE NULL ENTRNC DPRSSN  -- motion verbs
SAY LOCK THROW FIND INVENT       -- action verbs
```

`ROD2 = ROD+1` and `PLANT2 = PLANT+1` exploit a FORTRAN convention:
related objects sit adjacent in the vocab table.

### 3d. Initial counter values (lines 547-567)

```fortran
TURNS=0      LMWARN=.FALSE.   IWEST=0       KNFLOC=0
DETAIL=0     ABBNUM=5         NUMDIE=0      HOLDNG=0
DKILL=0      FOOBAR=0         BONUS=0       CLOCK1=30
CLOCK2=50    SAVED=0          CLOSNG=.F.    PANIC=.F.
CLOSED=.F.   GAVEUP=.F.       SCORNG=.F.
```

`MAXDIE` is determined dynamically (lines 553-554) by counting
how many reincarnation message pairs exist in `RTEXT(81..89)` — caps
at 5.

### 3e. Start-up flow (lines 619-626)

```fortran
DEMO = START(0)                       -- prime-time / restart check
CALL MOTD(.FALSE.)                    -- print message of the day
HINTED(3) = YES(65,1,0)               -- offer instructions, get +30/turn lamp
NEWLOC = 1                            -- start at end-of-road
SETUP = 3                             -- "running"
LIMIT = 330
IF (HINTED(3)) LIMIT = 1000           -- "novice" mode 3x lamp life
```

Hint #3 is the verbose-instructions offer (see `HINTED(3)=.TRUE.` =
"player wants instructions"). Accepting it costs 5 points but gives
1000 turns of lamp instead of 330. Hint #2 is for reading the
clue-in-the-repository at endgame.

---

## 4. Main loop / dwarves / movement (lines 619-1158)

### 4a. Movement frame (STMT 2)

Top of loop — `NEWLOC` is the proposed new location.

`STMT 71`: closing-time gate. If `CLOSNG` and `NEWLOC<9` (i.e. trying
to leave the cave), force `NEWLOC=LOC`, print msg #130, set
`CLOCK2=15` if not already panicked, set `PANIC=.TRUE.`.

`STMT 71` cont.: dwarf-block check. If a dwarf has seen us *and* came
from `NEWLOC`, the dwarf is blocking that exit — force `NEWLOC=LOC`,
print msg #2 ("A LITTLE DWARF WITH A BIG KNIFE BLOCKS YOUR WAY.").
Skipped if leaving FORCED rooms or pirate-forbidden rooms.

`STMT 74`: commit `LOC=NEWLOC`.

### 4b. Dwarf engine (STMT 6000-6030)

**Activation (STMT 6000):**
- If `DFLAG==1` and `LOC>=15` and `PCT(95)` succeeds: stay at `DFLAG=1`.
  i.e. 5% chance per visit to Hall of Mists to trigger the encounter.
- On trigger: `DFLAG=2`, kill 0-2 of the 5 dwarves randomly, replace
  any dwarf already at `LOC` with `DALTLC=18`, set all `ODLOC = DLOC`,
  print msg #3, drop the AXE at `LOC`.

**Per-turn motion (STMT 6010-6030):**
For each of the 6 dwarves:
- Skip if `DLOC(I)==0` (dead).
- Walk the `TRAVEL` table at `KEY(DLOC(I))`, accumulating valid
  destinations into `TK(1..J)`. Filters:
  - `NEWLOC > 300` → skip (special routine)
  - `NEWLOC < 15` → skip (no above-ground)
  - `NEWLOC == ODLOC(I)` → skip (no immediate backtrack)
  - already in `TK(1..J-1)` → skip (no duplicates)
  - `NEWLOC == DLOC(I)` → skip (don't stay put unless forced)
  - `FORCED(NEWLOC)` → skip (no forced rooms)
  - dwarf 6 (pirate) AND `BITSET(NEWLOC,3)` → skip (pirate-forbidden)
  - condition modifier `M==100` (forbidden-to-dwarves) → skip
- If no valid destinations, push `ODLOC(I)` onto `TK` (forced backtrack).
- `J = 1+RAN(J)` (random walk).
- Update `ODLOC(I) = DLOC(I)`, `DLOC(I) = TK(J)`.
- `DSEEN(I) = (DSEEN(I) AND LOC>=15) OR (new-loc=LOC OR old-loc=LOC)`.
- If seen and `I != 6`: dwarf moves to `LOC`, increment `DTOTAL`.
  If didn't move (was already adjacent): `ATTACK++`. If knife-floor
  flag is on, `KNFLOC = LOC`. Each attacker has a `STICK` chance
  proportional to `(DFLAG-2)*9.5%` of actually hitting.

**Pirate (dwarf 6) special case (STMT 6022-6027):**
- If pirate and `LOC == CHLOC` or `PROP(CHEST) >= 0` (chest already
  found), do nothing.
- Pirate scans treasures; if player carries any treasure, prints msg
  #128 ("Out from the shadows..."), moves all carried treasures and
  any unfixed in-room treasures to `CHLOC`, moves MESSAG to `CHLOC2`,
  pirate teleports to `CHLOC`. (Pyramid is exempted if at Plover or
  Dark room — too easy.)
- If `TALLY == TALLY2 + 1` and chest is the only outstanding treasure
  and lamp is here lit: print msg #186 ("There are faint rustling
  noises..."), move chest to CHLOC, etc. — pirate hint.
- Otherwise 20% chance to print msg #127 ("rustling sounds nearby").

**Reporting (STMT 75-84):**
- 0 dwarves → quiet
- 1 dwarf → msg #4 ("threatening little dwarf in the room")
- 2+ dwarves → "There are N threatening..."
- If any attacked: 1 attacker uses msg #5 + variants 6/7; multi-
  attackers uses "N of them throw knives at you!" + variants.
- If hits land: print msg "K+STICK" where K=6 (multi) or K=52 (single),
  set `OLDLC2=LOC`, GOTO 99 (death).

### 4c. Room description (STMT 2000-2012)

- If `LOC==0`, GOTO 99 (death — limbo).
- Pick `KK = STEXT(LOC)` (short) unless `MOD(ABB(LOC), ABBNUM)==0` or
  short doesn't exist — then `KK = LTEXT(LOC)`.
- If `FORCED(LOC)` or `.NOT.DARK(0)`: print room. Else: if
  `WZDARK.AND.PCT(35)`: GOTO 90 (pit-fall death). Else `KK = RTEXT(16)`
  (the canon "It is now pitch dark" warning).
- If `TOTING(BEAR)`: print msg #141 ("you are being followed by..." /
  "tame bear" line) before room.
- Print room.
- If `LOC==33` (Y2) and `PCT(25)` and not closing: print msg #8
  ("hollow voice says PLUGH").
- Walk `ATLOC(LOC)` chain printing each object's `PSPEAK`, except:
  - Skip if `OBJ==STEPS && TOTING(NUGGET)` (the dome-unclimbable hack).
  - If `PROP < 0` (treasure first-sight): set `PROP=0`, decrement
    `TALLY`, `PROP=1` for RUG (dragon on it) or CHAIN (locked to bear).
    If `TALLY==TALLY2 && TALLY!=0`: cap `LIMIT` at 35 (hurry-up).

### 4d. Per-turn upkeep (STMT 2600-2608)

- Hint check: for each `HINT in 4..HNTMAX`, if `BITSET(LOC, HINT)` (the
  hint-trigger bit is set on this room): increment `HINTLC(HINT)`.
  Otherwise reset to -1+1=0. If counter hits `HINTS(HINT,1)`: GOTO
  40000 (offer hint).
- If `CLOSED`: any toted object with `PROP<0` flips to `-1-PROP` so
  it stays mute when redropped.
- `WZDARK = DARK(0)`.
- Stale knife reset: `IF KNFLOC>0 AND KNFLOC!=LOC THEN KNFLOC=0`.
- `RAN(1)` to perturb the RNG.
- `GETIN` reads `WD1, WD1X, WD2, WD2X`.

### 4e. Per-turn timer ticks (STMT 2608-19999)

- `FOOBAR = MIN(0, -FOOBAR)` (decay)
- "MAGIC MODE" passphrase check (turn 0 only)
- `TURNS++`
- `IF DEMO AND TURNS>=SHORT GOTO 13000` (demo timeout)
- `IF VERB==SAY AND WD2!=0 → VERB=0`, `IF VERB==SAY GOTO 4090`
- `IF TALLY==0 AND LOC>=15 AND LOC!=33 → CLOCK1--`
- `IF CLOCK1==0 GOTO 10000` (closing!)
- `IF CLOCK1<0 → CLOCK2--`
- `IF CLOCK2==0 GOTO 11000` (full close — repository)
- `IF PROP(LAMP)==1 → LIMIT--`
- `IF LIMIT<=30 AND HERE(BATTER) AND PROP(BATTER)==0 AND HERE(LAMP) GOTO 12000` (auto-replace batteries)
- `IF LIMIT==0 GOTO 12400` (lamp out)
- `IF LIMIT<0 AND LOC<=8 GOTO 12600` (left cave, lamp dead → forced quit)
- `IF LIMIT<=30 GOTO 12200` (dim warning)

### 4f. Verb dispatch (STMT 19999-3000)

- `K = 43` default speak ("Where?")
- If `LIQLOC(LOC)==WATER → K=70` ("Your feet are wet")
- "ENTER STREAM"/"ENTER WATER" → SPEAK msg #70
- "ENTER X" with X != stream/water → set `WD1=WD2`, restart at STMT 2610
- "WATER PLANT", "OIL PLANT", "WATER DOOR", "OIL DOOR" → swap to
  POUR sequence
- "WEST" word handling: increment `IWEST`, on 10th time print msg #17
- Look up word in vocab. If not found: GOTO 3000 ("I don't know
  what you mean", with 20%/20% randomization across msgs #60/#61/#13)
- Dispatch by KQ = type+1: 1=motion verb (GOTO 8), 2=object (GOTO 5000),
  3=action (GOTO 4000), 4=special (GOTO 2010)

### 4g. Travel resolution (STMT 8-50)

`STMT 8` is reached with verb K. `KK = KEY(LOC)` is the start of this
room's TRAVEL slice.

- `K==NULL` (motion verb 1, fired by NULL re-entry) → GOTO 2 (just
  re-display)
- `K==BACK` → GOTO 20 (find verb that goes from LOC to OLDLOC)
- `K==LOOK` → GOTO 30 (DETAIL handling)
- `K==CAVE` → GOTO 40 (above/below ground messages)
- Save `OLDLC2 = OLDLOC`, `OLDLOC = LOC`.

`STMT 9` — walk TRAVEL slice:
```
LL = IABS(TRAVEL(KK))
IF MOD(LL,1000) IN (1, K) → GOTO 10 (this row matches; verb 1=any-verb)
IF TRAVEL(KK) < 0 → end of slice → GOTO 50 (no-such-exit)
KK++; GOTO 9
```

`STMT 10` — extract dest:
```
LL = LL/1000   (drop verb tag, leaves "M*1000+N" as "LL")
NEWLOC = LL/1000   (M, the condition)
K = MOD(NEWLOC, 100)   (object index for prop-checks)
IF NEWLOC <= 300 → GOTO 13 (no condition)
```

`STMT 11-13` — condition tests by M:
```
M=0..299: unconditional → STMT 13
M=300..399: PROP(M MOD 100) must NOT be 0 (M mod 100 = obj id)
M=400..499: PROP(M MOD 100) must NOT be 1
M=500..599: PROP(M MOD 100) must NOT be 2
... up to M=599 (FORTRAN supports up to ~999 in principle)
```

Failed condition → STMT 12: skip to next *different* destination.

`STMT 13`:
```
IF NEWLOC <= 100: GOTO 14 (probability check)
IF TOTING(K) OR (NEWLOC>200 AND AT(K)) → GOTO 16 (carrying-condition met)
GOTO 12 (skip)
```

`STMT 14`:
```
IF NEWLOC != 0 AND .NOT.PCT(NEWLOC) → GOTO 12 (failed probability roll)
```

`STMT 16`:
```
NEWLOC = MOD(LL, 1000)
IF NEWLOC <= 300 → GOTO 2 (just walk to NEWLOC; resume main loop)
IF NEWLOC <= 500 → GOTO 30000 (special routine — see below)
CALL RSPEAK(NEWLOC-500)   (msg #(N-500) bumper)
NEWLOC = LOC              (stay put)
GOTO 2
```

### 4h. Special motion routines (STMT 30000-30310)

Three only in canon. Already documented in `CANON_LOCATIONS.md`.

**301 — Plover-alcove squeeze (STMT 30100):**
```fortran
NEWLOC = 99 + 100 - LOC                    -- flip 99 ↔ 100
IF HOLDNG==0 OR (HOLDNG==1 AND TOTING(EMRALD)) → walk
NEWLOC = LOC
CALL RSPEAK(117)                           -- "won't fit through"
GOTO 2
```

**302 — Plover transport (STMT 30200):**
```fortran
CALL DROP(EMRALD, LOC)                     -- drop emerald in place
GOTO 12                                    -- pretend not carrying, re-walk
```

The PLOVER magic word handler in some other code path actually
invokes this at canon 33 / 100 if the player is carrying the emerald
— forces the squeeze, hence the chain.

**303 — Troll bridge (STMT 30300):**
- If `PROP(TROLL)==1` (paid but not crossed yet): print TROLL.PSPEAK[1]
  ("the troll steps out from beneath the bridge..."), reset
  `PROP(TROLL)=0`, JUGGLE the chasm/trolls, stay put.
- Else compute `NEWLOC = PLAC(TROLL) + FIXD(TROLL) - LOC` (flip 117↔122).
- If `PROP(TROLL)==0`: set to 1.
- If `TOTING(BEAR)`: msg #162 (chasm collapses, bear falls), set
  `PROP(CHASM)=1`, `PROP(TROLL)=2`, drop bear at NEWLOC, fix bear,
  `PROP(BEAR)=3` (dead). If we never found spices, `TALLY2++` (it's
  unreachable). Set `OLDLC2=NEWLOC`, GOTO 99 (player dies).

### 4i. BACK handling (STMT 20-25)

Walk TRAVEL slice looking for a verb that goes to OLDLOC (or OLDLC2 if
OLDLOC is FORCED). Saves a `K2` candidate that tracks "verb that goes
to FORCED-loc that goes to OLDLOC" as a fallback. If no path: msg
#140 ("Sorry, but I no longer seem to remember how it was you got
here.").

### 4j. LOOK / CAVE / no-exit (STMT 30-50)

- LOOK (STMT 30): "Sorry, but I am not allowed to give more detail"
  (msg #15) up to 3 times, then suppress. Resets `ABB(LOC)=0` so the
  next room display is long-form.
- CAVE (STMT 40): outdoors → msg #57 ("I don't know where..."); indoors
  → msg #58 ("you can't even see well enough to know which way is up").
- No-exit (STMT 50): default msg #12 ("I don't know how to apply that
  word"). Specific overrides: directional verbs use msg #9; in/out use
  msg #11; etc.

---

## 5. Death and resurrection (lines 1158-1204)

`STMT 90` (dark-room pit-fall): print msg #23 ("you fell into a pit...");
`OLDLC2 = LOC`. (Note: msg #23 is the broken-bones text, fired by
*either* the pit-fall hazard or canon room 20 entry.)

`STMT 99` (death entry):
- If `CLOSNG`: msg #131 ("It looks as though you're dead..."),
  `NUMDIE++`, GOTO 20000 (final score) — no resurrection during
  closing.
- Otherwise: `YEA = YES(81+NUMDIE*2, 82+NUMDIE*2, 54)`. Messages 81,
  83, 85, 87, 89 are death taunts; 82, 84, 86, 88, 90 are
  resurrection acks. Msg #54 is the "OK." cancel.
- `NUMDIE++`. If `NUMDIE==MAXDIE` or `.NOT.YEA` → GOTO 20000.
- Reincarnate: `PLACE(WATER)=0`, `PLACE(OIL)=0` (drop liquids out of
  bottle), `PROP(LAMP)=0` if lamp toted (force off), drop everything
  carried at `OLDLC2` (last safe loc) — except lamp which goes to
  loc 1 (end-of-road). Set `LOC=3` (well house), `OLDLOC=3`.
- GOTO 2000.

---

## 6. Action verb handlers (lines 1213-1810)

`STMT 4080` is the intransitive dispatch table (verb without object):
```
TAKE DROP SAY OPEN NOTH LOCK ON OFF WAVE CALM
WALK KILL POUR EAT  DRNK RUB TOSS QUIT FIND INVN
FEED FILL BLST SCOR FOO  BRF  READ BREK WAKE SUSP
HOUR
```

`STMT 4090` is the transitive table — same verbs, different targets.

### 6a. CARRY / TAKE (STMT 8010 / 9010)

**Intransitive (8010):** if exactly one object at `LOC` (and no dwarf):
auto-pick. Else "What?".

**Transitive (9010):**
- Already toting → msg #24 ("you are already carrying it!").
- `OBJ==PLANT && PROP(PLANT)<=0`: msg #115 ("the plant has exceptionally
  deep roots and cannot be pulled free of its rock").
- `OBJ==BEAR && PROP(BEAR)==1`: msg #169 ("the bear is still chained
  to the wall").
- `OBJ==CHAIN && PROP(BEAR)!=0`: msg #170 ("the chain is now unlocked").
- `FIXED(OBJ) != 0` → msg #25 ("you can't be serious!").
- WATER/OIL: must have empty bottle here, or msg #104/#105.
- `HOLDNG >= 7` → msg #92 ("you can't carry anything more"). 7-item
  limit is canon.
- `OBJ==BIRD && PROP(BIRD)==0`:
  - If `TOTING(ROD)` → msg #26 ("the bird was unafraid when you
    entered, but as you approach it becomes disturbed").
  - If not `TOTING(CAGE)` → msg #27 ("you can catch the bird, but you
    cannot carry it").
  - Else: `PROP(BIRD)=1` (caged), CARRY(bird) and CARRY(cage).
- `OBJ==BOTTLE && K!=0` (bottle holding something): set `PLACE(K)=-1`
  so the liquid travels with bottle.
- Increment `HOLDNG`, set `PLACE(OBJ)=-1`. SPEAK("OK").

### 6b. DROP (STMT 9020)

- ROD/ROD2 swap: if you have ROD2 and asked to drop ROD, drop ROD2
  instead.
- `.NOT.TOTING(OBJ)` → msg #29.
- `OBJ==BIRD && HERE(SNAKE)`: msg #30 (bird drives snake away),
  destroy snake, `PROP(SNAKE)=1`. If `CLOSED`: GOTO 19000 (player
  disturbed dwarves at endgame).
- `OBJ==COINS && HERE(VEND)`: destroy coins, drop BATTER, PSPEAK
  battery prop 0 ("fresh batteries").
- `OBJ==BIRD && AT(DRAGON) && PROP(DRAGON)==0`: msg #154 (bird
  flies into dragon's mouth, gets vaporized). Destroy bird. If snake
  not at home: `TALLY2++`.
- `OBJ==BEAR && AT(TROLL)`: msg #163 (troll runs away), move troll
  out of the way, set `PROP(TROLL)=2`. Then run normal drop logic.
- `OBJ==VASE && LOC != PLAC(PILLOW)`: msg #54 (drop without pillow).
  `PROP(VASE)=2` (broken). `FIXED(VASE)=-1`.
- Otherwise normal: drop OBJ, decrement HOLDNG.

### 6c. SAY (STMT 9030)

Echo `WD2 || WD1`. If word is a magic word (XYZZY=62, PLUGH=65,
PLOVER=71, FEE-FIE-FOE-FOO=2025): re-dispatch as that word, GOTO 2630.
Otherwise: `Okay, "<word>"`.

### 6d. OPEN/LOCK (STMT 8040 / 9040)

**Intransitive (8040):** auto-detect target — clam/oyster/door/grate/chain.

**Transitive (9040):**
- CLAM/OYSTER → STMT 9046 (see below).
- DOOR: msg #111 (rusty hinges). If `PROP(DOOR)==1` (oiled): msg #54.
- CAGE: msg #32 ("nothing here with a lock").
- KEYS: msg #55 ("you can't unlock the keys").
- GRATE/CHAIN: msg #31 ("you have no keys"). If `HERE(KEYS)`:
  - CHAIN → STMT 9048.
  - GRATE: msg #34 (already unlocked) / #35 (locked) / #36 (unlocking)
    / #37 (already locked) chosen by `PROP(GRATE)*2 + (lock?0:1)`.
    Set `PROP(GRATE) = LOCK?0:1`. (LOCK=2, UNLOCK=4 in vocab.)

**STMT 9046 (clam/oyster):**
- Can't carry it → msg #122/#123 ("don't have anything strong enough...").
- Don't have trident → msg #122/#123.
- Trying to LOCK a clam → msg #61 ("a mistake which is undoubtedly
  rare among adventurers").
- Otherwise (open clam): destroy clam, drop oyster at LOC, drop pearl
  at canon 105 (Cul-de-sac).

**STMT 9048 (chain unlock):**
- `PROP(BEAR)==0`: msg #41 ("there's no way to get past the bear").
- `PROP(CHAIN)==0`: msg #37 ("it was already unlocked").
- Else: `PROP(CHAIN)=0`, `FIXED(CHAIN)=0`. If bear isn't dead:
  `PROP(BEAR)=2` (released), `FIXED(BEAR)=2-PROP(BEAR)`. Msg #171.

### 6e. ON/OFF (STMT 9070 / 9080)

- Lamp on: if lamp not here, msg #29; if `LIMIT<0`, msg #184; else
  `PROP(LAMP)=1`, msg #39. If was dark, GOTO 2000 to redescribe.
- Lamp off: `PROP(LAMP)=0`, msg #40. If now dark, msg #16 (warning).

### 6f. WAVE (STMT 9090)

- Not toting → msg #29.
- Object isn't ROD or not at fissure or closing → msg #29 ("Nothing
  happens.").
- Otherwise: toggle `PROP(FISSUR)`, PSPEAK fissure prop.

### 6g. ATTACK / KILL (STMT 9120)

Auto-target (intransitive): scan for dwarf-here, snake, dragon, troll,
bear, bird, clam/oyster. If two enemies → "What?".

- BIRD: destroy, `PROP(BIRD)=0`. If snake not at home, `TALLY2++`.
  Msg #45 ("the little bird is now dead..."). If `CLOSED`: GOTO 19000.
- CLAM/OYSTER: msg #150 ("the shell is very strong and impervious...").
- SNAKE: msg #46 ("attacking the snake doesn't work").
- DWARF: msg #49 ("with what?  your bare hands?"). If `CLOSED`: GOTO 19000.
- DRAGON: msg #167 ("with what?  your bare hands?"). 
  If `PROP(DRAGON)==0` (dragon alive) AND user types YES at the prompt
  (msg #49):
  - PSPEAK dragon prop 1 ("the body of a huge green fierce dragon...").
  - `PROP(DRAGON)=2`, `PROP(RUG)=0`. Move dragon to room
    `(PLAC(DRAGON)+FIXD(DRAGON))/2 = 120` (the connecting canyon),
    move rug there too. Walk player to 120.
- TROLL: msg #157 ("the troll laughs at your puny effort").
- BEAR: msg #165/#166/#167/#168 keyed by `PROP(BEAR)`.
- THROW also lands here (with axe-related preflight at STMT 9170).

### 6h. POUR (STMT 9130)

- Object 0/bottle → set OBJ to current liquid in bottle.
- Not toting → msg #29.
- OBJ != OIL && != WATER → msg #78 ("you can't pour that").
- Empty bottle: `PROP(BOTTLE)=1`, `PLACE(OBJ)=0`.
- If at PLANT: msg #112 if not water; else PSPEAK plant prop, advance
  plant prop (mod 6) by 2: 0→2→4→0 cycle. Set `PROP(PLANT2)=PROP/2`.
  Force a re-look (`K=NULL; GOTO 8`).
- If at DOOR: `PROP(DOOR)=0` (or 1 if pouring oil). Msg #113 or #114.

### 6i. EAT / DRINK (STMT 8140 / 9140 / 9150)

- EAT FOOD: destroy food, msg #72.
- EAT BIRD/SNAKE/CLAM/OYSTER/DWARF/DRAGON/TROLL/BEAR: msg #71
  ("don't have appetite").
- DRINK WATER (or no obj at water-loc): if water in bottle, set
  `PROP(BOTTLE)=1`, `PLACE(WATER)=0`, msg #74. Otherwise msg #110.

### 6j. RUB (STMT 9160)

- `OBJ != LAMP`: msg #76 ("rubbing the electric lamp is not productive").

### 6k. THROW (STMT 9170)

- Treasure at TROLL → STMT 9178: drop OBJ at limbo (troll catches it).
  If we paid the troll, troll vanishes, troll2 takes over (the
  "phony troll" placeholder so the bridge can be re-crossed). Msg #159.
- FOOD with bear here → re-route to FEED.
- AXE only otherwise:
  - Dwarf in same room → STMT 9172. Roll: `RAN(3)==0` (33% chance) →
    msg #48 (dwarf dodges). Else dwarf killed: `DSEEN(I)=.FALSE.`,
    `DLOC(I)=0`, `DKILL++`. Msg #47 (or #149 first kill).
  - At dragon: msg #152 ("the axe glances off the dragon's tough
    hide").
  - At troll: msg #158 ("the troll deftly catches the axe").
  - With bear here → STMT 9176: msg #164 (bear catches axe), drop
    axe and FIX it (so it can't be re-taken).
  - Else: route through ATTACK with bird (tries to kill the bird).

### 6l. QUIT (STMT 8180)

`GAVEUP = YES(22, 54, 54)`. Msg #22: "Do you really want to quit now?".
If yes → GOTO 20000 (final score).

### 6m. FIND (STMT 9190)

- Object visible/here → msg #94 ("I believe what you want is right
  here with you").
- If carrying → msg #24.
- If `CLOSED` → msg #138 ("it must be unsuspectingly close to here").
- Else default-msg #59 (from ACTSPK).

### 6n. INVENTORY (STMT 8200)

Walk objects 1-100, PSPEAK `PROP=-1` (the inventory message) for each
toted object. If toting bear: msg #141 ("you are being followed by a
very large, tame bear"). If carrying nothing: msg #98 ("you're not
carrying anything").

### 6o. FEED (STMT 9210)

- BIRD: msg #100 ("it's not hungry, just unfriendly").
- SNAKE/DRAGON/TROLL: msg #102 ("there's nothing here to eat (at least,
  nothing edible)"). Snake-specific override: if HERE(BIRD) and not
  closed → msg #101 (snake eats bird!), destroy bird, `PROP(BIRD)=0`,
  `TALLY2++`.
- DWARF with food here: msg #103 ("you fool, dwarves eat only coal!"),
  `DFLAG++` (makes dwarves madder).
- BEAR: depends on `PROP(BEAR)` — feed only works if `PROP(BEAR)==0`
  and `HERE(FOOD)`. Then destroy food, `PROP(BEAR)=1` (tame),
  `FIXED(AXE)=0`, `PROP(AXE)=0` (axe drops free). Msg #168.
- Else: msg #14 ("I'm game. Would you care to explain how?").

### 6p. FILL (STMT 9220)

- VASE → STMT 9222: if at water loc and toting vase: msg #145
  (vase shatters from water shock), `PROP(VASE)=2`, `FIXED(VASE)=-1`.
- Bottle:
  - Already has liquid → msg #105 ("your bottle is already full").
  - No liquid here → msg #106 ("there is nothing here with which to
    fill the bottle").
  - Else: `PROP(BOTTLE) = MOD(COND(LOC),4)/2*2`. (0=water, 2=oil.)
    Msg #107 (water) or #108 (oil).

### 6q. BLAST (STMT 9230)

- `PROP(ROD2) < 0` (no dynamite) OR `.NOT.CLOSED` → msg #54 ("OK.").
- Else `BONUS = 133` default. `LOC==115` (NE end of repository) →
  `BONUS=134`. `HERE(ROD2)` → `BONUS=135` ("you blew yourself up").
- Print BONUS msg, GOTO 20000 (scoring with bonus).

### 6r. SCORE (STMT 8240)

`SCORNG=.TRUE.`, GOTO 20000 (compute), come back at 8241 to print:
"If you were to quit now, you would score N out of MX."
`GAVEUP = YES(143, 54, 54)`. If yes, exit.

### 6s. FEE-FIE-FOE-FOO (STMT 8250)

- Look up `WD1` in section 4 of vocab (special-verb table). Get `K`
  (1=FEE, 2=FIE, 3=FOE, 4=FOO).
- If `FOOBAR == 1-K` (the previous incantation step): advance.
  Else if `FOOBAR != 0`: msg #151 ("what's the matter, can't you read?
  Now you'd best start over.").
- `FOOBAR = K`. If `K != 4`: msg #54 ("OK."). 
- If `K == 4` (FOO): zero `FOOBAR`. If eggs at canon home (PLAC(EGGS)
  = canon 92 = Giant Room) and we're not standing there carrying them:
  no-op, msg #29 ("nothing happens"). Else: if eggs at limbo (place=0)
  and troll not yet vanished and `PROP(TROLL)==0`: bring troll back,
  `PROP(TROLL)=1` (so player can't easily re-cross). Move eggs to
  PLAC(EGGS). PSPEAK eggs prop based on whether we were there or near.

### 6t. BRIEF (STMT 8260)

`SPK=156`, `ABBNUM=10000`, `DETAIL=3`. (Permanent short descriptions.)
Msg #156: "Okay, from now on I'll only describe a place in full the
first time you come to it. To get the full description, say LOOK."

### 6u. READ (STMT 8270 / 9270)

Auto-detect target: MAGAZINE → MAGZIN, TABLET → TABLET, MESSAG → MESSAG,
or (if `CLOSED && TOTING(OYSTER)`): OYSTER. Read fails in dark.
- MAGZIN: msg #190.
- TABLET: msg #196 ("CONGRATULATIONS ON BRINGING LIGHT INTO THE
  DARK-ROOM!").
- MESSAG: msg #191 ("the message reads: GO WEST").
- OYSTER (only at closed time after hint): YESX(192, 193, 54) — the
  hint chain.

### 6v. BREAK (STMT 9280)

- MIRROR: msg #148. If `CLOSED`: GOTO 19000 (penalty).
- VASE if `PROP(VASE)==0`: msg #198 ("you have taken the vase and
  hurled it down to the depths"). `PROP(VASE)=2`, `FIXED(VASE)=-1`.
  Drop if toting.

### 6w. WAKE (STMT 9290)

- DWARF and `CLOSED`: msg #199 (dwarves wake up at endgame). GOTO 19000.

### 6x. SUSPEND (STMT 8300)

PDP-10-only: invokes `CIAO` to write save file with timestamp. On
restart, `SETUP=-1` reroutes to STMT 8305 to resume mid-game.

### 6y. HOURS (STMT 8310)

PDP-10 prime-time hours display.

---

## 7. Hint system (lines 1812-1852)

`HNTMAX` is the max hint number (canon = 9). Hints 1-3 are reserved:
- Hint 1: unused (would conflict with COND bit 0 = light).
- Hint 2: "remember if read repository clue" (used at endgame).
- Hint 3: "remember if asked for verbose instructions" (gates LIMIT
  bonus).

Hints 4-9 are the player-visible offers:
- 4 (CAVE): can't find way into cave (rooms 1-7).
- 5 (BIRD): can't catch bird (room 13).
- 6 (SNAKE): can't get past snake (room 19).
- 7 (MAZE): lost in maze (rooms 5, 65, 66, 108, 111).
- 8 (DARK): pondering dark room (room 100).
- 9 (WITT): at Witt's End (room 108).

Each hint has 4 fields in `HINTS(I, 1..4)`:
- 1: turn threshold (5/8/20/etc.)
- 2: point cost (5/2/3/4)
- 3: offer message number
- 4: hint message number

`STMT 40000` — dispatch by `HINT-3`:
- 40400 (CAVE): if grate locked AND no keys → offer.
- 40500 (BIRD): if bird here AND toting rod AND object is bird → offer.
- 40600 (SNAKE): if snake here AND no bird → offer.
- 40700 (MAZE): if no objects in current/old/old2 rooms AND holdng>1 → offer.
- 40800 (DARK): if emerald gotten AND pyramid not gotten → offer.
- 40900 (WITT): always offer.

`STMT 40010` (offer routine):
- `HINTLC(HINT)=0` (reset counter)
- YES `HINTS(HINT,3)`: ask "I am prepared to give you a hint, but it
  will cost you N points." (msg #40012)
- If accepted: `HINTED(HINT) = YES(175, HINTS(HINT,4), 54)`. Msg #175
  is "Sorry, I don't have any more hints" (the post-hint clamp).
- If hinted and `LIMIT > 30`: `LIMIT += 30 * HINTS(HINT,2)` (extra
  lamp turns to compensate for points lost).

---

## 8. Cave closing / endgame / scoring (lines 1853-2092)

### 8a. Closing trigger (STMT 10000)

Fires when `CLOCK1` reaches 0 (set when `TALLY==0` and player is
deep in cave for ~30 turns):

- `PROP(GRATE) = 0` (grate now stuck).
- `PROP(FISSUR) = 0` (bridge now stuck).
- All dwarves dead: `DSEEN(I)=.FALSE.`, `DLOC(I)=0`.
- Move troll to limbo, instantiate phony troll at canon 117/122
  (so the bridge geometry persists).
- If bear not dead: destroy bear.
- `PROP(CHAIN)=0`, `FIXED(CHAIN)=0`, `PROP(AXE)=0`, `FIXED(AXE)=0`.
- Msg #129 ("a sepulchral voice...").
- `CLOCK1=-1`, `CLOSNG=.TRUE.`.

### 8b. Repository setup (STMT 11000)

Fires when `CLOCK2` reaches 0:

- Move all sleeping dwarves, the empty bottles, plant nursery, oysters,
  lamps, rods (with stars), MIRROR to canon 115 (NE repository).
- Move grate, snake, caged bird, more rods, pillows, mirror's other
  half to canon 116 (SW repository).
- `MIRROR.FIXED=116` (spans both halves).
- Destroy everything the player was carrying (no inventory at endgame).
- Msg #132 ("a blinding flash of light...").
- `CLOSED=.TRUE.`. Player at canon 115. `OLDLOC=115`, `NEWLOC=115`.

### 8c. Lamp dim/replace (STMT 12000-12600)

- 12000 (auto-replace): `LIMIT<=30` AND `HERE(BATTER)` AND `PROP(BATTER)==0`
  AND `HERE(LAMP)`. Msg #188 ("your lamp is getting dim..."), set
  `PROP(BATTER)=1`, `LIMIT += 2500`, `LMWARN=.FALSE.`.
- 12200 (warn): `LIMIT<=30` and lamp here, `LMWARN=.TRUE.`. Msg
  varies — #187 (replacement available), #183 (no batteries seen),
  or #189 (batteries already used).
- 12400 (lamp out): `LIMIT==0`. Msg #184 ("your lamp has run out of
  power"). `PROP(LAMP)=0`. Force `LIMIT=-1`.
- 12600 (lost-cause forced quit): `LIMIT<0` AND outside cave. Msg
  #185 ("there's not much point in wandering around out here..."),
  `GAVEUP=.TRUE.`, GOTO 20000.

### 8d. Scoring (STMT 20000)

```
# Treasures
For I=50..MAXTRS where PTEXT(I)!=0:
  K = (I==CHEST ? 14 : (I>CHEST ? 16 : 12))
  If PROP(I)>=0: SCORE += 2 (found)
  If PLACE(I)==3 AND PROP(I)==0: SCORE += K-2 (deposited)
  MXSCOR += K

SCORE += (MAXDIE - NUMDIE) * 10        ; survived deaths
MXSCOR += MAXDIE * 10
SCORE += 4 if NOT(SCORNG OR GAVEUP)    ; didn't quit
MXSCOR += 4
SCORE += 25 if DFLAG != 0              ; got into cave
MXSCOR += 25
SCORE += 25 if CLOSNG                  ; reached endgame
MXSCOR += 25
If CLOSED:
  SCORE += 10 if BONUS==0   ; quit/killed at endgame
  SCORE += 25 if BONUS==135 ; klutzed (blasted yourself)
  SCORE += 30 if BONUS==134 ; wrong way (blasted at NE end)
  SCORE += 45 if BONUS==133 ; mastery (blasted at SW end)
MXSCOR += 45

SCORE += 1 if PLACE(MAGZIN)==108       ; magazine at Witt's End
MXSCOR += 1

SCORE += 2 (round it off)
MXSCOR += 2

For I=1..HNTMAX:
  If HINTED(I): SCORE -= HINTS(I,2)    ; hint penalty
```

Total MXSCOR = 350 in canon (15 treasures × ~14 + 50 deaths + 4 + 25
+ 25 + 45 + 1 + 2 = roughly 350).

Player class lookup: walk `CTEXT/CVAL` table for first `CVAL(I) >=
SCORE`. Print class message + "next rating in N point(s)".

---

## 9. I/O routines (lines 2098-2305)

| Routine | Lines | Purpose |
|---|---|---|
| `SPEAK(N)` | 2098-2120 | print msg starting at `LINES(N)`. Skip if `LINES(N+1) == '>$<'` (sentinel for empty messages). |
| `PSPEAK(MSG, SKIP)` | 2124-2142 | print SKIP+1th message starting at `PTEXT(MSG)`. SKIP=-1 prints inventory msg directly. |
| `RSPEAK(I)` | 2146-2156 | print section-6 msg #I. Equivalent to `SPEAK(RTEXT(I))`. |
| `MSPEAK(I)` | 2160-2170 | print section-12 magic msg. |
| `GETIN(W1, W1X, W2, W2X)` | 2174-2223 | read up to two 5-char words (split on whitespace). Lower-case hash via `XOR '@@@@@'`. |
| `YES(X,Y,Z)` | 2227-2237 | wrapper around `YESX` using `RSPEAK`. |
| `YESM(X,Y,Z)` | 2241-2251 | wrapper around `YESX` using `MSPEAK`. |
| `YESX(X,Y,Z,SPK)` | 2255-2275 | print X, read yes/no, print Y or Z, return bool. |
| `A5TOA1(A,B,C,CHARS,LENG)` | 2279-2305 | unpack A5-format words into a per-char array for sprintf-style formatting. |

---

## 10. Data-structure routines (lines 2306-2451)

| Routine | Purpose |
|---|---|
| `VOCAB(ID, INIT)` | Look up word in `KTAB/ATAB`. If `INIT>=0`: only consider words of that type, return mod 1000. |
| `DSTROY(OBJ)` | `MOVE(OBJ, 0)` — limbo. |
| `JUGGLE(OBJ)` | Pick up + drop at same loc — relocates OBJ to head of `ATLOC` chain (canonical "this is the most relevant thing here" presentation order). |
| `MOVE(OBJ, WHERE)` | Generic teleport: pick up if anywhere, drop at WHERE. Object IDs > 100 reference the second placement of two-place objects. |
| `PUT(OBJ, WHERE, PVAL)` | `MOVE` plus return `-1-PVAL` to set negated PROP for repository setup. |
| `CARRY(OBJ, WHERE)` | Add OBJ to player inventory. Removes from current chain, sets `PLACE=-1`, increments `HOLDNG`. |
| `DROP(OBJ, WHERE)` | Place OBJ at WHERE. Decrements HOLDNG if was carried. Prefixes onto `ATLOC` chain. |

---

## 11. Wizardry / PDP-10 timesharing (lines 2452-end)

| Routine | Purpose | Port relevance |
|---|---|---|
| `START(DUMMY)` | Prime-time check, save-restore latency. | ⚪ scope-out (PDP-10-specific) |
| `MAINT` | Maintenance mode (hours, magic word, demo length, save). | ⚪ scope-out |
| `WIZARD(DUMMY)` | Magic-word challenge protocol. | ⚪ scope-out |
| `HOURS`, `HOURSX`, `NEWHRS` | Display/edit prime-time hours. | ⚪ scope-out |
| `MOTD(F)` | Print message of the day. | 🟡 partial — port has welcome panel with credit splash |
| `POOF` | Init the wizard COMMON block defaults. | ⚪ scope-out |
| `CIAO` | Write save state and exit. | 🟡 partial — port has save/load |
| `DATIME(D, T)` | PDP-10 date/time. | 🟢 not needed — no time-of-day gates |

These are PDP-10-specific timesharing artifacts (multi-user prime time
gating, the wizard impostor challenge with hashed phrase verification,
holiday detection). For a modern port, ⚪ scope-out unless specifically
requested.

---

## 12. Magic numbers — every literal that gates behavior

This is the canonical "constants" inventory. Each port should match
these exactly unless deliberately diverging.

### Limits / bounds
| Const | Value | Source | Meaning |
|---|---|---|---|
| `LINSIZ` | 9650 | line 90 | message-text storage capacity (irrelevant for port) |
| `TRVSIZ` | 750 | line 90 | travel-table capacity |
| `TABSIZ` | 300 | line 90 | vocabulary capacity |
| `LOCSIZ` | 150 | line 90 | location capacity (canon uses 140) |
| `VRBSIZ` | 35 | line 90 | action verbs capacity |
| `RTXSIZ` | 205 | line 90 | section-6 message capacity |
| `CLSMAX` | 12 | line 90 | player class count |
| `HNTSIZ` | 20 | line 90 | hint capacity (canon uses 9) |
| `MAGSIZ` | 35 | line 90 | section-12 magic message capacity |
| `MAXTRS` | 79 | line 421 | highest treasure object ID |
| `HOLDNG` (max) | 7 | line 1245 | inventory-slot limit |

### Lamp and timing
| Const | Value | Source | Meaning |
|---|---|---|---|
| `LIMIT` (init) | 330 | line 625 | lamp battery turns |
| `LIMIT` (verbose) | 1000 | line 626 | with HINTED(3) |
| `LIMIT` (cap) | 35 | line 829 | hurry-up if treasures elusive |
| `LIMIT` (warn) | 30 | line 891 | dim warning threshold |
| `LIMIT` (battery refill) | +2500 | line 1957 | auto-replace adds 2500 |
| `CLOCK1` (init) | 30 | line 560 | turns from "found all" to closing |
| `CLOCK2` (init) | 50 | line 561 | turns from warning to flash |
| `CLOCK2` (panic) | 15 | line 633, 1355 | shorter timer if player tries to leave |

### Probabilities
| Roll | Value | Source | Meaning |
|---|---|---|---|
| First-dwarf trigger | 95% | line 668 | `IF LOC>=15 AND PCT(95) GOTO 2000` (5% spawns) |
| First-dwarf kill | 50% | line 673 | per dwarf, 50% to remove pre-spawn |
| Pirate-spotted noise | 20% | line 731 | 20% chance to print msg #127 |
| Y2 PLUGH whisper | 25% | line 808 | at room 33, 25% prints msg #8 |
| Pit-fall in dark | 35% | line 802 | per motion attempt (after warning) |
| Dwarf knife miss/hit | 95*(DFLAG-2)/1000 | line 762 | accuracy ramps up |
| Axe-throw kill chance | 33% | line 1571 | `RAN(3)==0` |
| Random "I don't understand" | 20%/20% | lines 920-921 | msg #60/#61/#13 split |
| `IWEST` shamng | every 10 | lines 901-902 | 10th "WEST" prints msg #17 |

### Scoring weights
| Weight | Value | Source | Meaning |
|---|---|---|---|
| Treasure found | 2 | line 2018 | per treasure |
| Pre-chest deposited | 12 | line 2015 | obj < CHEST (50..54) |
| Chest deposited | 14 | line 2016 | obj == CHEST (55) |
| Post-chest deposited | 16 | line 2017 | obj > CHEST (56..64) |
| Survived per death | 10 | line 2030 | (MAXDIE-NUMDIE)*10 |
| Didn't quit | 4 | line 2032 | bonus |
| Got into cave | 25 | line 2034 | DFLAG != 0 |
| Reached endgame | 25 | line 2036 | CLOSNG |
| BLAST mundane | 10 | line 2039 | BONUS == 0 (plain endgame death) |
| BLAST klutz | 25 | line 2040 | BONUS == 135 |
| BLAST wrong-way | 30 | line 2041 | BONUS == 134 |
| BLAST mastery | 45 | line 2042 | BONUS == 133 |
| Magazine at Witt's End | 1 | line 2047 | flavor bonus |
| Round-off | 2 | line 2052 | always-on |
| Hint penalty | per-hint | line 2058 | `HINTS(I, 2)` deducted if HINTED |

### Object ID constants (canon)
| Mnemonic | ID | Note |
|---|---|---|
| KEYS | 1 | |
| LAMP | 2 | |
| GRATE | 3 | fixed |
| CAGE | 4 | |
| ROD | 5 | rod with rusty star (magic) |
| ROD2 | 6 | rod with mark (decoy) |
| STEPS | 7 | fixed, two-loc (14 + 15) |
| BIRD | 8 | |
| DOOR | 9 | rusty iron door, fixed |
| PILLOW | 10 | |
| SNAKE | 11 | fixed at room 19 |
| FISSUR | 12 | crystal-bridge target, two-loc (17 + 27) |
| TABLET | 13 | fixed at 101 |
| CLAM | 14 | becomes oyster |
| OYSTER | 15 | spawned dynamically |
| MAGZIN | 16 | spelunker today |
| FOOD | 19 | |
| BOTTLE | 20 | |
| WATER | 21 | virtual obj for liquid in bottle |
| OIL | 22 | virtual obj for liquid in bottle |
| MIRROR | 23 | fixed at 109 |
| PLANT | 24 | fixed at 25 (West Pit) |
| PLANT2 | 25 | phony plant at 23 + 67 |
| AXE | 28 | dropped by first dwarf |
| DRAGON | 31 | fixed, two-loc (119 + 121) |
| CHASM | 32 | troll bridge target, two-loc (117 + 122) |
| TROLL | 33 | fixed, two-loc |
| TROLL2 | 34 | phony troll placeholder |
| BEAR | 35 | at canon 130 |
| MESSAG | 36 | second-maze message |
| VEND | 38 | vending machine at 140 |
| BATTER | 39 | batteries from vending |
| NUGGET (gold) | 50 | first treasure |
| COINS | 54 | |
| CHEST | 55 | dynamic (pirate stash) |
| EGGS | 56 | |
| TRIDNT | 57 | |
| VASE | 58 | fragile |
| EMRALD | 59 | |
| PYRAM | 60 | |
| PEARL | 61 | from oyster |
| RUG | 62 | under dragon |
| CHAIN | 64 | the 15th treasure (with bear) |

### Room hardcodes
| Const | Value | Meaning |
|---|---|---|
| `CHLOC` | 114 | pirate's chest stash (dead end of maze 1) |
| `CHLOC2` | 140 | dead end of maze 2 (where MESSAG goes) |
| `DALTLC` | 18 | dwarf alternate spawn |
| Initial `DLOC(1..6)` | 19, 27, 33, 44, 64, 114 | five dwarves + pirate |
| Reincarnation home | 3 | well house |
| Lamp on death | 1 | end of road |
| Plover Room | 99 / 100 | for routine 301 (`99+100-LOC`) |
| Pearl drop | 105 | when clam is broken (Cul-de-sac) |
| NE repository | 115 | where player ends at endgame |
| SW repository | 116 | grate + treasures + mirror |
| Witt's End | 108 | for magazine bonus |
| Y2 | 33 | for PLUGH whisper roll |
| `LOC>=15` | Hall of Mists | dwarves activate threshold |
| `LOC<=8` | above-ground | "outdoors" lamp-ran-out check |

---

## 13. Verb→branch dispatch table

From STMT 4080 (intransitive) and 4090 (transitive).

| Verb | ID | Intrans STMT | Trans STMT | Notes |
|---|---|---|---|---|
| TAKE / CARRY / GET | 1 | 8010 | 9010 | |
| DROP / RELEASE | 2 | 8000 | 9020 | |
| SAY | 3 | 8000 | 9030 | |
| OPEN / UNLOCK | 4 | 8040 | 9040 | also acts on clam/oyster |
| NOTHING / NULL | 5 | 2009 | 2009 | "OK." |
| LOCK | 6 | 8040 | 9040 | shares 9040 |
| ON | 7 | 9070 | 9070 | lamp on |
| OFF | 8 | 9080 | 9080 | lamp off |
| WAVE | 9 | 8000 | 9090 | |
| CALM / TAME / etc. | 10 | 8000 | 2011 | "OK." stub |
| WALK / GO / RUN | 11 | 2011 | 2011 | "OK." (already moved) |
| KILL / ATTACK | 12 | 9120 | 9120 | |
| POUR | 13 | 9130 | 9130 | |
| EAT | 14 | 8140 | 9140 | |
| DRINK | 15 | 9150 | 9150 | |
| RUB | 16 | 8000 | 9160 | |
| TOSS / THROW | 17 | 8000 | 9170 | |
| QUIT | 18 | 8180 | 2011 | |
| FIND | 19 | 8000 | 9190 | |
| INVENTORY / INVN | 20 | 8200 | 9190 | trans = FIND-equivalent |
| FEED | 21 | 8000 | 9210 | |
| FILL | 22 | 9220 | 9220 | |
| BLAST | 23 | 9230 | 9230 | |
| SCORE | 24 | 8240 | 2011 | |
| FOO / FEE / FIE / FIE | 25 | 8250 | 2011 | |
| BRIEF | 26 | 8260 | 2011 | |
| READ | 27 | 8270 | 9270 | |
| BREAK | 28 | 8000 | 9280 | |
| WAKE | 29 | 8000 | 9290 | |
| SUSPEND | 30 | 8300 | 2011 | |
| HOURS | 31 | 8310 | 2011 | |

---

## 14. Side-effect fingerprint per verb

A reverse index — what state each verb mutates. For the audit's
"port covers this verb" rows.

| Verb | Mutates |
|---|---|
| TAKE | `PLACE`, `HOLDNG`, `PROP(BIRD)` (cage), `PROP(BOTTLE)` (liquid follow) |
| DROP | `PLACE`, `HOLDNG`, `PROP(SNAKE)`, `PROP(BIRD)`, `PROP(VASE)`, `PROP(TROLL)`, `PROP(DRAGON)`, `PROP(BEAR)`, `FIXED(VASE)`, `TALLY2` |
| OPEN/LOCK | `PROP(GRATE)`, `PROP(DOOR)`, `PROP(CLAM)/(OYSTER)`, drops PEARL, `PROP(CHAIN)`, `PROP(BEAR)`, `FIXED(BEAR/CHAIN)`, `CLOCK2` (closing) |
| ON | `PROP(LAMP)` |
| OFF | `PROP(LAMP)` |
| WAVE | `PROP(FISSUR)` (toggle bridge) |
| ATTACK | `PROP(DRAGON)`, `PROP(RUG)`, moves player to dragon center, kills bird/snake, sets `PROP(BIRD)/(SNAKE)`, `TALLY2` |
| POUR | `PROP(BOTTLE)`, `PROP(PLANT)`, `PROP(PLANT2)`, `PROP(DOOR)`, `PLACE(WATER/OIL)` |
| EAT | destroys FOOD |
| DRINK | `PROP(BOTTLE)`, `PLACE(WATER)` |
| THROW | (axe at dwarf) `DSEEN`, `DLOC`, `DKILL`. (treasure at troll) destroys treasure, juggles troll/chasm. (food at bear) → FEED. |
| QUIT | `GAVEUP`, `SCORNG` (final score) |
| FIND | none |
| INVENTORY | none (just reads) |
| FEED | destroys FOOD, `PROP(BEAR)`, `FIXED(AXE)`, `PROP(AXE)`, `DFLAG` (if dwarf), kills bird (if snake) |
| FILL | `PROP(BOTTLE)`, `PLACE(WATER/OIL)`, `PROP(VASE)`, `FIXED(VASE)` |
| BLAST | `BONUS`, exits via 20000 |
| SCORE | `SCORNG` |
| FEE/FIE/FOE/FOO | `FOOBAR`, `PLACE(EGGS)`, `PROP(TROLL)` (resurrect if mid-cross) |
| BRIEF | `ABBNUM`, `DETAIL` |
| READ | `HINTED(2)` (oyster hint chain) |
| BREAK | `PROP(VASE)`, `FIXED(VASE)`, drops VASE if toted. `MIRROR` only at endgame. |
| WAKE | endgame penalty (GOTO 19000) only if CLOSED |
| SUSPEND | `SAVED`, `SAVET`, exits via CIAO |

---

## Bookkeeping

This document is hand-extracted from `advent.for` lines 1-2700 with
emphasis on routines and constants the port must replicate. The
remaining ~150 lines (lines 2700-end) cover:
- `MOTD`: message-of-the-day printer (port uses welcome panel).
- `POOF`: wizard-COMMON setup defaults (irrelevant).
- `CIAO`: file write/exit routine (port has its own save/load).
- `BUG(N)`: assertion failure routine.

These don't affect game behavior and are intentionally out of scope
for this inventory.

The companion `ADVENT_DAT_INVENTORY.md` is the data-side reference;
together they form the complete canon source-of-truth for the port
audit (`CANON_FULL_AUDIT.md` cross-references against current
`cca/godot/` and `cca/frame/cca.fgd`).
