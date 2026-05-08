#!/usr/bin/env python3
"""Generate the per-location canon reference for ARCHITECTURE.md.

Reads cca/canon/advent.dat sections 0/1/2/4/5 and the port's
topology.gd to produce a markdown table per room with:
  - Canon room name (section 0)
  - Canon entry/exit rows (section 2), decoded
  - Treasure / NPC / item home if any (section 5)
  - Port implementation status (topology.gd ROOMS + GATES)

Section index in advent.dat (separated by `-1`):
  0 = long-form descriptions
  1 = short-form descriptions
  2 = travel table (plain + special-handler rows)
  3 = vocabulary
  4 = arbitrary messages indexed 1..N
  5 = object placements (object_id room [room_alt])
  6 = object names (`*OBJECT_NAME` entries)
  7 = action verbs (e.g. for THROW handling)
  8 = scoring tiers
"""
import re
import pathlib
from collections import defaultdict

CANON = pathlib.Path("/Users/marktruluck/projects/frame-arcade/cca/canon/advent.dat")
TOPO  = pathlib.Path("/Users/marktruluck/projects/frame-arcade/cca/godot/scripts/topology.gd")

# Verb code → name (from canon section 3, the canonical motion words).
VERB_TO_DIR = {
    1: "ROAD/HILL",  2: "HILL",       3: "ENTER",     4: "UPSTREAM",
    5: "DOWNSTREAM", 6: "FOREST",     7: "FORWARD",   8: "BACK",
    9: "VALLEY",    10: "STAIRS",    11: "OUT",      12: "BUILDING",
    13: "GULLY",    14: "STREAM",    15: "ROCK",     16: "BED",
    17: "CRAWL",    18: "COBBLES",   19: "IN",       20: "SURFACE",
    22: "DARK",     23: "PASSAGE",   24: "LOW",      25: "CANYON",
    26: "AWKWARD",  27: "GIANT",     28: "VIEW",     29: "UP",
    30: "DOWN",     31: "PIT",       32: "OUTDOORS", 33: "CRACK",
    34: "STEPS",    35: "DOME",      36: "LEFT",     37: "RIGHT",
    38: "HALL",     39: "JUMP",      40: "BARREN",   41: "OVER",
    42: "ACROSS",   43: "EAST",      44: "WEST",     45: "NORTH",
    46: "SOUTH",    47: "NE",        48: "SE",       49: "SW",
    50: "NW",       51: "DEBRIS",    52: "HOLE",     53: "WALL",
    54: "BROKEN",   55: "Y2",        56: "CLIMB",    58: "FLOOR",
    59: "ROOM",     60: "SLIT",      61: "SLAB",     62: "SLABROOM",
    63: "DEPRESSION",64:"ENTRANCE",  65: "PLUGH",    66: "SECRET",
    67: "CAVE",     69: "CROSS",     70: "BEDQUILT", 71: "PLUGH",
    72: "ORIENTAL", 73: "CAVERN",    74: "SHELL",    75: "RESERVOIR",
    76: "OFFICE",   77: "FORK",
}

# Parse advent.dat by section. Per cca/canon/advent.for lines
# 95-156, the file is divided into numbered sections separated
# by `-1` markers, and the *first non-data line of each section
# is a single integer giving the section number*. Section 2
# (short-form descriptions) was omitted from the 1977 release —
# the file jumps from section 1 directly to section 3 (the
# travel table). We honour the explicit numbering rather than
# inferring contiguous ordering.
def parse_canon():
    sections = defaultdict(list)
    current = None
    expect_header = True
    for line in CANON.read_text().splitlines():
        if line.strip() == "-1":
            current = None
            expect_header = True
            continue
        if expect_header:
            try:
                current = int(line.strip())
            except ValueError:
                # First section's number is `1` on line 1; if it
                # isn't, the file is malformed.
                current = 1
            expect_header = False
            continue
        if current is not None:
            sections[current].append(line)
    return sections

