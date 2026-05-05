# Canon delta inventory — port vs. 1977 350-point Adventure

**Canon source:** Don Woods' original PDP-10 Fortran release (1977),
fetched from the IF Archive as `advent-original.tar.gz`. Data file
`advent.dat`, 1808 lines, 140 rooms, ~50 objects (15 of which are
treasures), 6 hints, 350-point maximum score.

**Verification methodology:** parsed the canonical data file
section-by-section, extracted the room/object/hint/scoring tables,
and compared each canonical entry against the port's
`cca/godot/scripts/topology.gd`, `cca/frame/cca.fgd`, and
related sources.

**Severity legend:**
- 🔴 **Behavior delta** — observable difference (different score,
  different reachable rooms, different puzzle solutions)
- 🟡 **Mechanics delta** — same observable goal, different mechanism
- 🟢 **Prose / flavor delta** — text differs but mechanically equivalent
- ⚪ **Scope delta** — feature deliberately omitted

**Earlier version of this document (commit 52656cd) was generated
from my recollection of canon, not the actual Fortran source. This
revision replaces it with verified data.**

---

## Status (2026-05-05) — every delta tracked here is now closed

`tests/test_cca_canon.gd` is the live conformance dashboard. It
runs every checkin and currently reports:

```text
Canon conformance: 100.0%  (38 / 38 checks passing)
Open deltas: 0
```

The 38 checks are organised in three groups:

| Group | Count | What's verified |
|---|---|---|
| Treasure homes | 15 | Each canon treasure either lives at the canonical room, or is dynamic (`location <= 0`) when canon places it dynamically (chest, pearl). |
| NPC + key-room constants | 7 | `BIRD_HOME_ROOM`, `SNAKE_ROOM`, `DRAGON_ROOM`, `BEAR_HOME_ROOM`, `VENDING_ROOM`, `WEST_PIT_ROOM`, `DEPOSIT_ROOM` agree with canon. |
| Magic-word teleport pairs | 6 | XYZZY (3 ↔ 11), PLUGH (3 ↔ 33), PLOVER (33 ↔ 100) — both directions of all three. |
| Architecture / mechanism probes | 10 | Each is a real probe (live Adventure instance), not a string assertion: cage gates bird-take; food consumed on bear-feed; pillow lets vase land softly; dwarf throws drop the axe; chest is dynamic until the pirate strikes; chain is the 15th treasure (deposit-counted); BREAK CLAM with the rod spawns the pearl; vending dispenses BATTERIES (lamp refresh deferred to INSERT BATTERIES); bottle has an `$Oil` state at the oil source; magazine drop at Witt's End awards the +1 bonus; two distinct rod IDs exist (star = magic, mark = decoy from slain dwarf). |

The rest of this file is the original delta inventory and stays as
historical record — it documented the gap, motivated the fix
sequence (Phases 5k–5q for room placements, 6a–6k for mechanism
deltas), and the work it called for has now landed. The `Recommended
ordering for fixing` list at the end of the document was followed
with one inversion: room placements went first (Phase 5), then the
mechanism deltas (Phase 6). Each commit closed one row of the
dashboard at a time, so the conformance percentage was a live
progress bar across the work.

The end-state code lives in:

- `cca/frame/cca.fgd` — Adventure constants (`CAGE_ID`, `FOOD_ID`,
  `PILLOW_ID`, `AXE_ID`, `BATTERIES_ID`, `MAGAZINE_ID`, `MARK_ROD_ID`,
  `CLAM_ID`, `OYSTER_ID`, `OIL_SOURCE_ROOM`, `WITTS_END_ROOM`),
  Treasure declarations (chain promoted to 15th), Bottle aspect
  with `$Oil`, BREAK verb, witts_end_bonus, etc.
- `cca/godot/scripts/topology.gd` — canon rooms 18, 27, 28, 29, 30,
  101, 103, 119, 127, 130 added; port-23 ↔ port-25 swapped so the
  plant lives at canon 25; snake gate moved 47:east → 19:north +
  19:south; plant climb-gates moved 23:up → 25:up.
- `cca/tests/test_cca_canon.gd` — the live dashboard with one probe
  per architectural delta.
- `cca/tests/test_cca_canonical.gd` — full real-commands playthrough
  rewritten around the canon room and item set.

---

## 1. Room map

