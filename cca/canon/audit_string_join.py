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
# Canon's advent.dat uses <NN> / <N> / <X> tokens as runtime
# placeholders the way Python uses {}. Normalize those to a single
# wildcard so a port-side concrete substitution (e.g. "45") still
# substring-matches the canon source ("<NN>").
ANGLE_PLACEHOLDER_RE = re.compile(r'<[A-Z]{1,4}>')
# Unicode dash + smart-quote folds — common when paste-quoting
# canon prose from various sources or when the codegen mangles
# UTF-8 encoding. Treat each as the plain ASCII form for matching.
DASH_FOLDS = {
    '—': '-',   # em-dash
    '–': '-',   # en-dash
    '−': '-',   # mathematical minus
    '‘': "'",   # left single quote
    '’': "'",   # right single quote
    '“': '"',   # left double quote
    '”': '"',   # right double quote
    '…': '...', # ellipsis
}
# Digit runs collapse to a single 'X' placeholder so concrete
# substitutions match against angle-bracketed canon tokens.
DIGIT_RE = re.compile(r'\d+')
WS_RE = re.compile(r'\s+')
# Reject very short strings — they match everything trivially
MIN_NORM_LEN = 12

def normalize(s):
    for src, dst in DASH_FOLDS.items():
        s = s.replace(src, dst)
    s = BBCODE_RE.sub('', s)
    s = PCT_RE.sub('X', s)             # wildcard placeholder
    s = ANGLE_PLACEHOLDER_RE.sub('X', s)
    s = DIGIT_RE.sub('X', s)
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
    targets = {0: 'room', 3: 'obj', 4: 'msg'}
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
# Some prose is stored to a field for deferred surfacing — e.g.,
# `self.last_warning = "Your lamp is getting dim…"` is the lamp
# tick warning, which the driver reads back via a getter. Catch
# any `self.<field> = "<literal>"` assignment whose RHS is a
# string long enough to be prose (rather than a state code).
FIELD_ASSIGN_RE = re.compile(r'self\.\w+\s*=\s*"((?:\\.|[^"\\])*)"')
# Gate bumper prose lives as `"msg": "..."` values in dict
# literals (Topology.GATES, gated_exits, etc.). Without this,
# every canon-msg-aligned gate bumper looks invisible.
MSG_DICT_RE = re.compile(r'"msg"\s*:\s*"((?:\\.|[^"\\])*)"')
# Local-variable assignments like `response = "I don't know..."`
# in the driver's verb-fallback substitution. Conservative —
# requires the LHS to be a bare identifier (no `.`), and the
# string must be long enough to be prose.
LOCAL_ASSIGN_RE = re.compile(r'^\s*(?:var\s+)?[a-z_]\w*\s*=\s*"((?:\\.|[^"\\])*)"', re.MULTILINE)
# Hint payload args — the FSM passes canon hint prose as the
# first argument to `request_hint(...)`. Some payloads are very
# short (canon msg #181 = "Don't go west." → 14 chars), below
# the generic 25-char threshold. This pattern catches them
# specifically so the audit doesn't miss canon hint prose just
# because of payload length.
#
# Whitespace match crosses newlines because Frame's codegen
# splits long `request_hint(...)` calls — the opening `(` lands
# on one line and the canon-prose string literal on the next.
HINT_ARG_RE = re.compile(r'request_hint\(\s*"((?:\\.|[^"\\])*)"', re.DOTALL)
# Inventory labels in `_format_inventory()`: each carried object
# emits `items.append("  Label")`. The labels are canon obj
# short-form names (advent.dat §5 prop=0). They run 8–25 chars,
# below the generic threshold, so this pattern catches them
# specifically. Strip the two leading spaces the format uses for
# bullet indent — canon doesn't have them.
INVENTORY_ITEM_RE = re.compile(r'items\.append\(\s*"\s*((?:\\.|[^"\\])*)"\s*\)')
# Fallback: any other string literal of substantial length.
# Catches method-call arguments like
# `self.witts_hint.request_hint("Don't go west.")` and
# array entries `items.append("Large gold nugget")` where the
# canon prose is in the code but not in an assignment-shaped
# emission. We rely on MIN_NORM_LEN to filter out short codes.
GENERIC_STR_RE = re.compile(r'"((?:\\.|[^"\\])*)"')
# Lines whose only quoted strings are framework debug output —
# excluded from the port emission table because they're never
# rendered to the player. The audit's `extract_emissions` skips
# every match on a line that starts with one of these prefixes.
DEBUG_CALL_PREFIXES = (
    'push_error(', 'push_warning(', 'print(', 'printerr(',
    'assert(',
)
# String literals that are FSM-internal verdicts (returned from
# Treasure/Bird/etc. action methods and consumed by Adventure
# dispatch logic, never rendered to the player). They're returned
# by `try_drop` / `try_take` / aspect bus handlers — the user
# sees the Adventure layer's wrapping prose instead. Excluded
# from the port emission set so they don't show up as RIGHT-ONLY.
FSM_VERDICT_CODES = {
    'dropped', 'dropped_soft', 'deposited', 'broken', 'vanished',
    'already broken', 'already deposited', 'already vanished',
    'not carried', 'carried', 'in_room', 'in_repository',
    'consume', 'allow', 'continue', 'block',
    'tiny', 'tall', 'huge', 'caged', 'released',
    'dead', 'alive', 'sleeping', 'fed', 'following',
    'awake', 'stalking', 'wandering', 'hungry', 'angry',
    'opened', 'closed', 'locked', 'unlocked', 'rusty', 'oiled',
    'built', 'broken_bridge', 'collapsed',
    'empty', 'full', 'water', 'oil',
    # Aspect-bus internal verdicts
    'pirate_steal', 'lamp_dim', 'lamp_dim_warn', 'lamp_warn',
    'lamp_extinguished', 'pirate_active',
}

