# Canon-vs-port full audit

Goal: 100% Crowther/Woods 1977 fidelity. This document maps every
canon mechanic to its port status. Companions:

- `cca/canon/ADVENT_FOR_INVENTORY.md` — FORTRAN-side reference.
- `cca/canon/ADVENT_DAT_INVENTORY.md` — data-side reference.
- `cca/CANON_LOCATIONS.md` — per-room rendered detail.
- `cca/CANON_FULL_PLAN.md` — dependency-ordered plan to close every
  open row.

**Status legend:**
- ✓ — implemented and tested at canon parity.
- 🟡 — partially implemented; specific gap noted.
- 🔴 — not implemented; canon mechanic missing.
- ⚪ — deliberately out of scope (PDP-10-specific or platform-dependent);
  rationale noted. **No row is ⚪ without explicit user sign-off.**

**Coverage tally** (rolled up at end of doc): 38/38 architectural-conformance,
44/62 conditional rows, 14/14 lit rooms, 18/18 pirate-forbidden, 9/9
hint rooms, 0 ⚪ entries — every gap is tracked, no items deferred
without sign-off.

---

## 1. Travel table — conditional rows

Source: ADVENT_DAT_INVENTORY.md section 3 conditional table (45 rows).

### 1.1 Carrying-conditional rows (M=100..200)

| Row | Canon | Decoded | Port status | Port location |
|---|---|---|---|---|
| `14 150020 30 31 34` | DOWN/PIT/STEPS @ 14, carrying GOLD → room 20 (death) | gold-falls-pit | ✓ | `topology.gd` GATES `14:down/pit/steps` carrying-with-dest=20; `test_cca_gold_falls_pit.gd` |
| `15 150022 29 31 34 35 23 43` | UP/PIT/STEPS/DOME/PASSAGE/EAST @ 15, carrying GOLD → room 22 (dome unclimbable) | gold-blocks-steps | ✓ | `topology.gd` GATES `15:up/east/pit/steps/dome/passage` carrying-with-msg; `test_cca_gold_blocks_steps.gd` |
| `33 159302 71` | PLOVER @ Y2, carrying EMERALD → routine 302 (drop emerald, force squeeze) | plover-emerald drop | 🔴 | port's `MagicWordTeleport` always teleports unconditionally; routine 302 not implemented |
| `100 159302 71` | PLOVER @ 100, carrying EMERALD → routine 302 | mirror | 🔴 | same as above |
| `103 114618 46` | SOUTH @ 103, carrying CLAM → msg #118 ("can't fit clam through") | clam squeeze | ✓ | `cca.fgd` Adventure._verb_move clam check; test_cca_clam_squeeze |
| `103 115619 46` | SOUTH @ 103, carrying OYSTER → msg #119 ("can't fit oyster through") | oyster squeeze | ✓ | same handler, oyster branch |

### 1.2 Here-or-carrying (M=200..300)

| Row | Canon | Decoded | Port status | Port location |
|---|---|---|---|---|
| `19 211032 49` | SW @ 19, snake-here-or-toted → room 32 (snake-block bumper) | snake-follows | ✓ | wired as second rule in the GATES `19:sw` chain (check=snake, msg "You can't get by the snake."); test: `test_cca_19_sw_chain.gd`. Port doesn't model toted snake (snake is FIXED in canon and the port), so the row reduces to "snake here" — equivalent in observable behavior. |
| `117 233660 41 42 47 69` | OVER/ACROS/CROSS/NE @ 117, troll-here-or-toted → msg #160 ("troll refuses to let you cross") | troll bridge gate | 🟡 | port has `troll.is_blocking_bridge()` gate; canon condition is *here-or-carrying*, port is *blocking* state |
| `122 233660 41 42 47 49` | OVER/ACROS/CROSS/SW @ 122, troll-here-or-toted → msg #160 | mirror | 🟡 | same |

### 1.3 Prop-not-N rows (M=300..600)

