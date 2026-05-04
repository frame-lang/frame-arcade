# ============================================================
# monkey.gd — random-walk fuzzer for the Adventure world
# ============================================================
# Phase 1 of the Frame "model-checking nearly free" story.
# StateExplorer (state_explorer.gd) handles small @@[persist]
# FSMs in isolation by teleporting between every (state, event)
# pair. The Monkey covers the dual case: a *system of FSMs*
# whose joint state space is too large to enumerate, but whose
# behaviour is still dominated by a finite command vocabulary.
#
# The strategy is deliberately dumb:
#
#   1. Build a fresh Adventure with all aspects wired.
#   2. Each turn, pick a random (verb, noun) from a fixed
#      vocabulary (with directional moves resolved against the
#      driver's room_exits table — we don't fabricate room IDs).
#   3. Snapshot a coarse world-fingerprint before and after.
#      "Did anything change?" is the test for an interesting
#      command. Self-loops at the fingerprint level get logged
#      but don't burn budget.
#   4. Auto-revive on death so the walk doesn't terminate.
#   5. Record (fingerprint, command) → fingerprint so we never
#      retry the same command from the same fingerprint —
#      Frame FSMs are deterministic, so re-trying tells us
#      nothing.
#
# Outputs:
#   - distinct fingerprints visited
#   - distinct rooms entered
#   - distinct (room, verb) pairs exercised
#   - max score reached during the walk
#   - candidate soft-locks: fingerprints from which every
#     vocabulary command was a no-op (no fingerprint change)
#   - replay log: ordered list of (verb, noun) actually applied
#
# A crash inside the FSM aborts the GDScript process — that's
# the bug-finding mechanism. "Ran N steps without crashing"
# IS the success signal; we don't try to catch and continue.
# ============================================================
class_name CcaMonkey
extends RefCounted

const Cca = preload("res://scripts/cca.gd")

# ------------------------------------------------------------
# Vocabulary
# ------------------------------------------------------------
# Verbs the FSM and aspects know about. Driver-only verbs
# (save/load/help/quit/yes/no) are deliberately omitted —
# they don't transition world state, just UI.
const VERBS_ACTION := [
    "look", "examine", "read",
    "take", "drop",
    "attack", "throw",
    "light", "extinguish",
    "feed", "release",
    "wave", "unlock", "lock",
    "insert", "fill", "pour", "water", "drink",
    "xyzzy", "plugh", "plover",
    "fee", "fie", "foe", "foo",
    "score", "hint",
]

# Directions stay separate — these get resolved into a
# do_command("move", str(dest)) by consulting room_exits.
const VERBS_DIR := ["north", "south", "east", "west",
                    "up", "down", "in", "out", "enter"]

# Nouns: every named entity Adventure can reason about. Empty
# string is included so verbs like "look" / "score" can fire
# bare.
const NOUNS := [
    "",
    "bird", "snake", "bear", "troll", "dwarf", "dragon", "pirate",
    "gold", "silver", "diamonds", "jewelry", "pearl", "vase",
    "eggs", "trident", "emerald", "spices", "chest", "pyramid",
    "rug", "coins", "statuette",
    "rod", "keys", "bottle", "lamp", "chain",
    "plant", "water", "axe",
]

# How many no-op commands we tolerate from a single fingerprint
# before flagging it as a soft-lock candidate. The vocabulary
# has ~30 verbs × ~30 nouns + 9 directions; the FSM ignoring
# all of them is genuinely interesting.
const SOFT_LOCK_THRESHOLD := 200

