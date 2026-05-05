# Canonical 1977 object placements

Decoded from `advent.dat` section 7. Format per row: `OBJ J K`
where `J` = primary location (room number) and `K` = `-1`
(immobile), `0` (movable with one location), or another room
number (object placed in two locations simultaneously).

Object IDs from `objects.txt`. `0` for J means "nowhere"
(placed dynamically — e.g. pirate's chest, oyster's pearl,
dwarf's axe).

## Items / fixtures (1-40)

| ID | Name | Primary loc | Second/flag |
|---|---|---|---|
| 1 | KEYS | 3 (well house) | movable |
| 2 | LANTERN | 3 (well house) | movable |
| 3 | GRATE | 8 (depression) | 9 (also seen below grate) — immobile |
| 4 | CAGE | 10 (cobble crawl) | movable |
| 5 | ROD-with-star (magic) | 11 (debris) | movable |
| 6 | ROD-with-mark (decoy) | 0 (nowhere) | — |
| 7 | STEPS | 14 (top of small pit) | 15 (also Hall of Mists) — immobile |
| 8 | BIRD | 13 (splendid chamber) | movable |
| 9 | DOOR (rusty iron) | 94 | -1 immobile |
| 10 | PILLOW | 96 (Soft Room) | movable |
| 11 | SNAKE | **19 (Hall of Mt King)** | -1 immobile |
| 12 | FISSURE (crystal bridge target) | 17 (east bank) | 27 (west bank) — immobile |
| 13 | TABLET | 101 (Dark-room) | -1 immobile |
| 14 | CLAM | 103 (Shell Room) | movable |
| 15 | OYSTER | 0 | (created from clam) |
| 16 | MAGAZINE | 106 (Anteroom) | movable |
| 19 | FOOD | 3 (well house) | movable |
| 20 | BOTTLE | 3 (well house) | movable |
| 23 | MIRROR | 109 (Mirror Canyon) | -1 immobile |
| 24 | PLANT | **25 (West Pit Twopit)** | -1 immobile |
| 25 | PHONY PLANT | 23 (West End Twopit) | 67 (East End Twopit) |
| 26 | STALACTITE | 111 | -1 immobile |
| 27 | SHADOWY FIGURE | 35 (low window pit, low side) | 110 (high side) |
| 28 | AXE | 0 | (dynamic; placed when first dwarf throws) |
| 29 | CAVE DRAWINGS | 97 (Oriental Room) | -1 immobile ✓ |
| 30 | PIRATE | 0 | -1 immobile |
| 31 | DRAGON | **119** | **121** (canyons; two-place) |
| 32 | CHASM | 117 (one side) | 122 (far side) |
| 33 | TROLL | 117 | 122 |
| 35 | BEAR | **130 (Barren Room)** | -1 immobile |
| 37 | VOLCANO | 126 (breath-taking view) | -1 immobile |
| 38 | VENDING MACHINE | 140 (DEAD END) | -1 immobile |
| 39 | BATTERIES | 0 | (dynamic; vending output) |
| 40 | CARPET/MOSS | 96 (Soft Room) | -1 immobile |

## Treasures (50-64)

| ID | Name | Canon location | Port location | Δ |
|---|---|---|---|---|
| 50 | GOLD NUGGET | **18 (low room w/ steps note)** | 11 (debris) | 🔴 |
| 51 | DIAMONDS | **27 (west side fissure)** | 71 (port "scorched cavern") | 🔴 |
| 52 | SILVER BARS | **28 (low n/s passage at hole)** | 33 (Y2) | 🔴 |
| 53 | JEWELRY | **29 (south side chamber)** | 118 (cliff with ledge) | 🔴 |
| 54 | RARE COINS | **30 (west side chamber Hall of Mt King)** | 134 (interp) | 🔴 |
| 55 | TREASURE CHEST | 0 (dynamic — placed by pirate) | 132 (interp, static) | 🟡 mechanism |
| 56 | GOLDEN EGGS | 92 (Giant Room) | 92 ✓ |
| 57 | JEWELED TRIDENT | **95 (Magnificent Cavern)** | 130 (interp) | 🔴 |
| 58 | MING VASE | 97 (Oriental Room) | 97 ✓ |
| 59 | EGG-SIZED EMERALD | **100 (Plover Room)** | 131 (interp) | 🔴 |
| 60 | PLATINUM PYRAMID | **101 (Dark-room)** | 133 (interp) | 🔴 |
| 61 | GLISTENING PEARL | 0 (dynamic — from oyster) | 100 (Plover, static) | 🔴 mechanism |
| 62 | PERSIAN RUG | **119 + 121 (with dragon)** | 71 (port dragon area) | 🔴 |
| 63 | RARE SPICES | **127 (Chamber of Boulders)** | 40 (port "Alcove") | 🔴 |
| 64 | GOLDEN CHAIN | (with bear, room 130) | non-treasure FSM in port | 🔴 fundamental |

## Implications for Phase 5+ work

The treasure-placement deltas alone require:

1. **Add canon room 18** (low room w/ steps note) for gold.
2. **Add canon room 28** (low n/s passage at hole) for silver.
3. **Add canon room 29** (south side chamber) for jewelry.
4. **Add canon room 30** (west side chamber Hall of Mt King) for coins.
5. **Add canon rooms 27, 95, 100, 101, 119, 121, 127** for various
   treasures to land canonically.
6. **Make CHEST and PEARL dynamic** (currently static in port).
7. **Make CHAIN a treasure** (currently non-treasure FSM).
8. **Add CAGE, FOOD, AXE, BATTERIES, PILLOW, OIL, CLAM, OYSTER,
   MAGAZINE** as canon-required objects.

This is the precise list driving the next phases. Each canon
move can now be made with reference to `placements.txt` for
authoritative location data.