# Section 1: long-form descriptions, multi-line per room. The
# 1977 release encodes the short name of each room as the final
# "YOU'RE AT/IN ..." line of its long-desc block, since section
# 2 was omitted. Returns (long_text, short_name) per room.
def parse_long_descs(lines):
    raw = defaultdict(list)
    for line in lines:
        m = re.match(r"^(\d+)\t(.*)", line)
        if m:
            raw[int(m.group(1))].append(m.group(2))
    out = {}
    for r, body in raw.items():
        long_text = " ".join(body)
        # The canonical short name is the trailing "YOU'RE ..." /
        # "YOU ARE ..." line; fall back to the first line if no
        # such recap is present.
        short = body[0]
        for line in body:
            if line.upper().startswith(("YOU'RE", "YOU ARE")):
                short = line
        out[r] = (long_text, short)
    return out

def parse_short_descs(lines):
    # Section 2 is empty in the 1977 file. Kept for forward-compat
    # with later canon releases that ship explicit short descs.
    descs = defaultdict(list)
    for line in lines:
        m = re.match(r"^(\d+)\t(.*)", line)
        if m:
            descs[int(m.group(1))].append(m.group(2))
    return {r: " ".join(d) for r, d in descs.items()}

# Section 6: arbitrary messages. Same multi-line format as section
# 1 — a leading number followed by a tab and a line of text;
# adjacent lines with the same number form one logical message.
# These are the messages canonical RSPEAK / PSPEAK calls reach.
def parse_arbitrary_messages(lines):
    raw = defaultdict(list)
    for line in lines:
        m = re.match(r"^(\d+)\t(.*)", line)
        if m:
            raw[int(m.group(1))].append(m.group(2))
    return {n: " ".join(body).strip() for n, body in raw.items()}

# Section 9: COND-bit assignments per location. Format per
# advent.for lines 160-176:
#   "BIT_N  loc_1  loc_2  ..."  sets bit N on each listed COND[loc].
# Bits 0-3 are gameplay; bits 4-9 are hint flags.
COND_BIT_LABELS = {
    0: "lit",
    1: "_oil_or_water_modifier",   # see merge below
    2: "liquid present",
    3: "pirate-forbidden",
    4: "hint: trying to get into cave",
    5: "hint: catching bird",
    6: "hint: dealing with snake",
    7: "hint: lost in maze",
    8: "hint: pondering dark room",
    9: "hint: at Witt's End",
}

def parse_cond_bits(lines):
    # Returns {room: set(bit_indices)}.
    bits_by_room = defaultdict(set)
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        try:
            bit = int(parts[0])
        except ValueError:
            continue
        for tok in parts[1:]:
            tok = tok.strip()
            if not tok:
                continue
            try:
                room = int(tok)
            except ValueError:
                continue
            bits_by_room[room].add(bit)
    return bits_by_room

# Render a per-room property line. Bit-1 only matters when bit-2
# is set; we collapse those into "water source" / "oil source".
def format_properties(bits):
    if not bits:
        return ""
    parts = []
    if 0 in bits:
        parts.append("**lit** (sunlit / always lit)")
    else:
        parts.append("dark (requires lamp)")
    if 2 in bits:
        if 1 in bits:
            parts.append("**oil source** (FILL BOTTLE here yields oil)")
        else:
            parts.append("**water source** (FILL BOTTLE here yields water)")
    if 3 in bits:
        parts.append("pirate-forbidden (won't enter unless following the player)")
    hint_labels = []
    for bit, label in COND_BIT_LABELS.items():
        if bit in bits and bit >= 4:
            hint_labels.append(label.replace("hint: ", ""))
    if hint_labels:
        parts.append("hint flags: " + ", ".join(hint_labels))
    return "; ".join(parts)