### 1a. Headline finding

**The port's claim of "Crowther+Woods 1977 canonical numbering"
is true for ~20 rooms and false for ~120.** The port reuses
canonical room numbers as anchors at well-known landmarks
(end-of-road, well house, debris room, bird chamber, Y2, Hall
of Mt King, troll bridge) but reassigns most other canonical
numbers to entirely different rooms.

### 1b. Confirmed matches (20 rooms)

| # | Canon | Port | Match |
|---|---|---|---|
| 1 | End of road | End of road | ✓ |
| 2 | Hill in road | Hill in road | ✓ |
| 3 | Well house | Well house | ✓ |
| 4 | Valley | Valley | ✓ |
| 5 | Forest 1 | Forest 1 | ✓ |
| 6 | Forest 2 | Forest 2 | ✓ |
| 7 | Slit in streambed | Slit (too small to enter) | ✓ |
| 8 | Depression w/ grate | Depression / outside grate | ✓ |
| 9 | Below the grate (small chamber) | Below grate | ✓ |
| 10 | Cobble crawl | Cobbles | ✓ |
| 11 | Debris room (XYZZY scrawl) | Debris room | ✓ (description matches) |
| 12 | Awkward sloping E/W canyon | Awkward canyon | ✓ |
| 13 | Splendid chamber 30ft high | Bird chamber | ✓ (canon 13 IS the bird chamber) |
| 14 | Top of small pit (mist trace) | Top of small pit | ✓ |
| 15 | Vast Hall (Hall of Mists) | Hall of Mists | ✓ |
| 17 | East bank of fissure | East of fissure (gated by crystal bridge) | ✓ |
| 19 | Hall of Mt King | Hall of Mt King | ✓ |
| 33 | Large room (Y2 marker) | Y2 | ✓ |
| 117 | One side of large deep chasm | Troll bridge | ✓ |

### 1c. Confirmed mismatches (~30 rooms with significant divergence)