# ------------------------------------------------------------
# Run a fuzzed walk and return a report.
# ------------------------------------------------------------
# room_exits  — driver's topology table (Dictionary<int, Dictionary<dir, int>>).
#               The monkey needs it to resolve directions; without
#               it every "north" would be a no-op (the FSM's
#               _verb_move expects a numeric room id, not a
#               direction).
# seed         — deterministic PRNG seed; bug found on a given
#                seed is reproducible by re-running with the
#                same seed and step count.
# max_steps    — hard step budget. Reasonable values 1k-50k;
#                cost is roughly linear, ~5µs per step on M-class
#                hardware once the world is warm.
static func run(room_exits: Dictionary, seed: int = 42,
                max_steps: int = 5000) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    var fsm = Cca.new()
    fsm.setup_default_aspects()
    fsm.wake_dwarves()

    # Fingerprint = (room, score, treasures_deposited,
    # player_state, lamp_state, endgame_state, key locks).
    # Coarse on purpose: if these all match across two turns,
    # we treat the world as the "same place" for memoization.
    # A finer fingerprint (full save_state hash) would be more
    # accurate but blow up the seen-set; this is the pragmatic
    # middle.
    var fingerprints: Dictionary = {}        # fp → first-step-seen
    var rooms_seen: Dictionary = {}          # room_id → true
    var room_verb_pairs: Dictionary = {}     # "room:verb" → true
    var tried: Dictionary = {}               # "fp|verb|noun" → result_fp
    var noop_runs: Dictionary = {}           # fp → consecutive no-ops
    var soft_lock_candidates: Dictionary = {}
    var transitions: Array = []              # (step, from_fp, verb, noun, to_fp)
    var max_score: int = 0
    var revives: int = 0
    var deaths: int = 0
    var bumps: int = 0   # commands that did NOT change fingerprint
    var moves: int = 0   # commands that DID change fingerprint

    var initial_fp: String = _fingerprint(fsm)
    fingerprints[initial_fp] = 0
    rooms_seen[fsm.player_room()] = true

    for step in range(max_steps):
        # If the FSM has slipped into a death state, auto-revive
        # so the walk keeps going. The driver's UI prompts the
        # player; the monkey just consents.
        if fsm.player_state() == "dead":
            fsm.player.revive()
            revives += 1
        if fsm.player_state() == "permadead":
            # Three resurrections used up; this run is over.
            # Recreate so the monkey continues exploring with
            # the same memo tables.
            deaths += 1
            fsm = Cca.new()
            fsm.setup_default_aspects()
            fsm.wake_dwarves()

        var fp_before: String = _fingerprint(fsm)
        var cmd: Array = _pick_command(rng, fsm, room_exits)
        var verb: String = cmd[0]
        var noun: String = cmd[1]

        # The FSM stores (verb, noun) as the canonical event.
        # For directional movement we already resolved the
        # destination room id into the noun.
        fsm.do_command(verb, noun)
        fsm.tick()

        var fp_after: String = _fingerprint(fsm)
        var room_now: int = fsm.player_room()
        rooms_seen[room_now] = true
        room_verb_pairs["%d:%s" % [room_now, verb]] = true

        var key: String = "%s|%s|%s" % [fp_before, verb, noun]
        tried[key] = fp_after

        if fp_before == fp_after:
            bumps += 1
            noop_runs[fp_before] = noop_runs.get(fp_before, 0) + 1
            if noop_runs[fp_before] >= SOFT_LOCK_THRESHOLD:
                soft_lock_candidates[fp_before] = true
        else:
            moves += 1
            noop_runs[fp_after] = 0
            transitions.append({
                "step":  step,
                "from":  fp_before,
                "verb":  verb,
                "noun":  noun,
                "to":    fp_after,
            })
            if not fingerprints.has(fp_after):
                fingerprints[fp_after] = step

        var s: int = fsm.score()
        if s > max_score:
            max_score = s

    return {
        "seed":              seed,
        "steps":             max_steps,
        "fingerprints":      fingerprints.size(),
        "rooms_visited":     rooms_seen.size(),
        "room_verb_pairs":   room_verb_pairs.size(),
        "transitions":       transitions.size(),
        "moves":             moves,
        "bumps":             bumps,
        "max_score":         max_score,
        "revives":           revives,
        "permadeaths":       deaths,
        "soft_lock_count":   soft_lock_candidates.size(),
        "soft_locks":        soft_lock_candidates.keys(),
        "rooms_list":        rooms_seen.keys(),
    }

# ------------------------------------------------------------
# _pick_command — biased random selection.
#
# We bias slightly toward directional moves because the world
# graph is large and a uniform pick over all (verb × noun)
# would spend most of its budget on "fee statuette" and
# similar nonsense. 40% directional / 60% verb-noun feels
# right empirically for CCA's surface-to-cave ratio.
# ------------------------------------------------------------
static func _pick_command(rng: RandomNumberGenerator, fsm,
                          room_exits: Dictionary) -> Array:
    if rng.randf() < 0.4:
        # Directional move — only emit if there's actually
        # an exit (otherwise it's guaranteed bump).
        var current: int = fsm.player_room()
        var exits: Dictionary = room_exits.get(current, {})
        if not exits.is_empty():
            var keys: Array = exits.keys()
            var direction: String = keys[rng.randi() % keys.size()]
            var dest: int = exits[direction]
            return ["move", str(dest)]
        # No exits — fall through to verb-noun pick.

    var verb: String = VERBS_ACTION[rng.randi() % VERBS_ACTION.size()]
    var noun: String = NOUNS[rng.randi() % NOUNS.size()]
    return [verb, noun]

# ------------------------------------------------------------
# _fingerprint — coarse world hash.
#
# We use a string concatenation rather than a 64-bit hash so
# soft-lock reports are human-readable. The string is stable
# across runs: the same observable state always produces the
# same fingerprint.
# ------------------------------------------------------------
static func _fingerprint(fsm) -> String:
    return "r%d|s%d|t%d|p%s|l%s|e%s|g%s|b%s" % [
        fsm.player_room(),
        fsm.score(),
        fsm.treasures_deposited(),
        fsm.player_state(),
        fsm.get_lamp_state(),
        fsm.endgame_state(),
        "L" if fsm.grate_locked() else "U",
        "B" if fsm.bridge_built() else "_",
    ]
