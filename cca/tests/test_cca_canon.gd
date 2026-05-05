extends SceneTree

# Canon conformance dashboard.
#
# Mechanically compares the port's runtime values against the
# canonical 1977 Crowther+Woods data committed in cca/canon/.
# Replaces the human-curated CANON_DELTAS.md row list with a
# test-derived one — close a delta in code, this test
# automatically marks the line "ok" without anyone having to
# remember to update the markdown.
#
# IMPORTANT: this test ALWAYS exits 0. It's a dashboard, not a
# blocker. The 23+ scenario tests still drive correctness; this
# one drives canon-fidelity progress visibility. The actionable
# data is the printed report — search for "deltas open" and
# scroll up to see exactly what's still out of canon.
#
# Sources:
#   - Treasure homes:  cca/canon/placements.txt section 7,
#                      decoded in canon/placements_decoded.md
#   - NPC home rooms:  same source
#   - Magic-word pairs: advent.dat section 3 (travel table),
#                      verified rows: "3 11 62" / "3 33 65" /
#                      "33 100 71" with motion 62=XYZZY,
#                      65=PLUGH, 71=PLOVER

const Cca = preload("res://scripts/cca.gd")

# ----- Canon targets -----

# Treasure homes (object_id -> canon_room).
# 0 == dynamic placement (e.g. pirate's stash, oyster's pearl).
const CANON_TREASURE_HOMES := {
    "gold":      18,    # low room w/ "you won't get it up the steps" sign
    "diamonds":  27,    # west side fissure, Hall of Mists
    "silver":    28,    # low n/s passage at hole
    "jewelry":   29,    # south side chamber
    "coins":     30,    # west side chamber Hall of Mt King
    "chest":     0,     # dynamic — placed by pirate steal
    "eggs":      92,    # Giant Room
    "trident":   95,    # Magnificent Cavern (waterfall)
    "vase":      97,    # Oriental Room
    "emerald":   100,   # Plover Room
    "pyramid":   101,   # Dark-room
    "pearl":     0,     # dynamic — from clam → oyster
    "rug":       119,   # canyon (with dragon)
    "spices":    127,   # Chamber of Boulders
}

# Adventure domain-constant home rooms.
const CANON_NPC_HOMES := {
    "BIRD_HOME_ROOM":   13,
    "SNAKE_ROOM":       19,
    "DRAGON_ROOM":      119,
    "BEAR_HOME_ROOM":   130,
    "VENDING_ROOM":     140,
    "WEST_PIT_ROOM":    25,
    "DEPOSIT_ROOM":     3,
}

# Magic-word teleport pairs per canon travel table.
const CANON_MAGIC_PAIRS := [
    ["xyzzy",  3,   11],
    ["xyzzy",  11,  3],
    ["plugh",  3,   33],
    ["plugh",  33,  3],
    ["plover", 33,  100],
    ["plover", 100, 33],
]

# Architecture / mechanism deltas (each is a known-open
# canon-fidelity gap that's bigger than a simple room move).
# These print as deltas until the corresponding feature lands.
const ARCHITECTURE_DELTAS := [
    "chain is the 15th treasure — port: chain is a non-treasure FSM",
    "cage required to take bird — port: bird directly takeable",
    "food item required to feed bear — port: feed verb has no food",
    "velvet pillow saves vase — port: vase shatters on any non-deposit drop",
    "axe is item from dwarf — port: throw verb without axe item",
    "batteries are item from vending — port: insert refreshes lamp directly",
    "magazine at Witt's End — port: not implemented",
    "two rods (star + mark) — port: one rod",
    "oil-in-bottle — port: water-only",
    "clam → oyster → pearl puzzle — port: pearl static at Plover",
]

# ----- State -----
var passed: int = 0
var failed: int = 0
var open_deltas: Array = []

func _check(label: String, ok: bool, detail: String = "") -> void:
    if ok:
        passed += 1
        print("  ok   %s" % label)
    else:
        failed += 1
        var line: String = "  FAIL %s" % label
        if detail != "":
            line = "%s    %s" % [line, detail]
        print(line)
        open_deltas.append([label.strip_edges(), detail])

# ----- Section runners -----
func _check_treasure_homes(adv) -> void:
    print()
    print("Treasure homes:")
    for name in CANON_TREASURE_HOMES:
        var canon_room: int = CANON_TREASURE_HOMES[name]
        var t = adv.get(name)
        if t == null:
            _check("  %s home" % name, false, "no Treasure FSM named '%s' on Adventure" % name)
            continue
        if canon_room == 0:
            # Canon-dynamic. Pass iff port is also "not at a fixed room"
            # (we treat any port location > 0 as a delta).
            var port_loc: int = t.get_location()
            _check(
                "  %-9s dynamic" % name,
                port_loc <= 0,
                "port: static at room %d (canon: dynamic)" % port_loc
            )
            continue
        var port_room: int = t.get_location()
        _check(
            "  %-9s home" % name,
            port_room == canon_room,
            "port=%d canon=%d" % [port_room, canon_room]
        )

func _check_npc_homes(adv) -> void:
    print()
    print("NPC + key-room constants:")
    for const_name in CANON_NPC_HOMES:
        var canon_room: int = CANON_NPC_HOMES[const_name]
        var port_value = adv.get(const_name)
        if port_value == null:
            _check("  %s" % const_name, false, "Adventure has no constant '%s'" % const_name)
            continue
        _check(
            "  %-20s" % const_name,
            int(port_value) == canon_room,
            "port=%s canon=%d" % [str(port_value), canon_room]
        )

func _check_magic_pairs() -> void:
    print()
    print("Magic-word teleport pairs:")
    for entry in CANON_MAGIC_PAIRS:
        var word: String = entry[0]
        var from_room: int = entry[1]
        var to_room: int = entry[2]
        # Fresh adventure per check so prior moves don't pollute.
        var adv = Cca.new()
        adv.setup_default_aspects()
        adv.player.move_to(from_room)
        adv.do_command(word, "")
        var actual: int = adv.player_room()
        _check(
            "  %-6s @ %3d → %3d" % [word, from_room, to_room],
            actual == to_room,
            "actual=%d" % actual
        )

func _check_architecture_deltas() -> void:
    print()
    print("Architecture / mechanism deltas:")
    for d in ARCHITECTURE_DELTAS:
        _check("  " + d, false, "")

# ----- Main -----
func _init():
    print("=== CCA canon conformance ===")
    print("(dashboard — always exits 0; reports open deltas)")

    var adv = Cca.new()
    adv.setup_default_aspects()

    _check_treasure_homes(adv)
    _check_npc_homes(adv)
    _check_magic_pairs()
    _check_architecture_deltas()

    print()
    print("=================================================")
    var total: int = passed + failed
    var pct: float = 100.0 * passed / max(1, total)
    print("Canon conformance: %.1f%%  (%d / %d checks passing)" % [pct, passed, total])
    print("Open deltas: %d" % failed)
    print("=================================================")
    print()
    print("PASS — canon conformance dashboard (informational)")
    quit(0)