# Detect forced-motion rooms per advent.for line 393:
#   IF(MOD(IABS(TRAVEL(K)),1000).EQ.1)COND(I)=2
# After the file's loaded into the TRAVEL array, each entry is
# encoded as `NEWLOC*1000 + verb_id`. So `mod 1000 == 1` means
# the row's verb is verb 1 (ROAD/HILL — historically used as the
# "any-verb" trigger for forced motion). In the file's section
# 3 layout this surfaces as a row whose verb list is exactly
# `[1]` and whose dest is the forced-motion target room (or 0
# meaning "stay put — print description"). Canonical examples:
#     20  0   1   →  death-pit room (any-verb → 0 = stay → die)
#     22  15  1   →  dome-bouncer  (any-verb → 15 = Hall of Mists)
#     26  88  1   →  plant-clamber (any-verb → 88 = cliff)
def find_forced_motion(travel_by_room):
    forced = {}
    for r, rows in travel_by_room.items():
        for dest, verbs in rows:
            if verbs == [1]:
                forced[r] = dest
                break
    return forced

# Section 2: travel table.
def parse_travel(lines):
    rows_by_room = defaultdict(list)
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        try:
            from_r = int(parts[0]); dest = int(parts[1])
        except ValueError:
            continue
        verbs = []
        for tok in parts[2:]:
            try: verbs.append(int(tok))
            except ValueError: pass
        rows_by_room[from_r].append((dest, verbs))
    return rows_by_room

# Section 5: object placements. Format: `obj_id  room  [room2]` —
# room2 is the secondary placement (chest at room 132 also at 18 etc.).
def parse_placements(lines):
    items_by_room = defaultdict(list)
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        try:
            obj_id = int(parts[0]); room = int(parts[1])
        except ValueError:
            continue
        if room <= 0 or room > 140:
            continue
        items_by_room[room].append(obj_id)
    return items_by_room

# Section 4: vocabulary. Per advent.for line 137-143, each line is
# `number TAB five-letter-word`. The number's high digit (N/1000)
# classifies: 0 = motion verb, 1 = object, 2 = action verb, 3 =
# special-case verb. Object names are entries with 1000 <= N < 2000
# and the canonical id is N - 1000.
def parse_object_names(lines):
    names = {}
    for line in lines:
        m = re.match(r"^(\d+)\t(.*)", line)
        if not m:
            continue
        n = int(m.group(1))
        if n < 1000 or n >= 2000:
            continue
        oid = n - 1000
        # Canon stores synonyms by listing the same id multiple
        # times — the first occurrence is the canonical name.
        names.setdefault(oid, m.group(2).strip().rstrip("."))
    return names

# Decode a section-2 dest into a human-readable form.
# Per cca/canon/advent.for lines 105-122 — the FORTRAN comment
# block that defines the canonical Y = M*1000 + N encoding:
#
#   N <= 300       go to room N
#   300 < N <= 500 special routine N-300 (computed-goto into hardcoded code)
#   N > 500        print msg N-500 (from section 6), stay in place
#
#   M = 0          unconditional
#   0 < M < 100    M% probability
#   M = 100        unconditional, but forbidden to dwarves
#   100 < M <= 200 must be carrying obj M-100
#   200 < M <= 300 must be carrying or co-located with obj M-200
#   300 < M <= 400 prop(M mod 100) must NOT be 0
#   400 < M <= 500 prop(M mod 100) must NOT be 1
#   500 < M <= 600 prop(M mod 100) must NOT be 2
#
# Special routines (per advent.for lines 1048-1098): only three
# exist —
#   301 = Plover-alcove tight passage (carry only emerald or empty)
#   302 = Plover transport (drop emerald, route through passage)
#   303 = Troll bridge crossing (handles dwarves + bear+chain)
SPECIAL_ROUTINE = {
    1: "Plover-alcove squeeze (only carry emerald or empty)",
    2: "Plover transport (drop emerald, use passage)",
    3: "Troll-bridge cross",
}

