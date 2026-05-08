# Per-location canon reference

Auto-generated from `cca/canon/advent.dat` and the port's 
`cca/godot/scripts/topology.gd`. Don't hand-edit this file — 
regenerate via `python3 cca/canon/gen_locations.py > cca/CANON_LOCATIONS.md`.

Decoding rules transcribed directly from `cca/canon/advent.for`:
- Travel-table `Y = M*1000 + N` encoding: lines 105-122.
- Special motion routines (N=301..303): lines 1045-1098 — see
  the *Special motion routines* section below.
- COND-bit assignments per location: lines 159-176.
- Forced-motion detection (cond=2): line 393.

Each location lists:
- Canon long-form description (section 1).
- Properties — lit/dark, water/oil source, pirate-forbidden, 
  hint-system flags (section 9 cond bits).
- Forced-motion target if any (cond=2).
- Every canon section-3 travel-table row that exits the room, 
  decoded — including the inlined text of any `msg #N` it 
  references.
- Reached-from list (which rooms route in via what verbs).
- Object/NPC placements (section 7).
- The port's current `topology.gd` ROOMS and GATES status.

---

## Special motion routines (canon dest 301..303)

The travel-table encoding allows `300 < N <= 500` to dispatch 
into a hardcoded routine (per `advent.for` lines 105-110). The 
1977 release defines exactly three. Behavior is transcribed 
verbatim from `advent.for` lines 1045-1098 — anywhere the 
port disagrees with these bodies is a port-side delta.

### Routine 301 — Plover-alcove squeeze (FORTRAN line 30100)

```fortran
30100   NEWLOC = 99 + 100 - LOC
        IF (HOLDNG.EQ.0 .OR.
     1     (HOLDNG.EQ.1 .AND. TOTING(EMRALD))) GOTO 2
        NEWLOC = LOC
        CALL RSPEAK(117)
        GOTO 2
```

**Effect:** at canon 99 ↔ 100 (Alcove ↔ Plover Room), the tight 
passage admits the player only with empty hands or carrying 
exactly one item — the emerald. Otherwise prints msg #117 
(*"SOMETHING YOU'RE CARRYING WON'T FIT THROUGH THE TUNNEL WITH YOU. YOU'D BEST TAKE INVENTORY AND DROP SOMETHING."*) 
and the player stays put. `99+100-LOC` flips between 99 and 100.

**Port:** `Adventure.plover_squeeze_blocked()` returns true 
when `HOLDNG > 1` *or* (HOLDNG == 1 and not carrying emerald). 
GATES `99:east`, `100:west` use the `plover_squeeze` check type.

### Routine 302 — Plover transport (FORTRAN line 30200)

```fortran
30200   CALL DROP(EMRALD,LOC)
        GOTO 12
```

**Effect:** if PLUGH is invoked at Y2 (33) or Plover Room (100) 
*while carrying the emerald*, the emerald is dropped at the 
current location and the player is then re-routed through the 
Plover passage rather than the normal PLUGH teleport — forcing 
them to use the squeeze (routine 301) to retrieve it. The canon 
section-3 condition `M = 159` (carrying obj 59 = emerald) gates 
this routine at both 33 and 100.

**Port:** *not currently implemented* as a special routine. The 
port handles PLUGH via `MagicWordTeleport` aspect which always 
teleports unconditionally — the canon emerald-carrying detour 
is a known divergence (logged in `CANON_DELTAS.md` if not yet 
there). Closing this would mean adding an inventory check in 
`MagicWordTeleport` for emerald + drop-and-reroute behaviour.

### Routine 303 — Troll-bridge crossing (FORTRAN line 30300)

```fortran
30300   IF (PROP(TROLL).NE.1) GOTO 30310
        CALL PSPEAK(TROLL,1)
        PROP(TROLL) = 0
        CALL MOVE(TROLL2, 0)
        CALL MOVE(TROLL2+100, 0)
        CALL MOVE(TROLL, PLAC(TROLL))
        CALL MOVE(TROLL+100, FIXD(TROLL))
        CALL JUGGLE(CHASM)
        NEWLOC = LOC
        GOTO 2

30310   NEWLOC = PLAC(TROLL) + FIXD(TROLL) - LOC
        IF (PROP(TROLL).EQ.0) PROP(TROLL) = 1
        IF (.NOT.TOTING(BEAR)) GOTO 2
        CALL RSPEAK(162)
        PROP(CHASM) = 1
        PROP(TROLL) = 2
        CALL DROP(BEAR, NEWLOC)
        FIXED(BEAR) = -1
        PROP(BEAR) = 3
        IF (PROP(SPICES).LT.0) TALLY2 = TALLY2 + 1
        OLDLC2 = NEWLOC
        GOTO 99
```

**Effect:** crossing the troll bridge between canon 117 (R_SWSIDE) 
and canon 122 (R_NESIDE). Logic depends on `PROP(TROLL)`:
- `PROP(TROLL) == 1` (already crossed once after paying): troll 
  steps out from hiding to block (PSPEAK msg 1), resets to 0 
  (demanding again), juggles chasm.
- otherwise: walk across (`PLAC(TROLL) + FIXD(TROLL) - LOC` flips 
  between 117 and 122), promote `PROP(TROLL)` to 1.