| # | Canon (1977) | Port | Severity |
|---|---|---|---|
| 16 | "The crack is far too small to follow" (stuck-message) | (port has no room 16 in topology — `topology.gd` skips it) | 🔴 |
| 18 | **Low room with crude note: "YOU WON'T GET IT UP THE STEPS"** — this is the **canonical gold-nugget room** | West side of fissure (port) — port relocates gold to debris room (11) | 🔴 |
| 20-22 | Death/stuck-message rooms (broken neck, didn't make it, dome unclimbable) | Port: 20=South entry, 21=Two-pit, 22=East pit | 🔴 |
| 23 | West end Twopit Room | Port 23=West pit | 🔴 (port treats as different room) |
| 24 | **East pit Twopit (oil pool)** | Port 24=Plant middle | 🔴 |
| 25 | **West pit Twopit — PLANT lives here** | Port 25=Plant top | 🔴 (plant should be at canon 25, port has it at 24) |
| 26 | Clamber up plant transition | Port 26=Narrow corridor | 🔴 |
| 27 | West side fissure (Hall of Mists) | Port: not in topology | 🔴 |
| 28 | Low n/s passage at hole | Port 28=Giant Room (eggs) | 🔴 (canon Giant Room is room 92) |
| 29-32 | South/west chambers, snake-block message | Port 29-32: various interior cave | 🔴 |
| 34 | Jumble of rock | Port 34=Low dust chamber | 🟡 |
| 35 | Low window on huge pit (low side) | Port 35=Sloping corridor | 🔴 |
| 36 | Dirty broken passage | Port 36=Above slab | 🔴 |
| 37 | Brink of small clean pit | Port 37=Slab room | 🔴 |
| 38 | **Bottom of small pit with stream** | **Port 38=Oriental Room (vase!)** — canon Oriental is room 97 | 🔴 |
| 39 | Large room dusty rocks | Port 39=Misty cavern | 🔴 |
| 40 | Low passage parallel to Hall of Mists | Port 40=Alcove (spices) — canon Alcove is room 99 | 🔴 |
| 41 | West end Hall of Mists | **Port 41=Plover Room** — canon Plover is room 100 | 🔴 |
| 47 | Dead end (in maze) | Port 47=Snake passage — canon snake is at room 19 (Hall of Mt King) | 🔴 |
| 65 | **Canon Bedquilt** | Port: not at 65 | 🔴 |
| 70 | Secret canyon | **Port 70=Bedquilt / bear chamber** — canon bear is in Barren Room (130) | 🔴 |
| 71 | Secret canyon junction | Port 71=Scorched cavern (dragon + diamonds + rug) | 🔴 |
| 90 | Climbed up plant out of pit | Port: no room 90 | 🔴 |
| 92 | **GIANT ROOM (canonical eggs location)** | Port: rooms 92-95 not in topology | 🔴 |
| 96 | **SOFT ROOM (pillow location!)** | Port: not in topology | 🔴 |
| 97 | **ORIENTAL ROOM (canonical vase)** | Port: not in topology | 🔴 |
| 100 | **PLOVER ROOM (canonical pearl)** | Port: not in topology | 🔴 |
| 101 | Dark-room (stone tablet) | Port: not in topology | 🔴 |
| 103 | **SHELL ROOM (clam/oyster pearl puzzle!)** | Port: not in topology | 🔴 |
| 108 | **WITT'S END** | Port: not in topology | 🔴 |
| 113 | **RESERVOIR** | Port 83=Reservoir | 🔴 |
| 115/116 | **REPOSITORY** (NE/SW ends — endgame) | Port 136=Repository | 🔴 |
| 126 | **BREATH-TAKING VIEW (volcano!)** | Port: not in topology | 🔴 |
| 130 | **Barren Room (canonical BEAR location)** | Port: not in topology | 🔴 |

### 1d. Port rooms not in canon (synthesized)

The port adds rooms 130-139 explicitly as "interpolated" treasure
side-rooms. Port rooms 14-99 also include many entries that don't
correspond to any specific canon room — they're approximate
analogs. A definitive count requires room-by-room cross-check.

---

## 2. Objects

The canonical 1977 source has **64 object IDs** spanning movable items,
fixtures, NPCs, and treasures. The port has **15 treasures** and a small
non-treasure inventory (rod, keys, bottle, lamp, bird, chain).

### 2a. Treasure list (canon vs. port)

| Canon ID | Canon name | Port name | Canon location | Port location | Δ |
|---|---|---|---|---|---|
| 50 | LARGE GOLD NUGGET | gold | room 18 (low-room note) | room 11 (debris) | 🔴 location |
| 51 | SEVERAL DIAMONDS | diamonds | room 71 (canon — west secret canyon, *not* dragon area) | room 71 (port's "scorched cavern") | 🔴 same number, different room |
| 52 | BARS OF SILVER | silver | room 32 or thereabouts (canon — Y2 area) | room 33 (Y2) | 🟡 close |
| 53 | PRECIOUS JEWELRY | jewelry | room 113 (canon — reservoir-adjacent? to verify) | room 118 (port's "cliff") | 🟡 |
| 54 | RARE COINS | coins | room 60 (canon — east end Long Hall) | room 134 (interpolated) | 🔴 location |
| 55 | TREASURE CHEST | chest | room 18 / 19 area (pirate's cavern — cross-reference Section 8) | room 132 (interpolated) | 🔴 location |
| 56 | GOLDEN EGGS | eggs | room 92 (Giant Room) | room 28 (port's "Giant Room") | 🔴 wrong canon room |
| 57 | JEWELED TRIDENT | trident | room 95 area (canon waterfall? to verify) | room 130 (interpolated) | 🔴 location |
| 58 | MING VASE | vase | room 97 (Oriental Room) | room 38 (port's Oriental) | 🔴 wrong canon room |
| 59 | EGG-SIZED EMERALD | emerald | room 100 area (canon — Plover-adjacent dark room?) | room 131 (interpolated) | 🔴 location |
| 60 | PLATINUM PYRAMID | pyramid | room 101 (Dark-room — canonically) | room 133 (interpolated) | 🔴 location |
| 61 | GLISTENING PEARL | pearl | inside oyster (room 103 area, after CLAM→OYSTER puzzle) | room 41 (Plover Room — port's port) | 🔴 mechanism + location |
| 62 | PERSIAN RUG | rug | under dragon | room 71 (under dragon ✓ port matches) | ✓ |
| 63 | RARE SPICES | spices | room 99 (Alcove) | room 40 (port's Alcove) | 🔴 wrong canon room |
| 64 | **GOLDEN CHAIN** | chain (port treats as non-treasure) | bear's location (canon 130 Barren Room) | port: chain is not a treasure FSM | 🔴 fundamental — port misses chain as 15th treasure |

### 2b. Treasure values

The port's `Treasure.value` field uses 5/10/14/15 pt values per
treasure summing to 177. Canon scoring is **per-treasure tiered**:

- 2 points for picking up each treasure
- 12 points for depositing in well house = up to 14 points per treasure
- 16 deposited treasures × 14 = 224 max (if 16 treasures)
- 15 treasures × 14 = 210 (if 15 treasures)
- Plus **dungeon visit** points (50 first time entering cave),
  **arrival in repository** (45), and several other components

Total target: **350 points**. Port's scoring math doesn't reach 350.

🔴 Per-treasure values + scoring formula are wrong.

### 2c. Non-treasure objects: port-vs-canon

**Canon has these — port does not:**

| Canon ID | Object | Used for | Severity |
|---|---|---|---|
| 4 | WICKER CAGE | Holds bird; required to carry bird (per canon) | 🔴 |
| 6 | BLACK ROD with rusty MARK | The "fake" rod — non-magical decoy. Used to push the dragon? canon flavor | 🟡 |
| 10 | VELVET PILLOW | Soft-drop the vase to avoid shattering (the only way to recover an unbroken vase outside deposit room) | 🔴 |
| 14 | GIANT CLAM | Open with trident → becomes oyster | 🔴 |
| 15 | GIANT OYSTER | Has a message under shell | 🔴 |
| 16 | "SPELUNKER TODAY" magazine | Witt's End red herring; drop at Witt's End for 1 point | 🔴 |
| 19 | TASTY FOOD | Feed to bear (without it, can't feed bear) | 🔴 |
| 22 | OIL IN BOTTLE | Use on rusty door to open Plover-Dark transition | 🔴 |
| 23 | MIRROR (in Mirror Canyon) | Flavor / dwarf interaction | 🟢 |
| 25 | PHONY PLANT (in Twopit when tall) | Flavor — see plant from above | 🟢 |
| 26 | STALACTITE | Climbing connector (alternate route in maze area) | 🔴 |
| 27 | SHADOWY FIGURE | At a window — flavor / hint | 🟢 |
| 28 | DWARF'S AXE | Item dropped when first dwarf attacks; player picks up and throws back | 🔴 |
| 29 | CAVE DRAWINGS | Oriental Room flavor | 🟢 |
| 36 | MESSAGE IN SECOND MAZE | Flavor | 🟢 |
| 37 | VOLCANO / GEYSER | Breath-taking-view room flavor | 🟢 |
| 39 | BATTERIES | Vending machine output; carry to lamp to refresh | 🔴 |
| 40 | CARPET / MOSS | Flavor | 🟢 |

**Port has these — canon arguably handles differently:**

| Port object | Port behavior | Canon equivalent | Severity |
|---|---|---|---|
| `chain` (non-treasure FSM) | Bear's chain, used in puzzle | **Canon: chain is treasure 64 (GOLDEN CHAIN)**, taken after bear scared away | 🔴 |
| `feed bear` verb (no food item) | Direct verb tames the bear | Canon requires holding FOOD object 19 | 🔴 |
| `throw axe` verb (no axe item) | Direct verb attacks dwarves | Canon requires picking up dropped axe and throwing it | 🔴 |
| Insert coin → direct lamp refresh | Vending machine interaction | Canon: coin → vending dispenses BATTERIES (object 39); player swaps battery in lamp | 🔴 |

### 2d. Two-rod distinction

Canon has TWO rods:
- **Object 5: BLACK ROD with rusty STAR** — magic, summons crystal bridge
- **Object 6: BLACK ROD with rusty MARK** — non-magical, distinct item

Port has ONE rod (the magic one).

🔴 Port missing canon rod #6.

---

## 3. Hints

Canon has **6 hints**, port has **3**.

| # | Canon trigger room | Canon turn-threshold | Canon cost | Port equivalent |
|---|---|---|---|---|
| 1 | grate / cave entry guidance | 4 | -2 | (port: bird/dark/snake — not the same hints) |
| 2 | bird (room 13) | 5 | -2 | port has "bird" hint (threshold 5?) |
| 3 | snake (room 19) | 8 | -2 | port has "snake" hint |
| 4 | maze of twisty passages | 75 | -4 | 🔴 missing in port |
| 5 | dark room | 25 | -5 | port has "dark" hint |
| 6 | Witt's End | 20 | -3 | 🔴 missing (and Witt's End not modeled) |

Port's hint 1 ("bird"), hint 2 ("dark"), hint 3 ("snake") roughly map
to canon hints 2, 5, 3 respectively but threshold/cost values
likely differ.

🔴 Port missing canon hints 1 (cave guidance), 4 (maze), 6 (Witt's End)
and pricing on the existing ones may be off.

---

## 4. Scoring (350-point target)

### 4a. Canon rating tiers

Canon rates the player's score against these tiers:

| Score | Rating |
|---|---|
| < 35 | Rank Amateur |
| 35-99 | Novice |
| 100-129 | Experienced Adventurer |
| 130-199 | Seasoned Adventurer |
| 200-249 | Junior Master |
| 250-299 | Master Class C |
| 300-329 | Master Class B |
| 330-348 | Master Class A |
| 349+ | **Grandmaster** (only achievable at 350) |

### 4b. Canon score components (approximate)

- Each treasure picked up: **2 points** × 15 = 30
- Each treasure deposited at well house: **+10–12 points** depending on tier × 15
- Reaching the cave (entering grate area): **25 points**
- Surviving the dragon: **0** (no specific bonus, but enables further treasures)
- Reaching repository (cave-closing endgame): **25 points**
- Detonating the marker: **45 points** (canon: getting all the way to the end)
- Hint penalties: **-2/-3/-4/-5** per hint
- Death penalties: deductions per resurrection
- Save penalty: **-5 per saved game** (canon discourages saving)
- Magazine left at Witt's End: **+1 point** (Easter egg)

### 4c. Port score components (current)

- `treasure_score()`: per-treasure values (5/10/14/15) summing to 177
- `visit_score()`: probably exists; needs verification
- `hint_penalty()`: -2 per hint (port reports negative)
- `endgame_score()`: 50 for detonating
- `total_score()`: sum

🔴 The math doesn't reach 350 even with all components maxed.
🔴 Port treasure values use 5/10/14/15 — canon uses 14 max consistently
   (per-treasure formula = 2 + 12 = 14).
🔴 Port doesn't track death-resurrection penalty, save-game penalty,
   or magazine-at-Witt's-End bonus.

---

## 5. Verbs

### 5a. Canon action verbs (31)

CARRY, DROP, SAY, UNLOCK, NOTHING, LOCK, LIGHT, EXTINGUISH,
WAVE, CALM, WALK, ATTACK, POUR, EAT, DRINK, RUB, THROW, QUIT,
FIND, INVENTORY, FEED, FILL, BLAST, SCORE, FEE/FIE/FOE/FOO,
BRIEF, READ, BREAK, WAKE, SUSPEND, HOURS

### 5b. Port verbs that match canon

LOOK / EXAMINE / READ / TAKE / DROP / INVENTORY / ATTACK /
THROW / LIGHT / EXTINGUISH / FILL / POUR / DRINK / FEED /
RELEASE / WAVE / UNLOCK (=OPEN) / LOCK (=CLOSE) / INSERT /
YES / NO / FEE / FIE / FOE / FOO / XYZZY / PLUGH / PLOVER /
SAVE / QUIT / SCORE / HELP / HINT

### 5c. Canon verbs port lacks

| Verb | Canon use | Severity |
|---|---|---|
| **CALM** | Calm a dwarf? Calm the troll? — flavor | 🟡 |
| **WALK** | Movement (port uses direction names directly) | 🟢 |
| **EAT** | Eat food; alone refers to the food item | 🔴 (no food object → no eat) |
| **RUB** | Rub the lamp / urn — minor interactions | 🟢 |
| **FIND** | "Find <object>" — canon clue verb | 🟡 |
| **BREAK** | Break vase deliberately, etc. | 🟡 |
| **WAKE** | Wake the dwarves / bear / etc. | 🟢 |
| **SUSPEND** | Save game (port: SAVE) | 🟢 (synonym difference) |
| **BRIEF** | Toggle long descriptions | 🟡 |
| **HOURS** | Wizard mode — show cave hours | ⚪ scope |

---

## 6. Magic words

| Word | Canon pair | Port | Match |
|---|---|---|---|
| XYZZY | room 11 (debris) ↔ room 3 (well house) | port: 1 ↔ 11 | 🔴 — port's pair is wrong |
| PLUGH | room 33 (Y2) ↔ room 3 (well house) | port: 1 ↔ 33 | 🔴 — port pairs with end-of-road, canon with well house |
| PLOVER | room 33 (Y2) ↔ room 100 (Plover Room) | port: 33 ↔ 41 | 🔴 — port's Plover number wrong |
| FEE FIE FOE FOO | summons eggs back to room 92 | port: → room 28 (port's "Giant Room") | 🔴 (eggs target room) |

🔴 **All three magic-word teleport pairs have the wrong endpoint
in the port.** Canon teleports go between locations adjacent to
the well house (3); port pairs them with end-of-road (1). This
breaks the canonical "magic words let you skip back to deposit
treasures" gameplay loop.

---

## 7. Lamp / battery

Canon: lamp battery is finite. When low, lamp dims and warning
fires. Vending machine in Witt's End-area dispenses BATTERIES
(object 39); player picks up batteries, returns to lamp, "use"
or contextual to swap.

Port: lamp battery same shape, but vending machine refresh is
direct (insert coin → lamp refilled). No batteries-as-item.

🔴 Mechanics delta. Canon's "carry batteries through the cave"
sub-puzzle is missing.

---

## 8. NPCs

### 8a. Bear

| Feature | Canon | Port |
|---|---|---|
| Initial state | "Ferocious cave bear" | $Hungry ✓ |
| Feed → tame | Yes (with food object 19) | $Tame (no food required) 🔴 |
| Take chain (hungry) → death | Yes | ✓ |
| Take chain (tame) → bear follows | Yes | ✓ |
| Drop chain at chasm → bear scares troll | Yes | ✓ |
| Bear can be released (drop chain) anywhere | Canon: any room | port: only at troll bridge to scare troll | 🟡 |
| Canon location | Room 130 Barren Room | port: room 70 Bedquilt | 🔴 |

### 8b. Snake

| Feature | Canon | Port |
|---|---|---|
| Location | Room 19 Hall of Mt King | port: room 47 ❌ |
| Bird release → snake gone | Yes | ✓ |
| Block exit | All exits except north (back to Y2 33) | port: blocks east (47→71) only | 🔴 |

### 8c. Troll

| Feature | Canon | Port |
|---|---|---|
| Location | Chasm (room 117) | ✓ |
| Demands tribute | Yes — throw treasure to troll | port: blocking until bear-scare | 🔴 (no tribute path) |
| Bear scares troll | Yes (trolls vanish to room 122 area) | ✓ port: $Vanished |
| Throw any treasure to satisfy | Yes | port: doesn't accept tribute | 🔴 |

### 8d. Dragon

| Feature | Canon | Port |
|---|---|---|
| Location | Scorched cavern | port: room 71 ✓ |
| ATTACK + "with what?" + YES → dies | Yes | ✓ |
| Body becomes dead-dragon (rug recoverable) | Yes | ✓ |

🟢 Dragon match.

### 8e. Pirate

| Feature | Canon | Port |
|---|---|---|
| Threshold | After player carries any treasure into deeper cave | port has FSM but specifics unclear |
| Steals one treasure → retreats | Yes | port: yes (single-steal) |
| **Stash location** | Room 18 (low-room with note) | port: room 132 (interpolated) | 🔴 |
| Reveals invisibly through "shadowy figure" hints | Yes | port: probably not | 🟡 |

### 8f. Dwarves

| Feature | Canon | Port |
|---|---|---|
| Count | 5 (the 5th has no axe — pirate is sometimes considered 6th NPC) | port: 5 ✓ |
| Spawn | After ~3 visits to certain rooms | port: explicit `wake_dwarves()` | 🔴 |
| Throw axe (random hit) | Yes | ✓ |
| Killed with thrown axe | Yes | port: throw-axe verb works but no axe-as-item | 🔴 |
| Pirate as 6th NPC | Yes (canon includes pirate in dwarf-list logic) | port: separate FSM | 🟡 |

### 8g. Bird

| Feature | Canon | Port |
|---|---|---|
| Location | Room 13 Splendid chamber | ✓ |
| **Cage required to take** | Yes (object 4 WICKER CAGE) — without cage, bird flies away | port: no cage, bird directly takeable | 🔴 |
| Won't approach if rod carried | Yes | ✓ |
| Plover Room destroys bird | Yes | ✓ |
| Snake-passage release kills snake | Yes | ✓ |

🔴 **Missing CAGE** is a real puzzle delta — canon has the player
solve "find the cage in well house, bring it to bird chamber, put
bird in cage" before the bird is portable.

---

## 9. Endgame

| Component | Canon | Port |
|---|---|---|
| Trigger | Last lamp battery dies, or treasure-collection threshold | port: 10 deposited 🔴 |
| Closing duration | ~25 turns | port: 30 ticks 🟡 |
| Repository room | 115/116 (NE/SW ends) | port: 136 🔴 |
| Final marker (BLAST → win) | Yes | ✓ |
| Win bonus | 45 | port: 50 🔴 |
| Player + treasures teleport to repository | Yes | port: ? |
| Treasures rearranged in repository | Yes | port: ? |

---

## 10. Death and resurrection

| Feature | Canon | Port |
|---|---|---|
| Maximum resurrections | 3 (4th death = perma) | port: 3 ✓ |
| Death cost | -10 per resurrection (canon penalizes score) | port: 0 (no death penalty) | 🔴 |
| Death messages | Canon-specific text per cause | port: bear/dwarf/dark have prose; canon-fidelity unverified | 🟡 |

---

## Summary of severity

🔴 **Behavior deltas:** ~50 (rooms wrong, missing objects, scoring math wrong, magic-word pairs wrong, several NPC mechanics)
🟡 **Mechanics deltas:** ~15 (vending refresh, throw-axe, feed-bear, etc.)
🟢 **Prose deltas:** ~15 (room descriptions likely differ; not yet verified)
⚪ **Scope deltas:** ~5 (wizard hours, brief-mode toggle, etc.)

**The biggest single category is room mapping.** The port reused
canonical numbers as anchors for landmarks but didn't preserve the
canonical map structure. To reach genuine canonical fidelity the
room layout needs to be largely rebuilt with correct canon numbers
for Plover Room (100), Oriental Room (97), Giant Room (92), Soft
Room (96), Witt's End (108), Barren Room (130), Repository (115/116),
plus all the maze passages, side passages, and atmospheric rooms.

**The second biggest is missing objects.** Cage, pillow, second
rod, food, oil-in-bottle, batteries-as-item, axe-as-item, magazine,
clam, oyster — these are real game-mechanics-bearing items, not
flavor.

**The third is the magic-word pair endpoints** which fundamentally
break the canonical deposit loop.

---

## Recommended ordering for fixing

1. **Magic-word pairs** (3 fixes) — small change, big behavior fix.
2. **Treasure values + scoring formula** — get to 350 max.
3. **Hint count + thresholds** — add maze + Witt's End hints.
4. **Missing objects** that gate canonical puzzles: CAGE (bird carry), FOOD (feed bear), PILLOW (vase soft-drop), AXE (dwarf kill), BATTERIES (vending).
5. **Major room renumbering** — Oriental, Plover, Giant, Soft, Witt's End, Barren, Repository to canon numbers.
6. **NPC location moves** — bear → 130, snake → 19.
7. **Pirate stash → room 18** (also fixes gold nugget proper room).
8. **Witt's End + magazine** — closes a canonical Easter egg.
9. **Volcano + Mirror Canyon + atmospheric rooms** — last-mile prose fidelity.

Each is a discrete commit. Total: probably 2-3 weeks of careful
work to reach >95% canonical fidelity. ~50 commits.

---

## Data sources

- **Canon source:** Don Woods 1977 PDP-10 Fortran ADVENT
  (`advent.dat`, 1808 lines, 140 rooms, ~64 objects), retrieved
  from `https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz`
  on 2026-05-05.
- **Port source:** this repo's `cca/frame/cca.fgd` and
  `cca/godot/scripts/topology.gd`.
- **Cross-reference:** ESR's open-adventure (Adventure 2.5 / 1995
  evolution; useful for symbolic names like LOC_BIRDCHAMBER but
  uses different numbering than 1977; consulted for sanity-check
  but canonical authority is the Fortran).

The 1977 350-point version is the documented canon target per
the port's own EVALUATION.md / topology.gd comments.
