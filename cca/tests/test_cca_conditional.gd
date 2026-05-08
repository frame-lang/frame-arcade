extends SceneTree

# Canon conditional-row coverage audit — companion to
# test_cca_topology.gd. The plain-row audit (140/140 rooms
# aligned) only checks canonical advent.dat section-2 rows
# whose dest is < 300 (unconditional motions). Canon also has
# 62 *special-handler* rows with dest >= 300 — bumper messages,
# msg500 routines, probabilistic alternates, and prop-gated
# conditional motions. Those are the audit's blind spot.
#
# This dashboard categorises every special-handler row and
# reports which ones the port's GATES dict represents and which
# are still uncovered. Always exits 0 (informational); use the
# categorised counts to track canon-fidelity progress over time.
#
# Categories:
#   bumper  — dest 301..500: print remark N-300, no movement.
#             Cosmetic; the port's "no exit" branch already emits
#             a generic message. Adding canon-prose gates on top
#             is a quality-of-life improvement, not a correctness
#             requirement.
#   msg500  — dest 501..1000: same idea as bumper but in a higher
#             code range (canon msgs 95/96/126/148/153 — slit-
#             squeeze, jump-off-bridge, treasury, volcano dive,
#             dragon block). Mostly bumper-equivalent in canon
#             effect; some early port commentary called these
#             "deaths" but they are no-go messages, not real
#             player.die() routines.
#   cond    — dest >= 1000 (encoded as CCC*1000+M): prop or
#             probability-gated motion to a real room. Includes
#             the troll-bridge crossing, plant gates, probabilistic
#             maze rooms, dark-pit fall (`14 150020 …`).

const Topology = preload("res://scripts/topology.gd")

const VERB_TO_DIR := {
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
    71: "plugh",     65: "plugh",    1:  "xyzzy",   55: "y2",
}

func _init():
    print("=== CCA canon conditional-row audit ===")
    print("(advent.dat section 2, dest >= 300 — special handlers)")
    print()

    var rows: Array = _parse_canon_specials()

    # Roll up port GATES keys for fast (room, dir) lookup.
    var gates: Dictionary = {}
    for k in Topology.GATES:
        gates[k] = true

    var bumper_total: int = 0;   var bumper_covered: int = 0
    var msg500_total:  int = 0;   var msg500_covered:  int = 0
    var cond_total:   int = 0;   var cond_covered:   int = 0
    var uncovered_per_room: Dictionary = {}

    for r in rows:
        var from_room: int = r[0]
        var dest: int = r[1]
        var verbs: Array = r[2]
        if from_room > 140:
            continue
        var category: String = _category(dest)
        var dirs: Array = []
        for v in verbs:
            if VERB_TO_DIR.has(v):
                dirs.append(VERB_TO_DIR[v])
        if dirs.is_empty():
            continue
        var any_covered: bool = false
        var missing: Array = []
        for d in dirs:
            if gates.has("%d:%s" % [from_room, d]):
                any_covered = true
            else:
                missing.append(d)
        if category == "bumper":
            bumper_total += 1
            if any_covered: bumper_covered += 1
        elif category == "msg500":
            msg500_total += 1
            if any_covered: msg500_covered += 1
        elif category == "cond":
            cond_total += 1
            if any_covered: cond_covered += 1
        if not missing.is_empty():
            if not uncovered_per_room.has(from_room):
                uncovered_per_room[from_room] = []
            uncovered_per_room[from_room].append([category, dest, verbs, missing])

    print("Coverage:")
    print("  bumper (msg-only)         %d / %d" % [bumper_covered, bumper_total])
    print("  msg500 (501..1000 bumpers) %d / %d" % [msg500_covered, msg500_total])
    print("  cond   (gated motion)     %d / %d" % [cond_covered, cond_total])
    print()
    print("Per-room uncovered rows (any-dir matched suffices for coverage):")
    var rooms: Array = uncovered_per_room.keys()
    rooms.sort()
    for room in rooms:
        print("  ROOM %d:" % room)
        for entry in uncovered_per_room[room]:
            var cat: String = entry[0]
            var dest: int = entry[1]
            var verbs: Array = entry[2]
            var miss: Array = entry[3]
            var verb_names: Array = []
            for v in verbs:
                verb_names.append(VERB_TO_DIR.get(v, "v%d" % v))
            print("    [%s]  canon `%d %d %s` (%s) ungated: %s" % [
                cat, room, dest,
                _join(verbs), " ".join(verb_names),
                ",".join(miss),
            ])

    print()
    print("=== summary ===")
    print("PASS — informational dashboard (%d / %d total covered)" % [
        bumper_covered + msg500_covered + cond_covered,
        bumper_total + msg500_total + cond_total,
    ])
    quit(0)

func _category(dest: int) -> String:
    if dest >= 301 and dest <= 500:
        return "bumper"
    if dest >= 501 and dest < 1000:
        return "msg500"
    return "cond"

func _join(arr: Array) -> String:
    var parts: Array = []
    for x in arr:
        parts.append(str(x))
    return " ".join(parts)

func _parse_canon_specials() -> Array:
    var path: String = "res://canon/advent.dat" if FileAccess.file_exists("res://canon/advent.dat") else "../canon/advent.dat"
    if not FileAccess.file_exists(path):
        path = "/Users/marktruluck/projects/frame-arcade/cca/canon/advent.dat"
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("could not open advent.dat at %s" % path)
        return []
    var section_count: int = 0
    var in_section_2: bool = false
    var rows: Array = []
    while not f.eof_reached():
        var line: String = f.get_line()
        if line.strip_edges() == "-1":
            section_count += 1
            in_section_2 = (section_count == 1)
            continue
        if not in_section_2:
            continue
        var parts: PackedStringArray = line.split("\t")
        if parts.size() < 3:
            continue
        var from_room: int = int(parts[0])
        var dest: int = int(parts[1])
        if dest < 300:
            continue
        var verbs: Array = []
        for i in range(2, parts.size()):
            var tok: String = parts[i]
            if tok == "":
                continue
            var v: int = int(tok)
            if v >= 100:
                continue
            verbs.append(v)
        rows.append([from_room, dest, verbs])
    f.close()
    return rows
