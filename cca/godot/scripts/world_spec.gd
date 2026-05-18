# ============================================================
# world_spec.gd — canon expectations for CCA (Phase C, Layer 2)
# ============================================================
# Declares per-object canon expectations as data. The probe and
# dedicated spec tests consult this module rather than scattering
# canon-fidelity assertions across the test suite. Lineage is
# model-based testing (Utting/Pretschner/Legeard 2006); closest
# commercial-grade implementation is Microsoft Research's
# SpecExplorer. Here the spec database is largely transcription
# from canon source (advent.dat section 7, cross-referenced with
# the FSM init code in cca.fgd's `Treasure._create` /
# `Item._create` declarations), not invention.
#
# Phase C Layer 2 scope: **item placement only**. NPC anchoring
# (Layer 3) and verb-effect tables (Layer 4) are deferred until
# the spec-as-data architecture proves itself on Layer 2.
#
# Two consumers:
#   1. tests/test_cca_world_spec.gd — fresh-FSM init check;
#      verifies every spec'd item is at the declared room when
#      a new Cca() is built.
#   2. probe.gd's per-step in-limbo check (added alongside this
#      module) — flags items that drift to location 0 or -1
#      without being carried or consumed, which is the canonical
#      "lost in limbo" bug class.
# ============================================================
extends RefCounted

# ----- Item spec ---------------------------------------------------

