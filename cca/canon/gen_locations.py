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
    placements   = parse_placements(sec[7])
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
    out.append("The travel-table dest decoder is a direct transcription of the spec ")
    out.append("at `cca/canon/advent.for` lines 105-122 (the FORTRAN comment block ")
    out.append("that defines the canonical `Y = M*1000 + N` encoding).")
    out.append("")
    out.append("Each location lists the canon long-form description, every canon ")
    out.append("section-3 travel-table row that exits the room (decoded), the rooms ")
    out.append("that lead in, any object/treasure/NPC placed there per canon section ")
    out.append("7, and the port's current implementation status.")
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

        # Object placements.
        if r in placements:
            obj_strs = []
            for oid in placements[r]:
                name = obj_names.get(oid, f"obj{oid}")
                obj_strs.append(f"{oid}={name}")
            out.append(f"**Objects/NPCs placed here (canon section 5):** {', '.join(obj_strs)}")
            out.append("")

        # Canon section-2 exits.
        if r in travel:
            out.append("**Canon exits (section 2):**")
            out.append("")
            out.append("| Dest | Verbs | Decoded |")
            out.append("|---|---|---|")
            for dest, verbs in travel[r]:
                out.append(f"| `{dest}` | `{verb_names(verbs)}` | {decode_dest(dest)} |")
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
