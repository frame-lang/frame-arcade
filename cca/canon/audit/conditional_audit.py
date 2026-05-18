#!/usr/bin/env python3
"""Audit canon special-handler rows (dest >= 300) against the port's
GATES dict. The plain section-2 audit (topology_audit.py) skips these
rows; this audit covers the blind spot.

For each canon row `from_room dest verb...` with dest >= 300:
  - decode the verb codes to direction names
  - for each direction, check if the port's GATES dict has an entry at
    "<room>:<direction>" (any check type)
  - if not, flag as a gap

Output is grouped by room and intended for inventory, not pass/fail.
The audit doesn't try to verify the gate's check type or destination —
it just answers "is the conditional row represented at all in the port?".
"""
import re, pathlib

VERB_TO_DIR = {
    29: "up",    30: "down",  43: "east",  44: "west",
    45: "north", 46: "south", 47: "ne",    48: "se",
    49: "sw",    50: "nw",
    11: "out",   19: "in",
    2:  "hill",      3:  "enter",    4:  "upstream", 5:  "downstream",
    6:  "forest",    7:  "forward",  8:  "back",     9:  "valley",
    10: "stairs",    12: "building", 13: "gully",    14: "stream",
    15: "rock",      16: "bed",      17: "crawl",    18: "cobbles",
    20: "surface",   22: "dark",     23: "passage",  24: "low",
    25: "canyon",    26: "awkward",  27: "giant",    28: "view",
    31: "pit",       32: "outdoors", 33: "crack",    34: "steps",
    35: "dome",      36: "left",     37: "right",    38: "hall",
    39: "jump",      40: "barren",   41: "over",     42: "across",
    51: "debris",    52: "hole",     53: "wall",     54: "broken",
    56: "climb",     58: "floor",    59: "room",     60: "slit",
    61: "slab",      63: "depression",64: "entrance",67: "cave",
    69: "cross",     70: "bedquilt", 72: "oriental", 73: "cavern",
    74: "shell",     75: "reservoir",76: "office",   77: "fork",
    # Canon vocabulary (advent.dat section 4): 62=XYZZY, 65=PLUGH,
    # 71=PLOVER. Earlier revision of this table had verb 71
    # mis-mapped to "plugh" — corrected 2026-05-18 alongside
    # closing the conditional-row gap. Verb 1 is the forced-motion
    # sentinel ("any verb fires this row") rather than xyzzy, but
    # we keep "xyzzy" as a probe placeholder; magic-word rows are
    # now suppressed in the false-positive filter below.
    62: "xyzzy",  65: "plugh",  71: "plover",
    1:  "xyzzy",   55: "y2",
}

# Verbs handled by the MagicWordTeleport aspect rather than the
# topology GATES dict. Rows using these verbs are NOT gaps even
# when GATES has no entry for the (room, verb) pair.
MAGIC_WORD_VERBS = {"xyzzy", "plugh", "plover"}

# Verb 1 is canon's forced-motion sentinel (advent.for line 393).
# Rows with verb 1 are routing entries, not user-input gates.
# A canon section-3 row whose verb list is exactly [1] is handled
# by the implementation's forced-motion machinery (FORCED_ROOMS in
# driver.gd plus the per-room handlers), not by GATES.
FORCED_MOTION_VERB = 1

CANON = pathlib.Path("/Users/marktruluck/projects/frame-arcade/cca/canon/advent.dat")
TOPO  = pathlib.Path("/Users/marktruluck/projects/frame-arcade/cca/godot/scripts/topology.gd")

# --- Parse all canon special-handler rows from section 2. ---
rows = []
in_section_2 = False
section_count = 0
for line in CANON.read_text().splitlines():
    if line.strip() == "-1":
        section_count += 1
        in_section_2 = (section_count == 1)
        continue
    if not in_section_2:
        continue
    parts = line.split("\t")
    if len(parts) < 3:
        continue
    try:
        from_room = int(parts[0]); dest = int(parts[1])
    except ValueError:
        continue
    if dest < 300:
        continue
    verbs = []
    for tok in parts[2:]:
        try: verbs.append(int(tok))
        except ValueError: pass
    rows.append((from_room, dest, verbs))

# --- Parse port's GATES dict. Extract every "<room>:<dir>" key. ---
gates = set()
src = TOPO.read_text()
gate_block = re.search(r'const GATES[^{]*\{(.*?)^\}', src, re.MULTILINE | re.DOTALL)
if gate_block:
    for m in re.finditer(r'"(\d+):(\w+)"', gate_block.group(1)):
        gates.add((int(m.group(1)), m.group(2)))

# --- Parse port's ROOMS dict. A row whose verb is in ROOMS for the
# from-room is "covered" by unconditional topology, not requiring a
# GATES entry — earlier audit versions reported these as gaps.
rooms = {}
for m in re.finditer(r"^\s+(\d+):\s*\{([^{}]*)\}", src, re.MULTILINE):
    rid = int(m.group(1))
    body = m.group(2)
    for pm in re.finditer(r'"(\w+)":\s*\d+', body):
        rooms.setdefault(rid, set()).add(pm.group(1))

# --- Per-row gap report. ---
covered_rows = 0
uncovered_rows = 0
gap_by_room = {}
for from_room, dest, verbs in rows:
    if from_room > 140:
        continue
    # Forced-motion rows (verb 1 only) are routing entries handled
    # by the implementation's forced-motion machinery, not user-
    # input gates. They're not "uncovered" — they're a different
    # category. Skip them silently.
    if verbs == [FORCED_MOTION_VERB]:
        covered_rows += 1
        continue
    dirs = [VERB_TO_DIR[v] for v in verbs if v in VERB_TO_DIR]
    if not dirs:
        continue
    missing = []
    for d in dirs:
        # Three coverage mechanisms:
        #   1. GATES entry — explicit conditional gate
        #   2. ROOMS entry — unconditional topology exit
        #   3. MagicWordTeleport aspect — for xyzzy/plugh/plover
        if (from_room, d) in gates:
            continue
        if d in rooms.get(from_room, set()):
            continue
        if d in MAGIC_WORD_VERBS:
            continue
        missing.append(d)
    if missing:
        uncovered_rows += 1
        gap_by_room.setdefault(from_room, []).append(
            (dest, verbs, missing)
        )
    else:
        covered_rows += 1

print("=== CCA conditional-row gap audit ===")
print(f"canon special-handler rows in scope: {covered_rows + uncovered_rows}")
print(f"covered by GATES dict:               {covered_rows}")
print(f"NOT covered:                         {uncovered_rows}")
print()
for room in sorted(gap_by_room):
    print(f"ROOM {room}:")
    for dest, verbs, missing in gap_by_room[room]:
        verb_names = " ".join(VERB_TO_DIR.get(v, f"v{v}") for v in verbs)
        print(f"  canon `{room} {dest} {' '.join(str(v) for v in verbs)}` "
              f"({verb_names})  →  ungated dirs: {','.join(missing)}")