def decode_dest_n(n):
    if n == 0:
        # Canon sentinel — used in forced-motion rows (`<room>  0  1`)
        # to mean "stay put". The engine then prints the room's long
        # description; for death-message rooms (20, 21) that *is* the
        # death prose, and the player's hp gets adjusted via separate
        # FORTRAN logic outside the travel table.
        return "→ stay put (forced-motion sentinel)"
    if 1 <= n <= 300:
        return f"→ room {n}"
    if 301 <= n <= 500:
        idx = n - 300
        label = SPECIAL_ROUTINE.get(idx, f"#{idx}")
        return f"special routine {idx} ({label})"
    if 501 <= n <= 1000:
        return f"print msg #{n - 500}"
    return f"dest={n} (unrecognised)"

def decode_dest(dest):
    # Y = M*1000 + N. For dest <= 1000, M = 0 (unconditional).
    if dest <= 1000:
        return decode_dest_n(dest)
    m = dest // 1000
    n = dest % 1000
    return f"if {decode_condition(m)}: {decode_dest_n(n)}"

# Decode a condition code per cca/canon/advent.for lines 114-122.
def decode_condition(m):
    if m == 0:
        return "always"
    if 1 <= m <= 99:
        return f"{m}% probability"
    if m == 100:
        return "always (forbidden to dwarves)"
    if 101 <= m <= 200:
        return f"carrying obj #{m - 100}"
    if 201 <= m <= 300:
        return f"carrying or co-located with obj #{m - 200}"
    if 301 <= m <= 400:
        return f"prop(obj #{m % 100}) ≠ 0"
    if 401 <= m <= 500:
        return f"prop(obj #{m % 100}) ≠ 1"
    if 501 <= m <= 600:
        return f"prop(obj #{m % 100}) ≠ 2"
    return f"cond=M{m}"

# Decode verb list to names.
def verb_names(verbs):
    return "/".join(VERB_TO_DIR.get(v, f"v{v}") for v in verbs) or "(any)"

# Parse port topology ROOMS dict.
def parse_port_rooms():
    src = TOPO.read_text()
    rooms = {}
    for m in re.finditer(r"^\s+(\d+):\s*\{([^{}]*)\}", src, re.MULTILINE):
        rid = int(m.group(1))
        body = m.group(2)
        pairs = {}
        for pm in re.finditer(r'"(\w+)":\s*(\d+)', body):
            pairs[pm.group(1)] = int(pm.group(2))
        rooms[rid] = pairs
    return rooms

# Parse port topology GATES dict.
def parse_port_gates():
    src = TOPO.read_text()
    gate_block = re.search(r"const GATES[^{]*\{(.*?)^\}", src, re.MULTILINE | re.DOTALL)
    gates = {}
    if gate_block:
        for m in re.finditer(r'"(\d+):(\w+)":\s*\{[^}]*"check":\s*"(\w+)"', gate_block.group(1)):
            room = int(m.group(1)); direction = m.group(2); check = m.group(3)
            gates.setdefault(room, []).append((direction, check))
    return gates