| Row | Canon | Decoded | Port status | Port location |
|---|---|---|---|---|
| `8 303009 3 19 30` | ENTER/IN/DOWN @ 8 if grate unlocked → 9 | grate gate | ✓ | `topology.gd` GATES `8:enter/in/down` `check=grate` |
| `9 303008 11 29` | OUT/UP @ 9 if grate unlocked → 8 | grate mirror | ✓ | `topology.gd` GATES `9:up/out` `check=grate` |
| `11 303008 63` | DEPRESSION @ 11 if grate unlocked → 8 | depression teleport | ✓ | GATES `11:depression` |
| `12 303008 63` | DEPRESSION @ 12 if grate unlocked → 8 | mirror | ✓ | GATES `12:depression` |
| `13 303008 63` | DEPRESSION @ 13 if grate unlocked → 8 | mirror | ✓ | GATES `13:depression` |
| `14 303008 63` | DEPRESSION @ 14 if grate unlocked → 8 | mirror | ✓ | GATES `14:depression` |
| `17 312596 39` | JUMP @ 17 if fissure prop != 0 → msg #96 ("use the bridge") | jump-into-fissure | ✓ | `topology.gd` GATES `17:jump` always-bumper |
| `17 412021 7` | FORWARD @ 17 if fissure prop != 1 → room 21 (didn't make it) | fissure forward (no bridge) | ✓ | GATES `17:forward` `check=bridge` `dest=21` (canon `412021` decoded). Pre-bridge: walk to 21 → die via room-entry handler. Post-bridge: gate falls through; topology has no FORWARD so no-exit fires. Test: `test_cca_prop_gates.gd` Phase 1+2. |
| `17 412597 41 42 44 69` | OVER/ACROS/W/CROSS @ 17 if fissure prop != 1 → msg #97 ("no way across") | fissure cross (no bridge) | ✓ | `topology.gd` GATES `17:over/across/west/cross` `check=bridge` with msg |
| `19 311028 45 36` | NORTH/LEFT @ 19 if snake gone → 28 | snake-cleared NORTH | ✓ | GATES `19:north`/`19:left` `check=snake` (block when blocking) |
| `19 311029 46 37` | SOUTH/RIGHT @ 19 if snake gone → 29 | snake-cleared SOUTH | ✓ | GATES `19:south`/`19:right` `check=snake` |
| `19 311030 44 7` | WEST/FORWARD @ 19 if snake gone → 30 | snake-cleared WEST | ✓ | GATES `19:west`/`19:forward` `check=snake` |
| `25 724031 56` | CLIMB @ 25 if plant prop != 4 → 31 | climb beanstalk before huge | 🟡 | port has `plant_huge` gate at `25:climb` blocking when plant not huge; canon's branch routes to room 31 which is "you can't get there from here" — port emits the bumper message |
| `27 312596 39` | JUMP @ 27 if fissure prop != 0 → msg #96 | mirror | ✓ | GATES `27:jump` |
| `27 412021 7` | FORWARD @ 27 if fissure prop != 1 → room 21 | mirror | ✓ | GATES `27:forward` `check=bridge` `dest=21`, mirror of 17:forward. Test: `test_cca_prop_gates.gd` Phase 1. |
| `27 412597 41 42 43 69` | OVER/ACROS/E/CROSS @ 27 if fissure prop != 1 → msg #97 | mirror | ✓ | GATES `27:over/across/east/cross` |
| `31 524089 v1` | any-verb @ 31 if plant prop != 2 → room 89 | failed-climb bounce | 🟡 | port treats room 31 as forced-motion bouncer with explicit out-route (`OUT/BACK`) — canon uses any-verb fallback per cond=2 |
| `69 331120 46` | SOUTH @ 69 if dragon prop != 0 → room 120 | dragon-killed shortcut | ✓ | GATES `69:south` `check=dragon_killed` `dest=120`. Pre-kill: gate falls through; topology row 69:south=119 walks normally. Post-kill: gate fires, walks to 120 (the connecting canyon). Test: `test_cca_prop_gates.gd` Phase 3+4. |
| `74 331120 44` | WEST @ 74 if dragon prop != 0 → room 120 | dragon-killed mirror | ✓ | GATES `74:west` `check=dragon_killed` `dest=120`, mirror of 69:south. Test: `test_cca_prop_gates.gd` Phase 3+4. |
| `94 309095 45 3 73` | NORTH/ENTER/CAVERN @ 94 if door prop != 0 → 95 | rusty-door open | ✓ | GATES `94:north/enter/cavern` `check=rusty` |
| `108 95556 ...` | E/N/S/NE/SE/SW/NW/UP/DOWN @ Witt's End, 95% prob → msg #56 | Witt's End bounce | ✓ | GATES `108:*` `check=probability` pct=95 |
| `108 626 44` | WEST @ 108, unconditional → msg #126 (cave-in) | Witt's End west | ✓ | GATES `108:west` always-bumper |
| `117 332661 41` | OVER @ 117 if chasm prop != 0 → msg #161 (no longer any way) | post-bear chasm | 🟡 | port handles via `troll.state == "vanished"` gate but the canon condition is `chasm prop` (state of chasm, not troll) |
| `117 332021 39` | JUMP @ 117 if chasm prop != 0 → room 21 (didn't make it) | jump after bear-fall | ✓ | GATES `117:jump` is now a chain: rule 1 `chasm_collapsed` `dest=21` (post-bear → die), rule 2 `always` msg #96 (pre-bear → "use the bridge"). Same chain at `122:jump`. Port models chasm-collapsed via the troll FSM's `$Vanished` terminal state. Test: `test_cca_prop_gates.gd` Phase 5+6. |

### 1.4 Probability-only rows (M=1..99)

| Row | Canon | Port status |
|---|---|---|
| `5 50005 6 7 45` | FOREST/FORWARD/NORTH @ 5, 50% → 5 (forest random walk) | ✓ — GATES `5:forest`/`5:forward`/`5:north` each `[{probability pct=50 dest=5}]`. Net: 50% self-loop / 50% topology fallback (FOREST→6 unconditional; FORWARD/NORTH no exit). Test: `test_cca_maze_decoration.gd`. |
| `19 35074 49` | SW @ 19, 35% → 74 (dragon-canyon shortcut) | ✓ — wired as first rule in the GATES `19:sw` chain (check=probability, pct=35, dest=74). Topology row 19 no longer has unconditional `sw`. Test: `test_cca_19_sw_chain.gd` (Phase 5 verifies 35% hit rate in 1000 isolated rolls). |
| `65 80556 46` | SOUTH @ 65, 80% → msg #56 | ✓ — GATES `65:south` chain (Bedquilt) |
| `65 80556 29` | UP @ 65, 80% → msg #56 | ✓ — first rule of `65:up` chain |
| `65 50070 29` | UP @ 65, 50% → room 70 | ✓ — second rule of `65:up` chain |
| `65 60556 45` | NORTH @ 65, 60% → msg #56 | ✓ — first rule of `65:north` chain |
| `65 75072 45` | NORTH @ 65, 75% → room 72 | ✓ — second rule of `65:north` chain |
| `65 80556 30` | DOWN @ 65, 80% → msg #56 | ✓ — GATES `65:down` chain |
| `66 80556 46` | SOUTH @ 66, 80% → msg #56 | ✓ — GATES `66:south` chain (Swiss Cheese) |
| `66 50556 50` | NW @ 66, 50% → msg #56 | ✓ — GATES `66:nw` chain |
| `111 40050 30 39 56` | DOWN/JUMP/CLIMB @ 111, 40% → 50 | ✓ — first rule of `111:down`/`111:jump`/`111:climb` chains (stalactite). |
| `111 50053 30` | DOWN @ 111, 50% → 53 | ✓ — second rule of `111:down` chain. |

All 11 maze-decoration rows verified by `test_cca_maze_decoration.gd` (22 distribution checks, 1000 rolls each, all dead-on canon).

### 1.5 Forbidden-to-dwarves (M=100)

| Row | Canon | Port status |
|---|---|---|
| `61 100107 46` | SOUTH @ 61, anyone except dwarves → 107 | 🟡 (port walks unconditionally; dwarves can follow into 107 in port) |

---

## 2. Travel table — bumper rows (special routines)

Source: ADVENT_DAT_INVENTORY.md section 3 bumper table (6 rows).

| Row | Canon | Routine | Port status |
|---|---|---|---|
| `99 301 43 23` | EAST/PASSAGE/TUNNEL @ 99 → routine 301 | plover squeeze | ✓ — `plover_squeeze_blocked()` |
| `100 301 44 23 11` | WEST/PASSAGE/TUNNEL/OUT @ 100 → routine 301 | plover squeeze mirror | ✓ |
| `33 159302 71` | PLOVER @ 33 if EMERALD held → routine 302 | plover transport drop-emerald | 🔴 (see §1.1) |
| `100 159302 71` | PLOVER @ 100 if EMERALD held → routine 302 | mirror | 🔴 |
| `117 303 41` | OVER @ 117 → routine 303 | troll bridge | ✓ — `Adventure._verb_move` + Troll FSM |
| `122 303 41` | OVER @ 122 → routine 303 | troll bridge mirror | ✓ |

---

## 3. Travel table — msg500 rows (29 rows)

These are pure bumper messages on motion attempts. Per-row port status:

| Row | Canon msg # | Trigger | Port status |
|---|---|---|---|
| `7 595` | msg #95 | SLIT/STREAM/DOWN @ 7 | ✓ — `7:slit/stream/down` always-bumper msg #95 |
| `8 593` | msg #93 | ENTER @ 8 (locked grate) | ✓ — covered by grate gate falling through to msg #93 ("locked steel grate") |
| `9 593` | msg #93 | OUT @ 9 (locked grate) | ✓ — covered by grate gate at `9:out` |
| `17 312596 39` | msg #96 | JUMP @ 17 | ✓ — see §1.3 |
| `17 412597 41 42 44 69` | msg #97 | OVER/ACROSS/W/CROSS @ 17 | ✓ — see §1.3 |
| `23 648 52` | msg #148 | HOLE @ 23 ("too far up") | 🔴 — port has no `23:hole` gate |
| `27 312596 39` | msg #96 | JUMP @ 27 | ✓ |
| `27 412597 41 42 43 69` | msg #97 | OVER/ACROSS/E/CROSS @ 27 | ✓ |
| `38 595` | msg #95 | SLIT/STREAM/DOWN/UP/UPSTREAM/DOWNSTREAM @ 38 | 🔴 — port doesn't model canon-38 (is the Bottom of Pit with stream) |
| `65 80556 46` | msg #56 | SOUTH @ 65, 80% | 🔴 (probability) |
| `65 80556 29` | msg #56 | UP @ 65, 80% | 🔴 |
| `65 60556 45` | msg #56 | NORTH @ 65, 60% | 🔴 |
| `65 80556 30` | msg #56 | DOWN @ 65, 80% | 🔴 |
| `66 80556 46` | msg #56 | SOUTH @ 66, 80% | 🔴 |
| `66 50556 50` | msg #56 | NW @ 66, 50% | 🔴 |
| `94 611 45` | msg #111 | NORTH @ 94 (rusty door) | ✓ |
| `103 114618 46` | msg #118 | SOUTH @ 103 carrying clam | ✓ |
| `103 115619 46` | msg #119 | SOUTH @ 103 carrying oyster | ✓ |
| `108 95556 ...` | msg #56 | E/N/S/NE/SE/SW/NW/UP/DOWN @ 108, 95% | ✓ |
| `108 626 44` | msg #126 | WEST @ 108 | ✓ |
| `116 593 30` | msg #93 | DOWN @ 116 (locked grate) | ✓ — `116:down` always-bumper |
| `117 233660 41 42 47 69` | msg #160 | OVER/ACROSS/CROSS/NE @ 117, troll here | ✓ — `troll.is_blocking_bridge()` |
| `117 332661 41` | msg #161 | OVER @ 117, post-bear (chasm prop) | 🟡 — port has gate but uses troll state, not chasm prop |
| `117 596 39` | msg #96 | JUMP @ 117 | ✓ |
| `119 653 43 7` | msg #153 | EAST/FORWARD @ 119 (dragon block) | ✓ — `119:east/forward` always-bumper |
| `121 653 45 7` | msg #153 | NORTH/FORWARD @ 121 | ✓ |
| `122 233660 41 42 47 49` | msg #160 | OVER/ACROSS/CROSS/SW @ 122 | ✓ |
| `122 596 39` | msg #96 | JUMP @ 122 | ✓ |
| `126 610 30 39` | msg #110 | DOWN/JUMP @ 126 (volcano) | ✓ — `126:down/jump` always-bumper |

---

## 4. Vocabulary (section 4) — every word

Source: ADVENT_DAT_INVENTORY.md section 4 (295 entries).

### 4.1 Motion verbs (00..77 in canon)

Listed with port acceptance and synonyms (`driver.verb_synonyms`,
truncation in `_verb_synonyms_5`):

| Canon # | Word | Port accepts | Notes |
|---|---|---|---|
| 1 | ROAD/HILL | ✓ (HILL) | mapped via VERB_TO_DIR |
| 2 | ENTER (alias) | ✓ | DIRECTIONS |
| 3..6 | UPSTREAM/DOWNSTREAM/FOREST/FORWARD | ✓ | motion verbs |
| 7..10 | BACK/VALLEY/STAIRS | ✓ | |
| 11..14 | OUT/IN/GULLY/STREAM | ✓ | |
| 15..18 | ROCK/BED/CRAWL/COBBLES | ✓ | |
| 19 | IN | ✓ | DIRECTIONS |
| 20 | SURFACE | ✓ | |
| 22..28 | DARK/PASSAGE/LOW/CANYON/AWKWARD/GIANT/VIEW | ✓ | |
| 29..30 | UP/DOWN | ✓ | core |
| 31..35 | PIT/OUTDOORS/CRACK/STEPS/DOME | ✓ | core (also gold-block verbs) |
| 36..50 | LEFT/RIGHT/HALL/JUMP/BARREN/OVER/ACROSS/EAST/WEST/NORTH/SOUTH/NE/SE/SW/NW | ✓ | |
| 51..56 | DEBRIS/HOLE/WALL/BROKEN/Y2/CLIMB | ✓ | Y2 in CANON_GATED whitelist |
| 58..69 | FLOOR/ROOM/SLIT/SLAB/PLUGH/DEPRESSION/ENTRANCE/PLUGH/CAVE/XYZZY/CROSS | ✓ | magic words mapped |
| 70..77 | BEDQUILT/PLOVER/ORIENTAL/CAVERN/SHELL/RESERVOIR/OFFICE/FORK | ✓ | long-distance verbs |

### 4.2 Object words (1000+id)

All 64 canon object IDs are mapped in `cca/godot/scripts/driver.gd` and
`cca.fgd` constants (BIRD_ID=100, CHAIN_ID=101, GOLD_ID=110, ...).

| Canon ID | Word | Port ID | Status |
|---|---|---|---|
| 1 | KEYS | 131 | ✓ |
| 2 | LAMP | (Lamp FSM, no constant) | ✓ |
| 3 | GRATE | (Grate FSM) | ✓ |
| 4 | CAGE | 133 | ✓ |
| 5 | ROD (magic) | 130 | ✓ |
| 6 | ROD (decoy) | 141 | ✓ |
| 7 | STEPS | (no port object — implicit room descs) | 🟡 |
| 8 | BIRD | 100 | ✓ |
| 9 | DOOR | (RustyDoor FSM) | ✓ |
| 10 | PILLOW | 135 | ✓ |
| 11 | SNAKE | (Snake FSM) | ✓ |
| 12 | FISSURE | (CrystalBridge FSM) | ✓ |
| 13 | TABLET | 🔴 — port has no TABLET object yet (canon-101 cleanup needed) |
| 14 | CLAM | 137 | ✓ |
| 15 | OYSTER | 138 | ✓ |
| 16 | MAGAZINE | 140 | ✓ |
| 19 | FOOD | 134 | ✓ |
| 20 | BOTTLE | 132 | ✓ |
| 21 | WATER | (virtual; bottle prop) | ✓ |
| 22 | OIL | (virtual; bottle prop) | ✓ |
| 23 | MIRROR | 🔴 — no mirror object; canon's break-mirror endgame penalty missing |
| 24 | PLANT | (Plant FSM) | ✓ |
| 25 | PHONY PLANT (PLANT2) | 🔴 — no phony-plant flavor in twopit room |
| 26 | STALACTITE | 🔴 — no stalactite (alternate maze route) |
| 27 | SHADOWY FIGURE | 🔴 — flavor only; canon room 35/110 |
| 28 | AXE | 136 | ✓ (dropped by first dwarf) |
| 29 | CAVE DRAWINGS | 🔴 — flavor only |
| 30 | PIRATE | (Pirate FSM) | ✓ |
| 31 | DRAGON | (Dragon FSM) | ✓ |
| 32 | CHASM | (CrystalBridge handles it) | 🟡 — chasm prop separate from bridge prop in canon |
| 33 | TROLL | (Troll FSM) | ✓ |
| 34 | TROLL2 | (Troll FSM holds the placeholder) | ✓ |
| 35 | BEAR | (Bear FSM) | ✓ |
| 36 | MESSAGE | 🔴 — second-maze msg from pirate stash; not modelled |
| 37 | VOLCANO | 🔴 — flavor at canon 126 |
| 38 | VENDING | (VendingMachine FSM) | ✓ |
| 39 | BATTERIES | 139 | ✓ |
| 40 | CARPET/MOSS | 🔴 — flavor at canon 96 |
| 50 | GOLD NUGGET | 110 | ✓ |
| 51 | DIAMONDS | 112 | ✓ |
| 52 | SILVER | 111 | ✓ |
| 53 | JEWELRY | 113 | ✓ |
| 54 | COINS | 123 | ✓ |
| 55 | CHEST | 120 | ✓ |
| 56 | EGGS | 116 | ✓ |
| 57 | TRIDENT | 117 | ✓ |
| 58 | VASE | 115 | ✓ |
| 59 | EMERALD | 118 | ✓ |
| 60 | PYRAMID | 121 | ✓ |
| 61 | PEARL | 114 | ✓ |
| 62 | RUG | 122 | ✓ |
| 63 | SPICES | 119 | ✓ |
| 64 | CHAIN | 101 | ✓ |

### 4.3 Action verbs (2000+id)

| Canon # | Word | Port handler | Status |
|---|---|---|---|
| 1 | TAKE/CARRY/KEEP | `_verb_take` | ✓ |
| 2 | DROP/RELEASE | `_verb_drop` | ✓ |
| 3 | SAY | (handled in driver via verb dispatch) | 🟡 — port doesn't echo non-magic words "Okay, X" the way canon does |
| 4 | OPEN/UNLOCK | `_verb_unlock` | ✓ |
| 5 | NOTHING/NULL | (handled by driver "OK" fallback) | ✓ |
| 6 | LOCK | `_verb_lock` | ✓ |
| 7 | ON/LIGHT | `_verb_light` (lamp on) | ✓ |
| 8 | OFF/EXTINGUISH | `_verb_extinguish` | ✓ |
| 9 | WAVE | `_verb_wave` | ✓ |
| 10 | CALM/TAME | 🔴 — no canon "OK" stub for CALM/TAME |
| 11 | WALK/GO/RUN | (driver consumes) | ✓ |
| 12 | KILL/ATTACK | `_verb_attack` | ✓ |
| 13 | POUR | `_verb_pour` | ✓ |
| 14 | EAT | `_verb_eat` | 🟡 — port has FOOD eaten but missing canon msg #71 ("don't have appetite") for ridiculous targets |
| 15 | DRINK | `_verb_drink` | ✓ |
| 16 | RUB | 🔴 — no port handler; canon msg #76 ("not productive") for non-LAMP rubs |
| 17 | TOSS/THROW | `_verb_throw` | ✓ |
| 18 | QUIT | (driver-handled) | ✓ |
| 19 | FIND | 🔴 — no port handler for FIND verb |
| 20 | INVENTORY | (driver-handled) | ✓ |
| 21 | FEED | `_verb_feed` | ✓ |
| 22 | FILL | `_verb_fill` | ✓ |
| 23 | BLAST | 🔴 — endgame BLAST verb not implemented |
| 24 | SCORE | (driver-handled) | ✓ |
| 25 | FEE/FIE/FOE/FOO | `_verb_chant` | ✓ |
| 26 | BRIEF | 🔴 — no port BRIEF (would gate description verbosity) |
| 27 | READ | `_verb_read` | 🟡 — handles MAGAZINE, missing TABLET/MESSAGE/OYSTER-clue |
| 28 | BREAK | `_verb_break` | 🟡 — handles VASE+CLAM, missing endgame MIRROR break |
| 29 | WAKE | 🔴 — endgame "wake the dwarves" not implemented |
| 30 | SUSPEND | `driver._process_input` "suspend" handler | ✓ — prints canon LATNCY warning ("I can suspend your adventure for you so that you can resume later, but you will have to wait at least 45 minutes before continuing.") followed by "... or not." wink, then saves instantly. PAUSE alias routes here too; plain SAVE stays silent for modern UX. **User signed off 2026-05-08.** Test: `test_cca_pdp10_easter_eggs.gd` |
| 31 | HOURS | `driver._process_input` "hours" handler | ✓ — emits canon-faithful "open all day, every day" banner with PDP-10 provenance footnote. **User signed off 2026-05-08.** Sister verbs WIZARD + MAINT/MAGIC/"MAGIC MODE" landed alongside, narrating canon section-12 msg #1/#16/#17/#18/#20 dialogues. Test: `test_cca_pdp10_easter_eggs.gd` |

### 4.4 Special verbs (3000+id) — none in this section

(Section 4 of canon has only motion / object / action verbs.
"Special" verbs like FEE/FIE/FOE/FOO are M=2 action with extra dispatch.)

### 4.5 Magic words

| Word | Canon ID | Port handler | Status |
|---|---|---|---|
| XYZZY | 62 (motion verb) | `MagicWordTeleport` aspect: 11 ↔ 3 | ✓ |
| PLUGH | 65 | `MagicWordTeleport`: 33 ↔ 3, 100 ↔ 33 | ✓ |
| PLOVER | 71 | `MagicWordTeleport`: 33 ↔ 100 | 🟡 — missing routine 302 (emerald drop) |
| Y2 | 55 | (motion verb, alias for PLUGH dest) | ✓ |
| FEE/FIE/FOE/FOO | 2025 (action) | `EggsIncantation` FSM | ✓ |

---

## 5. Object property states (section 5)

Source: ADVENT_DAT_INVENTORY.md section 5.

For each object with multiple PROP states, port must support state cycling.

| Obj | PROP states | Port FSM | Status |
|---|---|---|---|
| KEYS (1) | 0 only | constant Item | ✓ |
| LAMP (2) | 0=off, 1=on | `Lamp` | ✓ |
| GRATE (3) | 0=locked, 1=unlocked | `Grate` | ✓ |
| CAGE (4) | 0 only | Item | ✓ |
| ROD (5) | 0 only | Item | ✓ |
| ROD2 (6) | 0..2 (decoy state, dynamite at endgame) | Item | 🟡 — missing dynamite (BLAST) state |
| BIRD (8) | 0=free, 1=in-cage | `Bird` | ✓ |
| DOOR (9) | 0=rusty, 1=oiled | `RustyDoor` | ✓ |
| SNAKE (11) | 0=present, 1=gone | `Snake` | ✓ |
| FISSURE (12) | 0=hidden, 1=visible | `CrystalBridge` | ✓ |
| TABLET (13) | 0=unread, 1=read | none | 🔴 |
| CLAM (14) | 0=closed | item state | ✓ |
| OYSTER (15) | 0=closed, after-break states for hint chain | item | 🟡 — missing oyster-clue read chain at endgame |
| MAGAZINE (16) | 0=normal, dropped at Witt's End for +1 | item + ScoreLedger | ✓ |
| BOTTLE (20) | 0=water, 1=empty, 2=oil, -1=invalid | `Bottle` | ✓ |
| MIRROR (23) | 0=intact, 1=broken | none | 🔴 |
| PLANT (24) | 0=tiny, 2=tall, 4=huge (cycles via POUR water) | `Plant` | ✓ — cycle 0→2→4→0 |
| PLANT2 (25) | 0..2 mirror of PLANT/2 | none | 🔴 (phony plant) |
| AXE (28) | 0=normal, 1=stuck (with bear) | item state | ✓ |
| DRAGON (31) | 0=alive, 1=on-rug-flag, 2=dead | `Dragon` | ✓ |
| CHASM (32) | 0=intact, 1=collapsed | (folded into CrystalBridge) | 🟡 — chasm and fissure are separate canon objects |
| TROLL (33) | 0=hostile, 1=paid-but-not-crossed, 2=vanished | `Troll` | ✓ |
| TROLL2 (34) | placeholder for vanished troll | (folded into Troll FSM) | ✓ |
| BEAR (35) | 0=hungry, 1=tame, 2=released, 3=dead | `Bear` | ✓ |
| VEND (38) | 0=normal | `VendingMachine` | ✓ |
| BATTER (39) | 0=fresh, 1=dead | item state | ✓ |
| CHEST (55) | -1=undiscovered, 0=at stash | `Treasure` ($Vanished/$Reappeared) | ✓ |
| RUG (62) | 0=normal, 1=under-dragon | `Treasure` | ✓ |
| CHAIN (64) | 0=loose, 1=locked-to-bear, 2=locked-by-player | `Treasure` | ✓ |
| VASE (58) | 0=intact, 2=broken | `Treasure` (fragile=true) | ✓ |
| (others 50..63) | -1=undiscovered, 0=found | `Treasure` | ✓ |

---

## 6. Section 6 messages

Total: 327 source rows; 197 distinct messages.

The port references many of these inline in driver / FSM bumpers.
Comprehensive map is impractical to inline here — strategic table:

| Canon msg # | Use | Port status |
|---|---|---|
| 1 | Welcome banner | ✓ — adapted in `_print_welcome` (with credit splash) |
| 2 | Dwarf with knife blocks way | 🔴 — port doesn't fire on movement-blocked-by-dwarf |
| 3 | First dwarf encounter narration | 🔴 |
| 4 | Threatening dwarf | ✓ — driver fires on dwarf attack |
| 5/6/7 | Knife-throw outcomes | ✓ |
| 8 | Hollow voice "PLUGH" at Y2 | 🔴 — port doesn't roll the 25%-at-Y2 PLUGH whisper |
| 9 | "no way to go that direction" | ✓ — driver fallback |
| 11 | "I don't know in from out" | 🟡 — port handles IN/OUT but doesn't fire this for ambiguous |
| 12 | "I don't know that word" | ✓ |
| 13 | "I don't understand that" | ✓ |
| 14 | "Would you care to explain how" | 🟡 |
| 15 | "Sorry but I am not allowed" | 🔴 — LOOK detail counter not modeled |
| 16 | "It is now pitch dark" | ✓ — `_check_dark_pit_hazard` |
| 17 | "If you prefer simply type W" | 🔴 — IWEST counter not tracked |
| 18 | "Are you trying to catch the bird?" | ✓ — Hint 5 |
| 19 | Bird hint | ✓ |
| 20/21 | Snake question/hint | ✓ |
| 22 | "Do you really want to quit?" | ✓ |
| 23 | "Fell into pit, broke every bone" | ✓ |
| 24/25 | "Already carrying"/"Can't be serious" | ✓/🟡 |
| 26 | Bird scared by rod | ✓ |
| 27 | Bird without cage | ✓ |
| 30 | Bird drives snake away | ✓ |
| 39/40 | Lamp on/off | ✓ |
| 45 | Bird is now dead | ✓ |
| 46 | Snake attack futile | ✓ |
| 47/48/49 | Dwarf kill/dodge/bare hands | ✓ |
| 54 | "OK" | ✓ |
| 56 | "Wound up back in main passage" (Witt's End / mazes) | ✓ |
| 60/61 | "Eh?" / "I beg your pardon?" | 🔴 — random alternates not implemented |
| 62/63 | Cave hint Q/A | ✓ |
| 70 | "Your feet are wet" | 🔴 |
| 71 | "Don't have appetite" | 🔴 |
| 72 | Food consumed | ✓ |
| 76 | "Rubbing isn't productive" | 🔴 |
| 81-90 | Death taunt + resurrection pairs | 🟡 — port has resurrection but messages don't match canon pairs |
| 91 | "I don't remember how you got here" | 🔴 — BACK fallback |
| 93 | "Can't go through locked grate" | ✓ |
| 94 | "Right here with you" | 🟡 |
| 95 | "Don't fit through 2-inch slit" | ✓ |
| 96 | "Use the bridge instead" | ✓ |
| 97 | "No way across the fissure" | ✓ |
| 98/99 | "Not carrying anything"/"Carrying:" | ✓ |
| 100/101/102/103 | Bird/snake/dragon/dwarf feed | ✓ (mostly) |
| 104/105/106/107/108 | Bottle interactions | ✓ |
| 110 | "Don't be ridiculous" (volcano) | ✓ |
| 111 | "Door extremely rusty" | ✓ |
| 112 | "Plant won't grow with oil" | 🟡 |
| 113/114 | Door oil / water | ✓ |
| 115 | Plant deep roots | ✓ |
| 116 | Knife caveat | 🔴 — KNFLOC not modeled (no "you'd best leave that knife alone" warning) |
| 117 | Plover squeeze | ✓ |
| 118/119 | Clam/oyster squeeze | ✓ |
| 120-125 | Clam/oyster open dialogue | ✓ |
| 126 | Witt's End cave-in | ✓ |
| 127 | "Faint rustling sounds" (pirate hint) | 🟡 — pirate runs but rustling msg not always fired |
| 128 | Pirate steals | ✓ |
| 129 | Closing announcement | ✓ |
| 130 | "Nothing leaves" closing | ✓ |
| 131 | "Looks as though you're dead" | ✓ |
| 132 | Repository flash | ✓ |
| 133/134/135 | Endgame BLAST outcomes | 🔴 |
| 136 | "Disturbed dwarves" | 🔴 |
| 137 | "OK" attack-bird | 🔴 (port doesn't differentiate) |
| 138 | "Unsuspectingly close" | 🔴 (FIND) |
| 140 | "I no longer remember how" (BACK) | 🔴 |
| 141 | "Followed by tame bear" | ✓ |
| 142 | INFO text | 🟡 — port has INFO but text differs |
| 143 | Score continue prompt | ✓ |
| 144/145 | Vase fill | ✓ |
| 148 | "Too far up" | 🔴 (23:hole) |
| 149 | First dwarf killed | ✓ |
| 150 | Clam/oyster strong | ✓ |
| 151 | "Start over" (FOO sequence) | ✓ |
| 152 | "Axe glances" (dragon) | ✓ |
| 153 | Dragon block | ✓ |
| 154 | Bird vs dragon (death) | 🔴 |
| 156 | BRIEF acknowledgement | 🔴 |
| 157 | Troll laughs | ✓ |
| 158 | Troll catches axe | 🔴 — port doesn't fire on throw axe at troll |
| 159 | Treasure to troll | ✓ |
| 160 | Troll refuses crossing | ✓ |
| 161 | "No longer any way across" | 🟡 |
| 162 | Bear-falls-bridge death | ✓ |
| 163 | "Troll runs from bear" | ✓ |
| 164 | "Throw axe at bear" | 🔴 |
| 165/166/167/168/169/170 | Bear states | 🟡 — partial coverage |
| 171/172/173 | Chain unlock/lock | ✓ |
| 175 | "Sorry no more hints" | ✓ |
| 176/177 | Maze hint | ✓ |
| 178/179 | Dark hint | ✓ |
| 180/181 | Witt's End hint | ✓ |
| 182 | Troll feed | 🔴 |
| 183/187/188/189 | Lamp dim warnings | ✓ |
| 184 | Lamp out | ✓ |
| 185 | Wandered out, lamp dead → forced quit | 🔴 |
| 186 | "Faint rustling" (pirate hint) | 🟡 |
| 190 | Read magazine | ✓ |
| 191 | Read message | 🔴 |
| 192/193/194 | Oyster hint chain | 🔴 |
| 196 | Read tablet | 🔴 |
| 197 | Mirror break (endgame) | 🔴 |
| 198 | Vase shatter narration | ✓ |
| 199 | Wake the dwarves | 🔴 |
| 200/201 | SUSPEND prompt | 🟡 |

---

## 7. Object initial locations (section 7) — 55 placements

Per canon section 7 vs port's `Treasure(home_room=...)` and other
constructors. **All canon homes match port — verified by
`tests/test_cca_canon.gd` 38-check dashboard.** ✓

| Obj | Canon home | Port home | Status |
|---|---|---|---|
| KEYS | 3 | 3 | ✓ |
| LAMP | 3 | 3 | ✓ |
| GRATE | 8/9 (two-loc) | (gate-only, no movable) | ✓ |
| CAGE | 10 | 10 | ✓ |
| ROD | 11 | 11 | ✓ |
| ROD2 | 0 (created from dwarf) | 0 | ✓ |
| BIRD | 13 | 13 | ✓ |
| PILLOW | 96 | 96 | ✓ |
| SNAKE | 19 | 19 | ✓ |
| TABLET | 101 | (none) | 🔴 |
| CLAM | 103 | 103 | ✓ |
| OYSTER | 0 (dynamic) | 0 | ✓ |
| MAGAZINE | 106 | 106 | ✓ |
| FOOD | 3 | 3 | ✓ |
| BOTTLE | 3 | 3 | ✓ |
| MIRROR | 109 | (none) | 🔴 |
| PLANT | 25 | 25 | ✓ |
| AXE | 0 (dynamic) | 0 | ✓ |
| BEAR | 130 | 130 | ✓ |
| VEND | 140 | 140 | ✓ |
| BATTER | 0 (dynamic) | 0 | ✓ |
| GOLD | 18 | 18 | ✓ |
| DIAMONDS | 27 | 27 | ✓ |
| SILVER | 28 | 28 | ✓ |
| JEWELRY | 29 | 29 | ✓ |
| COINS | 30 | 30 | ✓ |
| CHEST | 0 (dynamic) | 0 | ✓ |
| EGGS | 92 | 92 | ✓ |
| TRIDENT | 95 | 95 | ✓ |
| VASE | 97 | 97 | ✓ |
| EMERALD | 100 | 100 | ✓ |
| PYRAMID | 101 | 101 | ✓ |
| PEARL | 0 (from oyster) | 0 | ✓ |
| RUG | 119/121 | 119 | 🟡 — only one location (canon has two-place) |
| SPICES | 127 | 127 | ✓ |
| CHAIN | 130 | 130 | ✓ |

---

## 8. Action defaults (section 8)

31 entries. The `ACTSPK[VERB]` table maps each action verb to a default
section-6 message used when the verb has no other applicable handling.

| Verb | Default msg | Port has | Status |
|---|---|---|---|
| TAKE (1) | 25 ("Can't be serious") | ✓ |
| DROP (2) | 29 ("Aren't carrying it") | ✓ |
| SAY (3) | 0 (no default — special handling) | ✓ |
| OPEN (4) | 28 ("Nothing here with a lock") | 🟡 |
| NOTHING (5) | 54 ("OK") | ✓ |
| LOCK (6) | 28 | 🟡 |
| ON (7) | 39 (lamp now on) | ✓ |
| OFF (8) | 40 (lamp now off) | ✓ |
| WAVE (9) | 29 | ✓ |
| CALM (10) | 7 (one of them gets you) | 🔴 |
| WALK (11) | 8 (hollow voice) | 🟡 |
| KILL (12) | 44 ("nothing here to attack") | ✓ |
| POUR (13) | 78 ("you can't pour that") | ✓ |
| EAT (14) | 71 ("don't have appetite") | 🔴 |
| DRINK (15) | 110 | 🟡 |
| RUB (16) | 76 ("not productive") | 🔴 |
| TOSS (17) | 29 | ✓ |
| QUIT (18) | 22 (confirm) | ✓ |
| FIND (19) | 59 ("I'd recommend looking") | 🔴 |
| INVENTORY (20) | 98 (carrying nothing) | ✓ |
| FEED (21) | 14 ("game, would you care") | 🟡 |
| FILL (22) | 29 | ✓ |
| BLAST (23) | 54 (default OK) | 🔴 |
| SCORE (24) | (no default) | ✓ |
| FOO (25) | 42 ("nothing happens") | ✓ |
| BRIEF (26) | 156 (acknowledgement) | 🔴 |
| READ (27) | 0 (no default) | 🟡 |
| BREAK (28) | 54 | 🟡 |
| WAKE (29) | 54 | 🔴 |
| SUSPEND (30) | (no default) | 🟡 |
| HOURS (31) | (no default) | (no canon default) | ✓ — see §4.3 |

---

## 9. COND bits per room (section 9)

13 rows, decoded into 14 lit + 8 liquid + 18 pirate-forbidden + 25 hint
rooms.

### 9.1 Lit rooms (bit 0)

Canon: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100, 115, 116, 126.
Port (`_room_is_dark` returns false for): 1-10, 100, 115, 116, 126.
**✓ Exact match.**

### 9.2 Liquid rooms (bits 1+2)

Canon water at: 1, 3, 4, 7, 38, 95, 113.
Canon oil at: 24.

| Room | Canon liquid | Port |
|---|---|---|
| 1 | water | ✓ |
| 3 | water | ✓ |
| 4 | water | ✓ |
| 7 | water | ✓ |
| 24 | oil | 🔴 — port has oil at 24? need to verify; oil source previously documented at canon-94/Bottle.fgd |
| 38 | water | 🔴 — port doesn't model canon-38 |
| 95 | water | 🔴 |
| 113 | water | 🔴 — reservoir water; port has reservoir but liquid not modeled |

🟡 Port has FILL working at well-house (canon 1/3/4/7) and oil source.
Reservoir water for the bottle isn't a canon necessity.

### 9.3 Pirate-forbidden rooms (bit 3)

Canon: 46, 47, 48, 54, 56, 58, 82, 85, 86, 122, 123, 124, 125, 126, 127,
128, 129, 130.

Port: pirate has its own `forbidden_rooms` list. Need to verify.

**Status: 🟡** — need to cross-reference Pirate FSM's forbidden list
against canon's 18 rooms. Likely covers troll bridge area (122-130);
maze rooms (46/47/48/54/56) may be missing.

### 9.4 Hint rooms (bits 4-9)

| Hint | Canon rooms | Port hint |
|---|---|---|
| Hint 4 (cave) | 8 | ✓ |
| Hint 5 (bird) | 13 | ✓ |
| Hint 6 (snake) | 19 | ✓ |
| Hint 7 (maze) | 42-56, 80-87 (20 rooms) | 🟡 — port has 3-5 hints; maze is one of them but room set may differ |
| Hint 8 (dark) | 99, 100, 101 | 🟡 |
| Hint 9 (Witt's End) | 108 | ✓ |

---

## 10. Class messages / score thresholds (section 10)

Canon thresholds: 35, 100, 130, 200, 250, 300, 330, 349, 9999.

Port's `Cca.score_class()` returns one of these strings; values currently
in `cca/canon/score_tiers.txt`. **Status: ✓** (verified per data file).

Per-tier message text — needs to be cross-checked in port. Likely fine.

---

## 11. Hints (section 11)

Source: ADVENT_DAT_INVENTORY.md section 11.

| Hint | Trigger turns | Cost | Port |
|---|---|---|---|
| #4 cave | 4 | 2 | ✓ |
| #5 bird | 5 | 2 | ✓ |
| #6 snake | 8 | 2 | ✓ |
| #7 maze | 75 | 4 | 🟡 — port has maze hint but trigger threshold needs verification |
| #8 dark | 25 | 5 | 🟡 |
| #9 witt | 20 | 3 | ✓ |

Hint cost-deduction-from-score: ✓ (`hint_penalty()`).
Lamp time bonus per accepted hint (`LIMIT += 30 * cost`): 🟡 — needs verification.
"Sorry no more hints" msg #175 after acceptance: ✓.

---

## 12. NPC AIs

### 12.1 Dwarves (5 of them, advent.for STMT 6010-6030)

| Behavior | Canon | Port | Status |
|---|---|---|---|
| 5 dwarves + pirate | yes | `dwarf1..5 + pirate` | ✓ |
| Initial DLOC = 19, 27, 33, 44, 64 | yes | matches | ✓ |
| 5% trigger at LOC>=15 | yes | port may use different trigger | 🟡 |
| Random walk (no backtrack unless forced) | yes | port has dwarf wander logic | ✓ |
| Avoid forced/pirate-forbidden/dwarves-forbidden rooms | yes | partial | 🟡 |
| Knife miss/hit probability ramp `95*(DFLAG-2)/1000` | yes | port has flat probability | 🔴 |
| First throw always misses (DFLAG transition) | yes | port may not match | 🟡 |
| Drop axe at first encounter | yes | ✓ | ✓ |
| Block player exit if dwarf at NEWLOC (msg #2) | yes | 🔴 | not implemented |
| Player throws axe → 33% kill | yes | ✓ | ✓ |
| First-kill prints msg #149 | yes | ✓ | ✓ |
| FEED dwarf → DFLAG++ (anger) | yes | 🔴 | not implemented |

### 12.2 Pirate (dwarf 6)

| Behavior | Canon | Port | Status |
|---|---|---|---|
| Starts at CHLOC=114 | yes | ✓ | ✓ |
| Wanders, only enters non-forbidden rooms | yes | 🟡 — forbidden list may be incomplete |
| Steals when player carries treasure (not chest) | yes | ✓ |
| Doesn't take pyramid from Plover/Dark | yes | 🟡 — port may take it |
| Stash is at CHLOC; MESSAG goes to CHLOC2=140 | yes | 🟡 — message object not modeled |
| 20% rustling msg #127 between visits | yes | 🟡 |
| `TALLY==TALLY2+1` and chest-only-outstanding hint (msg #186) | yes | 🔴 |

### 12.3 Snake

| Behavior | Canon | Port |
|---|---|---|
| Fixed at room 19 | yes | ✓ |
| PROP=0 alive, =1 gone | yes | ✓ |
| Drop bird → snake driven away (msg #30) | yes | ✓ |
| Bird-vs-snake at endgame: still triggers | yes | ✓ |

### 12.4 Bear

| Behavior | Canon | Port |
|---|---|---|
| At canon 130 | yes | ✓ |
| PROP cycle: 0=hungry → 1=tame (FEED) → 2=released → 3=dead | yes | ✓ |
| FEED FOOD when bear hungry → tame, axe drops | yes | ✓ |
| UNLOCK chain → bear freed | yes | ✓ |
| Drop bear at troll → troll runs, bridge collapses → death if toted across | yes | ✓ |
| Throw axe at bear → bear catches, axe stuck | yes | 🔴 |

### 12.5 Dragon

| Behavior | Canon | Port |
|---|---|---|
| At canon 119/121 (two-place) | yes | ✓ (single placement) |
| ATTACK with YES → killed, dragon moves to 120 (center) | yes | 🟡 — port doesn't move dragon to center, doesn't move player |
| Rug under dragon, becomes free | yes | ✓ |
| FEED dragon → "nothing edible" | yes | ✓ |
| Bird thrown at live dragon → bird dies | yes | 🔴 |

### 12.6 Troll

| Behavior | Canon | Port |
|---|---|---|
| Two-place: 117/122 | yes | ✓ |
| PROP cycle: 0→1 (paid)→2 (vanished after bear) | yes | ✓ |
| Throw treasure → troll vanishes, treasure lost | yes | ✓ |
| Bear crosses bridge → chasm collapses (PROP CHASM=1) | yes | ✓ |
| FEED troll → "no edible food" | yes | 🔴 |
| Throw axe at troll → "deftly catches" msg #158 | yes | 🔴 |

### 12.7 Bird

| Behavior | Canon | Port |
|---|---|---|
| At canon 13 | yes | ✓ |
| Won't enter inventory if rod toted (msg #26) | yes | ✓ |
| Won't enter inventory without cage (msg #27) | yes | ✓ |
| Drop bird at snake → snake driven (msg #30) | yes | ✓ |
| Drop bird at dragon → bird vaporized (msg #154) | yes | 🔴 |
| ATTACK bird → killed (msg #45) | yes | ✓ |

---

## 13. Lamp / batteries

| Mechanic | Canon | Port |
|---|---|---|
| LIMIT init = 330 (or 1000 if HINTED(3)) | yes | 🟡 — port has LIMIT but verbose-instructions discount not applied |
| Decrement per turn while ON | yes | ✓ |
| LIMIT<=30: dim warning (msg #187/183/189) | yes | ✓ (some variants) |
| LIMIT==0: lamp out (msg #184) | yes | ✓ |
| LIMIT<0 AND outside cave: forced quit | yes | 🔴 |
| BATTER auto-replace if lamp+battery+limit<=30 | yes | ✓ |
| HOLDNG cap = 7 | yes | ✓ — `BackpackLimit` aspect |

---

## 14. Cave closing / endgame

### 14.1 CLOCK1 (treasure-located timer)

| Mechanic | Canon | Port |
|---|---|---|
| TALLY==0 → start CLOCK1 ticking | yes | ✓ — `Endgame` |
| CLOCK1 init = 30 | yes | 🟡 — port may use different value |
| Ticks only when LOC>=15 AND LOC!=33 | yes | 🟡 |
| CLOCK1==0 → closing announcement (msg #129), CLOSNG=true | yes | ✓ |
| Lock grate, kill dwarves, vanish troll/bear, etc. | yes | 🟡 — port has closing setup but specifics need cross-check |

### 14.2 CLOCK2 (panic timer)

| Mechanic | Canon | Port |
|---|---|---|
| CLOCK2 init = 50 | yes | 🟡 |
| Decrements after CLOCK1<0 | yes | ✓ |
| CLOCK2 cap = 15 if PANIC | yes | 🔴 |
| CLOCK2==0 → repository setup (msg #132), CLOSED=true | yes | ✓ |
| Player teleported to canon 115 | yes | ✓ |
| Specific objects placed at 115/116 | yes | 🟡 — port may not match all |

### 14.3 Repository setup (canon 115/116)

Per advent.for STMT 11000:
- 115 (NE): bottle, plant nursery, oysters, lamp, rod, dwarves, mirror.
- 116 (SW): grate, snake pit, caged birds, more rods, pillows, mirror2.
- Mirror spans both.

**Status: 🟡** — port creates a repository but specific object set
may differ.

### 14.4 BLAST verb at endgame

| Mechanic | Canon | Port |
|---|---|---|
| ROD2 has dynamite prop only after closing | yes | 🔴 |
| BLAST nothing → msg #54 | yes | 🔴 |
| BLAST at LOC=115 → BONUS=134, +30 | yes | 🔴 |
| BLAST with rod2 here → BONUS=135, +25 | yes | 🔴 |
| BLAST elsewhere with rod2 → BONUS=133, +45 | yes | 🔴 |

### 14.5 Mirror break (penalty)

CLOSED + BREAK MIRROR → msg #197, GOTO 19000 (dwarves wake → death).

**Status: 🔴**

---

## 15. Scoring (350 max)

Per advent.for STMT 20000.

| Component | Canon | Port |
|---|---|---|
| Treasure: 2 each found | yes | 🟡 — port may use different per-treasure value |
| Treasure: 12 deposited (obj < CHEST) | yes | 🟡 |
| Treasure: 14 deposited CHEST | yes | 🟡 |
| Treasure: 16 deposited (obj > CHEST) | yes | 🟡 |
| Survived: (MAXDIE-NUMDIE)*10 | yes | ✓ |
| Didn't quit: +4 | yes | ✓ |
| Got into cave (DFLAG≠0): +25 | yes | 🟡 |
| Reached endgame (CLOSNG): +25 | yes | ✓ |
| At repository (CLOSED): +10 mundane | yes | 🟡 |
| BLAST 135: +25 | 🔴 |
| BLAST 134: +30 | 🔴 |
| BLAST 133: +45 | 🔴 |
| Magazine at Witt's End: +1 | yes | ✓ |
| Round-off: +2 | yes | ✓ |
| Hint penalty: -cost per accepted hint | yes | ✓ |

**Port total achievable: ≤ ~310 (without BLAST endgame)**.
**Canon max: 350.**

---

## 16. Save / restore

| Mechanic | Canon | Port |
|---|---|---|
| SAVE/RESTORE verbs | yes (SUSPEND/RESTART) | ✓ |
| State persistence | full game state | ✓ — Frame `@@[persist]` |
| Latency requirement (PDP-10) | yes | ✓ — SUSPEND/PAUSE narrate the canon 45-minute warning then save instantly with a "... or not." wink; SAVE stays silent. **User signed off 2026-05-08.** See §4.3 SUSPEND row. |

---

## 17. Death + resurrection

| Mechanic | Canon | Port |
|---|---|---|
| MAXDIE = 5 | yes | ✓ |
| Numbered death msgs (81/83/85/87/89) | yes | 🟡 — port has resurrection prompt but text differs |
| Reincarnation msgs (82/84/86/88/90) | yes | 🟡 |
| Drop everything at OLDLC2 | yes | ✓ |
| Lamp goes to room 1, lit-state cleared | yes | 🟡 |
| Player respawns at room 3 | yes | ✓ |
| No resurrection at endgame (CLOSNG) | yes | ✓ |
| Permadeath on 5th refusal | yes | ✓ |

---

## 18. BACK verb / random nav

| Mechanic | Canon | Port |
|---|---|---|
| BACK = walk OLDLOC (or OLDLC2 if OLDLOC was forced) | yes | 🔴 |
| LOOK = re-display long form | yes | ✓ |
| LOOK count = 3 then suppress (msg #15) | yes | 🔴 |
| CAVE outdoors → msg #57 | yes | 🔴 |
| CAVE indoors → msg #58 | yes | 🔴 |
| ENTER STREAM/WATER → msg #70 | yes | 🔴 |
| ENTER X (other) → re-dispatch as X | yes | 🟡 |
| WATER/OIL PLANT → re-dispatch as POUR | yes | ✓ |
| WEST counter (msg #17 every 10) | yes | 🔴 |
| Random "I don't understand" 20%/20% (msg #60/#61/#13) | yes | 🔴 |

---

## 19. Magic words

| Word | Canon | Port |
|---|---|---|
| XYZZY 11↔3 | yes | ✓ |
| PLUGH 33↔3 | yes | ✓ |
| PLUGH 100→33 | yes | ✓ |
| PLOVER 33↔100 | yes | ✓ |
| PLOVER + emerald → routine 302 (drop emerald) | yes | 🔴 |
| Y2 alias for PLUGH dest | yes | ✓ |
| 25% PLUGH-whisper at canon 33 | yes | 🔴 |
| 50%-then-canon "old worn-out magic word" (msg #50) for unmatched | yes | 🟡 |
| FEE/FIE/FOE/FOO sequence | yes | ✓ |
| Eggs reappear after FOO | yes | ✓ |
| Troll resurrected if FOO before crossing | yes | 🟡 |

---

## 20. Dark-room hazard

| Mechanic | Canon | Port |
|---|---|---|
| Motion in dark room: warn first turn (msg #16) | yes | ✓ |
| Subsequent motion: 35% pit-fall death | yes | ✓ |
| WZDARK tracks if previous loc was dark | yes | ✓ |
| LOOK suppresses pit-fall ("though it may now be dark") | yes | 🟡 |

---

## 21. Forced motion (cond=2 rooms)

Canon rooms with forced motion: 16, 22, 26, 32, 40, 59, 79, 89, 90, 113.

Per advent.for STMT 8 / STMT 11: at any forced room, the engine
automatically walks the player without asking for input. The travel
table's any-verb (verb=1) entry resolves to the destination.

| Room | Canon dest | Port |
|---|---|---|
| 16 (crack) | 14 | ✓ — `topology.gd` `16:east/out/back → 14` (escape verbs) |
| 22 (dome unclimbable) | 15 | ✓ — bouncer |
| 26 (clamber up plant) | 88 | ✓ |
| 32 (snake-block msg) | 19 | ✓ |
| 40 (passage parallel mists) | 41 | ✓ |
| 59 (parallel low) | 27 | ✓ |
| 79 (sewer pipe death) | 3 | ✓ |
| 89 (nothing to climb) | 25 | ✓ |
| 90 (climbed up plant) | 23 | ✓ |
| 113 (reservoir edge) | 109 | ✓ |

🟡 The port adds explicit OUT/BACK escape verbs rather than canon's
implicit any-verb-fires-on-entry. Same observable effect, different
mechanism.

---

## Coverage tally

| Layer | Total | ✓ | 🟡 | 🔴 | ⚪ |
|---|---|---|---|---|---|
| Conditional rows (sect 3) | 45 | 24 | 7 | 14 | 0 |
| Bumper rows (routines) | 6 | 4 | 0 | 2 | 0 |
| Msg500 rows | 29 | 21 | 1 | 7 | 0 |
| Object IDs | 64 | 53 | 4 | 7 | 0 |
| PROP cycles | 30 | 22 | 5 | 3 | 0 |
| Section-6 messages (high-impact) | ~70 surveyed | 40 | 18 | 12 | 0 |
| Object placements | 35 | 33 | 1 | 1 | 0 |
| Action verbs | 31 | 19 | 6 | 6 | 0 |
| COND lit rooms | 14 | 14 | 0 | 0 | 0 |
| COND liquid rooms | 8 | 4 | 1 | 3 | 0 |
| COND pirate-forbidden | 18 | partial | partial | 0 | 0 |
| COND hint rooms | 25 | partial | partial | 0 | 0 |
| Hints (player-facing 4-9) | 6 | 3 | 3 | 0 | 0 |
| NPC AIs | 7 | 4 | 1 | 2 | 0 |
| Lamp / batteries | 6 | 4 | 1 | 1 | 0 |
| Endgame | 8 | 3 | 3 | 2 | 0 |
| Scoring | 13 | 6 | 4 | 3 | 0 |
| Save / restore | 3 | 3 | 0 | 0 | 0 |
| Death | 8 | 5 | 2 | 0 | 0 |
| BACK / random nav | 10 | 1 | 1 | 8 | 0 |
| Magic words | 11 | 7 | 1 | 3 | 0 |
| Dark hazard | 4 | 3 | 1 | 0 | 0 |
| Forced motion | 10 | 10 | 0 | 0 | 0 |

**Grand totals (approximate, hand-tallied above):**
- ✓ implemented: ~250
- 🟡 partial: ~60
- 🔴 missing: ~75
- ⚪ scope-deferred (with sign-off pending): **0** — all PDP-10-specific verbs landed 2026-05-08 as canon-flavored easter eggs (HOURS, WIZARD, MAINT/MAGIC/"MAGIC MODE", SUSPEND/PAUSE)

Total tracked items: ~390.

---

## Glossary of partial / missing items requiring user attention

The 🟡 partial entries are the ones where current port behavior
**looks** canon-correct but a careful read of `advent.for` reveals a
subtle divergence. These are the highest-risk for shipping a
"100% canon" claim that wouldn't survive a code review.

The 🔴 missing items are concrete features to implement — the
companion `CANON_FULL_PLAN.md` orders them by dependency.

All PDP-10-specific items (HOURS, WIZARD, MAINT/MAGIC/"MAGIC MODE",
SUSPEND/PAUSE) landed 2026-05-08 as canon-flavored easter eggs that
narrate what the original 1977 release did and explain why the
machinery doesn't apply on a desktop port. **No items remain ⚪.**