def extract_emissions(path):
    """Return list of (line_no, kind, text) for emitted strings."""
    items = []
    # Multi-line scan for request_hint(...) — codegen splits long
    # calls across two lines. Track each match's starting line so
    # the audit report still points at the right source line.
    full_text = open(path).read()
    for m in HINT_ARG_RE.finditer(full_text):
        text = m.group(1).encode().decode('unicode_escape')
        if len(normalize(text)) >= MIN_NORM_LEN:
            line_no = full_text.count('\n', 0, m.start()) + 1
            items.append((line_no, 'hint_arg', text))
    for m in INVENTORY_ITEM_RE.finditer(full_text):
        text = m.group(1).encode().decode('unicode_escape')
        # Inventory labels use the MIN_NORM_LEN floor, not the
        # generic 25-char threshold. Canon obj names "Set of keys"
        # (11 chars) and "Tasty food" (10 chars) are intentionally
        # short. We dial slightly lower so they're visible to the
        # left-join.
        if len(normalize(text)) >= 8:
            line_no = full_text.count('\n', 0, m.start()) + 1
            items.append((line_no, 'inventory', text))
    with open(path) as f:
        for i, line in enumerate(f, start=1):
            stripped = line.lstrip()
            # Skip pure-comment lines — GDScript comments start
            # with `#` and any string literal on them is just
            # documentation, not player-facing output.
            if stripped.startswith('#'):
                continue
            # Skip lines whose only quoted strings live inside a
            # debug call — these never render to the player.
            if any(stripped.startswith(p) for p in DEBUG_CALL_PREFIXES):
                continue
            for m in PRINTLN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'println', text))
            for m in RETURN_STR_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if normalize(text) in FSM_VERDICT_CODES:
                    continue
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'return', text))
            for m in RETURN_ASSIGN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if normalize(text) in FSM_VERDICT_CODES:
                    continue
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'fsm_emit', text))
            for m in FIELD_ASSIGN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'field_assign', text))
            for m in MSG_DICT_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'gate_msg', text))
            for m in LOCAL_ASSIGN_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if len(normalize(text)) >= MIN_NORM_LEN:
                    items.append((i, 'local_assign', text))
            # GENERIC pass — only emit if not already caught above
            # on this line, and require length >= 25 to avoid
            # catching short type labels / state codes / paths.
            # Dedup also by normalized form so a line with both
            # `items.append("  Foo")` and a generic-pattern match
            # for the same literal doesn't double-count.
            existing_texts = {t for (l, k, t) in items if l == i}
            existing_norms = {normalize(t) for t in existing_texts}
            for m in GENERIC_STR_RE.finditer(line):
                text = m.group(1).encode().decode('unicode_escape')
                if text in existing_texts:
                    continue
                if normalize(text) in existing_norms:
                    continue
                if len(normalize(text)) >= 25:
                    items.append((i, 'generic', text))
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
    # Obj entries (canon §5 prop labels) use a lower threshold —
    # canon ships short inventory labels like "TASTY FOOD" (10
    # chars) and "SET OF KEYS" (11 chars). Generic msg entries
    # stick at the higher floor since shorter strings there
    # produce noisy false-positive matches against any prose.
    canon_table = []
    for key, text in canon.items():
        n = normalize(text)
        floor = 8 if key.startswith('obj#') else MIN_NORM_LEN
        if len(n) >= floor:
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