def main():
    sec = parse_canon()
    # Canon section numbers per advent.for lines 95-180:
    #   1 = long-form descriptions
    #   2 = short-form descriptions (OMITTED in the 1977 release)
    #   3 = travel table
    #   4 = vocabulary (motion verbs N<1000, objects 1000..1999,
    #                   action verbs 2000..2999, specials 3000..)
    #   5 = object descriptions (inventory + per-prop messages)
    #   6 = arbitrary messages (RSPEAK / msg #N)
    #   7 = object locations (placements)
    long_descs   = parse_long_descs(sec[1])
    short_descs  = parse_short_descs(sec[2])     # empty in 1977
    travel       = parse_travel(sec[3])
    obj_names    = parse_object_names(sec[4])
    arb_messages = parse_arbitrary_messages(sec[6])
    placements   = parse_placements(sec[7])
    cond_bits    = parse_cond_bits(sec[9])
    forced       = find_forced_motion(travel)
    port_rooms   = parse_port_rooms()
    port_gates   = parse_port_gates()

    # Build entry-points: which rooms come INTO this room.
    entries_by_room = defaultdict(list)
    for src_room, rows in travel.items():
        for dest, verbs in rows:
            if 1 <= dest <= 140:
                entries_by_room[dest].append((src_room, verbs))

    out = []
    out.append("# Per-location canon reference")
    out.append("")
    out.append("Auto-generated from `cca/canon/advent.dat` and the port's ")
    out.append("`cca/godot/scripts/topology.gd`. Don't hand-edit this file — ")
    out.append("regenerate via `python3 cca/canon/gen_locations.py > cca/CANON_LOCATIONS.md`.")
    out.append("")
    out.append("Decoding rules transcribed directly from `cca/canon/advent.for`:")
    out.append("- Travel-table `Y = M*1000 + N` encoding: lines 105-122.")
    out.append("- Special motion routines (N=301..303): lines 1045-1098 — see")
    out.append("  the *Special motion routines* section below.")
    out.append("- COND-bit assignments per location: lines 159-176.")
    out.append("- Forced-motion detection (cond=2): line 393.")
    out.append("")
    out.append("Each location lists:")
    out.append("- Canon long-form description (section 1).")
    out.append("- Properties — lit/dark, water/oil source, pirate-forbidden, ")
    out.append("  hint-system flags (section 9 cond bits).")
    out.append("- Forced-motion target if any (cond=2).")
    out.append("- Every canon section-3 travel-table row that exits the room, ")
    out.append("  decoded — including the inlined text of any `msg #N` it ")
    out.append("  references.")
    out.append("- Reached-from list (which rooms route in via what verbs).")
    out.append("- Object/NPC placements (section 7).")
    out.append("- The port's current `topology.gd` ROOMS and GATES status.")
    out.append("")
    out.append("---")
    out.append("")
    out.append("## Special motion routines (canon dest 301..303)")
    out.append("")
    out.append("The travel-table encoding allows `300 < N <= 500` to dispatch ")
    out.append("into a hardcoded routine (per `advent.for` lines 105-110). The ")
    out.append("1977 release defines exactly three. Behavior is transcribed ")
    out.append("verbatim from `advent.for` lines 1045-1098 — anywhere the ")
    out.append("port disagrees with these bodies is a port-side delta.")
    out.append("")
    out.append("### Routine 301 — Plover-alcove squeeze (FORTRAN line 30100)")
    out.append("")
    out.append("```fortran")
    out.append("30100   NEWLOC = 99 + 100 - LOC")
    out.append("        IF (HOLDNG.EQ.0 .OR.")
    out.append("     1     (HOLDNG.EQ.1 .AND. TOTING(EMRALD))) GOTO 2")
    out.append("        NEWLOC = LOC")
    out.append("        CALL RSPEAK(117)")
    out.append("        GOTO 2")
    out.append("```")
    out.append("")
    out.append("**Effect:** at canon 99 ↔ 100 (Alcove ↔ Plover Room), the tight ")
    out.append("passage admits the player only with empty hands or carrying ")
    out.append("exactly one item — the emerald. Otherwise prints msg #117 ")
    if 117 in arb_messages:
        out.append(f"(*\"{arb_messages[117]}\"*) ")
    out.append("and the player stays put. `99+100-LOC` flips between 99 and 100.")
    out.append("")
    out.append("**Port:** `Adventure.plover_squeeze_blocked()` returns true ")
    out.append("when `HOLDNG > 1` *or* (HOLDNG == 1 and not carrying emerald). ")
    out.append("GATES `99:east`, `100:west` use the `plover_squeeze` check type.")
    out.append("")
    out.append("### Routine 302 — Plover transport (FORTRAN line 30200)")
    out.append("")
    out.append("```fortran")
    out.append("30200   CALL DROP(EMRALD,LOC)")
    out.append("        GOTO 12")
    out.append("```")
    out.append("")
    out.append("**Effect:** if PLUGH is invoked at Y2 (33) or Plover Room (100) ")
    out.append("*while carrying the emerald*, the emerald is dropped at the ")
    out.append("current location and the player is then re-routed through the ")
    out.append("Plover passage rather than the normal PLUGH teleport — forcing ")
    out.append("them to use the squeeze (routine 301) to retrieve it. The canon ")
    out.append("section-3 condition `M = 159` (carrying obj 59 = emerald) gates ")
    out.append("this routine at both 33 and 100.")
    out.append("")
    out.append("**Port:** *not currently implemented* as a special routine. The ")
    out.append("port handles PLUGH via `MagicWordTeleport` aspect which always ")
    out.append("teleports unconditionally — the canon emerald-carrying detour ")
    out.append("is a known divergence (logged in `CANON_DELTAS.md` if not yet ")
    out.append("there). Closing this would mean adding an inventory check in ")
    out.append("`MagicWordTeleport` for emerald + drop-and-reroute behaviour.")
    out.append("")
    out.append("### Routine 303 — Troll-bridge crossing (FORTRAN line 30300)")
    out.append("")
    out.append("```fortran")
    out.append("30300   IF (PROP(TROLL).NE.1) GOTO 30310")
    out.append("        CALL PSPEAK(TROLL,1)")
    out.append("        PROP(TROLL) = 0")
    out.append("        CALL MOVE(TROLL2, 0)")
    out.append("        CALL MOVE(TROLL2+100, 0)")
    out.append("        CALL MOVE(TROLL, PLAC(TROLL))")
    out.append("        CALL MOVE(TROLL+100, FIXD(TROLL))")
    out.append("        CALL JUGGLE(CHASM)")
    out.append("        NEWLOC = LOC")
    out.append("        GOTO 2")
    out.append("")
    out.append("30310   NEWLOC = PLAC(TROLL) + FIXD(TROLL) - LOC")
    out.append("        IF (PROP(TROLL).EQ.0) PROP(TROLL) = 1")
    out.append("        IF (.NOT.TOTING(BEAR)) GOTO 2")
    out.append("        CALL RSPEAK(162)")
    out.append("        PROP(CHASM) = 1")
    out.append("        PROP(TROLL) = 2")
    out.append("        CALL DROP(BEAR, NEWLOC)")
    out.append("        FIXED(BEAR) = -1")
    out.append("        PROP(BEAR) = 3")
    out.append("        IF (PROP(SPICES).LT.0) TALLY2 = TALLY2 + 1")
    out.append("        OLDLC2 = NEWLOC")
    out.append("        GOTO 99")
    out.append("```")
    out.append("")
    out.append("**Effect:** crossing the troll bridge between canon 117 (R_SWSIDE) ")
    out.append("and canon 122 (R_NESIDE). Logic depends on `PROP(TROLL)`:")
    out.append("- `PROP(TROLL) == 1` (already crossed once after paying): troll ")
    out.append("  steps out from hiding to block (PSPEAK msg 1), resets to 0 ")
    out.append("  (demanding again), juggles chasm.")
    out.append("- otherwise: walk across (`PLAC(TROLL) + FIXD(TROLL) - LOC` flips ")
    out.append("  between 117 and 122), promote `PROP(TROLL)` to 1.")
    out.append("- if carrying the bear: PSPEAK msg 162 ('the bear lumbers across, ")
    out.append("  scaring the troll'), troll permanently scared (`PROP(TROLL)=2`), ")
    out.append("  bear dropped on far side and immobilised, chasm crossed.")
    out.append("")
    out.append("**Port:** the `Troll` Frame system handles `$Demanding → pay_toll → ")
    out.append("$TollPaid → bear_arrives → $Vanished`. Bridge-crossing dest 117↔122 ")
    out.append("is encoded directly in `topology.gd` with the `troll` gate check ")
    out.append("rather than via a special-routine dispatch.")
    out.append("")
    out.append("---")
    out.append("")

    for r in range(1, 141):
        long_text, short = ("", "no canon entry")
        if r in long_descs:
            long_text, short = long_descs[r]
        # If section 2 *did* ship a short desc (later canon
        # releases), prefer that; otherwise fall back to the
        # YOU'RE-AT recap line we extracted from section 1.
        title = short_descs.get(r, short).strip().rstrip(".")
        out.append(f"## {r:>3} — {title}")
        out.append("")

        if long_text:
            d = re.sub(r"\s+", " ", long_text).strip()
            out.append(f"> {d}")
            out.append("")

        # Per-room properties from canon section 9 cond bits.
        prop_line = format_properties(cond_bits.get(r, set()))
        if prop_line:
            out.append(f"**Properties (section 9):** {prop_line}")
            out.append("")

        # Forced motion (cond=2) — auto-bounce on entry.
        if r in forced:
            target = forced[r]
            if target == 0:
                out.append(f"**Forced motion (cond=2):** any verb stays put — "
                           f"this is a transition / death-message room. The ")
                out.append(f"engine prints the room's long description and ")
                out.append(f"continues on the player's *next* turn from here.")
            else:
                out.append(f"**Forced motion (cond=2):** any verb routes to "
                           f"room {target}. The engine prints this room's ")
                out.append(f"long description as a one-time transition message ")
                out.append(f"then auto-walks the player to {target}.")
            out.append("")

        # Object placements (canon section 7).
        if r in placements:
            obj_strs = []
            for oid in placements[r]:
                name = obj_names.get(oid, f"obj{oid}")
                obj_strs.append(f"{oid}={name}")
            out.append(f"**Objects/NPCs placed here (section 7):** {', '.join(obj_strs)}")
            out.append("")

        # Canon section-3 exits with inline message text.
        if r in travel:
            out.append("**Canon exits (section 3):**")
            out.append("")
            out.append("| Dest | Verbs | Decoded |")
            out.append("|---|---|---|")
            for dest, verbs in travel[r]:
                decoded = decode_dest(dest)
                # If the decoded string references a `msg #N`,
                # inline the actual canon prose so a reader doesn't
                # have to look up section 6 separately.
                msg_match = re.search(r"msg #(\d+)", decoded)
                if msg_match:
                    n = int(msg_match.group(1))
                    if n in arb_messages:
                        msg = arb_messages[n]
                        # Trim very long messages to keep the
                        # table readable; full text is in canon's
                        # section 6 if needed.
                        if len(msg) > 220:
                            msg = msg[:217] + "..."
                        decoded += f"<br><small>↳ *\"{msg}\"*</small>"
                out.append(f"| `{dest}` | `{verb_names(verbs)}` | {decoded} |")
            out.append("")

        # Entry points (rooms that route INTO this one).
        if r in entries_by_room:
            entries = sorted(set((src, tuple(v)) for src, v in entries_by_room[r]))
            entry_strs = [f"{s} ({verb_names(list(v))})" for s, v in entries[:8]]
            more = "" if len(entries) <= 8 else f" + {len(entries)-8} more"
            out.append(f"**Reached from:** {', '.join(entry_strs)}{more}")
            out.append("")

        # Port implementation.
        if r in port_rooms:
            exits = port_rooms[r]
            if exits:
                exit_strs = [f"{d}→{dest}" for d, dest in sorted(exits.items())]
                out.append(f"**Port `topology.gd` ROOMS[{r}]:** `{{{', '.join(exit_strs)}}}`")
            else:
                out.append(f"**Port `topology.gd` ROOMS[{r}]:** `{{}}` (no exits)")
            out.append("")
        else:
            out.append(f"**Port `topology.gd` ROOMS[{r}]:** *(not in port)*")
            out.append("")

        if r in port_gates:
            gate_strs = [f"{d}/{check}" for d, check in port_gates[r]]
            out.append(f"**Port GATES[{r}]:** {', '.join(gate_strs)}")
            out.append("")

        out.append("---")
        out.append("")

    print("\n".join(out))

if __name__ == "__main__":
    main()