- if carrying the bear: PSPEAK msg 162 ('the bear lumbers across, 
  scaring the troll'), troll permanently scared (`PROP(TROLL)=2`), 
  bear dropped on far side and immobilised, chasm crossed.

**Port:** the `Troll` Frame system handles `$Demanding → pay_toll → 
$TollPaid → bear_arrives → $Vanished`. Bridge-crossing dest 117↔122 
is encoded directly in `topology.gd` with the `troll` gate check 
rather than via a special-routine dispatch.

---

##   1 — YOU'RE AT END OF ROAD AGAIN

> YOU ARE STANDING AT THE END OF A ROAD BEFORE A SMALL BRICK BUILDING. AROUND YOU IS A FOREST. A SMALL STREAM FLOWS OUT OF THE BUILDING AND DOWN A GULLY. YOU'RE AT END OF ROAD AGAIN.

**Properties (section 9):** **lit** (sunlit / always lit); **water source** (FILL BOTTLE here yields water)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `2` | `HILL/WEST/UP` | → room 2 |
| `3` | `ENTER/BUILDING/IN/EAST` | → room 3 |
| `4` | `DOWNSTREAM/GULLY/STREAM/SOUTH/DOWN` | → room 4 |
| `5` | `FOREST/NORTH/EAST` | → room 5 |
| `8` | `DEPRESSION` | → room 8 |

**Reached from:** 2 (HILL/BUILDING/FORWARD/EAST/NORTH/DOWN), 3 (ENTER/OUT/OUTDOORS/WEST), 4 (UPSTREAM/BUILDING/NORTH), 6 (HILL/NORTH), 7 (BUILDING), 8 (BUILDING)

**Port `topology.gd` ROOMS[1]:** `{building→3, depression→8, down→4, downstream→4, east→3, enter→3, forest→5, gully→4, hill→2, in→3, north→5, south→4, stream→4, up→2, west→2}`

---

##   2 — YOU'RE AT HILL IN ROAD

> YOU HAVE WALKED UP A HILL, STILL IN THE FOREST. THE ROAD SLOPES BACK DOWN THE OTHER SIDE OF THE HILL. THERE IS A BUILDING IN THE DISTANCE. YOU'RE AT HILL IN ROAD.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `1` | `HILL/BUILDING/FORWARD/EAST/NORTH/DOWN` | → room 1 |
| `5` | `FOREST/NORTH/SOUTH` | → room 5 |

**Reached from:** 1 (HILL/WEST/UP)

**Port `topology.gd` ROOMS[2]:** `{building→1, down→1, east→1, forest→5, forward→1, hill→1, north→1, south→5}`

---

##   3 — YOU'RE INSIDE BUILDING

> YOU ARE INSIDE A BUILDING, A WELL HOUSE FOR A LARGE SPRING. YOU'RE INSIDE BUILDING.

**Properties (section 9):** **lit** (sunlit / always lit); **water source** (FILL BOTTLE here yields water)

**Objects/NPCs placed here (section 7):** 1=KEYS, 2=LAMP, 19=FOOD, 20=BOTTL

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `1` | `ENTER/OUT/OUTDOORS/WEST` | → room 1 |
| `11` | `SLABROOM` | → room 11 |
| `33` | `PLUGH` | → room 33 |
| `79` | `DOWNSTREAM/STREAM` | → room 79 |

**Reached from:** 1 (ENTER/BUILDING/IN/EAST), 11 (SLABROOM), 33 (PLUGH), 79 (ROAD/HILL)

**Port `topology.gd` ROOMS[3]:** `{downstream→79, enter→1, out→1, outdoors→1, stream→79, west→1}`

---

##   4 — YOU'RE IN VALLEY

> YOU ARE IN A VALLEY IN THE FOREST BESIDE A STREAM TUMBLING ALONG A ROCKY BED. YOU'RE IN VALLEY.

**Properties (section 9):** **lit** (sunlit / always lit); **water source** (FILL BOTTLE here yields water)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `1` | `UPSTREAM/BUILDING/NORTH` | → room 1 |
| `5` | `FOREST/EAST/WEST/UP` | → room 5 |
| `7` | `DOWNSTREAM/SOUTH/DOWN` | → room 7 |
| `8` | `DEPRESSION` | → room 8 |

**Reached from:** 1 (DOWNSTREAM/GULLY/STREAM/SOUTH/DOWN), 5 (VALLEY/EAST/DOWN), 6 (VALLEY/EAST/WEST/DOWN), 7 (UPSTREAM/NORTH)

**Port `topology.gd` ROOMS[4]:** `{building→1, depression→8, down→7, downstream→7, east→5, forest→5, north→1, south→7, up→5, upstream→1, west→5}`

---

##   5 — YOU'RE IN FOREST

> YOU ARE IN OPEN FOREST, WITH A DEEP VALLEY TO ONE SIDE. YOU'RE IN FOREST.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `4` | `VALLEY/EAST/DOWN` | → room 4 |
| `50005` | `FOREST/FORWARD/NORTH` | if 50% probability: → room 5 |
| `6` | `FOREST` | → room 6 |
| `5` | `WEST/SOUTH` | → room 5 |

**Reached from:** 1 (FOREST/NORTH/EAST), 2 (FOREST/NORTH/SOUTH), 4 (FOREST/EAST/WEST/UP), 5 (WEST/SOUTH), 6 (FOREST/SOUTH), 7 (FOREST/EAST/WEST), 8 (FOREST/EAST/WEST/SOUTH)

**Port `topology.gd` ROOMS[5]:** `{down→4, east→4, forest→6, south→5, valley→4, west→5}`

---

##   6 — YOU'RE IN FOREST

> YOU ARE IN OPEN FOREST NEAR BOTH A VALLEY AND A ROAD. YOU'RE IN FOREST.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `1` | `HILL/NORTH` | → room 1 |
| `4` | `VALLEY/EAST/WEST/DOWN` | → room 4 |
| `5` | `FOREST/SOUTH` | → room 5 |

**Reached from:** 5 (FOREST)

**Port `topology.gd` ROOMS[6]:** `{down→4, east→4, forest→5, hill→1, north→1, south→5, valley→4, west→4}`

---

##   7 — YOU'RE AT SLIT IN STREAMBED

> AT YOUR FEET ALL THE WATER OF THE STREAM SPLASHES INTO A 2-INCH SLIT IN THE ROCK. DOWNSTREAM THE STREAMBED IS BARE ROCK. YOU'RE AT SLIT IN STREAMBED.

**Properties (section 9):** **lit** (sunlit / always lit); **water source** (FILL BOTTLE here yields water)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `1` | `BUILDING` | → room 1 |
| `4` | `UPSTREAM/NORTH` | → room 4 |
| `5` | `FOREST/EAST/WEST` | → room 5 |
| `8` | `DOWNSTREAM/ROCK/BED/SOUTH` | → room 8 |
| `595` | `SLIT/STREAM/DOWN` | print msg #95<br><small>↳ *"YOU DON'T FIT THROUGH A TWO-INCH SLIT!"*</small> |

**Reached from:** 4 (DOWNSTREAM/SOUTH/DOWN), 8 (UPSTREAM/GULLY/NORTH)

**Port `topology.gd` ROOMS[7]:** `{bed→8, building→1, downstream→8, east→5, forest→5, north→4, rock→8, south→8, upstream→4, west→5}`

**Port GATES[7]:** slit/always, stream/always, down/always

---

##   8 — YOU'RE OUTSIDE GRATE

> YOU ARE IN A 20-FOOT DEPRESSION FLOORED WITH BARE DIRT. SET INTO THE DIRT IS A STRONG STEEL GRATE MOUNTED IN CONCRETE. A DRY STREAMBED LEADS INTO THE DEPRESSION. YOU'RE OUTSIDE GRATE.

**Properties (section 9):** **lit** (sunlit / always lit); hint flags: trying to get into cave

**Objects/NPCs placed here (section 7):** 3=GRATE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `5` | `FOREST/EAST/WEST/SOUTH` | → room 5 |
| `1` | `BUILDING` | → room 1 |
| `7` | `UPSTREAM/GULLY/NORTH` | → room 7 |
| `303009` | `ENTER/IN/DOWN` | if prop(obj #3) ≠ 0: → room 9 |
| `593` | `ENTER` | print msg #93<br><small>↳ *"YOU CAN'T GO THROUGH A LOCKED STEEL GRATE!"*</small> |

**Reached from:** 1 (DEPRESSION), 4 (DEPRESSION), 7 (DOWNSTREAM/ROCK/BED/SOUTH)

**Port `topology.gd` ROOMS[8]:** `{building→1, down→9, east→5, enter→9, forest→5, gully→7, in→9, north→7, south→5, upstream→7, west→5}`

**Port GATES[8]:** down/grate, in/grate

---

##   9 — YOU'RE BELOW THE GRATE

> YOU ARE IN A SMALL CHAMBER BENEATH A 3X3 STEEL GRATE TO THE SURFACE. A LOW CRAWL OVER COBBLES LEADS INWARD TO THE WEST. YOU'RE BELOW THE GRATE.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `303008` | `OUT/UP` | if prop(obj #3) ≠ 0: → room 8 |
| `593` | `OUT` | print msg #93<br><small>↳ *"YOU CAN'T GO THROUGH A LOCKED STEEL GRATE!"*</small> |
| `10` | `CRAWL/COBBLES/IN/WEST` | → room 10 |
| `14` | `PIT` | → room 14 |
| `11` | `DEBRIS` | → room 11 |

**Reached from:** 10 (OUT/SURFACE/v21/EAST), 11 (ENTRANCE), 12 (ENTRANCE), 13 (ENTRANCE), 14 (ENTRANCE)

**Port `topology.gd` ROOMS[9]:** `{cobbles→10, crawl→10, debris→11, in→10, pit→14, west→10}`

---

##  10 — YOU'RE IN COBBLE CRAWL

> YOU ARE CRAWLING OVER COBBLES IN A LOW PASSAGE. THERE IS A DIM LIGHT AT THE EAST END OF THE PASSAGE. YOU'RE IN COBBLE CRAWL.

**Properties (section 9):** **lit** (sunlit / always lit)

**Objects/NPCs placed here (section 7):** 4=CAGE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `9` | `OUT/SURFACE/v21/EAST` | → room 9 |
| `11` | `IN/DARK/WEST/DEBRIS` | → room 11 |
| `14` | `PIT` | → room 14 |

**Reached from:** 9 (CRAWL/COBBLES/IN/WEST), 11 (CRAWL/COBBLES/PASSAGE/LOW/EAST)

**Port `topology.gd` ROOMS[10]:** `{dark→11, debris→11, east→9, in→11, out→9, pit→14, surface→9, west→11}`

---

##  11 — YOU'RE IN DEBRIS ROOM

> YOU ARE IN A DEBRIS ROOM FILLED WITH STUFF WASHED IN FROM THE SURFACE. A LOW WIDE PASSAGE WITH COBBLES BECOMES PLUGGED WITH MUD AND DEBRIS HERE, BUT AN AWKWARD CANYON LEADS UPWARD AND WEST. A NOTE ON THE WALL SAYS "MAGIC WORD XYZZY". YOU'RE IN DEBRIS ROOM.

**Objects/NPCs placed here (section 7):** 5=ROD

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `303008` | `DEPRESSION` | if prop(obj #3) ≠ 0: → room 8 |
| `9` | `ENTRANCE` | → room 9 |
| `10` | `CRAWL/COBBLES/PASSAGE/LOW/EAST` | → room 10 |
| `12` | `CANYON/IN/UP/WEST` | → room 12 |
| `3` | `SLABROOM` | → room 3 |
| `14` | `PIT` | → room 14 |

**Reached from:** 3 (SLABROOM), 9 (DEBRIS), 10 (IN/DARK/WEST/DEBRIS), 12 (DOWN/EAST/DEBRIS), 13 (DEBRIS), 14 (DEBRIS)

**Port `topology.gd` ROOMS[11]:** `{canyon→12, cobbles→10, crawl→10, east→10, entrance→9, in→12, low→10, passage→10, pit→14, up→12, west→12}`

---

##  12 — YOU ARE IN AN AWKWARD SLOPING EAST/WEST CANYON

> YOU ARE IN AN AWKWARD SLOPING EAST/WEST CANYON.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `303008` | `DEPRESSION` | if prop(obj #3) ≠ 0: → room 8 |
| `9` | `ENTRANCE` | → room 9 |
| `11` | `DOWN/EAST/DEBRIS` | → room 11 |
| `13` | `IN/UP/WEST` | → room 13 |
| `14` | `PIT` | → room 14 |

**Reached from:** 11 (CANYON/IN/UP/WEST), 13 (CANYON/EAST)

**Port `topology.gd` ROOMS[12]:** `{debris→11, down→11, east→11, entrance→9, in→13, pit→14, up→13, west→13}`

---

##  13 — YOU'RE IN BIRD CHAMBER

> YOU ARE IN A SPLENDID CHAMBER THIRTY FEET HIGH. THE WALLS ARE FROZEN RIVERS OF ORANGE STONE. AN AWKWARD CANYON AND A GOOD PASSAGE EXIT FROM EAST AND WEST SIDES OF THE CHAMBER. YOU'RE IN BIRD CHAMBER.

**Properties (section 9):** dark (requires lamp); hint flags: catching bird

**Objects/NPCs placed here (section 7):** 8=BIRD

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `303008` | `DEPRESSION` | if prop(obj #3) ≠ 0: → room 8 |
| `9` | `ENTRANCE` | → room 9 |
| `11` | `DEBRIS` | → room 11 |
| `12` | `CANYON/EAST` | → room 12 |
| `14` | `PASSAGE/PIT/WEST` | → room 14 |

**Reached from:** 12 (IN/UP/WEST), 14 (PASSAGE/EAST), 57 (DOWN/CLIMB)

**Port `topology.gd` ROOMS[13]:** `{canyon→12, debris→11, east→12, entrance→9, passage→14, pit→14, west→14}`

---

##  14 — YOU'RE AT TOP OF SMALL PIT

> AT YOUR FEET IS A SMALL PIT BREATHING TRACES OF WHITE MIST. AN EAST PASSAGE ENDS HERE EXCEPT FOR A SMALL CRACK LEADING ON. YOU'RE AT TOP OF SMALL PIT.

**Objects/NPCs placed here (section 7):** 7=STEPS

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `303008` | `DEPRESSION` | if prop(obj #3) ≠ 0: → room 8 |
| `9` | `ENTRANCE` | → room 9 |
| `11` | `DEBRIS` | → room 11 |
| `13` | `PASSAGE/EAST` | → room 13 |
| `150020` | `DOWN/PIT/STEPS` | if carrying obj #50: → room 20 |
| `15` | `DOWN` | → room 15 |
| `16` | `CRACK/WEST` | → room 16 |

**Reached from:** 9 (PIT), 10 (PIT), 11 (PIT), 12 (PIT), 13 (PASSAGE/PIT/WEST), 15 (UP), 16 (ROAD/HILL)

**Port `topology.gd` ROOMS[14]:** `{crack→16, debris→11, down→15, east→13, entrance→9, passage→13, west→16}`

---

##  15 — YOU'RE IN HALL OF MISTS

> YOU ARE AT ONE END OF A VAST HALL STRETCHING FORWARD OUT OF SIGHT TO THE WEST. THERE ARE OPENINGS TO EITHER SIDE. NEARBY, A WIDE STONE STAIRCASE LEADS DOWNWARD. THE HALL IS FILLED WITH WISPS OF WHITE MIST SWAYING TO AND FRO ALMOST AS IF ALIVE. A COLD WIND BLOWS UP THE STAIRCASE. THERE IS A PASSAGE AT THE TOP OF A DOME BEHIND YOU. YOU'RE IN HALL OF MISTS.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `18` | `LEFT/SOUTH` | → room 18 |
| `17` | `FORWARD/HALL/WEST` | → room 17 |
| `19` | `STAIRS/DOWN/NORTH` | → room 19 |
| `150022` | `UP/PIT/STEPS/DOME/PASSAGE/EAST` | if carrying obj #50: → room 22 |
| `14` | `UP` | → room 14 |
| `34` | `Y2` | → room 34 |

**Reached from:** 14 (DOWN), 17 (HALL/EAST), 18 (HALL/OUT/NORTH), 19 (STAIRS/UP/EAST), 22 (ROAD/HILL), 34 (UP)

**Port `topology.gd` ROOMS[15]:** `{down→19, forward→17, hall→17, left→18, north→19, south→18, stairs→19, up→14, west→17}`

---

##  16 — THE CRACK IS FAR TOO SMALL FOR YOU TO FOLLOW

> THE CRACK IS FAR TOO SMALL FOR YOU TO FOLLOW.

**Forced motion (cond=2):** any verb routes to room 14. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 14.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `14` | `ROAD/HILL` | → room 14 |

**Reached from:** 14 (CRACK/WEST)

**Port `topology.gd` ROOMS[16]:** `{back→14, east→14, out→14}`

---

##  17 — YOU'RE ON EAST BANK OF FISSURE

> YOU ARE ON THE EAST BANK OF A FISSURE SLICING CLEAR ACROSS THE HALL. THE MIST IS QUITE THICK HERE, AND THE FISSURE IS TOO WIDE TO JUMP. YOU'RE ON EAST BANK OF FISSURE.

**Objects/NPCs placed here (section 7):** 12=FISSU

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `15` | `HALL/EAST` | → room 15 |
| `312596` | `JUMP` | if prop(obj #12) ≠ 0: print msg #96<br><small>↳ *"I RESPECTFULLY SUGGEST YOU GO ACROSS THE BRIDGE INSTEAD OF JUMPING."*</small> |
| `412021` | `FORWARD` | if prop(obj #12) ≠ 1: → room 21 |
| `412597` | `OVER/ACROSS/WEST/CROSS` | if prop(obj #12) ≠ 1: print msg #97<br><small>↳ *"THERE IS NO WAY ACROSS THE FISSURE."*</small> |
| `27` | `OVER` | → room 27 |

**Reached from:** 15 (FORWARD/HALL/WEST), 27 (OVER)

**Port `topology.gd` ROOMS[17]:** `{across→27, cross→27, east→15, hall→15, over→27, west→27}`

**Port GATES[17]:** over/bridge, across/bridge, west/bridge, cross/bridge, jump/always

---

##  18 — YOU'RE IN NUGGET OF GOLD ROOM

> THIS IS A LOW ROOM WITH A CRUDE NOTE ON THE WALL. THE NOTE SAYS, "YOU WON'T GET IT UP THE STEPS". YOU'RE IN NUGGET OF GOLD ROOM.

**Objects/NPCs placed here (section 7):** 50=GOLD

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `15` | `HALL/OUT/NORTH` | → room 15 |

**Reached from:** 15 (LEFT/SOUTH)

**Port `topology.gd` ROOMS[18]:** `{hall→15, north→15, out→15}`

---

##  19 — YOU'RE IN HALL OF MT KING

> YOU ARE IN THE HALL OF THE MOUNTAIN KING, WITH PASSAGES OFF IN ALL DIRECTIONS. YOU'RE IN HALL OF MT KING

**Properties (section 9):** dark (requires lamp); hint flags: dealing with snake

**Objects/NPCs placed here (section 7):** 11=SNAKE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `15` | `STAIRS/UP/EAST` | → room 15 |
| `311028` | `NORTH/LEFT` | if prop(obj #11) ≠ 0: → room 28 |
| `311029` | `SOUTH/RIGHT` | if prop(obj #11) ≠ 0: → room 29 |
| `311030` | `WEST/FORWARD` | if prop(obj #11) ≠ 0: → room 30 |
| `32` | `NORTH` | → room 32 |
| `35074` | `SW` | if 35% probability: → room 74 |
| `211032` | `SW` | if carrying or co-located with obj #11: → room 32 |
| `74` | `SECRET` | → room 74 |

**Reached from:** 15 (STAIRS/DOWN/NORTH), 28 (HALL/OUT/SOUTH), 29 (HALL/OUT/NORTH), 30 (HALL/OUT/EAST), 32 (ROAD/HILL), 74 (EAST)

**Port `topology.gd` ROOMS[19]:** `{east→15, forward→30, left→28, north→28, right→29, secret→74, south→29, stairs→15, sw→74, up→15, west→30}`

**Port GATES[19]:** north/snake, south/snake, west/snake, left/snake, right/snake, forward/snake

---

##  20 — YOU ARE AT THE BOTTOM OF THE PIT WITH A BROKEN NECK

> YOU ARE AT THE BOTTOM OF THE PIT WITH A BROKEN NECK.

**Forced motion (cond=2):** any verb stays put — this is a transition / death-message room. The 
engine prints the room's long description and 
continues on the player's *next* turn from here.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `0` | `ROAD/HILL` | → stay put (forced-motion sentinel) |

**Reached from:** 35 (JUMP), 88 (JUMP), 110 (JUMP)

**Port `topology.gd` ROOMS[20]:** `{}` (no exits)

---

##  21 — YOU DIDN'T MAKE IT

> YOU DIDN'T MAKE IT.

**Forced motion (cond=2):** any verb stays put — this is a transition / death-message room. The 
engine prints the room's long description and 
continues on the player's *next* turn from here.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `0` | `ROAD/HILL` | → stay put (forced-motion sentinel) |

**Port `topology.gd` ROOMS[21]:** `{}` (no exits)

---

##  22 — THE DOME IS UNCLIMBABLE

> THE DOME IS UNCLIMBABLE.

**Forced motion (cond=2):** any verb routes to room 15. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 15.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `15` | `ROAD/HILL` | → room 15 |

**Port `topology.gd` ROOMS[22]:** `{back→15, out→15}`

---

##  23 — YOU'RE AT WEST END OF TWOPIT ROOM

> YOU ARE AT THE WEST END OF THE TWOPIT ROOM. THERE IS A LARGE HOLE IN THE WALL ABOVE THE PIT AT THIS END OF THE ROOM. YOU'RE AT WEST END OF TWOPIT ROOM.

**Objects/NPCs placed here (section 7):** 25=PLANT	(MUST BE NEXT OBJECT AFTER "REAL" PLANT)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `67` | `EAST/ACROSS` | → room 67 |
| `68` | `WEST/SLAB` | → room 68 |
| `25` | `DOWN/PIT` | → room 25 |
| `648` | `HOLE` | print msg #148<br><small>↳ *"IT IS TOO FAR UP FOR YOU TO REACH."*</small> |

**Reached from:** 25 (UP/OUT), 67 (WEST/ACROSS), 68 (SOUTH), 90 (ROAD/HILL)

**Port `topology.gd` ROOMS[23]:** `{across→67, down→25, east→67, pit→25, slab→68, west→68}`

**Port GATES[23]:** hole/always

---

##  24 — YOU'RE IN EAST PIT

> YOU ARE AT THE BOTTOM OF THE EASTERN PIT IN THE TWOPIT ROOM. THERE IS A SMALL POOL OF OIL IN ONE CORNER OF THE PIT. YOU'RE IN EAST PIT.

**Properties (section 9):** dark (requires lamp); **oil source** (FILL BOTTLE here yields oil)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `67` | `UP/OUT` | → room 67 |

**Reached from:** 67 (DOWN/PIT)

**Port `topology.gd` ROOMS[24]:** `{out→67, up→67}`

---

##  25 — YOU'RE IN WEST PIT

> YOU ARE AT THE BOTTOM OF THE WESTERN PIT IN THE TWOPIT ROOM. THERE IS A LARGE HOLE IN THE WALL ABOUT 25 FEET ABOVE YOU. YOU'RE IN WEST PIT.

**Objects/NPCs placed here (section 7):** 24=PLANT

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `23` | `UP/OUT` | → room 23 |
| `724031` | `CLIMB` | if cond=M724: → room 31 |
| `26` | `CLIMB` | → room 26 |

**Reached from:** 23 (DOWN/PIT), 88 (DOWN/CLIMB/EAST), 89 (ROAD/HILL)

**Port `topology.gd` ROOMS[25]:** `{climb→26, out→23, up→23}`

**Port GATES[25]:** up/plant_tall, out/plant_tall, climb/plant_huge

---

##  26 — YOU CLAMBER UP THE PLANT AND SCURRY THROUGH THE HOLE AT THE TOP

> YOU CLAMBER UP THE PLANT AND SCURRY THROUGH THE HOLE AT THE TOP.

**Forced motion (cond=2):** any verb routes to room 88. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 88.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `88` | `ROAD/HILL` | → room 88 |

**Reached from:** 25 (CLIMB)

**Port `topology.gd` ROOMS[26]:** `{back→88, east→88, out→88}`

---

##  27 — YOU ARE ON THE WEST SIDE OF THE FISSURE IN THE HALL OF MISTS

> YOU ARE ON THE WEST SIDE OF THE FISSURE IN THE HALL OF MISTS.

**Objects/NPCs placed here (section 7):** 51=DIAMO

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `312596` | `JUMP` | if prop(obj #12) ≠ 0: print msg #96<br><small>↳ *"I RESPECTFULLY SUGGEST YOU GO ACROSS THE BRIDGE INSTEAD OF JUMPING."*</small> |
| `412021` | `FORWARD` | if prop(obj #12) ≠ 1: → room 21 |
| `412597` | `OVER/ACROSS/EAST/CROSS` | if prop(obj #12) ≠ 1: print msg #97<br><small>↳ *"THERE IS NO WAY ACROSS THE FISSURE."*</small> |
| `17` | `OVER` | → room 17 |
| `40` | `NORTH` | → room 40 |
| `41` | `WEST` | → room 41 |

**Reached from:** 17 (OVER), 41 (EAST), 59 (ROAD/HILL)

**Port `topology.gd` ROOMS[27]:** `{across→17, cross→17, east→17, north→40, over→17, west→41}`

**Port GATES[27]:** over/bridge, across/bridge, east/bridge, cross/bridge, jump/always

---

##  28 — YOU ARE IN A LOW N/S PASSAGE AT A HOLE IN THE FLOOR.  THE HOLE GOES

> YOU ARE IN A LOW N/S PASSAGE AT A HOLE IN THE FLOOR. THE HOLE GOES DOWN TO AN E/W PASSAGE.

**Objects/NPCs placed here (section 7):** 52=SILVE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `19` | `HALL/OUT/SOUTH` | → room 19 |
| `33` | `NORTH/Y2` | → room 33 |
| `36` | `DOWN/HOLE` | → room 36 |

**Reached from:** 33 (SOUTH), 36 (UP/HOLE)

**Port `topology.gd` ROOMS[28]:** `{down→36, hall→19, hole→36, north→33, out→19, south→19}`

---

##  29 — YOU ARE IN THE SOUTH SIDE CHAMBER

> YOU ARE IN THE SOUTH SIDE CHAMBER.

**Objects/NPCs placed here (section 7):** 53=JEWEL

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `19` | `HALL/OUT/NORTH` | → room 19 |

**Port `topology.gd` ROOMS[29]:** `{hall→19, north→19, out→19}`

---

##  30 — YOU ARE IN THE WEST SIDE CHAMBER OF THE HALL OF THE MOUNTAIN KING

> YOU ARE IN THE WEST SIDE CHAMBER OF THE HALL OF THE MOUNTAIN KING. A PASSAGE CONTINUES WEST AND UP HERE.

**Objects/NPCs placed here (section 7):** 54=COINS

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `19` | `HALL/OUT/EAST` | → room 19 |
| `62` | `WEST/UP` | → room 62 |

**Reached from:** 62 (EAST)

**Port `topology.gd` ROOMS[30]:** `{east→19, hall→19, out→19, up→62, west→62}`

---

##  31 — >$<

> >$<

**Forced motion (cond=2):** any verb routes to room 524089. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 524089.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `524089` | `ROAD/HILL` | if prop(obj #24) ≠ 2: → room 89 |
| `90` | `ROAD/HILL` | → room 90 |

**Port `topology.gd` ROOMS[31]:** `{}` (no exits)

---

##  32 — YOU CAN'T GET BY THE SNAKE

> YOU CAN'T GET BY THE SNAKE.

**Forced motion (cond=2):** any verb routes to room 19. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 19.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `19` | `ROAD/HILL` | → room 19 |

**Reached from:** 19 (NORTH)

**Port `topology.gd` ROOMS[32]:** `{back→19, out→19, south→19}`

---

##  33 — YOU'RE AT "Y2"

> YOU ARE IN A LARGE ROOM, WITH A PASSAGE TO THE SOUTH, A PASSAGE TO THE WEST, AND A WALL OF BROKEN ROCK TO THE EAST. THERE IS A LARGE "Y2" ON A ROCK IN THE ROOM'S CENTER. YOU'RE AT "Y2".

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `3` | `PLUGH` | → room 3 |
| `28` | `SOUTH` | → room 28 |
| `34` | `EAST/WALL/BROKEN` | → room 34 |
| `35` | `WEST` | → room 35 |
| `159302` | `PLUGH` | if carrying obj #59: special routine 2 (Plover transport (drop emerald, use passage)) |
| `100` | `PLUGH` | → room 100 |

**Reached from:** 3 (PLUGH), 28 (NORTH/Y2), 34 (DOWN/Y2), 35 (EAST/Y2), 100 (PLUGH)

**Port `topology.gd` ROOMS[33]:** `{broken→34, east→34, south→28, wall→34, west→35}`

---

##  34 — YOU ARE IN A JUMBLE OF ROCK, WITH CRACKS EVERYWHERE

> YOU ARE IN A JUMBLE OF ROCK, WITH CRACKS EVERYWHERE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `33` | `DOWN/Y2` | → room 33 |
| `15` | `UP` | → room 15 |

**Reached from:** 15 (Y2), 33 (EAST/WALL/BROKEN)

**Port `topology.gd` ROOMS[34]:** `{down→33, up→15}`

---

##  35 — YOU'RE AT WINDOW ON PIT

> YOU'RE AT A LOW WINDOW OVERLOOKING A HUGE PIT, WHICH EXTENDS UP OUT OF SIGHT. A FLOOR IS INDISTINCTLY VISIBLE OVER 50 FEET BELOW. TRACES OF WHITE MIST COVER THE FLOOR OF THE PIT, BECOMING THICKER TO THE RIGHT. MARKS IN THE DUST AROUND THE WINDOW WOULD SEEM TO INDICATE THAT SOMEONE HAS BEEN HERE RECENTLY. DIRECTLY ACROSS THE PIT FROM YOU AND 25 FEET AWAY THERE IS A SIMILAR WINDOW LOOKING INTO A LIGHTED ROOM. A SHADOWY FIGURE CAN BE SEEN THERE PEERING BACK AT YOU. YOU'RE AT WINDOW ON PIT.

**Objects/NPCs placed here (section 7):** 27=SHADO

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `33` | `EAST/Y2` | → room 33 |
| `20` | `JUMP` | → room 20 |

**Reached from:** 33 (WEST)

**Port `topology.gd` ROOMS[35]:** `{east→33, jump→20}`

---

##  36 — YOU'RE IN DIRTY PASSAGE

> YOU ARE IN A DIRTY BROKEN PASSAGE. TO THE EAST IS A CRAWL. TO THE WEST IS A LARGE PASSAGE. ABOVE YOU IS A HOLE TO ANOTHER PASSAGE. YOU'RE IN DIRTY PASSAGE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `37` | `EAST/CRAWL` | → room 37 |
| `28` | `UP/HOLE` | → room 28 |
| `39` | `WEST` | → room 39 |
| `65` | `BEDQUILT` | → room 65 |

**Reached from:** 28 (DOWN/HOLE), 37 (WEST/CRAWL), 39 (EAST/PASSAGE)

**Port `topology.gd` ROOMS[36]:** `{bedquilt→65, crawl→37, east→37, hole→28, up→28, west→39}`

---

##  37 — YOU ARE ON THE BRINK OF A SMALL CLEAN CLIMBABLE PIT.  A CRAWL LEADS

> YOU ARE ON THE BRINK OF A SMALL CLEAN CLIMBABLE PIT. A CRAWL LEADS WEST.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `36` | `WEST/CRAWL` | → room 36 |
| `38` | `DOWN/PIT/CLIMB` | → room 38 |

**Reached from:** 36 (EAST/CRAWL), 38 (CLIMB/UP/OUT)

**Port `topology.gd` ROOMS[37]:** `{climb→38, crawl→36, down→38, pit→38, west→36}`

---

##  38 — YOU ARE IN THE BOTTOM OF A SMALL PIT WITH A LITTLE STREAM, WHICH

> YOU ARE IN THE BOTTOM OF A SMALL PIT WITH A LITTLE STREAM, WHICH ENTERS AND EXITS THROUGH TINY SLITS.

**Properties (section 9):** dark (requires lamp); **water source** (FILL BOTTLE here yields water)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `37` | `CLIMB/UP/OUT` | → room 37 |
| `595` | `SLIT/STREAM/DOWN/UPSTREAM/DOWNSTREAM` | print msg #95<br><small>↳ *"YOU DON'T FIT THROUGH A TWO-INCH SLIT!"*</small> |

**Reached from:** 37 (DOWN/PIT/CLIMB)

**Port `topology.gd` ROOMS[38]:** `{climb→37, out→37, up→37}`

**Port GATES[38]:** slit/always, stream/always, down/always, upstream/always, downstream/always

---

##  39 — YOU'RE IN DUSTY ROCK ROOM

> YOU ARE IN A LARGE ROOM FULL OF DUSTY ROCKS. THERE IS A BIG HOLE IN THE FLOOR. THERE ARE CRACKS EVERYWHERE, AND A PASSAGE LEADING EAST. YOU'RE IN DUSTY ROCK ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `36` | `EAST/PASSAGE` | → room 36 |
| `64` | `DOWN/HOLE/FLOOR` | → room 64 |
| `65` | `BEDQUILT` | → room 65 |

**Reached from:** 36 (WEST), 64 (UP/CLIMB/ROOM), 65 (UP)

**Port `topology.gd` ROOMS[39]:** `{bedquilt→65, down→64, east→36, floor→64, hole→64, passage→36}`

---

##  40 — YOU HAVE CRAWLED THROUGH A VERY LOW WIDE PASSAGE PARALLEL TO AND NORTH

> YOU HAVE CRAWLED THROUGH A VERY LOW WIDE PASSAGE PARALLEL TO AND NORTH OF THE HALL OF MISTS.

**Forced motion (cond=2):** any verb routes to room 41. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 41.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `41` | `ROAD/HILL` | → room 41 |

**Reached from:** 27 (NORTH)

**Port `topology.gd` ROOMS[40]:** `{back→41, east→41, out→41, west→41}`

---

##  41 — YOU'RE AT WEST END OF HALL OF MISTS

> YOU ARE AT THE WEST END OF HALL OF MISTS. A LOW WIDE CRAWL CONTINUES WEST AND ANOTHER GOES NORTH. TO THE SOUTH IS A LITTLE PASSAGE 6 FEET OFF THE FLOOR. YOU'RE AT WEST END OF HALL OF MISTS.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `42` | `SOUTH/UP/PASSAGE/CLIMB` | → room 42 |
| `27` | `EAST` | → room 27 |
| `59` | `NORTH` | → room 59 |
| `60` | `WEST/CRAWL` | → room 60 |

**Reached from:** 27 (WEST), 40 (ROAD/HILL), 42 (UP), 60 (EAST/UP/CRAWL)

**Port `topology.gd` ROOMS[41]:** `{climb→42, crawl→60, east→27, north→59, passage→42, south→42, up→42, west→60}`

---

##  42 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `41` | `UP` | → room 41 |
| `42` | `NORTH` | → room 42 |
| `43` | `EAST` | → room 43 |
| `45` | `SOUTH` | → room 45 |
| `80` | `WEST` | → room 80 |

**Reached from:** 41 (SOUTH/UP/PASSAGE/CLIMB), 42 (NORTH), 43 (WEST), 45 (WEST), 80 (NORTH)

**Port `topology.gd` ROOMS[42]:** `{east→43, north→42, south→45, up→41, west→80}`

---

##  43 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `42` | `WEST` | → room 42 |
| `44` | `SOUTH` | → room 44 |
| `45` | `EAST` | → room 45 |

**Reached from:** 42 (EAST), 44 (EAST), 45 (NORTH)

**Port `topology.gd` ROOMS[43]:** `{east→45, south→44, west→42}`

---

##  44 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `43` | `EAST` | → room 43 |
| `48` | `DOWN` | → room 48 |
| `50` | `SOUTH` | → room 50 |
| `82` | `NORTH` | → room 82 |

**Reached from:** 43 (SOUTH), 48 (UP/OUT), 50 (EAST), 82 (SOUTH/OUT)

**Port `topology.gd` ROOMS[44]:** `{down→48, east→43, north→82, south→50}`

---

##  45 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `42` | `WEST` | → room 42 |
| `43` | `NORTH` | → room 43 |
| `46` | `EAST` | → room 46 |
| `47` | `SOUTH` | → room 47 |
| `87` | `UP/DOWN` | → room 87 |

**Reached from:** 42 (SOUTH), 43 (EAST), 46 (WEST/OUT), 47 (EAST/OUT), 87 (UP/DOWN), 111 (DOWN)

**Port `topology.gd` ROOMS[45]:** `{down→87, east→46, north→43, south→47, up→87, west→42}`

---

##  46 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `45` | `WEST/OUT` | → room 45 |

**Reached from:** 45 (EAST)

**Port `topology.gd` ROOMS[46]:** `{out→45, west→45}`

---

##  47 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `45` | `EAST/OUT` | → room 45 |

**Reached from:** 45 (SOUTH)

**Port `topology.gd` ROOMS[47]:** `{east→45, out→45}`

---

##  48 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `44` | `UP/OUT` | → room 44 |

**Reached from:** 44 (DOWN)

**Port `topology.gd` ROOMS[48]:** `{out→44, up→44}`

---

##  49 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `50` | `EAST` | → room 50 |
| `51` | `WEST` | → room 51 |

**Reached from:** 50 (WEST), 51 (WEST)

**Port `topology.gd` ROOMS[49]:** `{east→50, west→51}`

---

##  50 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `44` | `EAST` | → room 44 |
| `49` | `WEST` | → room 49 |
| `51` | `DOWN` | → room 51 |
| `52` | `SOUTH` | → room 52 |

**Reached from:** 44 (SOUTH), 49 (EAST), 51 (UP), 52 (WEST)

**Port `topology.gd` ROOMS[50]:** `{down→51, east→44, south→52, west→49}`

---

##  51 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `49` | `WEST` | → room 49 |
| `50` | `UP` | → room 50 |
| `52` | `EAST` | → room 52 |
| `53` | `SOUTH` | → room 53 |

**Reached from:** 49 (WEST), 50 (DOWN), 52 (EAST), 53 (WEST)

**Port `topology.gd` ROOMS[51]:** `{east→52, south→53, up→50, west→49}`

---

##  52 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `50` | `WEST` | → room 50 |
| `51` | `EAST` | → room 51 |
| `52` | `SOUTH` | → room 52 |
| `53` | `UP` | → room 53 |
| `55` | `NORTH` | → room 55 |
| `86` | `DOWN` | → room 86 |

**Reached from:** 50 (SOUTH), 51 (EAST), 52 (SOUTH), 53 (NORTH), 55 (WEST), 86 (UP/OUT)

**Port `topology.gd` ROOMS[52]:** `{down→86, east→51, north→55, south→52, up→53, west→50}`

---

##  53 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `51` | `WEST` | → room 51 |
| `52` | `NORTH` | → room 52 |
| `54` | `SOUTH` | → room 54 |

**Reached from:** 51 (SOUTH), 52 (UP), 54 (WEST/OUT)

**Port `topology.gd` ROOMS[53]:** `{north→52, south→54, west→51}`

---

##  54 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `53` | `WEST/OUT` | → room 53 |

**Reached from:** 53 (SOUTH)

**Port `topology.gd` ROOMS[54]:** `{out→53, west→53}`

---

##  55 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `52` | `WEST` | → room 52 |
| `55` | `NORTH` | → room 55 |
| `56` | `DOWN` | → room 56 |
| `57` | `EAST` | → room 57 |

**Reached from:** 52 (NORTH), 55 (NORTH), 56 (UP/OUT), 57 (WEST)

**Port `topology.gd` ROOMS[55]:** `{down→56, east→57, north→55, west→52}`

---

##  56 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `55` | `UP/OUT` | → room 55 |

**Reached from:** 55 (DOWN)

**Port `topology.gd` ROOMS[56]:** `{out→55, up→55}`

---

##  57 — YOU'RE AT BRINK OF PIT

> YOU ARE ON THE BRINK OF A THIRTY FOOT PIT WITH A MASSIVE ORANGE COLUMN DOWN ONE WALL. YOU COULD CLIMB DOWN HERE BUT YOU COULD NOT GET BACK UP. THE MAZE CONTINUES AT THIS LEVEL. YOU'RE AT BRINK OF PIT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `13` | `DOWN/CLIMB` | → room 13 |
| `55` | `WEST` | → room 55 |
| `58` | `SOUTH` | → room 58 |
| `83` | `NORTH` | → room 83 |
| `84` | `EAST` | → room 84 |

**Reached from:** 55 (EAST), 58 (EAST/OUT), 83 (SOUTH), 84 (NORTH)

**Port `topology.gd` ROOMS[57]:** `{climb→13, down→13, east→84, north→83, south→58, west→55}`

---

##  58 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `57` | `EAST/OUT` | → room 57 |

**Reached from:** 57 (SOUTH)

**Port `topology.gd` ROOMS[58]:** `{east→57, out→57}`

---

##  59 — YOU HAVE CRAWLED THROUGH A VERY LOW WIDE PASSAGE PARALLEL TO AND NORTH

> YOU HAVE CRAWLED THROUGH A VERY LOW WIDE PASSAGE PARALLEL TO AND NORTH OF THE HALL OF MISTS.

**Forced motion (cond=2):** any verb routes to room 27. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 27.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `27` | `ROAD/HILL` | → room 27 |

**Reached from:** 41 (NORTH)

**Port `topology.gd` ROOMS[59]:** `{back→27, east→27, out→27, south→27}`

---

##  60 — YOU'RE AT EAST END OF LONG HALL

> YOU ARE AT THE EAST END OF A VERY LONG HALL APPARENTLY WITHOUT SIDE CHAMBERS. TO THE EAST A LOW WIDE CRAWL SLANTS UP. TO THE NORTH A ROUND TWO FOOT HOLE SLANTS DOWN. YOU'RE AT EAST END OF LONG HALL.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `41` | `EAST/UP/CRAWL` | → room 41 |
| `61` | `WEST` | → room 61 |
| `62` | `NORTH/DOWN/HOLE` | → room 62 |

**Reached from:** 41 (WEST/CRAWL), 61 (EAST), 62 (WEST)

**Port `topology.gd` ROOMS[60]:** `{crawl→41, down→62, east→41, hole→62, north→62, up→41, west→61}`

---

##  61 — YOU'RE AT WEST END OF LONG HALL

> YOU ARE AT THE WEST END OF A VERY LONG FEATURELESS HALL. THE HALL JOINS UP WITH A NARROW NORTH/SOUTH PASSAGE. YOU'RE AT WEST END OF LONG HALL.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `60` | `EAST` | → room 60 |
| `62` | `NORTH` | → room 62 |
| `100107` | `SOUTH` | if always (forbidden to dwarves): → room 107 |

**Reached from:** 60 (WEST), 62 (SOUTH), 107 (DOWN)

**Port `topology.gd` ROOMS[61]:** `{east→60, north→62}`

---

##  62 — YOU ARE AT A CROSSOVER OF A HIGH N/S PASSAGE AND A LOW E/W ONE

> YOU ARE AT A CROSSOVER OF A HIGH N/S PASSAGE AND A LOW E/W ONE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `60` | `WEST` | → room 60 |
| `63` | `NORTH` | → room 63 |
| `30` | `EAST` | → room 30 |
| `61` | `SOUTH` | → room 61 |

**Reached from:** 30 (WEST/UP), 60 (NORTH/DOWN/HOLE), 61 (NORTH), 63 (SOUTH/OUT)

**Port `topology.gd` ROOMS[62]:** `{east→30, north→63, south→61, west→60}`

---

##  63 — DEAD END

> DEAD END

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `62` | `SOUTH/OUT` | → room 62 |

**Reached from:** 62 (NORTH)

**Port `topology.gd` ROOMS[63]:** `{out→62, south→62}`

---

##  64 — YOU'RE AT COMPLEX JUNCTION

> YOU ARE AT A COMPLEX JUNCTION. A LOW HANDS AND KNEES PASSAGE FROM THE NORTH JOINS A HIGHER CRAWL FROM THE EAST TO MAKE A WALKING PASSAGE GOING WEST. THERE IS ALSO A LARGE ROOM ABOVE. THE AIR IS DAMP HERE. YOU'RE AT COMPLEX JUNCTION.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `39` | `UP/CLIMB/ROOM` | → room 39 |
| `65` | `WEST/BEDQUILT` | → room 65 |
| `103` | `NORTH/SHELL` | → room 103 |
| `106` | `EAST` | → room 106 |

**Reached from:** 39 (DOWN/HOLE/FLOOR), 65 (EAST), 103 (SOUTH), 106 (UP)

**Port `topology.gd` ROOMS[64]:** `{bedquilt→65, climb→39, east→106, north→103, room→39, shell→103, up→39, west→65}`

---

##  65 — YOU ARE IN BEDQUILT, A LONG EAST/WEST PASSAGE WITH HOLES EVERYWHERE

> YOU ARE IN BEDQUILT, A LONG EAST/WEST PASSAGE WITH HOLES EVERYWHERE. TO EXPLORE AT RANDOM SELECT NORTH, SOUTH, UP, OR DOWN.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `64` | `EAST` | → room 64 |
| `66` | `WEST` | → room 66 |
| `80556` | `SOUTH` | if 80% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `68` | `SLAB` | → room 68 |
| `80556` | `UP` | if 80% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `50070` | `UP` | if 50% probability: → room 70 |
| `39` | `UP` | → room 39 |
| `60556` | `NORTH` | if 60% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `75072` | `NORTH` | if 75% probability: → room 72 |
| `71` | `NORTH` | → room 71 |
| `80556` | `DOWN` | if 80% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `106` | `DOWN` | → room 106 |

**Reached from:** 36 (BEDQUILT), 39 (BEDQUILT), 64 (WEST/BEDQUILT), 66 (NE), 68 (NORTH), 70 (DOWN/PASSAGE), 71 (SE), 72 (BEDQUILT) + 1 more

**Port `topology.gd` ROOMS[65]:** `{down→106, east→64, north→71, slab→68, up→39, west→66}`

---

##  66 — YOU'RE IN SWISS CHEESE ROOM

> YOU ARE IN A ROOM WHOSE WALLS RESEMBLE SWISS CHEESE. OBVIOUS PASSAGES GO WEST, EAST, NE, AND NW. PART OF THE ROOM IS OCCUPIED BY A LARGE BEDROCK BLOCK. YOU'RE IN SWISS CHEESE ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `65` | `NE` | → room 65 |
| `67` | `WEST` | → room 67 |
| `80556` | `SOUTH` | if 80% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `77` | `CANYON` | → room 77 |
| `96` | `EAST` | → room 96 |
| `50556` | `NW` | if 50% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `97` | `ORIENTAL` | → room 97 |

**Reached from:** 65 (WEST), 67 (EAST), 77 (NORTH/CRAWL), 96 (WEST/OUT), 97 (SE)

**Port `topology.gd` ROOMS[66]:** `{canyon→77, east→96, ne→65, oriental→97, west→67}`

---

##  67 — YOU'RE AT EAST END OF TWOPIT ROOM

> YOU ARE AT THE EAST END OF THE TWOPIT ROOM. THE FLOOR HERE IS LITTERED WITH THIN ROCK SLABS, WHICH MAKE IT EASY TO DESCEND THE PITS. THERE IS A PATH HERE BYPASSING THE PITS TO CONNECT PASSAGES FROM EAST AND WEST. THERE ARE HOLES ALL OVER, BUT THE ONLY BIG ONE IS ON THE WALL DIRECTLY OVER THE WEST PIT WHERE YOU CAN'T GET TO IT. YOU'RE AT EAST END OF TWOPIT ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `66` | `EAST` | → room 66 |
| `23` | `WEST/ACROSS` | → room 23 |
| `24` | `DOWN/PIT` | → room 24 |

**Reached from:** 23 (EAST/ACROSS), 24 (UP/OUT), 66 (WEST)

**Port `topology.gd` ROOMS[67]:** `{across→23, down→24, east→66, pit→24, west→23}`

---

##  68 — YOU'RE IN SLAB ROOM

> YOU ARE IN A LARGE LOW CIRCULAR CHAMBER WHOSE FLOOR IS AN IMMENSE SLAB FALLEN FROM THE CEILING (SLAB ROOM). EAST AND WEST THERE ONCE WERE LARGE PASSAGES, BUT THEY ARE NOW FILLED WITH BOULDERS. LOW SMALL PASSAGES GO NORTH AND SOUTH, AND THE SOUTH ONE QUICKLY BENDS WEST AROUND THE BOULDERS. YOU'RE IN SLAB ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `23` | `SOUTH` | → room 23 |
| `69` | `UP/CLIMB` | → room 69 |
| `65` | `NORTH` | → room 65 |

**Reached from:** 23 (WEST/SLAB), 65 (SLAB), 69 (DOWN/SLAB)

**Port `topology.gd` ROOMS[68]:** `{climb→69, north→65, south→23, up→69}`

---

##  69 — YOU ARE IN A SECRET N/S CANYON ABOVE A LARGE ROOM

> YOU ARE IN A SECRET N/S CANYON ABOVE A LARGE ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `68` | `DOWN/SLAB` | → room 68 |
| `331120` | `SOUTH` | if prop(obj #31) ≠ 0: → room 120 |
| `119` | `SOUTH` | → room 119 |
| `109` | `NORTH` | → room 109 |
| `113` | `RESERVOIR` | → room 113 |

**Reached from:** 68 (UP/CLIMB), 109 (SOUTH), 119 (NORTH/OUT), 120 (NORTH)

**Port `topology.gd` ROOMS[69]:** `{down→68, north→109, reservoir→113, slab→68, south→119}`

---

##  70 — YOU ARE IN A SECRET N/S CANYON ABOVE A SIZABLE PASSAGE

> YOU ARE IN A SECRET N/S CANYON ABOVE A SIZABLE PASSAGE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `71` | `NORTH` | → room 71 |
| `65` | `DOWN/PASSAGE` | → room 65 |
| `111` | `SOUTH` | → room 111 |

**Reached from:** 71 (SOUTH), 111 (NORTH)

**Port `topology.gd` ROOMS[70]:** `{down→65, north→71, passage→65, south→111}`

---

##  71 — YOU'RE AT JUNCTION OF THREE SECRET CANYONS

> YOU ARE IN A SECRET CANYON AT A JUNCTION OF THREE CANYONS, BEARING NORTH, SOUTH, AND SE. THE NORTH ONE IS AS TALL AS THE OTHER TWO COMBINED. YOU'RE AT JUNCTION OF THREE SECRET CANYONS.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `65` | `SE` | → room 65 |
| `70` | `SOUTH` | → room 70 |
| `110` | `NORTH` | → room 110 |

**Reached from:** 65 (NORTH), 70 (NORTH), 110 (WEST)

**Port `topology.gd` ROOMS[71]:** `{north→110, se→65, south→70}`

---

##  72 — YOU ARE IN A LARGE LOW ROOM.  CRAWLS LEAD NORTH, SE, AND SW

> YOU ARE IN A LARGE LOW ROOM. CRAWLS LEAD NORTH, SE, AND SW.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `65` | `BEDQUILT` | → room 65 |
| `118` | `SW` | → room 118 |
| `73` | `NORTH` | → room 73 |
| `97` | `SE/ORIENTAL` | → room 97 |

**Reached from:** 73 (SOUTH/CRAWL/OUT), 91 (DOWN/CLIMB), 97 (WEST/CRAWL), 118 (DOWN)

**Port `topology.gd` ROOMS[72]:** `{bedquilt→65, north→73, oriental→97, se→97, sw→118}`

---

##  73 — DEAD END CRAWL

> DEAD END CRAWL.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `72` | `SOUTH/CRAWL/OUT` | → room 72 |

**Reached from:** 72 (NORTH)

**Port `topology.gd` ROOMS[73]:** `{crawl→72, out→72, south→72}`

---

##  74 — YOU'RE IN SECRET E/W CANYON ABOVE TIGHT CANYON

> YOU ARE IN A SECRET CANYON WHICH HERE RUNS E/W. IT CROSSES OVER A VERY TIGHT CANYON 15 FEET BELOW. IF YOU GO DOWN YOU MAY NOT BE ABLE TO GET BACK UP. YOU'RE IN SECRET E/W CANYON ABOVE TIGHT CANYON.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `19` | `EAST` | → room 19 |
| `331120` | `WEST` | if prop(obj #31) ≠ 0: → room 120 |
| `121` | `WEST` | → room 121 |
| `75` | `DOWN` | → room 75 |

**Reached from:** 19 (SECRET), 120 (EAST), 121 (EAST/OUT)

**Port `topology.gd` ROOMS[74]:** `{down→75, east→19, west→121}`

---

##  75 — YOU ARE AT A WIDE PLACE IN A VERY TIGHT N/S CANYON

> YOU ARE AT A WIDE PLACE IN A VERY TIGHT N/S CANYON.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `76` | `SOUTH` | → room 76 |
| `77` | `NORTH` | → room 77 |

**Reached from:** 74 (DOWN), 76 (NORTH), 77 (EAST)

**Port `topology.gd` ROOMS[75]:** `{north→77, south→76}`

---

##  76 — THE CANYON HERE BECOMES TOO TIGHT TO GO FURTHER SOUTH

> THE CANYON HERE BECOMES TOO TIGHT TO GO FURTHER SOUTH.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `75` | `NORTH` | → room 75 |

**Reached from:** 75 (SOUTH)

**Port `topology.gd` ROOMS[76]:** `{north→75}`

---

##  77 — YOU ARE IN A TALL E/W CANYON.  A LOW TIGHT CRAWL GOES 3 FEET NORTH AND

> YOU ARE IN A TALL E/W CANYON. A LOW TIGHT CRAWL GOES 3 FEET NORTH AND SEEMS TO OPEN UP.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `75` | `EAST` | → room 75 |
| `78` | `WEST` | → room 78 |
| `66` | `NORTH/CRAWL` | → room 66 |

**Reached from:** 66 (CANYON), 75 (NORTH), 78 (SOUTH)

**Port `topology.gd` ROOMS[77]:** `{crawl→66, east→75, north→66, west→78}`

---

##  78 — THE CANYON RUNS INTO A MASS OF BOULDERS -- DEAD END

> THE CANYON RUNS INTO A MASS OF BOULDERS -- DEAD END.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `77` | `SOUTH` | → room 77 |

**Reached from:** 77 (WEST)

**Port `topology.gd` ROOMS[78]:** `{south→77}`

---

##  79 — THE STREAM FLOWS OUT THROUGH A PAIR OF 1 FOOT DIAMETER SEWER PIPES

> THE STREAM FLOWS OUT THROUGH A PAIR OF 1 FOOT DIAMETER SEWER PIPES. IT WOULD BE ADVISABLE TO USE THE EXIT.

**Forced motion (cond=2):** any verb routes to room 3. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 3.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `3` | `ROAD/HILL` | → room 3 |

**Reached from:** 3 (DOWNSTREAM/STREAM)

**Port `topology.gd` ROOMS[79]:** `{back→3, out→3, up→3}`

---

##  80 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `42` | `NORTH` | → room 42 |
| `80` | `WEST` | → room 80 |
| `80` | `SOUTH` | → room 80 |
| `81` | `EAST` | → room 81 |

**Reached from:** 42 (WEST), 80 (WEST), 80 (SOUTH), 81 (WEST/OUT)

**Port `topology.gd` ROOMS[80]:** `{east→81, north→42, south→80, west→80}`

---

##  81 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `80` | `WEST/OUT` | → room 80 |

**Reached from:** 80 (EAST)

**Port `topology.gd` ROOMS[81]:** `{out→80, west→80}`

---

##  82 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `44` | `SOUTH/OUT` | → room 44 |

**Reached from:** 44 (NORTH)

**Port `topology.gd` ROOMS[82]:** `{out→44, south→44}`

---

##  83 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `57` | `SOUTH` | → room 57 |
| `84` | `EAST` | → room 84 |
| `85` | `WEST` | → room 85 |

**Reached from:** 57 (NORTH), 84 (WEST), 85 (EAST/OUT)

**Port `topology.gd` ROOMS[83]:** `{east→84, south→57, west→85}`

---

##  84 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `57` | `NORTH` | → room 57 |
| `83` | `WEST` | → room 83 |
| `114` | `NW` | → room 114 |

**Reached from:** 57 (EAST), 83 (EAST), 114 (SE)

**Port `topology.gd` ROOMS[84]:** `{north→57, nw→114, west→83}`

---

##  85 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `83` | `EAST/OUT` | → room 83 |

**Reached from:** 83 (WEST)

**Port `topology.gd` ROOMS[85]:** `{east→83, out→83}`

---

##  86 — DEAD END

> DEAD END

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `52` | `UP/OUT` | → room 52 |

**Reached from:** 52 (DOWN)

**Port `topology.gd` ROOMS[86]:** `{out→52, up→52}`

---

##  87 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL ALIKE.

**Properties (section 9):** dark (requires lamp); hint flags: lost in maze

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `45` | `UP/DOWN` | → room 45 |

**Reached from:** 45 (UP/DOWN)

**Port `topology.gd` ROOMS[87]:** `{down→45, up→45}`

---

##  88 — YOU'RE IN NARROW CORRIDOR

> YOU ARE IN A LONG, NARROW CORRIDOR STRETCHING OUT OF SIGHT TO THE WEST. AT THE EASTERN END IS A HOLE THROUGH WHICH YOU CAN SEE A PROFUSION OF LEAVES. YOU'RE IN NARROW CORRIDOR.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `25` | `DOWN/CLIMB/EAST` | → room 25 |
| `20` | `JUMP` | → room 20 |
| `92` | `WEST/GIANT` | → room 92 |

**Reached from:** 26 (ROAD/HILL), 92 (SOUTH)

**Port `topology.gd` ROOMS[88]:** `{climb→25, down→25, east→25, giant→92, jump→20, west→92}`

---

##  89 — THERE IS NOTHING HERE TO CLIMB.  USE "UP" OR "OUT" TO LEAVE THE PIT

> THERE IS NOTHING HERE TO CLIMB. USE "UP" OR "OUT" TO LEAVE THE PIT.

**Forced motion (cond=2):** any verb routes to room 25. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 25.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `25` | `ROAD/HILL` | → room 25 |

**Port `topology.gd` ROOMS[89]:** `{back→25, out→25, up→25}`

---

##  90 — YOU HAVE CLIMBED UP THE PLANT AND OUT OF THE PIT

> YOU HAVE CLIMBED UP THE PLANT AND OUT OF THE PIT.

**Forced motion (cond=2):** any verb routes to room 23. The engine prints this room's 
long description as a one-time transition message 
then auto-walks the player to 23.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `23` | `ROAD/HILL` | → room 23 |

**Reached from:** 31 (ROAD/HILL)

**Port `topology.gd` ROOMS[90]:** `{back→23, out→23, up→23}`

---

##  91 — YOU'RE AT STEEP INCLINE ABOVE LARGE ROOM

> YOU ARE AT THE TOP OF A STEEP INCLINE ABOVE A LARGE ROOM. YOU COULD CLIMB DOWN HERE, BUT YOU WOULD NOT BE ABLE TO CLIMB UP. THERE IS A PASSAGE LEADING BACK TO THE NORTH. YOU'RE AT STEEP INCLINE ABOVE LARGE ROOM.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `95` | `NORTH/CAVERN/PASSAGE` | → room 95 |
| `72` | `DOWN/CLIMB` | → room 72 |

**Reached from:** 95 (WEST)

**Port `topology.gd` ROOMS[91]:** `{cavern→95, climb→72, down→72, north→95, passage→95}`

---

##  92 — YOU'RE IN GIANT ROOM

> YOU ARE IN THE GIANT ROOM. THE CEILING HERE IS TOO HIGH UP FOR YOUR LAMP TO SHOW IT. CAVERNOUS PASSAGES LEAD EAST, NORTH, AND SOUTH. ON THE WEST WALL IS SCRAWLED THE INSCRIPTION, "FEE FIE FOE FOO" [SIC]. YOU'RE IN GIANT ROOM.

**Objects/NPCs placed here (section 7):** 56=EGGS

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `88` | `SOUTH` | → room 88 |
| `93` | `EAST` | → room 93 |
| `94` | `NORTH` | → room 94 |

**Reached from:** 88 (WEST/GIANT), 93 (SOUTH/GIANT/OUT), 94 (SOUTH/GIANT/PASSAGE), 95 (GIANT)

**Port `topology.gd` ROOMS[92]:** `{east→93, north→94, south→88}`

---

##  93 — THE PASSAGE HERE IS BLOCKED BY A RECENT CAVE-IN

> THE PASSAGE HERE IS BLOCKED BY A RECENT CAVE-IN.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `92` | `SOUTH/GIANT/OUT` | → room 92 |

**Reached from:** 92 (EAST)

**Port `topology.gd` ROOMS[93]:** `{giant→92, out→92, south→92}`

---

##  94 — YOU ARE AT ONE END OF AN IMMENSE NORTH/SOUTH PASSAGE

> YOU ARE AT ONE END OF AN IMMENSE NORTH/SOUTH PASSAGE.

**Objects/NPCs placed here (section 7):** 9=DOOR

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `92` | `SOUTH/GIANT/PASSAGE` | → room 92 |
| `309095` | `NORTH/ENTER/CAVERN` | if prop(obj #9) ≠ 0: → room 95 |
| `611` | `NORTH` | print msg #111<br><small>↳ *"THE DOOR IS EXTREMELY RUSTY AND REFUSES TO OPEN."*</small> |

**Reached from:** 92 (NORTH), 95 (SOUTH/OUT)

**Port `topology.gd` ROOMS[94]:** `{cavern→95, enter→95, giant→92, north→95, passage→92, south→92}`

**Port GATES[94]:** north/rusty, enter/rusty, cavern/rusty

---

##  95 — YOU'RE IN CAVERN WITH WATERFALL

> YOU ARE IN A MAGNIFICENT CAVERN WITH A RUSHING STREAM, WHICH CASCADES OVER A SPARKLING WATERFALL INTO A ROARING WHIRLPOOL WHICH DISAPPEARS THROUGH A HOLE IN THE FLOOR. PASSAGES EXIT TO THE SOUTH AND WEST. YOU'RE IN CAVERN WITH WATERFALL.

**Properties (section 9):** dark (requires lamp); **water source** (FILL BOTTLE here yields water)

**Objects/NPCs placed here (section 7):** 57=TRIDE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `94` | `SOUTH/OUT` | → room 94 |
| `92` | `GIANT` | → room 92 |
| `91` | `WEST` | → room 91 |

**Reached from:** 91 (NORTH/CAVERN/PASSAGE)

**Port `topology.gd` ROOMS[95]:** `{giant→92, out→94, south→94, west→91}`

---

##  96 — YOU'RE IN SOFT ROOM

> YOU ARE IN THE SOFT ROOM. THE WALLS ARE COVERED WITH HEAVY CURTAINS, THE FLOOR WITH A THICK PILE CARPET. MOSS COVERS THE CEILING. YOU'RE IN SOFT ROOM.

**Objects/NPCs placed here (section 7):** 10=PILLO, 40=CARPE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `66` | `WEST/OUT` | → room 66 |

**Reached from:** 66 (EAST)

**Port `topology.gd` ROOMS[96]:** `{out→66, west→66}`

---

##  97 — YOU'RE IN ORIENTAL ROOM

> THIS IS THE ORIENTAL ROOM. ANCIENT ORIENTAL CAVE DRAWINGS COVER THE WALLS. A GENTLY SLOPING PASSAGE LEADS UPWARD TO THE NORTH, ANOTHER PASSAGE LEADS SE, AND A HANDS AND KNEES CRAWL LEADS WEST. YOU'RE IN ORIENTAL ROOM.

**Objects/NPCs placed here (section 7):** 29=DRAWI, 58=VASE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `66` | `SE` | → room 66 |
| `72` | `WEST/CRAWL` | → room 72 |
| `98` | `UP/NORTH/CAVERN` | → room 98 |

**Reached from:** 66 (ORIENTAL), 72 (SE/ORIENTAL), 98 (SOUTH/ORIENTAL)

**Port `topology.gd` ROOMS[97]:** `{cavern→98, crawl→72, north→98, se→66, up→98, west→72}`

---

##  98 — YOU'RE IN MISTY CAVERN

> YOU ARE FOLLOWING A WIDE PATH AROUND THE OUTER EDGE OF A LARGE CAVERN. FAR BELOW, THROUGH A HEAVY WHITE MIST, STRANGE SPLASHING NOISES CAN BE HEARD. THE MIST RISES UP THROUGH A FISSURE IN THE CEILING. THE PATH EXITS TO THE SOUTH AND WEST. YOU'RE IN MISTY CAVERN.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `97` | `SOUTH/ORIENTAL` | → room 97 |
| `99` | `WEST` | → room 99 |

**Reached from:** 97 (UP/NORTH/CAVERN), 99 (NW/CAVERN)

**Port `topology.gd` ROOMS[98]:** `{oriental→97, south→97, west→99}`

---

##  99 — YOU'RE IN ALCOVE

> YOU ARE IN AN ALCOVE. A SMALL NW PATH SEEMS TO WIDEN AFTER A SHORT DISTANCE. AN EXTREMELY TIGHT TUNNEL LEADS EAST. IT LOOKS LIKE A VERY TIGHT SQUEEZE. AN EERIE LIGHT CAN BE SEEN AT THE OTHER END. YOU'RE IN ALCOVE.

**Properties (section 9):** dark (requires lamp); hint flags: pondering dark room

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `98` | `NW/CAVERN` | → room 98 |
| `301` | `EAST/PASSAGE` | special routine 1 (Plover-alcove squeeze (only carry emerald or empty)) |
| `100` | `EAST` | → room 100 |

**Reached from:** 98 (WEST), 100 (WEST)

**Port `topology.gd` ROOMS[99]:** `{cavern→98, east→100, nw→98}`

**Port GATES[99]:** passage/always, east/plover_squeeze

---

## 100 — YOU'RE IN PLOVER ROOM

> YOU'RE IN A SMALL CHAMBER LIT BY AN EERIE GREEN LIGHT. AN EXTREMELY NARROW TUNNEL EXITS TO THE WEST. A DARK CORRIDOR LEADS NE. YOU'RE IN PLOVER ROOM.

**Properties (section 9):** **lit** (sunlit / always lit); hint flags: pondering dark room

**Objects/NPCs placed here (section 7):** 59=EMERA

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `301` | `WEST/PASSAGE/OUT` | special routine 1 (Plover-alcove squeeze (only carry emerald or empty)) |
| `99` | `WEST` | → room 99 |
| `159302` | `PLUGH` | if carrying obj #59: special routine 2 (Plover transport (drop emerald, use passage)) |
| `33` | `PLUGH` | → room 33 |
| `101` | `NE/DARK` | → room 101 |

**Reached from:** 33 (PLUGH), 99 (EAST), 101 (SOUTH/PLUGH/OUT)

**Port `topology.gd` ROOMS[100]:** `{dark→101, ne→101, plover→33, west→99}`

**Port GATES[100]:** passage/always, out/always, west/plover_squeeze

---

## 101 — YOU'RE IN DARK-ROOM

> YOU'RE IN THE DARK-ROOM. A CORRIDOR LEADING SOUTH IS THE ONLY EXIT. YOU'RE IN DARK-ROOM.

**Properties (section 9):** dark (requires lamp); hint flags: pondering dark room

**Objects/NPCs placed here (section 7):** 13=TABLE, 60=PLATI

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `100` | `SOUTH/PLUGH/OUT` | → room 100 |

**Reached from:** 100 (NE/DARK)

**Port `topology.gd` ROOMS[101]:** `{out→100, south→100}`

---

## 102 — YOU'RE IN ARCHED HALL

> YOU ARE IN AN ARCHED HALL. A CORAL PASSAGE ONCE CONTINUED UP AND EAST FROM HERE, BUT IS NOW BLOCKED BY DEBRIS. THE AIR SMELLS OF SEA WATER. YOU'RE IN ARCHED HALL.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `103` | `DOWN/SHELL/OUT` | → room 103 |

**Reached from:** 103 (UP/HALL)

**Port `topology.gd` ROOMS[102]:** `{down→103, out→103, shell→103}`

---

## 103 — YOU'RE IN SHELL ROOM

> YOU'RE IN A LARGE ROOM CARVED OUT OF SEDIMENTARY ROCK. THE FLOOR AND WALLS ARE LITTERED WITH BITS OF SHELLS IMBEDDED IN THE STONE. A SHALLOW PASSAGE PROCEEDS DOWNWARD, AND A SOMEWHAT STEEPER ONE LEADS UP. A LOW HANDS AND KNEES PASSAGE ENTERS FROM THE SOUTH. YOU'RE IN SHELL ROOM.

**Objects/NPCs placed here (section 7):** 14=CLAM

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `102` | `UP/HALL` | → room 102 |
| `104` | `DOWN` | → room 104 |
| `114618` | `SOUTH` | if carrying obj #14: print msg #118<br><small>↳ *"YOU CAN'T FIT THIS FIVE-FOOT CLAM THROUGH THAT LITTLE PASSAGE!"*</small> |
| `115619` | `SOUTH` | if carrying obj #15: print msg #119<br><small>↳ *"YOU CAN'T FIT THIS FIVE-FOOT OYSTER THROUGH THAT LITTLE PASSAGE!"*</small> |
| `64` | `SOUTH` | → room 64 |

**Reached from:** 64 (NORTH/SHELL), 102 (DOWN/SHELL/OUT), 104 (UP/SHELL), 105 (SHELL)

**Port `topology.gd` ROOMS[103]:** `{down→104, hall→102, south→64, up→102}`

---

## 104 — YOU ARE IN A LONG SLOPING CORRIDOR WITH RAGGED SHARP WALLS

> YOU ARE IN A LONG SLOPING CORRIDOR WITH RAGGED SHARP WALLS.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `103` | `UP/SHELL` | → room 103 |
| `105` | `DOWN` | → room 105 |

**Reached from:** 103 (DOWN), 105 (UP/OUT)

**Port `topology.gd` ROOMS[104]:** `{down→105, shell→103, up→103}`

---

## 105 — YOU ARE IN A CUL-DE-SAC ABOUT EIGHT FEET ACROSS

> YOU ARE IN A CUL-DE-SAC ABOUT EIGHT FEET ACROSS.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `104` | `UP/OUT` | → room 104 |
| `103` | `SHELL` | → room 103 |

**Reached from:** 104 (DOWN)

**Port `topology.gd` ROOMS[105]:** `{out→104, shell→103, up→104}`

---

## 106 — YOU'RE IN ANTEROOM

> YOU ARE IN AN ANTEROOM LEADING TO A LARGE PASSAGE TO THE EAST. SMALL PASSAGES GO WEST AND UP. THE REMNANTS OF RECENT DIGGING ARE EVIDENT. A SIGN IN MIDAIR HERE SAYS "CAVE UNDER CONSTRUCTION BEYOND THIS POINT. PROCEED AT OWN RISK. [WITT CONSTRUCTION COMPANY]" YOU'RE IN ANTEROOM.

**Objects/NPCs placed here (section 7):** 16=MAGAZ

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `64` | `UP` | → room 64 |
| `65` | `WEST` | → room 65 |
| `108` | `EAST` | → room 108 |

**Reached from:** 64 (EAST), 65 (DOWN), 108 (EAST)

**Port `topology.gd` ROOMS[106]:** `{east→108, up→64, west→65}`

---

## 107 — YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL DIFFERENT

> YOU ARE IN A MAZE OF TWISTY LITTLE PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `131` | `SOUTH` | → room 131 |
| `132` | `SW` | → room 132 |
| `133` | `NE` | → room 133 |
| `134` | `SE` | → room 134 |
| `135` | `UP` | → room 135 |
| `136` | `NW` | → room 136 |
| `137` | `EAST` | → room 137 |
| `138` | `WEST` | → room 138 |
| `139` | `NORTH` | → room 139 |
| `61` | `DOWN` | → room 61 |

**Reached from:** 131 (WEST), 132 (NW), 133 (UP), 134 (NE), 135 (NORTH), 136 (EAST), 137 (SE), 138 (DOWN) + 1 more

**Port `topology.gd` ROOMS[107]:** `{down→61, east→137, ne→133, north→139, nw→136, se→134, south→131, sw→132, up→135, west→138}`

---

## 108 — YOU'RE AT WITT'S END

> YOU ARE AT WITT'S END. PASSAGES LEAD OFF IN *ALL* DIRECTIONS. YOU'RE AT WITT'S END.

**Properties (section 9):** dark (requires lamp); hint flags: at Witt's End

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `95556` | `EAST/NORTH/SOUTH/NE/SE/SW/NW/UP/DOWN` | if 95% probability: print msg #56<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND WOUND UP BACK IN THE MAIN PASSAGE."*</small> |
| `106` | `EAST` | → room 106 |
| `626` | `WEST` | print msg #126<br><small>↳ *"YOU HAVE CRAWLED AROUND IN SOME LITTLE HOLES AND FOUND YOUR WAY BLOCKED BY A RECENT CAVE-IN.  YOU ARE NOW BACK IN THE MAIN PASSAGE."*</small> |

**Reached from:** 106 (EAST)

**Port `topology.gd` ROOMS[108]:** `{east→106}`

**Port GATES[108]:** east/probability, north/probability, south/probability, ne/probability, se/probability, sw/probability, nw/probability, up/probability, down/probability, west/always

---

## 109 — YOU'RE IN MIRROR CANYON

> YOU ARE IN A NORTH/SOUTH CANYON ABOUT 25 FEET ACROSS. THE FLOOR IS COVERED BY WHITE MIST SEEPING IN FROM THE NORTH. THE WALLS EXTEND UPWARD FOR WELL OVER 100 FEET. SUSPENDED FROM SOME UNSEEN POINT FAR ABOVE YOU, AN ENORMOUS TWO-SIDED MIRROR IS HANGING PARALLEL TO AND MIDWAY BETWEEN THE CANYON WALLS. (THE MIRROR IS OBVIOUSLY PROVIDED FOR THE USE OF THE DWARVES, WHO AS YOU KNOW, ARE EXTREMELY VAIN.) A SMALL WINDOW CAN BE SEEN IN EITHER WALL, SOME FIFTY FEET UP. YOU'RE IN MIRROR CANYON.

**Objects/NPCs placed here (section 7):** 23=MIRRO

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `69` | `SOUTH` | → room 69 |
| `113` | `NORTH/RESERVOIR` | → room 113 |

**Reached from:** 69 (NORTH), 113 (SOUTH/OUT/v109)

**Port `topology.gd` ROOMS[109]:** `{north→113, reservoir→113, south→69}`

---

## 110 — YOU'RE AT WINDOW ON PIT

> YOU'RE AT A LOW WINDOW OVERLOOKING A HUGE PIT, WHICH EXTENDS UP OUT OF SIGHT. A FLOOR IS INDISTINCTLY VISIBLE OVER 50 FEET BELOW. TRACES OF WHITE MIST COVER THE FLOOR OF THE PIT, BECOMING THICKER TO THE LEFT. MARKS IN THE DUST AROUND THE WINDOW WOULD SEEM TO INDICATE THAT SOMEONE HAS BEEN HERE RECENTLY. DIRECTLY ACROSS THE PIT FROM YOU AND 25 FEET AWAY THERE IS A SIMILAR WINDOW LOOKING INTO A LIGHTED ROOM. A SHADOWY FIGURE CAN BE SEEN THERE PEERING BACK AT YOU. YOU'RE AT WINDOW ON PIT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `71` | `WEST` | → room 71 |
| `20` | `JUMP` | → room 20 |

**Reached from:** 71 (NORTH)

**Port `topology.gd` ROOMS[110]:** `{jump→20, west→71}`

---

## 111 — YOU'RE AT TOP OF STALACTITE

> A LARGE STALACTITE EXTENDS FROM THE ROOF AND ALMOST REACHES THE FLOOR BELOW. YOU COULD CLIMB DOWN IT, AND JUMP FROM IT TO THE FLOOR, BUT HAVING DONE SO YOU WOULD BE UNABLE TO REACH IT TO CLIMB BACK UP. YOU'RE AT TOP OF STALACTITE.

**Objects/NPCs placed here (section 7):** 26=STALA

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `70` | `NORTH` | → room 70 |
| `40050` | `DOWN/JUMP/CLIMB` | if 40% probability: → room 50 |
| `50053` | `DOWN` | if 50% probability: → room 53 |
| `45` | `DOWN` | → room 45 |

**Reached from:** 70 (SOUTH)

**Port `topology.gd` ROOMS[111]:** `{down→45, north→70}`

---

## 112 — YOU ARE IN A LITTLE MAZE OF TWISTING PASSAGES, ALL DIFFERENT

> YOU ARE IN A LITTLE MAZE OF TWISTING PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `131` | `SW` | → room 131 |
| `132` | `NORTH` | → room 132 |
| `133` | `EAST` | → room 133 |
| `134` | `NW` | → room 134 |
| `135` | `SE` | → room 135 |
| `136` | `NE` | → room 136 |
| `137` | `WEST` | → room 137 |
| `138` | `DOWN` | → room 138 |
| `139` | `UP` | → room 139 |
| `140` | `SOUTH` | → room 140 |

**Reached from:** 131 (EAST), 132 (SE), 133 (SOUTH), 134 (SW), 135 (UP), 136 (NORTH), 137 (WEST), 138 (NW) + 2 more

**Port `topology.gd` ROOMS[112]:** `{down→138, east→133, ne→136, north→132, nw→134, se→135, south→140, sw→131, up→139, west→137}`

---

## 113 — YOU'RE AT RESERVOIR

> YOU ARE AT THE EDGE OF A LARGE UNDERGROUND RESERVOIR. AN OPAQUE CLOUD OF WHITE MIST FILLS THE ROOM AND RISES RAPIDLY UPWARD. THE LAKE IS FED BY A STREAM, WHICH TUMBLES OUT OF A HOLE IN THE WALL ABOUT 10 FEET OVERHEAD AND SPLASHES NOISILY INTO THE WATER SOMEWHERE WITHIN THE MIST. THE ONLY PASSAGE GOES BACK TOWARD THE SOUTH. YOU'RE AT RESERVOIR.

**Properties (section 9):** dark (requires lamp); **water source** (FILL BOTTLE here yields water)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `109` | `SOUTH/OUT/v109` | → room 109 |

**Reached from:** 69 (RESERVOIR), 109 (NORTH/RESERVOIR)

**Port `topology.gd` ROOMS[113]:** `{out→109, reservoir→109, south→109}`

---

## 114 — DEAD END

> DEAD END

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `84` | `SE` | → room 84 |

**Reached from:** 84 (NW)

**Port `topology.gd` ROOMS[114]:** `{out→84, se→84}`

---

## 115 — YOU'RE AT NE END

> YOU ARE AT THE NORTHEAST END OF AN IMMENSE ROOM, EVEN LARGER THAN THE GIANT ROOM. IT APPEARS TO BE A REPOSITORY FOR THE "ADVENTURE" PROGRAM. MASSIVE TORCHES FAR OVERHEAD BATHE THE ROOM WITH SMOKY YELLOW LIGHT. SCATTERED ABOUT YOU CAN BE SEEN A PILE OF BOTTLES (ALL OF THEM EMPTY), A NURSERY OF YOUNG BEANSTALKS MURMURING QUIETLY, A BED OF OYSTERS, A BUNDLE OF BLACK RODS WITH RUSTY STARS ON THEIR ENDS, AND A COLLECTION OF BRASS LANTERNS. OFF TO ONE SIDE A GREAT MANY DWARVES ARE SLEEPING ON THE FLOOR, SNORING LOUDLY. A SIGN NEARBY READS: "DO NOT DISTURB THE DWARVES!" AN IMMENSE MIRROR IS HANGING AGAINST ONE WALL, AND STRETCHES TO THE OTHER END OF THE ROOM, WHERE VARIOUS OTHER SUNDRY OBJECTS CAN BE GLIMPSED DIMLY IN THE DISTANCE. YOU'RE AT NE END.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `116` | `SW` | → room 116 |

**Reached from:** 116 (NE)

**Port `topology.gd` ROOMS[115]:** `{east→116, sw→116}`

---

## 116 — YOU'RE AT SW END

> YOU ARE AT THE SOUTHWEST END OF THE REPOSITORY. TO ONE SIDE IS A PIT FULL OF FIERCE GREEN SNAKES. ON THE OTHER SIDE IS A ROW OF SMALL WICKER CAGES, EACH OF WHICH CONTAINS A LITTLE SULKING BIRD. IN ONE CORNER IS A BUNDLE OF BLACK RODS WITH RUSTY MARKS ON THEIR ENDS. A LARGE NUMBER OF VELVET PILLOWS ARE SCATTERED ABOUT ON THE FLOOR. A VAST MIRROR STRETCHES OFF TO THE NORTHEAST. AT YOUR FEET IS A LARGE STEEL GRATE, NEXT TO WHICH IS A SIGN WHICH READS, "TREASURE VAULT. KEYS IN MAIN OFFICE." YOU'RE AT SW END.

**Properties (section 9):** **lit** (sunlit / always lit)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `115` | `NE` | → room 115 |
| `593` | `DOWN` | print msg #93<br><small>↳ *"YOU CAN'T GO THROUGH A LOCKED STEEL GRATE!"*</small> |

**Reached from:** 115 (SW)

**Port `topology.gd` ROOMS[116]:** `{ne→115, west→115}`

**Port GATES[116]:** down/always

---

## 117 — YOU'RE ON SW SIDE OF CHASM

> YOU ARE ON ONE SIDE OF A LARGE, DEEP CHASM. A HEAVY WHITE MIST RISING UP FROM BELOW OBSCURES ALL VIEW OF THE FAR SIDE. A SW PATH LEADS AWAY FROM THE CHASM INTO A WINDING CORRIDOR. YOU'RE ON SW SIDE OF CHASM.

**Objects/NPCs placed here (section 7):** 32=CHASM, 33=TROLL

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `118` | `SW` | → room 118 |
| `233660` | `OVER/ACROSS/CROSS/NE` | if carrying or co-located with obj #33: print msg #160<br><small>↳ *"THE TROLL REFUSES TO LET YOU CROSS."*</small> |
| `332661` | `OVER` | if prop(obj #32) ≠ 0: print msg #161<br><small>↳ *"THERE IS NO LONGER ANY WAY ACROSS THE CHASM."*</small> |
| `303` | `OVER` | special routine 3 (Troll-bridge cross) |
| `332021` | `JUMP` | if prop(obj #32) ≠ 0: → room 21 |
| `596` | `JUMP` | print msg #96<br><small>↳ *"I RESPECTFULLY SUGGEST YOU GO ACROSS THE BRIDGE INSTEAD OF JUMPING."*</small> |

**Reached from:** 118 (UP)

**Port `topology.gd` ROOMS[117]:** `{across→122, cross→122, ne→122, over→122, sw→118}`

**Port GATES[117]:** over/troll, across/troll, cross/troll, ne/troll, jump/always

---

## 118 — YOU'RE IN SLOPING CORRIDOR

> YOU ARE IN A LONG WINDING CORRIDOR SLOPING OUT OF SIGHT IN BOTH DIRECTIONS. YOU'RE IN SLOPING CORRIDOR.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `72` | `DOWN` | → room 72 |
| `117` | `UP` | → room 117 |

**Reached from:** 72 (SW), 117 (SW)

**Port `topology.gd` ROOMS[118]:** `{down→72, up→117}`

---

## 119 — YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST

> YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST.

**Objects/NPCs placed here (section 7):** 31=DRAGO, 62=RUG

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `69` | `NORTH/OUT` | → room 69 |
| `653` | `EAST/FORWARD` | print msg #153<br><small>↳ *"THE DRAGON LOOKS RATHER NASTY.	YOU'D BEST NOT TRY TO GET BY."*</small> |

**Reached from:** 69 (SOUTH)

**Port `topology.gd` ROOMS[119]:** `{north→69, out→69}`

**Port GATES[119]:** east/always, forward/always

---

## 120 — YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST

> YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `69` | `NORTH` | → room 69 |
| `74` | `EAST` | → room 74 |

**Port `topology.gd` ROOMS[120]:** `{east→74, north→69}`

---

## 121 — YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST

> YOU ARE IN A SECRET CANYON WHICH EXITS TO THE NORTH AND EAST.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `74` | `EAST/OUT` | → room 74 |
| `653` | `NORTH/FORWARD` | print msg #153<br><small>↳ *"THE DRAGON LOOKS RATHER NASTY.	YOU'D BEST NOT TRY TO GET BY."*</small> |

**Reached from:** 74 (WEST)

**Port `topology.gd` ROOMS[121]:** `{east→74, out→74}`

**Port GATES[121]:** north/always, forward/always

---

## 122 — YOU'RE ON NE SIDE OF CHASM

> YOU ARE ON THE FAR SIDE OF THE CHASM. A NE PATH LEADS AWAY FROM THE CHASM ON THIS SIDE. YOU'RE ON NE SIDE OF CHASM.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `123` | `NE` | → room 123 |
| `233660` | `OVER/ACROSS/CROSS/SW` | if carrying or co-located with obj #33: print msg #160<br><small>↳ *"THE TROLL REFUSES TO LET YOU CROSS."*</small> |
| `303` | `OVER` | special routine 3 (Troll-bridge cross) |
| `596` | `JUMP` | print msg #96<br><small>↳ *"I RESPECTFULLY SUGGEST YOU GO ACROSS THE BRIDGE INSTEAD OF JUMPING."*</small> |
| `124` | `FORK` | → room 124 |
| `126` | `VIEW` | → room 126 |
| `129` | `BARREN` | → room 129 |

**Reached from:** 123 (WEST)

**Port `topology.gd` ROOMS[122]:** `{across→117, barren→129, cross→117, fork→124, ne→123, over→117, sw→117, view→126}`

**Port GATES[122]:** over/troll, across/troll, cross/troll, sw/troll, jump/always

---

## 123 — YOU'RE IN CORRIDOR

> YOU'RE IN A LONG EAST/WEST CORRIDOR. A FAINT RUMBLING NOISE CAN BE HEARD IN THE DISTANCE. YOU'RE IN CORRIDOR.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `122` | `WEST` | → room 122 |
| `124` | `EAST/FORK` | → room 124 |
| `126` | `VIEW` | → room 126 |
| `129` | `BARREN` | → room 129 |

**Reached from:** 122 (NE), 124 (WEST)

**Port `topology.gd` ROOMS[123]:** `{barren→129, east→124, fork→124, view→126, west→122}`

---

## 124 — YOU'RE AT FORK IN PATH

> THE PATH FORKS HERE. THE LEFT FORK LEADS NORTHEAST. A DULL RUMBLING SEEMS TO GET LOUDER IN THAT DIRECTION. THE RIGHT FORK LEADS SOUTHEAST DOWN A GENTLE SLOPE. THE MAIN CORRIDOR ENTERS FROM THE WEST. YOU'RE AT FORK IN PATH.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `123` | `WEST` | → room 123 |
| `125` | `NE/LEFT` | → room 125 |
| `128` | `SE/RIGHT/DOWN` | → room 128 |
| `126` | `VIEW` | → room 126 |
| `129` | `BARREN` | → room 129 |

**Reached from:** 122 (FORK), 123 (EAST/FORK), 125 (SOUTH/FORK), 126 (FORK), 127 (FORK), 128 (NORTH/UP/FORK), 129 (FORK), 130 (FORK)

**Port `topology.gd` ROOMS[124]:** `{barren→129, down→128, left→125, ne→125, right→128, se→128, view→126, west→123}`

---

## 125 — YOU'RE AT JUNCTION WITH WARM WALLS

> THE WALLS ARE QUITE WARM HERE. FROM THE NORTH CAN BE HEARD A STEADY ROAR, SO LOUD THAT THE ENTIRE CAVE SEEMS TO BE TREMBLING. ANOTHER PASSAGE LEADS SOUTH, AND A LOW CRAWL GOES EAST. YOU'RE AT JUNCTION WITH WARM WALLS.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `124` | `SOUTH/FORK` | → room 124 |
| `126` | `NORTH/VIEW` | → room 126 |
| `127` | `EAST/CRAWL` | → room 127 |

**Reached from:** 124 (NE/LEFT), 126 (SOUTH/PASSAGE/OUT), 127 (WEST/OUT/CRAWL)

**Port `topology.gd` ROOMS[125]:** `{crawl→127, east→127, fork→124, north→126, south→124, view→126}`

---

## 126 — YOU'RE AT BREATH-TAKING VIEW

> YOU ARE ON THE EDGE OF A BREATH-TAKING VIEW. FAR BELOW YOU IS AN ACTIVE VOLCANO, FROM WHICH GREAT GOUTS OF MOLTEN LAVA COME SURGING OUT, CASCADING BACK DOWN INTO THE DEPTHS. THE GLOWING ROCK FILLS THE FARTHEST REACHES OF THE CAVERN WITH A BLOOD-RED GLARE, GIVING EVERY- THING AN EERIE, MACABRE APPEARANCE. THE AIR IS FILLED WITH FLICKERING SPARKS OF ASH AND A HEAVY SMELL OF BRIMSTONE. THE WALLS ARE HOT TO THE TOUCH, AND THE THUNDERING OF THE VOLCANO DROWNS OUT ALL OTHER SOUNDS. EMBEDDED IN THE JAGGED ROOF FAR OVERHEAD ARE MYRIAD TWISTED FORMATIONS COMPOSED OF PURE WHITE ALABASTER, WHICH SCATTER THE MURKY LIGHT INTO SINISTER APPARITIONS UPON THE WALLS. TO ONE SIDE IS A DEEP GORGE, FILLED WITH A BIZARRE CHAOS OF TORTURED ROCK WHICH SEEMS TO HAVE BEEN CRAFTED BY THE DEVIL HIMSELF. AN IMMENSE RIVER OF FIRE CRASHES OUT FROM THE DEPTHS OF THE VOLCANO, BURNS ITS WAY THROUGH THE GORGE, AND PLUMMETS INTO A BOTTOMLESS PIT FAR OFF TO YOUR LEFT. TO THE RIGHT, AN IMMENSE GEYSER OF BLISTERING STEAM ERUPTS CONTINUOUSLY FROM A BARREN ISLAND IN THE CENTER OF A SULFUROUS LAKE, WHICH BUBBLES OMINOUSLY. THE FAR RIGHT WALL IS AFLAME WITH AN INCANDESCENCE OF ITS OWN, WHICH LENDS AN ADDITIONAL INFERNAL SPLENDOR TO THE ALREADY HELLISH SCENE. A DARK, FOREBODING PASSAGE EXITS TO THE SOUTH. YOU'RE AT BREATH-TAKING VIEW.

**Properties (section 9):** **lit** (sunlit / always lit); pirate-forbidden (won't enter unless following the player)

**Objects/NPCs placed here (section 7):** 37=VOLCA

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `125` | `SOUTH/PASSAGE/OUT` | → room 125 |
| `124` | `FORK` | → room 124 |
| `610` | `DOWN/JUMP` | print msg #110<br><small>↳ *"DON'T BE RIDICULOUS!"*</small> |

**Reached from:** 122 (VIEW), 123 (VIEW), 124 (VIEW), 125 (NORTH/VIEW), 127 (VIEW), 128 (VIEW), 129 (VIEW), 130 (VIEW)

**Port `topology.gd` ROOMS[126]:** `{fork→124, out→125, passage→125, south→125}`

**Port GATES[126]:** jump/always, down/always

---

## 127 — YOU'RE IN CHAMBER OF BOULDERS

> YOU ARE IN A SMALL CHAMBER FILLED WITH LARGE BOULDERS. THE WALLS ARE VERY WARM, CAUSING THE AIR IN THE ROOM TO BE ALMOST STIFLING FROM THE HEAT. THE ONLY EXIT IS A CRAWL HEADING WEST, THROUGH WHICH IS COMING A LOW RUMBLING. YOU'RE IN CHAMBER OF BOULDERS.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Objects/NPCs placed here (section 7):** 63=SPICE

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `125` | `WEST/OUT/CRAWL` | → room 125 |
| `124` | `FORK` | → room 124 |
| `126` | `VIEW` | → room 126 |

**Reached from:** 125 (EAST/CRAWL)

**Port `topology.gd` ROOMS[127]:** `{crawl→125, fork→124, out→125, view→126, west→125}`

---

## 128 — YOU'RE IN LIMESTONE PASSAGE

> YOU ARE WALKING ALONG A GENTLY SLOPING NORTH/SOUTH PASSAGE LINED WITH ODDLY SHAPED LIMESTONE FORMATIONS. YOU'RE IN LIMESTONE PASSAGE.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `124` | `NORTH/UP/FORK` | → room 124 |
| `129` | `SOUTH/DOWN/BARREN` | → room 129 |
| `126` | `VIEW` | → room 126 |

**Reached from:** 124 (SE/RIGHT/DOWN), 129 (WEST/UP)

**Port `topology.gd` ROOMS[128]:** `{barren→129, down→129, fork→124, north→124, south→129, up→124, view→126}`

---

## 129 — YOU'RE IN FRONT OF BARREN ROOM

> YOU ARE STANDING AT THE ENTRANCE TO A LARGE, BARREN ROOM. A SIGN POSTED ABOVE THE ENTRANCE READS: "CAUTION! BEAR IN ROOM!" YOU'RE IN FRONT OF BARREN ROOM.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `128` | `WEST/UP` | → room 128 |
| `124` | `FORK` | → room 124 |
| `130` | `EAST/IN/BARREN/ENTER` | → room 130 |
| `126` | `VIEW` | → room 126 |

**Reached from:** 122 (BARREN), 123 (BARREN), 124 (BARREN), 128 (SOUTH/DOWN/BARREN), 130 (WEST/OUT)

**Port `topology.gd` ROOMS[129]:** `{barren→130, east→130, enter→130, fork→124, in→130, up→128, view→126, west→128}`

---

## 130 — YOU'RE IN BARREN ROOM

> YOU ARE INSIDE A BARREN ROOM. THE CENTER OF THE ROOM IS COMPLETELY EMPTY EXCEPT FOR SOME DUST. MARKS IN THE DUST LEAD AWAY TOWARD THE FAR END OF THE ROOM. THE ONLY EXIT IS THE WAY YOU CAME IN. YOU'RE IN BARREN ROOM.

**Properties (section 9):** dark (requires lamp); pirate-forbidden (won't enter unless following the player)

**Objects/NPCs placed here (section 7):** 35=BEAR, 64=CHAIN

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `129` | `WEST/OUT` | → room 129 |
| `124` | `FORK` | → room 124 |
| `126` | `VIEW` | → room 126 |

**Reached from:** 129 (EAST/IN/BARREN/ENTER)

**Port `topology.gd` ROOMS[130]:** `{fork→124, out→129, view→126, west→129}`

---

## 131 — YOU ARE IN A MAZE OF TWISTING LITTLE PASSAGES, ALL DIFFERENT

> YOU ARE IN A MAZE OF TWISTING LITTLE PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `WEST` | → room 107 |
| `132` | `SE` | → room 132 |
| `133` | `NW` | → room 133 |
| `134` | `SW` | → room 134 |
| `135` | `NE` | → room 135 |
| `136` | `UP` | → room 136 |
| `137` | `DOWN` | → room 137 |
| `138` | `NORTH` | → room 138 |
| `139` | `SOUTH` | → room 139 |
| `112` | `EAST` | → room 112 |

**Reached from:** 107 (SOUTH), 112 (SW), 132 (UP), 133 (DOWN), 134 (NORTH), 135 (SE), 136 (WEST), 137 (NE) + 2 more

**Port `topology.gd` ROOMS[131]:** `{down→137, east→112, ne→135, north→138, nw→133, se→132, south→139, sw→134, up→136, west→107}`

---

## 132 — YOU ARE IN A LITTLE MAZE OF TWISTY PASSAGES, ALL DIFFERENT

> YOU ARE IN A LITTLE MAZE OF TWISTY PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `NW` | → room 107 |
| `131` | `UP` | → room 131 |
| `133` | `NORTH` | → room 133 |
| `134` | `SOUTH` | → room 134 |
| `135` | `WEST` | → room 135 |
| `136` | `SW` | → room 136 |
| `137` | `NE` | → room 137 |
| `138` | `EAST` | → room 138 |
| `139` | `DOWN` | → room 139 |
| `112` | `SE` | → room 112 |

**Reached from:** 107 (SW), 112 (NORTH), 131 (SE), 133 (WEST), 134 (NW), 135 (DOWN), 136 (UP), 137 (SOUTH) + 2 more

**Port `topology.gd` ROOMS[132]:** `{down→139, east→138, ne→137, north→133, nw→107, se→112, south→134, sw→136, up→131, west→135}`

---

## 133 — YOU ARE IN A TWISTING MAZE OF LITTLE PASSAGES, ALL DIFFERENT

> YOU ARE IN A TWISTING MAZE OF LITTLE PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `UP` | → room 107 |
| `131` | `DOWN` | → room 131 |
| `132` | `WEST` | → room 132 |
| `134` | `NE` | → room 134 |
| `135` | `SW` | → room 135 |
| `136` | `EAST` | → room 136 |
| `137` | `NORTH` | → room 137 |
| `138` | `NW` | → room 138 |
| `139` | `SE` | → room 139 |
| `112` | `SOUTH` | → room 112 |

**Reached from:** 107 (NE), 112 (EAST), 131 (NW), 132 (NORTH), 134 (SE), 135 (SOUTH), 136 (SW), 137 (DOWN) + 2 more

**Port `topology.gd` ROOMS[133]:** `{down→131, east→136, ne→134, north→137, nw→138, se→139, south→112, sw→135, up→107, west→132}`

---

## 134 — YOU ARE IN A TWISTING LITTLE MAZE OF PASSAGES, ALL DIFFERENT

> YOU ARE IN A TWISTING LITTLE MAZE OF PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `NE` | → room 107 |
| `131` | `NORTH` | → room 131 |
| `132` | `NW` | → room 132 |
| `133` | `SE` | → room 133 |
| `135` | `EAST` | → room 135 |
| `136` | `DOWN` | → room 136 |
| `137` | `SOUTH` | → room 137 |
| `138` | `UP` | → room 138 |
| `139` | `WEST` | → room 139 |
| `112` | `SW` | → room 112 |

**Reached from:** 107 (SE), 112 (NW), 131 (SW), 132 (SOUTH), 133 (NE), 135 (EAST), 136 (DOWN), 137 (UP) + 2 more

**Port `topology.gd` ROOMS[134]:** `{down→136, east→135, ne→107, north→131, nw→132, se→133, south→137, sw→112, up→138, west→139}`

---

## 135 — YOU ARE IN A TWISTY LITTLE MAZE OF PASSAGES, ALL DIFFERENT

> YOU ARE IN A TWISTY LITTLE MAZE OF PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `NORTH` | → room 107 |
| `131` | `SE` | → room 131 |
| `132` | `DOWN` | → room 132 |
| `133` | `SOUTH` | → room 133 |
| `134` | `EAST` | → room 134 |
| `136` | `WEST` | → room 136 |
| `137` | `SW` | → room 137 |
| `138` | `NE` | → room 138 |
| `139` | `NW` | → room 139 |
| `112` | `UP` | → room 112 |

**Reached from:** 107 (UP), 112 (SE), 131 (NE), 132 (WEST), 133 (SW), 134 (EAST), 136 (SOUTH), 137 (NW) + 2 more

**Port `topology.gd` ROOMS[135]:** `{down→132, east→134, ne→138, north→107, nw→139, se→131, south→133, sw→137, up→112, west→136}`

---

## 136 — YOU ARE IN A TWISTY MAZE OF LITTLE PASSAGES, ALL DIFFERENT

> YOU ARE IN A TWISTY MAZE OF LITTLE PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `EAST` | → room 107 |
| `131` | `WEST` | → room 131 |
| `132` | `UP` | → room 132 |
| `133` | `SW` | → room 133 |
| `134` | `DOWN` | → room 134 |
| `135` | `SOUTH` | → room 135 |
| `137` | `NW` | → room 137 |
| `138` | `SE` | → room 138 |
| `139` | `NE` | → room 139 |
| `112` | `NORTH` | → room 112 |

**Reached from:** 107 (NW), 112 (NE), 131 (UP), 132 (SW), 133 (EAST), 134 (DOWN), 135 (WEST), 137 (NORTH) + 2 more

**Port `topology.gd` ROOMS[136]:** `{down→134, east→107, ne→139, north→112, nw→137, se→138, south→135, sw→133, up→132, west→131}`

---

## 137 — YOU ARE IN A LITTLE TWISTY MAZE OF PASSAGES, ALL DIFFERENT

> YOU ARE IN A LITTLE TWISTY MAZE OF PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `SE` | → room 107 |
| `131` | `NE` | → room 131 |
| `132` | `SOUTH` | → room 132 |
| `133` | `DOWN` | → room 133 |
| `134` | `UP` | → room 134 |
| `135` | `NW` | → room 135 |
| `136` | `NORTH` | → room 136 |
| `138` | `SW` | → room 138 |
| `139` | `EAST` | → room 139 |
| `112` | `WEST` | → room 112 |

**Reached from:** 107 (EAST), 112 (WEST), 131 (DOWN), 132 (NE), 133 (NORTH), 134 (SOUTH), 135 (SW), 136 (NW) + 2 more

**Port `topology.gd` ROOMS[137]:** `{down→133, east→139, ne→131, north→136, nw→135, se→107, south→132, sw→138, up→134, west→112}`

---

## 138 — YOU ARE IN A MAZE OF LITTLE TWISTING PASSAGES, ALL DIFFERENT

> YOU ARE IN A MAZE OF LITTLE TWISTING PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `DOWN` | → room 107 |
| `131` | `EAST` | → room 131 |
| `132` | `NE` | → room 132 |
| `133` | `UP` | → room 133 |
| `134` | `WEST` | → room 134 |
| `135` | `NORTH` | → room 135 |
| `136` | `SOUTH` | → room 136 |
| `137` | `SE` | → room 137 |
| `139` | `SW` | → room 139 |
| `112` | `NW` | → room 112 |

**Reached from:** 107 (WEST), 112 (DOWN), 131 (NORTH), 132 (EAST), 133 (NW), 134 (UP), 135 (NE), 136 (SE) + 2 more

**Port `topology.gd` ROOMS[138]:** `{down→107, east→131, ne→132, north→135, nw→112, se→137, south→136, sw→139, up→133, west→134}`

---

## 139 — YOU ARE IN A MAZE OF LITTLE TWISTY PASSAGES, ALL DIFFERENT

> YOU ARE IN A MAZE OF LITTLE TWISTY PASSAGES, ALL DIFFERENT.

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `107` | `SW` | → room 107 |
| `131` | `NW` | → room 131 |
| `132` | `EAST` | → room 132 |
| `133` | `WEST` | → room 133 |
| `134` | `NORTH` | → room 134 |
| `135` | `DOWN` | → room 135 |
| `136` | `SE` | → room 136 |
| `137` | `UP` | → room 137 |
| `138` | `SOUTH` | → room 138 |
| `112` | `NE` | → room 112 |

**Reached from:** 107 (NORTH), 112 (UP), 131 (SOUTH), 132 (DOWN), 133 (SE), 134 (WEST), 135 (NW), 136 (NE) + 2 more

**Port `topology.gd` ROOMS[139]:** `{down→135, east→132, ne→112, north→134, nw→131, se→136, south→138, sw→107, up→137, west→133}`

---

## 140 — DEAD END

> DEAD END

**Objects/NPCs placed here (section 7):** 38=MACHI

**Canon exits (section 3):**

| Dest | Verbs | Decoded |
|---|---|---|
| `112` | `NORTH/OUT` | → room 112 |

**Reached from:** 112 (SOUTH)

**Port `topology.gd` ROOMS[140]:** `{north→112, out→112}`

---

