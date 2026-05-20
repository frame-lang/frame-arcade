# ============================================================
# cca_model_adapter.gd — CCA's binding to FrameStateChecker
# ============================================================
# Concrete FrameModelAdapter for Colossal Cave Adventure. This is
# the worked example of the generalization: the entire CCA
# domain is exposed to the domain-agnostic checker through these
# ~10 methods, and every method is a thin delegate to machinery
# that already exists (the Driver's parser/dispatch,
# Adventure.save_state/restore_state, Driver.list_actions_here).
#
# The point of the demonstration: because CCA is Frame-native,
# binding it to a model checker is a thin adapter, not a
# model-extraction project. save()/restore() are the FSM's own
# persistence; hash() reads query methods; enumerate_actions() is
# the affordance list the game already computes for its prober.
#
# reset_session() is the load-bearing override — it carries the
# incomplete-state-vector lesson (the prompts-state-leak): the
# modal prompt dispatcher lives on the Driver, outside
# fsm.save_state, so we re-derive it from world state after every
# restore.
# ============================================================
extends "res://scripts/frame_model_adapter.gd"

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")

# Carryable item IDs for the inventory component of the state
# vector. Mirrors state_space.gd's ITEM_IDS — the demo test
# cross-validates that this adapter reproduces state_space.gd's
# reachability count, which pins the two against drift.
const ITEM_IDS: Array = [
    100, 101, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
    120, 121, 122, 123, 130, 131, 132, 133, 134, 135, 136, 137,
    138, 139, 140, 141, 142,
]

var rng_seed: int = 42

# Optional milestone seed. If non-empty, make_root() restores the
# driver to this snapshot — the explorer then treats it as the
# initial state (directed search from a deep milestone, the
# remedy for BFS reachability-depth). Empty == canonical start.
var seed_bytes: PackedByteArray = PackedByteArray()

func _init(p_seed: int = 42):
    rng_seed = p_seed

func make_root():
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = rng_seed
    d._build_verb_synonyms_5()
    if not seed_bytes.is_empty():
        d.fsm.restore_state(seed_bytes)
    return d

func save(o) -> PackedByteArray:
    return o.fsm.save_state()

func restore(o, bytes: PackedByteArray) -> void:
    o.fsm.restore_state(bytes)

# THE incomplete-state-vector remedy. The PromptDispatcher is a
# Frame FSM but lives on the Driver, deliberately NOT composed
# onto Adventure's persistence envelope (documented in
# cca.fgd). So fsm.save_state doesn't capture it. After a
# restore we re-derive it from world state exactly as a fresh
# session would: idle unless the player is dead, in which case
# the revive prompt is re-offered.
func reset_session(o) -> void:
    o.prompts = Cca.PromptDispatcher.new()
    if o.fsm.player.get_state() == "dead":
        o.prompts.offer_revive()

# Enabled transitions = the canon-gated affordances the game
# computes for its prober, minus the "wild" parser-coverage
# entries (those self-loop and don't expand the frontier).
func enumerate_actions(o) -> Array:
    var out: Array = []
    for action in o.list_actions_here():
        if action.get("kind", "") == "wild":
            continue
        out.append(action)
    return out

func apply(o, action) -> void:
    o._process_input(String(action.get("input", "")))

# State vector: room + sorted inventory + NPC states + endgame
# phase. Score, lamp battery, and turn count are intentionally
# excluded — they are invariant-checked, not state-
# distinguishers (including them would explode the graph without
# adding reachability).
#
# Endgame phase is in the vector for a SUBTLE reason worth
# stating: winning (BLAST at the repository) is the transition
# in_repository → won, and it changes NOTHING about room,
# inventory, or NPCs. Without endgame in the hash the won state
# is indistinguishable from the pre-blast state, BFS dedup drops
# it, and the liveness query EF-won can never see the goal. A
# state vector adequate for REACHABILITY (room coverage) is not
# automatically adequate for LIVENESS (goal-reachability) —
# the vector must distinguish the proposition you're checking.
# During normal play endgame is uniformly "active", so this
# adds no extra states to the reachability search (the room
# count is unchanged — cross-validated against state_space.gd).
func state_hash(o) -> String:
    var inv: Array = []
    for id in ITEM_IDS:
        if o.fsm.player.carrying(id):
            inv.append(str(id))
    var f = o.fsm
    return "r=%d|i=%s|n=%s,%s,%s,%s,%s|e=%s" % [
        f.player_room(), "/".join(inv),
        f.bird.get_state(), f.snake.get_state(), f.bear.get_state(),
        f.troll.get_state(), f.pirate.get_state(),
        f.endgame_state(),
    ]

# Safety invariants (Lamport). Returns violation strings.
func invariants(o) -> Array:
    var f = o.fsm
    var out: Array = []
    var room: int = f.player_room()
    if room < 1 or room > 140:
        out.append("player_room %d out of range [1..140]" % room)
    if f.score() < -100:
        out.append("score %d below sanity floor" % f.score())
    var deposits: int = f.treasures_deposited()
    if deposits < 0 or deposits > 15:
        out.append("treasures_deposited %d out of [0..15]" % deposits)
    var es: String = f.endgame_state()
    if not (es in ["active", "closing", "in_repository", "won", "permadead"]):
        out.append("unknown endgame state '%s'" % es)
    return out

# Observable signature for bisimulation: the state vector PLUS
# the host-side prompt state the hash omits. This is what makes
# the restore-soundness check able to SEE an incomplete state
# vector — if reset_session were removed, a leaked prompt would
# diverge `observe` even though `hash` matched.
func observe(o) -> String:
    return "%s|prompt=%s/%s|player=%s" % [
        state_hash(o), o.prompts.is_active(), o.prompts.current_prompt(),
        o.fsm.player.get_state(),
    ]

# Convenience predicates for liveness queries.
func is_won(o) -> bool:
    return o.fsm.endgame_state() == "won"