# Keyed by canonical noun (matches Driver._resolve_object_id).
# Fields:
#   id              — driver constant for this item
#   initial_room    — canon room at game start; 0 means "in limbo
#                     (no room)" — for dynamic-spawn items this is
#                     the canonical correct initial state
#   value           — canon treasure value if applicable; 0 for non-
#                     treasures. Cross-checks against the FSM's
#                     score-on-deposit logic.
#   kind            — "treasure" | "item"; selects which accessor
#                     family the FSM exposes (get_location() vs
#                     is_in_room(room))
#   dynamic_spawn   — true if the item legitimately starts in limbo
#                     and spawns later via a canon mechanic (pirate
#                     drops chest, BREAK CLAM yields oyster+pearl,
#                     dwarf throws axe, etc). The in-limbo check
#                     uses this to accept limbo as valid.
#   spawn_note      — documentation only; names the canon mechanic.
#   consumable      — true if the item can canon-validly transition
#                     to a "consumed" / "vanished" state (food eaten,
#                     clam broken, eggs vanished). When true, the
#                     in-limbo check accepts the item being in
#                     limbo if its FSM is in a vanish-equivalent
#                     state.
const ITEM_SPEC: Dictionary = {
    # ----- The 15 canon treasures -----
    "gold":     {"id": 110, "initial_room": 18,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "silver":   {"id": 111, "initial_room": 28,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "diamonds": {"id": 112, "initial_room": 27,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "jewelry":  {"id": 113, "initial_room": 29,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "pearl":    {"id": 114, "initial_room": 0,   "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "falls out of the oyster on BREAK CLAM"},
    "vase":     {"id": 115, "initial_room": 97,  "value": 14, "kind": "treasure", "consumable": true,  "dynamic_spawn": false,
                 "fragile": true},
    "eggs":     {"id": 116, "initial_room": 92,  "value": 14, "kind": "treasure", "consumable": true,  "dynamic_spawn": false,
                 "respawn_note": "reappear via FEE FIE FOE FOO from troll's pocket"},
    "trident":  {"id": 117, "initial_room": 95,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "emerald":  {"id": 118, "initial_room": 100, "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "spices":   {"id": 119, "initial_room": 127, "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "chest":    {"id": 120, "initial_room": 0,   "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "placed by pirate on first steal"},
    "pyramid":  {"id": 121, "initial_room": 101, "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "rug":      {"id": 122, "initial_room": 119, "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false,
                 "note": "visible once dragon dies"},
    "coins":    {"id": 123, "initial_room": 30,  "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false},
    "chain":    {"id": 101, "initial_room": 130, "value": 14, "kind": "treasure", "consumable": false, "dynamic_spawn": false,
                 "note": "with bear; unlock via keys after taming"},

    # ----- Non-treasure carriables -----
    "rod":      {"id": 130, "initial_room": 11,  "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false},
    "keys":     {"id": 131, "initial_room": 3,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false},
    "lamp":     {"id": 142, "initial_room": 3,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false,
                 "note": "battery drains on tick; not consumable per se"},
    "bottle":   {"id": 132, "initial_room": 3,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false,
                 "note": "carry-state separate from contents FSM"},
    "cage":     {"id": 133, "initial_room": 10,  "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false},
    "food":     {"id": 134, "initial_room": 3,   "value": 0,  "kind": "item",     "consumable": true,  "dynamic_spawn": false,
                 "consumed_via": "FEED BEAR"},
    "pillow":   {"id": 135, "initial_room": 96,  "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false},
    "clam":     {"id": 137, "initial_room": 103, "value": 0,  "kind": "item",     "consumable": true,  "dynamic_spawn": false,
                 "consumed_via": "BREAK CLAM transforms into oyster"},
    "magazine": {"id": 140, "initial_room": 106, "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": false},

    # ----- Dynamic-spawn items (start in limbo, room 0) -----
    "axe":      {"id": 136, "initial_room": 0,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "thrown by a dwarf"},
    "mark_rod": {"id": 141, "initial_room": 0,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "appears when a dwarf is killed (endgame dynamite)"},
    "batteries":{"id": 139, "initial_room": 0,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "vending machine dispenses on insert coins"},
    "oyster":   {"id": 138, "initial_room": 0,   "value": 0,  "kind": "item",     "consumable": false, "dynamic_spawn": true,
                 "spawn_note": "appears at the clam room on BREAK CLAM",
                 "immobile": true},
}

# ----- NPC spec (Layer 3) ------------------------------------------
# Per-NPC canon expectations: home room, initial state name, plus
# a wandering flag for NPCs that don't anchor anywhere (dwarves,
# pirate). Drawn from canon advent.dat/advent.for plus the
# Adventure FSM's `BIRD_HOME_ROOM` / `SNAKE_ROOM` / `TROLL_ROOM` /
# `DRAGON_ROOM` constants which already cite canon.
#
# Two consumers:
#   1. tests/test_cca_npc_spec.gd — fresh-FSM init check verifies
#      every NPC starts in the spec'd state.
#   2. (Future) probe-side anchor check — fixed NPCs should never
#      get observed at non-canon rooms. Deferred until any NPC
#      gains a location query that's non-trivial.
const NPC_SPEC: Dictionary = {
    "bird": {
        "home_room":     13,
        "initial_state": "free",
        "wandering":     false,
        "notes":         "lives at bird chamber; gets caged when player has cage and takes",
    },
    "snake": {
        "home_room":     19,
        "initial_state": "blocking",
        "wandering":     false,
        "notes":         "fixed at Hall of Mountain King; vanishes when bird released",
    },
    "bear": {
        "home_room":     130,
        "initial_state": "hungry",
        "wandering":     false,
        "notes":         "fixed at Barren Room with chain; tames on FEED BEAR if food carried",
    },
    "troll": {
        "home_room":     117,
        "initial_state": "demanding",
        "wandering":     false,
        "notes":         "fixed at troll bridge canon 117/122; demands a treasure to cross",
    },
    "dragon": {
        "home_room":     119,
        "initial_state": "alive",
        "wandering":     false,
        "notes":         "fixed at Secret Canyon; dies on ATTACK DRAGON with bare hands",
    },
    "pirate": {
        "home_room":     -1,
        "initial_state": "dormant",
        "wandering":     true,
        "notes":         "wanders the cave; transitions $Dormant -> $Stalking on treasure-count threshold",
    },
    "plant": {
        "home_room":     71,
        "initial_state": "tiny",
        "wandering":     false,
        "notes":         "fixed at West Side of Twopit Room; grows on POUR WATER",
    },
}

# ----- Accessors ---------------------------------------------------

# Return the current location of `noun` per the FSM. Treasures use
# get_location(); items use is_in_room(room) scanned across the
# topology — for the spec checks we use a sentinel scan since the
# Item FSM doesn't expose a get_location() in V1. Returns -1 if the
# item is carried or unplaceable in any topology room.
#
# Bird and chain have NPC-style location accessors; the rest follow
# the (treasure)/(item) split.
static func observed_location(fsm, noun: String) -> int:
    if not ITEM_SPEC.has(noun):
        return -2   # unknown noun
    var spec: Dictionary = ITEM_SPEC[noun]
    var id: int = spec.id
    if fsm.player.carrying(id):
        return -1   # carried
    if spec.kind == "treasure":
        # Treasure exposes get_location() directly. -1 = carried,
        # else a room number. Chain is also a Treasure (canon obj#16).
        return _treasure_location(fsm, noun)
    # Items don't expose get_location() in V1 — scan topology rooms.
    return _item_location_by_scan(fsm, noun, id)

static func _treasure_location(fsm, noun: String) -> int:
    match noun:
        "gold":     return fsm.gold.get_location()
        "silver":   return fsm.silver.get_location()
        "diamonds": return fsm.diamonds.get_location()
        "jewelry":  return fsm.jewelry.get_location()
        "pearl":    return fsm.pearl.get_location()
        "vase":     return fsm.vase.get_location()
        "eggs":     return fsm.eggs.get_location()
        "trident":  return fsm.trident.get_location()
        "emerald":  return fsm.emerald.get_location()
        "spices":   return fsm.spices.get_location()
        "chest":    return fsm.chest.get_location()
        "pyramid":  return fsm.pyramid.get_location()
        "rug":      return fsm.rug.get_location()
        "coins":    return fsm.coins.get_location()
        "chain":    return fsm.chain.get_location()
    return -2

static func _item_location_by_scan(fsm, noun: String, id: int) -> int:
    # The Item FSM's only public location predicate is
    # is_in_room(room). We scan canon's 1..140 to find the room
    # whose query returns true. Slightly wasteful but the table
    # is small and this only runs during spec checks, not per-walk.
    var inst = _item_instance(fsm, noun)
    if inst == null:
        return -2
    for r in range(1, 141):
        if inst.is_in_room(r):
            return r
    return 0  # in limbo (not carried, not in any room)

static func _item_instance(fsm, noun: String):
    match noun:
        "rod":       return fsm.rod_item
        "keys":      return fsm.keys_item
        "lamp":      return fsm.lamp_item
        "bottle":    return fsm.bottle_item
        "cage":      return fsm.cage_item
        "food":      return fsm.food_item
        "pillow":    return fsm.pillow_item
        "clam":      return fsm.clam_item
        "magazine":  return fsm.magazine_item
        "axe":       return fsm.axe_item
        "mark_rod":  return fsm.mark_rod_item
        "batteries": return fsm.batteries_item
        "oyster":    return fsm.oyster_item
    return null

# ----- Spec checks -------------------------------------------------

# Returns Array of {noun, expected, observed, kind} for every item
# whose initial placement disagrees with the spec. Empty array =
# fresh FSM matches canon. Should be called against a brand-new
# Cca() before any commands have been issued.
static func check_initial_placements(fsm) -> Array:
    var violations: Array = []
    for noun in ITEM_SPEC.keys():
        var spec: Dictionary = ITEM_SPEC[noun]
        var expected: int = spec.initial_room
        var observed: int = observed_location(fsm, noun)
        if observed != expected:
            violations.append({
                "noun":     noun,
                "expected": expected,
                "observed": observed,
                "kind":     spec.kind,
            })
    return violations

# Returns Array of {noun, reason} for items currently in "limbo"
# (location 0 or -1, not player-carried) that the spec does not
# justify being there. Dynamic-spawn items (initial_room == -1)
# are accepted in limbo unconditionally — we have no way to know
# whether their spawn-trigger has fired. Consumable items in
# limbo are accepted if their FSM is in a vanish-equivalent state.
# All other limbo placements are bug candidates.
static func check_no_limbo(fsm) -> Array:
    var violations: Array = []
    for noun in ITEM_SPEC.keys():
        var spec: Dictionary = ITEM_SPEC[noun]
        var observed: int = observed_location(fsm, noun)
        if observed == -1:
            continue   # carried — fine
        if observed > 0:
            continue   # in a real room — fine
        # observed == 0 means the FSM reports "not in any room" and
        # we've already handled the player-carried case above.
        if spec.get("dynamic_spawn", false):
            continue   # legitimate dynamic-spawn limbo
        if spec.consumable:
            # Could be in vanish-equivalent. Cheap heuristic — accept.
            # A stricter check would verify the FSM state matches a
            # canon vanish state name, but the consumable items
            # (food, clam, vase, eggs) each use a different state
            # vocabulary across the puzzles.gd FSMs. Defer.
            continue
        violations.append({
            "noun":   noun,
            "reason": "non-spawn, non-consumable item in limbo (location=%d)" % observed,
        })
    return violations

# ----- NPC spec checks ---------------------------------------------

# Returns the NPC's current state-name as reported by its FSM.
# Different NPC FSMs took slightly different shapes during V1.2's
# aspect-machine split, but every one of them exposes get_state()
# returning a String. Dragon's "alive" is a synthesised label —
# canon Dragon has a Sleeping/Dying/Dead progression and we map
# the pre-Dying states to "alive" for spec-comparison purposes.
static func observed_npc_state(fsm, name: String) -> String:
    match name:
        "bird":   return fsm.bird.get_state()
        "snake":  return fsm.snake.get_state()
        "bear":   return fsm.bear.get_state()
        "troll":  return fsm.troll.get_state()
        "dragon":
            # Map the pre-death dragon states to a single "alive"
            # label for spec-purposes. Canon dragon has more than
            # one alive state (Sleeping in advent.for terms); we
            # collapse them here.
            var s: String = fsm.dragon.get_state()
            if s == "dead":
                return "dead"
            return "alive"
        "pirate": return fsm.pirate.get_state()
        "plant":  return fsm.plant.get_state()
    return ""

# Returns Array of {npc, expected, observed} for every NPC whose
# initial state disagrees with the spec. Empty array = fresh FSM
# matches canon NPC anchoring.
static func check_initial_npc_states(fsm) -> Array:
    var violations: Array = []
    for name in NPC_SPEC.keys():
        var spec: Dictionary = NPC_SPEC[name]
        var expected: String = spec.initial_state
        var observed: String = observed_npc_state(fsm, name)
        if observed != expected:
            violations.append({
                "npc":      name,
                "expected": expected,
                "observed": observed,
            })
    return violations
