#!/usr/bin/env python3
"""
Canon vs port string left-join audit.

LEFT  = canon prose the 1977 game emits (advent.dat msg catalog + advent.for
        FORMAT() strings).
RIGHT = strings the port emits (driver.gd + cca_main.gd _println literals;
        cca.gd return-string literals from the generated FSM).

Output:
  - MATCHED:    port string contains canon (or vice versa) after normalization
  - LEFT-ONLY:  canon msg nobody on the port emits → potential missing prose
  - RIGHT-ONLY: port string with no canon partner → potential port-only English

Normalization: lowercase, strip BBCode, replace %s/%d with wildcard, collapse
whitespace. Match: substring containment in either direction. Concatenate
adjacent multi-line canon entries (same msg id on consecutive lines).
"""
import re
import sys
from pathlib import Path
from collections import defaultdict

REPO = Path("/Users/marktruluck/projects/frame-arcade")
ADVENT_DAT = REPO / "cca/canon/advent.dat"
ADVENT_FOR = REPO / "cca/canon/advent.for"
PORT_FILES = [
    REPO / "cca/godot/scripts/driver.gd",
    REPO / "arcade/godot/scripts/cca_main.gd",
    REPO / "cca/godot/scripts/cca.gd",
]

BBCODE_RE = re.compile(r'\[/?[^\]]{1,40}\]')
PCT_RE = re.compile(r'%[sd]')
WS_RE = re.compile(r'\s+')
# Reject very short strings — they match everything trivially
MIN_NORM_LEN = 12

def normalize(s):
    s = BBCODE_RE.sub('', s)
    s = PCT_RE.sub('X', s)         # wildcard placeholder
    s = s.lower()
    s = WS_RE.sub(' ', s).strip()
    # Strip trailing/leading punctuation noise that varies between sources
    return s

# ---------- Canon side ----------
def parse_advent_dat():
    """Parse advent.dat. Returns {compound_id: text}.

    advent.dat sections are separated by '-1' lines. ID numbering RESTARTS
    each section — so msg #10 in section 5 is a different msg from room
    #10's description in section 1. We key by `s<N>:#<id>` to preserve
    the section context.

    Sections of interest:
      1 = long-form room descriptions (msg id = room id)
      2 = short-form room descriptions
      3 = travel table (skip — numerical)
      4 = vocabulary (skip)
      5 = RSPEAK message catalog (the canonical "msg #N")
      6 = object descriptions

    Section 5 is the primary target. Section 6 is secondary. Room descs
    (1+2) are handled by the FSM's _verb_look per-room and would need
    different match logic; out of scope for this pass.
    """
    raw = ADVENT_DAT.read_text().splitlines()
    sections = []
    cur = []
    for line in raw:
        if line.strip() == '-1':
            if cur:
                sections.append(cur)
            cur = []
        else:
            cur.append(line)
    if cur:
        sections.append(cur)

    msgs = {}
    # Section indexing — this canon advent.dat omits the short-form
    # room description section, so the canon section labels we see
    # are 1, 3, 4, 5, 6, 7, … (no 2). In our 0-indexed sections list:
    #   sections[0] = canon §1 (long room descriptions) — skip
    #   sections[1] = canon §3 (travel table) — numerical, skip
    #   sections[2] = canon §4 (vocabulary)    — skip
    #   sections[3] = canon §5 (object prop descriptions) ← OBJ
    #   sections[4] = canon §6 (msg catalog)              ← MSG
    #   sections[5] = canon §7 (object classes / scoring) — skip
    targets = {3: 'obj', 4: 'msg'}
    for s_idx, section in enumerate(sections):
        if s_idx not in targets:
            continue
        kind = targets[s_idx]
        for line in section:
            m = re.match(r'^(\d+)\t(.*)$', line)
            if not m:
                continue
            mid_str = m.group(1)
            text = m.group(2)
            # Skip vocabulary-style entries (object headers like
            # "31\t*DRAGON") — these aren't prose.
            if text.startswith('*'):
                continue
            key = f"{kind}#{mid_str}"   # keep leading zeros for prop ids
            if key in msgs:
                msgs[key] = msgs[key] + ' ' + text
            else:
                msgs[key] = text
    return msgs

