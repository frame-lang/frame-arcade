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
const Topology = preload("res://scripts/topology.gd")

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
    "chain":     130,   # Barren Room (with bear) — 15th canon treasure
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

# Architecture / mechanism deltas. Each entry is a probe:
#   [label, probe_func_name, default_open_message]
# probe_func_name is invoked via call() with a fresh Adventure;
# return true if the canon mechanism is in place (delta closed),
# false if the port still has the legacy behavior. The probe
# names are resolved lazily so we can re-fold features in
# without pre-declaring all of them at script-load time.
var ARCHITECTURE_PROBES := [
    ["chain is the 15th treasure",            "_probe_chain_treasure",     "port: chain is a non-treasure FSM"],
    ["cage required to take bird",            "_probe_cage_required",      "port: bird directly takeable"],
    ["food item required to feed bear",       "_probe_food_required",      "port: feed verb has no food"],
    ["velvet pillow saves vase",              "_probe_pillow_saves_vase",  "port: vase shatters on any non-deposit drop"],
    ["axe is item from dwarf",                "_probe_axe_item",           "port: throw verb without axe item"],
    ["batteries are item from vending",       "_probe_batteries_item",     "port: insert refreshes lamp directly"],
    ["magazine at Witt's End",                "_probe_magazine_at_witts",  "port: not implemented"],
    ["two rods (star + mark)",                "_probe_two_rods",           "port: one rod"],
    ["oil-in-bottle",                         "_probe_oil_in_bottle",      "port: water-only"],
    ["clam → oyster → pearl puzzle",          "_probe_clam_oyster_pearl",  "port: pearl static at Plover"],
    # Phase 7 canon-mechanic probes ----------------------------
    ["PLOVER tunnel gates non-emerald",       "_probe_plover_squeeze",     "port: no inventory gate on 99↔100"],
    ["throw treasure at troll vanishes it",   "_probe_troll_throw",        "port: troll only flees from bear"],
    ["6 canon hints registered",              "_probe_six_hints",          "port: 3 hints (bird/cave/snake)"],
    ["dwarves auto-wake after deep dwell",    "_probe_dwarf_auto_wake",    "port: only manual wake_dwarves()"],
    ["cave-closing teleports to Repository",  "_probe_repository_teleport","port: in_repository state but no teleport"],
    ["statuette is not a treasure",           "_probe_no_statuette",       "port: 16th treasure (port-only)"],
    ["Witt's End canon: only E exits + 95% gate", "_probe_witts_end_canon", "port: walking corridor at 108:north"],
    ["chest spawns at canon room 18",         "_probe_chest_room_canon",   "port: chest at port-132"],
    ["rusty door at canon 94 oils via bottle","_probe_rusty_door",         "port: 94:north flat-bumpered, no puzzle"],
    ["clam squeeze blocks 103:south",         "_probe_clam_squeeze",       "port: 103 walkable carrying shellfish"],
    ["dark-room pit-fall after warning",      "_probe_dark_pit_fall",      "port: dark moves are silent"],
    ["death-message rooms 20/21 kill",        "_probe_death_rooms",        "port: 20/21 are stuck rooms"],
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
    for entry in ARCHITECTURE_PROBES:
        var label: String = entry[0]
        var probe_name: String = entry[1]
        var open_msg: String = entry[2]
        # Probes are written as methods on this script. We
        # `call()` by name so each new Phase 6 step lands one
        # probe at a time without script-wide load ordering.
        var ok: bool = false
        if has_method(probe_name):
            var result = call(probe_name)
            ok = bool(result)
        _check("  " + label, ok, "" if ok else open_msg)

# ----- Architecture probes -----
# Each probe creates a fresh Adventure and exercises the
# canonical mechanism. Returns true when the port matches canon.
# Missing probes are treated as "not yet implemented" (delta
# stays open).

func _probe_cage_required() -> bool:
    # Canon: bird won't enter inventory without a wicker cage.
    # Probe: at the bird chamber WITHOUT the cage, `take bird`
    # must NOT capture the bird; with the cage, it must.
    # Two-arm check ensures the gate is genuine (not just a
    # blanket "no").
    var no_cage = Cca.new()
    no_cage.setup_default_aspects()
    no_cage.do_command("light", "")
    no_cage.player.move_to(13)
    no_cage.do_command("take", "bird")
    var refused_without_cage: bool = (
        no_cage.bird_state() == "free"
        and not no_cage.player.carrying(no_cage.BIRD_ID)
    )

    var with_cage = Cca.new()
    with_cage.setup_default_aspects()
    with_cage.do_command("light", "")
    with_cage.player.move_to(10)
    with_cage.do_command("take", "cage")
    with_cage.player.move_to(13)
    with_cage.do_command("take", "bird")
    var captured_with_cage: bool = (
        with_cage.bird_state() == "caged"
        and with_cage.player.carrying(with_cage.BIRD_ID)
    )

    return refused_without_cage and captured_with_cage

func _probe_food_required() -> bool:
    # Canon: feed bear refuses without the food item; succeeds
    # once the player picks up FOOD at the well house.
    var no_food = Cca.new()
    no_food.setup_default_aspects()
    no_food.do_command("light", "")
    no_food.player.move_to(no_food.BEAR_HOME_ROOM)
    no_food.do_command("feed", "bear")
    var refused: bool = no_food.bear_state() == "hungry"

    var with_food = Cca.new()
    with_food.setup_default_aspects()
    with_food.do_command("light", "")
    with_food.player.move_to(3)
    with_food.do_command("take", "food")
    with_food.player.move_to(with_food.BEAR_HOME_ROOM)
    with_food.do_command("feed", "bear")
    var tamed: bool = with_food.bear_state() == "tame"
    # Food consumed on feed.
    var consumed: bool = not with_food.food_item.is_carried()

    return refused and tamed and consumed

func _probe_pillow_saves_vase() -> bool:
    # Canon: vase shatters on a non-deposit drop EXCEPT when the
    # velvet pillow is in the same room. Two-arm probe:
    #   1. drop vase at non-pillow room → broken
    #   2. drop pillow first, then vase → in_room (saved)
    var no_pillow = Cca.new()
    no_pillow.setup_default_aspects()
    no_pillow.do_command("light", "")
    no_pillow.player.move_to(97)               # Oriental Room (vase home)
    no_pillow.do_command("take", "vase")
    no_pillow.player.move_to(11)               # debris room (no pillow)
    no_pillow.do_command("drop", "vase")
    var shattered: bool = no_pillow.vase.get_state() == "broken"

    var with_pillow = Cca.new()
    with_pillow.setup_default_aspects()
    with_pillow.do_command("light", "")
    with_pillow.player.move_to(96)             # Soft Room (pillow home)
    with_pillow.do_command("take", "pillow")
    with_pillow.player.move_to(97)
    with_pillow.do_command("take", "vase")
    with_pillow.player.move_to(11)
    with_pillow.do_command("drop", "pillow")
    var resp = with_pillow.do_command("drop", "vase")
    var saved: bool = (
        with_pillow.vase.get_state() == "in_room"
        and not with_pillow.vase.is_broken()
    )

    return shattered and saved

func _probe_axe_item() -> bool:
    # Canon: throw verb requires axe, which originates from a
    # dwarf throw. Two-arm probe:
    #   1. fresh adventure: throw axe → "you have no axe"
    #   2. seed an axe (via the "first dwarf throws" rig) and
    #      verify the player can take it and throw it.
    var no_axe = Cca.new()
    no_axe.setup_default_aspects()
    no_axe.do_command("light", "")
    no_axe.player.move_to(12)
    var resp_no = no_axe.do_command("throw", "axe")
    var refused: bool = resp_no.to_lower().contains("no axe")

    var with_axe = Cca.new()
    with_axe.setup_default_aspects()
    with_axe.do_command("light", "")
    with_axe.wake_dwarves()
    with_axe.player.move_to(12)        # dwarf1 spawn
    # Tick until either dwarf rolls a throw and drops an axe.
    var got_axe: bool = false
    for i in 30:
        with_axe.tick()
        if with_axe.axe_item.get_location() > 0 or with_axe.axe_item.is_carried():
            got_axe = true
            break
        if with_axe.player_state() == "dead":
            with_axe.player.revive()
            with_axe.player.move_to(12)
    return refused and got_axe

func _probe_chest_dynamic() -> bool:
    # Canon: chest is placed dynamically by the pirate, not
    # static at world init. Probe: fresh adventure → chest
    # should NOT be at any room yet.
    var adv = Cca.new()
    adv.setup_default_aspects()
    var loc: int = adv.chest.get_location()
    return loc <= 0

func _probe_batteries_item() -> bool:
    # Canon: vending dispenses batteries; lamp refresh requires
    # INSERT BATTERIES. Probe: insert coins → batteries appear,
    # not yet refresh; insert batteries → refresh.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(30)
    adv.do_command("take", "coins")
    adv.player.move_to(adv.VENDING_ROOM)
    # Drain a few ticks BEFORE the insert so we have measurable
    # headroom — the refresh on INSERT BATTERIES will visibly
    # bump the battery count back up.
    for i in 5:
        adv.tick()
    var pre_insert: int = adv.battery_left()
    adv.do_command("insert", "coins")
    var bat_at_room: bool = adv.batteries_item.get_location() == adv.VENDING_ROOM
    var lamp_unchanged: bool = adv.battery_left() < pre_insert + 1
    adv.do_command("take", "batteries")
    var pre_refresh: int = adv.battery_left()
    adv.do_command("insert", "batteries")
    var lamp_refreshed: bool = adv.battery_left() > pre_refresh
    return bat_at_room and lamp_unchanged and lamp_refreshed

func _probe_two_rods() -> bool:
    # Canon: two rods exist — STAR (the magic-bridge one, at
    # canon 11 from start) and MARK (decoy, dropped by a slain
    # dwarf). Probe verifies both are distinct items by
    # construction.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    # STAR rod sits at the debris room from init.
    var star_at_home: bool = adv.rod_item.get_location() == 11 and not adv.rod_item.is_carried()
    # MARK rod is not in the world yet.
    var mark_absent: bool = adv.mark_rod_item.get_location() <= 0 and not adv.mark_rod_item.is_carried()
    # The two IDs differ.
    var distinct: bool = adv.ROD_ID != adv.MARK_ROD_ID
    return star_at_home and mark_absent and distinct

func _probe_magazine_at_witts() -> bool:
    # Canon: magazine spawns at canon 106 (Anteroom). Dropping
    # it at canon 108 (Witt's End) awards a 1-point bonus.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(adv.MAGAZINE_HOME_ROOM)
    adv.do_command("take", "magazine")
    var carried: bool = adv.player.carrying(adv.MAGAZINE_ID)
    adv.player.move_to(adv.WITTS_END_ROOM)
    var pre_bonus: int = adv.witts_end_bonus
    adv.do_command("drop", "magazine")
    var bonus_awarded: bool = adv.witts_end_bonus == 1 and pre_bonus == 0
    return carried and bonus_awarded

func _probe_oil_in_bottle() -> bool:
    # Canon: bottle can hold oil, not just water. Probe: at the
    # canon oil source, FILL BOTTLE produces $Oil; pour empties.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(3)
    adv.do_command("take", "bottle")
    adv.player.move_to(adv.OIL_SOURCE_ROOM)
    adv.do_command("fill", "bottle")
    var has_oil: bool = adv.bottle.has_oil()
    var not_water: bool = not adv.bottle.has_water()
    adv.do_command("pour", "")
    var emptied: bool = adv.bottle.get_state() == "empty"
    return has_oil and not_water and emptied

func _probe_clam_oyster_pearl() -> bool:
    # Canon: pearl is dynamic — falls out of the clam when the
    # player breaks it. Probe: clam at canon 103, take it, BREAK
    # CLAM with the rod elsewhere → pearl spawns at the break
    # room.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    # Pearl should NOT be at any room initially.
    if adv.pearl.get_location() > 0:
        return false
    adv.player.move_to(11)
    adv.do_command("take", "rod")
    adv.player.move_to(adv.CLAM_HOME_ROOM)
    adv.do_command("take", "clam")
    var carries_clam: bool = adv.player.carrying(adv.CLAM_ID)
    adv.player.move_to(16)
    # Canon msg #120 — drop the clam before opening it.
    adv.do_command("drop", "clam")
    adv.do_command("break", "clam")
    var pearl_here: bool = adv.pearl.get_location() == 16
    var oyster_here: bool = adv.oyster_item.get_location() == 16
    return carries_clam and pearl_here and oyster_here

func _probe_chain_treasure() -> bool:
    # Canon: chain is the 15th treasure — depositing it counts
    # toward treasures_deposited and worth its 14 points.
    # Probe: take + drop chain at well house, then verify.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(3)
    adv.do_command("take", "food")
    adv.player.move_to(adv.BEAR_HOME_ROOM)
    adv.do_command("feed", "bear")
    adv.do_command("take", "chain")
    var carried: bool = adv.chain.get_state() == "carried"
    adv.player.move_to(3)
    adv.do_command("drop", "chain")
    var deposited: bool = adv.chain.is_deposited()
    var counts: bool = adv.treasures_deposited() >= 1
    return carried and deposited and counts

# ----- Phase 7 mechanic probes -----

func _probe_plover_squeeze() -> bool:
    # Canon: 99↔100 narrow tunnel rejects players carrying anything
    # other than the emerald (or empty hands).
    var adv = Cca.new()
    adv.setup_default_aspects()
    var empty: bool = not adv.plover_squeeze_blocked()
    adv.player.take(adv.GOLD_ID)
    var with_gold: bool = adv.plover_squeeze_blocked()
    adv.player.drop(adv.GOLD_ID)
    adv.player.take(adv.EMERALD_ID)
    var with_emerald: bool = not adv.plover_squeeze_blocked()
    return empty and with_gold and with_emerald

func _probe_troll_throw() -> bool:
    # Canon: THROW <treasure> at troll bridge → troll flees with it.
    # Treasure transitions to $Vanished, value drops to 0.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.do_command("light", "")
    adv.player.move_to(18)
    adv.do_command("take", "gold")
    adv.player.move_to(adv.TROLL_ROOM)
    var blocking_pre: bool = adv.troll.is_blocking_bridge()
    adv.do_command("throw", "gold")
    var vanished: bool = adv.gold.is_vanished()
    var value_zero: bool = adv.gold.get_value() == 0
    var troll_gone: bool = not adv.troll.is_blocking_bridge()
    return blocking_pre and vanished and value_zero and troll_gone

func _probe_six_hints() -> bool:
    # Canon (advent.dat section 9, hint table): 6 active hints —
    # cave, bird, snake, maze, plover, witts. Each must respond to
    # hint_state() with a non-"unknown".
    var adv = Cca.new()
    adv.setup_default_aspects()
    for name in ["cave", "bird", "snake", "maze", "plover", "witts"]:
        if adv.hint_state(name) == "unknown":
            return false
    return true

func _probe_dwarf_auto_wake() -> bool:
    # Canon: dwarves wake implicitly after the player has spent
    # ~13 turns in the deep cave. Tick from a deep room and check
    # the latch flips.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(20)
    var pre: String = adv.dwarf1.get_state()
    for _i in range(20):
        adv.tick()
    var post_wake: bool = adv.dwarves_auto_woken
    var dwarf_woke: bool = adv.dwarf1.get_state() == "stalking"
    return pre == "hidden" and post_wake and dwarf_woke

func _probe_repository_teleport() -> bool:
    # Canon: when the cave-closing timer drains, the player is
    # whisked to the SW Repository (canon room 116). Drive the
    # endgame FSM to in_repository, then tick — the rising edge
    # check in Adventure.tick() must move the player to 116.
    var adv = Cca.new()
    adv.setup_default_aspects()
    # Defer the dwarf auto-wake so its axe-throws don't reset
    # the player back to the start room mid-probe.
    adv.DWARF_WAKE_THRESHOLD = 9999
    adv.player.move_to(33)
    for _i in range(10):
        adv.endgame.treasure_deposited()
    var safety: int = 200
    while not adv.endgame.in_repository() and safety > 0:
        adv.tick()
        safety -= 1
    return adv.endgame.in_repository() and adv.player_room() == 116

func _probe_no_statuette() -> bool:
    # Phase 7b removed the port-only statuette. Probe ensures the
    # FSM doesn't expose a `statuette` field anymore.
    var adv = Cca.new()
    adv.setup_default_aspects()
    return not (adv.has_method("statuette") or "statuette" in adv)

func _probe_witts_end_canon() -> bool:
    # Canon 108 (Witt's End) per advent.dat row `108 95556 …`
    # has exactly one walking exit — `108 106 43` (E → 106, the
    # 5% escape) — and a 95% probability bounce-back gate on
    # E/N/S/NE/SE/SW/NW/UP/DOWN. Any other ROOMS exit is a port
    # deviation; no probability gate means the puzzle isn't canon.
    var exits: Dictionary = Topology.ROOMS.get(108, {})
    var only_east: bool = exits.size() == 1 and exits.get("east", -1) == 106
    var has_prob_gate: bool = false
    if Topology.GATES.has("108:east"):
        has_prob_gate = Topology.GATES["108:east"].get("check", "") == "probability"
    return only_east and has_prob_gate

func _probe_chest_room_canon() -> bool:
    # Phase 7a: pirate stash relocated from port-132 to canon 18
    # ("YOU WON'T GET IT UP THE STEPS" room).
    var adv = Cca.new()
    adv.setup_default_aspects()
    return adv.CHEST_ROOM == 18

func _probe_rusty_door() -> bool:
    # Canon 94 → 95 puzzle: door starts $Rusty, blocking
    # NORTH/ENTER/CAVERN with msg #111. Filling the bottle at
    # the oil source (canon 105) and POURing at canon 94
    # transitions $Rusty → $Oiled with msg #114, after which
    # all three access verbs walk through to canon 95.
    var adv = Cca.new()
    adv.setup_default_aspects()
    var starts_rusty: bool = adv.rusty_door.is_rusty()
    # Synthetic setup: bottle in inventory, filled with oil at 105,
    # walk to 94, POUR.
    adv.player.take(adv.BOTTLE_ID)
    adv.bottle_item.try_take(3)
    adv.player.move_to(adv.OIL_SOURCE_ROOM)
    adv.do_command("fill", "")
    var has_oil: bool = adv.bottle.has_oil()
    adv.player.move_to(adv.RUSTY_DOOR_ROOM)
    var pour_resp: String = adv.do_command("pour", "")
    var oiled_now: bool = not adv.rusty_door.is_rusty()
    var canon_msg: bool = "freed up the hinges" in pour_resp
    return starts_rusty and has_oil and oiled_now and canon_msg

func _probe_clam_squeeze() -> bool:
    # Canon 103:south refuses with msg #118 / #119 when the
    # player carries the clam or the oyster (the five-foot
    # shellfish doesn't fit through the narrow passage to 64).
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(103)
    adv.do_command("take", "clam")
    var carrying: bool = adv.player.carrying(adv.CLAM_ID)
    var resp: String = adv.do_command("move", "64")
    var blocked: bool = adv.player_room() == 103
    var canon_msg: bool = "five-foot clam" in resp
    return carrying and blocked and canon_msg

func _probe_dark_pit_fall() -> bool:
    # Canon: motion in a dark cave room with the lamp out emits
    # the canon "pitch dark" warning on the first attempt and
    # has a 35% chance of fatal pit-fall on subsequent attempts.
    # The warning marker is per-room — moving to a fresh dark
    # room re-fires the warning.
    var Driver = load("res://scripts/driver.gd")
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    var rtl := RichTextLabel.new()
    rtl.bbcode_enabled = true
    d.output = rtl
    d.fsm.player.move_to(11)        # debris room — dark, lamp off
    var dark: bool = d.fsm.room_is_dark_now()
    var fired: bool = d._check_dark_pit_hazard()    # first → warn
    var marked: bool = d._dark_warned_room == 11
    return dark and fired and marked

func _probe_death_rooms() -> bool:
    # Canon: rooms 20 ("at the bottom of the pit with a broken
    # neck") and 21 ("you didn't make it") are death-message
    # rooms. Anything routing the player there fires
    # player.die() with the matching canon prose.
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.player.move_to(35)
    var resp: String = adv.do_command("move", "20")
    var dead: bool = adv.player_state() == "dead"
    var canon_msg: bool = "broke every bone" in resp
    return dead and canon_msg

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