def parse_advent_for():
    """Pull FORMAT() strings from advent.for as supplementary canon."""
    extras = {}
    raw = ADVENT_FOR.read_text()
    # Lines like:  9    FORMAT(/' Please answer the question.')
    # The text inside the single quotes is the canon prose.
    for m in re.finditer(
            r"FORMAT\s*\(\s*/?\s*'([^']+)'\s*\)", raw):
        text = m.group(1).strip()
        if len(text) >= MIN_NORM_LEN:
            extras[f"for:{m.start()}"] = text
    return extras

# ---------- Port side ----------
PRINTLN_RE = re.compile(r'_println\(\s*"((?:\\.|[^"\\])*)"')
RETURN_STR_RE = re.compile(r'return\s+"((?:\\.|[^"\\])*)"')
# Frame-generated FSM emissions in cca.gd compile to assignment
# (`self._context_stack[-1]._return = "..."`) rather than `return`.
# Without this third pattern, every Frame `@@:return("…")` and
# every `@@:("…")` was invisible to the audit, producing false
# LEFT-ONLY entries for canon msgs the port actually emits.
RETURN_ASSIGN_RE = re.compile(r'_return\s*=\s*"((?:\\.|[^"\\])*)"')

def extract_emissions(path):
    """Return list of (line_no, kind, text) for emitted strings."""
    items = []
    with open(path) as f:
        for i, line in enumerate(f, start=1):
            for m in PRINTLN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'println', text))
            for m in RETURN_STR_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'return', text))
            for m in RETURN_ASSIGN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'fsm_emit', text))
    return items

# ---------- Join ----------
def fuzzy_contains(short, long):
    """True if short is contained in long after normalization, with a small
    edit-distance tolerance for trailing punctuation."""
    short = short.rstrip(' .!,;:?')
    if not short:
        return False
    return short in long

def main():
    canon = parse_advent_dat()
    canon_extras = parse_advent_for()

    # Build canon lookup: (key, normalized_text, raw_text)
    canon_table = []
    for key, text in canon.items():
        n = normalize(text)
        if len(n) >= MIN_NORM_LEN:
            canon_table.append((f"dat:{key}", n, text))
    for key, text in canon_extras.items():
        n = normalize(text)
        if len(n) >= MIN_NORM_LEN:
            canon_table.append((key, n, text))

    # Build port lookup
    port_table = []
    for path in PORT_FILES:
        rel = path.relative_to(REPO)
        for line_no, kind, text in extract_emissions(path):
            port_table.append((f"{rel}:{line_no}", normalize(text), text))

    print(f"Canon entries (>={MIN_NORM_LEN} normalized chars): {len(canon_table)}")
    print(f"Port emissions: {len(port_table)}\n")

    # Match — every port emission gets credited against every canon msg
    # whose prose contains it (or is contained by it). One canon msg may
    # match many port emissions (canon msg #49 "WITH WHAT? YOUR BARE
    # HANDS?" appears at every attack handler), and one port emission
    # may match multiple canon msgs (rare, but possible with substrings).
    canon_matched = set()
    port_matched = set()
    matches = []  # (canon_key, port_key, canon_text_short, port_text_short)
    for ckey, cnorm, ctext in canon_table:
        for pkey, pnorm, ptext in port_table:
            if fuzzy_contains(cnorm, pnorm) or fuzzy_contains(pnorm, cnorm):
                matches.append((ckey, pkey, ctext, ptext))
                canon_matched.add(ckey)
                port_matched.add(pkey)

    canon_unmatched = [(k, n, t) for (k, n, t) in canon_table if k not in canon_matched]
    port_unmatched = [(k, n, t) for (k, n, t) in port_table if k not in port_matched]

    print(f"=== MATCHED ({len(matches)}) ===")
    print(f"(canon msgs whose prose is found verbatim or as substring on the port side)")
    print(f"... omitting full listing — see --verbose")
    print()

    print(f"=== LEFT-ONLY ({len(canon_unmatched)}): canon prose the port never emits ===")
    for k, n, t in sorted(canon_unmatched):
        snippet = t[:100] + ('…' if len(t) > 100 else '')
        print(f"  {k:14s}  {snippet}")
    print()

    print(f"=== RIGHT-ONLY ({len(port_unmatched)}): port strings with no canon partner ===")
    for k, n, t in sorted(port_unmatched):
        snippet = t[:100].replace('\n', ' ')
        if len(t) > 100:
            snippet += '…'
        print(f"  {k:55s}  {snippet}")

if __name__ == '__main__':
    main()
