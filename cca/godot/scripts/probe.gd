# ============================================================
# probe.gd — LFU-biased coverage walker for CCA
# ============================================================
# Phase 2 of the model-checking story (Phase 1 = state_space.gd's
# BFS, Phase 0 = monkey.gd's uniform-random fuzz). The probe sits
# between them: it walks the world through the real Driver
# command path (not the FSM directly), picks the least-frequently-
# actuated action available at each step (random tiebreak), and
# accumulates a global (room, action) coverage table across many
# walks.
#
# Strategy:
#
#   1. Build a fresh CapturedDriver per walk (preserves
#      determinism, drops output to /dev/null).
#   2. At each step, ask the driver "what can the player do
#      here?" via list_actions_here(). Each entry has an `input`
#      string ("light lamp"), a stable coverage `key`
#      ("light:lamp"), and a `kind` for reporting.
#   3. Look up coverage for "<room>:<key>" — pick the action(s)
#      with the smallest count, break ties uniformly at random.
#   4. Feed action.input through the driver's text pipeline
#      (driver._process_input) exactly as a real player would.
#   5. Increment the coverage counter.
#   6. Terminate the walk on permadeath, victory (endgame won),
#      or step cap. Auto-revive on the first two deaths so the
#      walk doesn't end on every drowning.
#
# The bias toward unexplored (room, action) pairs is the key
# difference vs. monkey.gd: a uniform random walker spends most
# of its budget re-actuating common verbs at common rooms. LFU
# steers toward the long tail — which is where canon corners
# live.
#
# Run cost: each walk does ~500 steps at ~1ms per driver
# command. 100 walks ≈ 50 sec; 1000 walks ≈ 8 min. The hash table
# grows to thousands of entries; memory is not a concern.
#
# Determinism: the probe takes one master seed. Per-walk RNG
# seeds derive from `master_seed + walk_idx`, so reruns are
# reproducible. The tiebreak RNG accumulates state across walks
# (otherwise every walk would pick the same tied action from the
# same starting state).
# ============================================================
extends RefCounted

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const H = preload("res://scripts/_test_helpers.gd")
const WorldGraph = preload("res://scripts/world_graph.gd")

# ----- Configuration -----------------------------------------------

# Master seed for single-sweep runs (backward compatibility). Per-
# walk seeds derive as `master_seed + walk_idx`. If `seeds` below is
# non-empty, this field is overwritten per sweep — leave it alone
# in multi-seed mode.
var master_seed: int = 0

# Multi-seed sweep list. Each value runs `walk_count` walks with
# that seed as the per-sweep master; coverage and the learned
# graph accumulate across sweeps. The pooling is intentional —
# later sweeps see what earlier ones already covered and are
# pushed by LFU toward fresher cells.
#
# Why multi-seed: CCA has probabilistic branches (Witt's End 95/5,
# dark-pit 35%, dwarf walks, pirate stalking) that under a single
# seed collapse to one rolled outcome per turn. Varying the seed
# unfolds different slices of the probabilistic space; the graph
# unions them. Empty list = single sweep using `master_seed`.
var seeds: Array = []

# Per-walk hard step cap. Canon's WTF threshold is ~500 turns
# before nags start; 500 keeps each walk well within "normal"
# game length.
var max_steps_per_walk: int = 500

# Walks to run per sweep. Total walks = walk_count × max(seeds.size(), 1).
var walk_count: int = 100

# If true, auto-revive on death (so a walk can survive multiple
# deaths before terminating). If false, the walk ends on the
# first death.
var auto_revive: bool = true

# Maximum revives per walk before we let it die. Canon allows 3
# revives before permadeath; matching that here means a walk
# effectively ends after the 4th death.
var max_revives_per_walk: int = 3

# ----- Results ------------------------------------------------------

# coverage["<room>:<action_key>"] → count of times exercised.
# The single namespace key keeps the table flat and easy to
# serialise; reports group by room/kind at print time.
var coverage: Dictionary = {}

# rooms_seen[room_id] → count of turns where the player started
# the step in that room. Independent of coverage so we can
# report "room visited at all" separately from "room exercised
# with every available verb".
var rooms_seen: Dictionary = {}

# Per-walk termination accounting.
var walks_run: int = 0
var deaths: int = 0
var permadeaths: int = 0
var victories: int = 0
var step_cap_hits: int = 0
var stuck_walks: int = 0   # walk where list_actions_here() returned empty

# Aggregate stats.
var max_score: int = 0
var total_steps: int = 0
var actions_taken: int = 0   # total LFU picks executed
var sweeps_run: int = 0      # number of master-seed values exercised
var seeds_used: Array = []   # the actual seeds, in run order

# Trace of the most-recent walk — list of "room:action" strings.
# Useful when debugging a walk that crashed or ended unexpectedly.
var last_trace: Array = []

# Passive automata learner. Each step of every walk records one
# (from_state, action, to_state) observation; over many walks the
# graph fills in an explicit transition model of the reachable
# world. See world_graph.gd for the lineage (L*/RPNI). The graph
# is the artifact that lets future work do shortest-path routing
# to under-explored cells instead of relying purely on local LFU
# tie-breaking.
var graph: WorldGraph = WorldGraph.new()

# ----- Go-Explore archive (Phase B) --------------------------------
# Ecoffet et al. 2019 / Nature 2021. The insight that cracked
# Montezuma's Revenge: don't always start from the canonical state.
# Save promising states to an archive, then at walk-start sample
# one and `restore_state` to it. The walker skips the boring
# prefix and spends its budget exploring from the frontier.
#
# Each archive entry is keyed by state_hash and remembers:
#   bytes        — fsm.save_state() snapshot, ready for restore
#   trajectory   — action_keys from canonical root to this state
#                  (concatenation: parent's trajectory + walk path)
#   score        — score at the moment this cell was archived
#   visit_count  — how many times the probe restored from this cell
#   room         — which room this state's in (for diagnostics)
# The trajectory is what makes "I won" actionable — once we
# observe a victory cell, we have the full action sequence that
# produced it.
var archive: Dictionary = {}

# Probability a walk starts from an archive sample rather than
# canonical. 0.7 is the Go-Explore default; bumped higher when
# the goal is gameplay completion ASAP (exploitation-heavy).
var archive_return_prob: float = 0.8

# Top-K bias for archive sampling. With probability `topk_prob`,
# sample uniformly from the top 20% of cells by score; otherwise
# sample uniformly across the whole archive. The two-mode scheme
# avoids the weighted-sum failure where 99% of cells are at score 0
# and sheer count overwhelms any per-cell score weighting. With
# user goal "conclude gameplay as fast as possible," exploitation
# of the high-score frontier dominates.
var archive_topk_prob: float = 0.7

# RNG for archive sampling. Independent so per-sweep determinism
# is preserved.
var _archive_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ----- Trajectories of interest ------------------------------------
# Best score reached on any walk and the action sequence that led
# there. Updated whenever a walk's score exceeds the running max.
var best_score_trajectory: Array = []
var best_score_walk: int = -1

# First victory observed. If `first_victory_walk` stays at -1 the
# probe never won. When it fires, `first_victory_trajectory` is the
# replayable action sequence from canonical root to victory.
var first_victory_walk: int = -1
var first_victory_trajectory: Array = []
var first_victory_steps: int = -1

# If true, the run stops at the first observed victory. With user
# goal "conclude gameplay as fast as possible" this avoids burning
# budget after the goal is reached.
var stop_on_victory: bool = true

# ----- Graph-routed coverage permutation (Phase B.2) ---------------
# The pure LFU walker keeps re-discovering the same prefix every
# walk (well-house → take items → walk to grate → ...). Once the
# world graph has those edges recorded, we can SHORT-CIRCUIT the
# prefix: pick an under-tested target cell, BFS-shortest-path to it
# via the graph, replay the plan, then exercise broad parser
# coverage at the target state.
#
# This is "graph-routed coverage permutation" — the routing is the
# navigation primitive, the storm at the target is the coverage
# multiplier. The save/restore-around-each-storm-action exercises
# N action paths from a single anchor state, which is the unique
# advantage white-box FSM access gives us over RL/Jericho-style
# agents (they can't atomically rewind state).
var routed_walk_prob: float = 0.35     # fraction of walks that take the routed path
var storm_size: int = 25               # max actions to fire per storm at target

# Per-run stats for the routing/storm path.
var routed_walks: int = 0              # walks that took the routed path
var storm_actions: int = 0             # actions exercised via the storm primitive
var routing_failures: int = 0          # routed walks where shortest_path returned empty

# Tiebreak RNG. Persists across walks so two structurally
# identical walks at different points in the run pick different
# tied actions.
var _tiebreak_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ----- Entry points -------------------------------------------------

# Run `walk_count` walks per sweep. If `seeds` is non-empty, runs
# one sweep per seed; otherwise runs a single sweep using
# `master_seed`. Coverage and the world graph pool across sweeps —
# sweep N starts with LFU bias informed by sweeps 1..N-1, so its
# walks are pushed toward cells the earlier sweeps under-exercised.
# Tiebreak RNG resets per sweep so individual sweeps remain
# reproducible given the same prior history.
func run() -> void:
    var seed_list: Array = seeds if not seeds.is_empty() else [master_seed]
    seeds_used = seed_list.duplicate()
    for seed in seed_list:
        master_seed = seed
        _tiebreak_rng.seed = seed
        _archive_rng.seed = seed ^ 0x5a5a5a5a
        for w in range(walk_count):
            _walk(w)
            walks_run += 1
            if stop_on_victory and first_victory_walk >= 0:
                # Early termination — user goal is gameplay completion ASAP.
                sweeps_run += 1
                return
        sweeps_run += 1

# Build a headless driver and walk it for up to max_steps_per_walk
# steps. Walk-local state (revive count, current trace) lives in
# locals; cross-walk aggregate state lives on `self`.
func _walk(walk_idx: int) -> void:
    var driver: H.CapturedDriver = _make_driver(walk_idx)
    last_trace = []
    var revives_left: int = max_revives_per_walk

    # Go-Explore "Go" phase: with probability `archive_return_prob`,
    # restore from a sampled archive cell instead of starting from
    # canonical. The walker spends its budget exploring from the
    # frontier rather than rediscovering XYZZY and the well-house
    # item-pickup sequence every walk.
    var trajectory_prefix: Array = []
    if not archive.is_empty() and _archive_rng.randf() < archive_return_prob:
        var sampled_hash: String = _sample_archive_cell()
        if sampled_hash != "":
            var cell: Dictionary = archive[sampled_hash]
            driver.fsm.restore_state(cell.bytes)
            cell.visit_count += 1
            trajectory_prefix = cell.trajectory.duplicate()

    # Phase B.2: routed coverage permutation. With probability
    # `routed_walk_prob`, BFS-route to an under-tested cell and
    # storm-test it before falling back into the normal LFU walk.
    # This is the "use the graph" leg of the hybrid walker —
    # exploration's discoveries get exploited via the route, and
    # the storm exercises broad parser coverage at the anchor.
    var routed_actions_used: int = 0
    if archive.size() >= 30 and _archive_rng.randf() < routed_walk_prob:
        routed_actions_used = _routed_walk_phase(driver, walk_idx)

    for step in range(max_steps_per_walk - routed_actions_used):
        total_steps += 1

        # Termination checks BEFORE the action — covers cases
        # where the previous step pushed us into a terminal
        # state (victory, permadeath) and we haven't recorded it
        # yet.
        var endgame: String = driver.fsm.endgame_state()
        if endgame == "won":
            victories += 1
            if first_victory_walk < 0:
                first_victory_walk = walks_run
                first_victory_trajectory = trajectory_prefix + last_trace.duplicate()
                first_victory_steps = first_victory_trajectory.size()
            return
        if driver.fsm.player_state() == "permadead":
            permadeaths += 1
            return

        # Death handling — Player FSM is in $Dead. Auto-revive if
        # we have revives left and auto_revive is on; otherwise
        # the walk ends here.
        if driver.fsm.player_state() == "dead":
            deaths += 1
            if auto_revive and revives_left > 0:
                revives_left -= 1
                driver.fsm.player.revive()
            else:
                return

        # Some driver code paths open a modal Y/N prompt
        # (PromptDispatcher) that swallows the next non-y/n input
        # with "Please answer the question." The prober isn't
        # equipped to navigate those, so we proactively consent
        # (yes to revive, no to anything else) to keep the walk
        # moving. Done as a peek-and-answer before action pick
        # so coverage stays attached to actual world verbs.
        if driver.prompts.is_active():
            var prompt_name: String = driver.prompts.current_prompt()
            # Revive prompts shouldn't fire if we already handled
            # the "dead" branch above, but guard defensively.
            var answer: String = "yes" if prompt_name == "revive" else "no"
            driver._process_input(answer)
            continue

        var room: int = driver.fsm.player_room()
        rooms_seen[room] = rooms_seen.get(room, 0) + 1

        var available: Array = driver.list_actions_here()
        if available.is_empty():
            # The introspection emits LOOK unconditionally, so an
            # empty list means the FSM is in a state where even
            # the room lookup failed. Flag and end the walk.
            stuck_walks += 1
            return

        var action: Dictionary = _pick_lfu(available, room)
        var cov_key: String = "%d:%s" % [room, action.key]
        coverage[cov_key] = coverage.get(cov_key, 0) + 1
        last_trace.append(cov_key)
        actions_taken += 1

        # Snapshot before the action for graph recording. We hash
        # AFTER reading `room` above so the from_room and
        # from_hash agree even on rapid revisits.
        var from_hash: String = _state_hash(driver, room)

        driver._process_input(action.input)

        # Snapshot after. The pair (from_hash, action.key, to_hash)
        # is the L*-style observation: one membership-query answer
        # in the world automaton's transition table.
        var to_room: int = driver.fsm.player_room()
        var to_hash: String = _state_hash(driver, to_room)
        graph.record(from_hash, room, action.key, to_hash, to_room)

        var score: int = driver.fsm.score()
        if score > max_score:
            max_score = score
            best_score_trajectory = trajectory_prefix + last_trace.duplicate()
            best_score_walk = walks_run

        # Archive any newly-observed cell. The bytes + trajectory
        # together are what makes the cell *replayable*: restore
        # the bytes for fast return, or replay the trajectory from
        # canonical for trust verification.
        if not archive.has(to_hash):
            archive[to_hash] = {
                "bytes": driver.fsm.save_state(),
                "trajectory": trajectory_prefix + last_trace.duplicate(),
                "score": score,
                "visit_count": 0,
                "room": to_room,
            }

        # Victory check inline — `won` state can transition mid-step
        # (e.g. BLAST in repository). Catching it here saves us a
        # whole extra iteration of dead-state handling above.
        if driver.fsm.endgame_state() == "won":
            victories += 1
            if first_victory_walk < 0:
                first_victory_walk = walks_run
                first_victory_trajectory = trajectory_prefix + last_trace.duplicate()
                first_victory_steps = first_victory_trajectory.size()
            return

    step_cap_hits += 1

# ----- LFU action picker --------------------------------------------

# Pick the action with the smallest coverage count at `room`,
# breaking ties uniformly at random. Cost is O(actions); the
# action list at any room is bounded (~10-30) so this is cheap
# even with thousands of coverage entries.
# Sample an archive cell using a top-K scheme. The naive weighted-
# sum approach gets swamped when 99% of cells are at score 0 and
# only 1 cell is at score 30 — even with a 20× score weight the
# sheer count of zero-score cells dominates. Top-K fixes this by
# committing some fraction of samples to the highest-scoring cells
# unconditionally.
#
# Behaviour:
#   archive_topk_prob (0.7) — sample from the top 20% by score
#   1 - archive_topk_prob  — sample anywhere (LFU-style fallback)
#
# This is the Go-Explore "prioritised sampling" recipe (Ecoffet
# 2019 §3.2) adapted for a discrete-score domain. The fallback
# slice prevents starvation when the high-score frontier is a
# dead end and the walker needs to back off to a different region.
func _sample_archive_cell() -> String:
    if archive.is_empty():
        return ""
    if _archive_rng.randf() < archive_topk_prob:
        # Top-K branch: sort by score (desc), pick from the top 20%.
        # Cheap enough — archive is bounded by reachable cells.
        var sorted_keys: Array = archive.keys()
        sorted_keys.sort_custom(func(a, b): return archive[a].score > archive[b].score)
        var topk: int = max(1, sorted_keys.size() / 5)
        return sorted_keys[_archive_rng.randi() % topk]
    # Fallback branch: uniform random over the whole archive.
    var keys: Array = archive.keys()
    return keys[_archive_rng.randi() % keys.size()]

# Pick an under-tested archive cell as a routing target. Priority
# order:
#   1. Cells dangling in the graph (observed as targets but never
#      explored from) — these are the L*-style frontier states; we
#      *know* they're reachable but never tried any actions from
#      them. Highest coverage payoff per visit.
#   2. Cells with the fewest distinct actions tried (i.e. fewer
#      outgoing edges in the graph). These are under-permuted —
#      we've been there but exercised only a subset of the
#      available vocabulary.
#   3. Cells with the lowest visit_count in the archive (the
#      classical LFU-on-cells signal).
# Returns "" if no candidates exist (e.g. archive empty).
func _pick_routing_target() -> String:
    if archive.is_empty():
        return ""
    var dangling: Array = graph.dangling_states()
    if not dangling.is_empty():
        # Filter to ones we have archive entries for (some danglings
        # are observed-as-targets but not yet archived because they
        # were observed as `to_hash` only, never as `from_hash`).
        var archived_dangling: Array = []
        for h in dangling:
            if archive.has(h):
                archived_dangling.append(h)
        if not archived_dangling.is_empty():
            return archived_dangling[_archive_rng.randi() % archived_dangling.size()]
    # Fewest-distinct-actions next. Cheap to compute against the
    # transitions table.
    var best_hash: String = ""
    var best_action_count: int = 0x7fffffff
    for h in archive:
        var n_actions: int = 0
        if graph.transitions.has(h):
            n_actions = graph.transitions[h].size()
        if n_actions < best_action_count:
            best_action_count = n_actions
            best_hash = h
    return best_hash

# Fire `storm_size` distinct actions from a single anchor state,
# rewinding with restore_state between each. Each storm action
# records a coverage cell + a graph edge, but doesn't progress
# world state — the rewind is what makes this "permutation
# testing at one state" rather than "exploration from one state."
#
# Returns the number of actions actually fired (may be less than
# storm_size if the anchor state has fewer available actions).
func _action_storm(driver: H.CapturedDriver, anchor_bytes: PackedByteArray) -> int:
    var anchor_room: int = driver.fsm.player_room()
    var anchor_hash: String = _state_hash(driver, anchor_room)
    var available: Array = driver.list_actions_here()
    if available.is_empty():
        return 0
    # Shuffle so the storm exercises a random subset each visit
    # rather than the same first N actions every time.
    var indices: Array = []
    for i in range(available.size()):
        indices.append(i)
    # Fisher-Yates shuffle using the deterministic tiebreak RNG.
    for i in range(indices.size() - 1, 0, -1):
        var j: int = _tiebreak_rng.randi() % (i + 1)
        var tmp = indices[i]
        indices[i] = indices[j]
        indices[j] = tmp

    var fired: int = 0
    var limit: int = min(storm_size, available.size())
    for k in range(limit):
        var action: Dictionary = available[indices[k]]
        var cov_key: String = "%d:%s" % [anchor_room, action.key]
        coverage[cov_key] = coverage.get(cov_key, 0) + 1
        actions_taken += 1
        fired += 1

        driver._process_input(action.input)

        var to_room: int = driver.fsm.player_room()
        var to_hash: String = _state_hash(driver, to_room)
        graph.record(anchor_hash, anchor_room, action.key, to_hash, to_room)

        # Archive the storm's observed destination if novel.
        if not archive.has(to_hash):
            archive[to_hash] = {
                "bytes": driver.fsm.save_state(),
                "trajectory": [],   # storm cells don't have a clean trajectory
                "score": driver.fsm.score(),
                "visit_count": 0,
                "room": to_room,
            }

        # Rewind to the anchor for the next storm action. This is
        # the move RL/Jericho agents cannot make.
        driver.fsm.restore_state(anchor_bytes)
    return fired

# A routed walk: route to an under-tested cell, storm-test it, then
# resume normal LFU exploration from there. The split makes the
# walk's budget useful for coverage permutation even when the
# walker is deep in an explored region — instead of cycling
# through LFU at a saturated cell, it gets transported to a
# fresh frontier and exercises broad parser coverage.
#
# Returns the number of actions consumed (route length + storm)
# so the caller can deduct from the remaining step budget.
func _routed_walk_phase(driver: H.CapturedDriver, walk_idx: int) -> int:
    routed_walks += 1
    var target_hash: String = _pick_routing_target()
    if target_hash == "":
        routing_failures += 1
        return 0
    # Plan the route via BFS over the learned graph.
    var current_room: int = driver.fsm.player_room()
    var current_hash: String = _state_hash(driver, current_room)
    var plan: Array = graph.shortest_path(current_hash, target_hash)
    if plan.is_empty():
        routing_failures += 1
        return 0
    # Replay the plan. Each step is exercised the same way a
    # normal walk step would be — list_actions_here, find the
    # action whose key matches the plan's next step, fire it.
    # If the action isn't currently available (graph stale,
    # probabilistic divergence, etc.) abort the replay and let
    # the LFU walker take over.
    var actions_used: int = 0
    for action_key in plan:
        var room: int = driver.fsm.player_room()
        var available: Array = driver.list_actions_here()
        var match_action: Dictionary = {}
        for a in available:
            if a.key == action_key:
                match_action = a
                break
        if match_action.is_empty():
            break
        var from_hash: String = _state_hash(driver, room)
        var cov_key: String = "%d:%s" % [room, action_key]
        coverage[cov_key] = coverage.get(cov_key, 0) + 1
        actions_taken += 1
        actions_used += 1
        driver._process_input(match_action.input)
        var to_room: int = driver.fsm.player_room()
        var to_hash: String = _state_hash(driver, to_room)
        graph.record(from_hash, room, action_key, to_hash, to_room)
    # Storm at the (best-effort) target.
    var anchor_bytes: PackedByteArray = driver.fsm.save_state()
    var fired: int = _action_storm(driver, anchor_bytes)
    storm_actions += fired
    actions_used += fired
    return actions_used

func _pick_lfu(available: Array, room: int) -> Dictionary:
    var min_count: int = 0x7fffffff
    var candidates: Array = []
    for action in available:
        var key: String = "%d:%s" % [room, action.key]
        var c: int = coverage.get(key, 0)
        if c < min_count:
            min_count = c
            candidates = [action]
        elif c == min_count:
            candidates.append(action)
    # Movement-preferred tiebreak. With wild verb emission at ~150
    # actions per state, the walker can spend most of its budget
    # cycling through `examine X / wave Y` at every room before
    # leaving. Biasing ties toward `kind == "move"` makes the
    # walker traverse rooms faster, which is what we need to
    # populate the archive with deep cells and reach victory. If
    # there are no movement actions tied at the minimum, fall back
    # to the full tied set (and uniform random among them).
    var move_only: Array = []
    for action in candidates:
        if action.kind == "move":
            move_only.append(action)
    var pool: Array = move_only if not move_only.is_empty() else candidates
    return pool[_tiebreak_rng.randi() % pool.size()]

# ----- Driver construction ------------------------------------------

# Build a CapturedDriver suitable for a probe walk. Output goes
# into a captured array (discarded after the walk); FSM gets a
# per-walk deterministic seed.
func _make_driver(walk_idx: int) -> H.CapturedDriver:
    var d: H.CapturedDriver = H.CapturedDriver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.wake_dwarves()
    d.prompts = Cca.PromptDispatcher.new()
    # CapturedDriver overrides _println but the rest of the
    # driver still touches input/output sometimes — provide
    # stubs so we don't crash on a stray reference.
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = (master_seed + walk_idx) & 0x7fffffff
    d._build_verb_synonyms_5()
    return d

# ----- Reporting ----------------------------------------------------

# Top-line summary. Prints walk-level stats + coverage breadth.
# Callers can also inspect `coverage` directly for finer-grained
# slicing.
func report() -> void:
    if seeds_used.size() > 1:
        print("=== CCA probe report (%d sweeps, seeds=%s) ===" % [
            sweeps_run, str(seeds_used)])
    else:
        var only_seed: int = seeds_used[0] if seeds_used.size() > 0 else master_seed
        print("=== CCA probe report (seed=%d) ===" % only_seed)
    print("Sweeps run:      %d  (one per seed)" % sweeps_run)
    print("Walks run:       %d  (%d per sweep)" % [walks_run, walk_count])
    print("Total steps:     %d  (cap %d/walk)" % [total_steps, max_steps_per_walk])
    print("Actions taken:   %d" % actions_taken)
    print("Rooms visited:   %d  / 140 canon" % rooms_seen.size())
    print("Coverage cells:  %d  (distinct room/action pairs)" % coverage.size())
    print("Max score:       %d" % max_score)
    print("Archive cells:   %d  (Go-Explore: distinct states snapshotted)" % archive.size())
    print("Routed walks:    %d  (BFS-routed to under-tested target cells)" % routed_walks)
    print("Routing fails:   %d  (target unreachable in graph; fell back to LFU)" % routing_failures)
    print("Storm actions:   %d  (save/restore-rewound permutations at target anchors)" % storm_actions)
    if first_victory_walk >= 0:
        print("VICTORY:         walk #%d, %d-step trajectory" % [
            first_victory_walk, first_victory_steps])
    else:
        print("Victory:         not reached in this run")
    print("")
    print("Walk outcomes:")
    print("  victories:     %d" % victories)
    print("  step-caps:     %d" % step_cap_hits)
    print("  permadeaths:   %d" % permadeaths)
    print("  stuck walks:   %d" % stuck_walks)
    print("  total deaths:  %d  (auto-revived where possible)" % deaths)

# Print the (room, action) pairs that were exercised the fewest
# times. `limit` truncates the list. With LFU the bottom is
# normally everything-at-1 (touched once each); the value is in
# seeing what's *still* at zero after K walks.
func report_least_actuated(limit: int = 20) -> void:
    var sorted_keys: Array = coverage.keys()
    sorted_keys.sort_custom(func(a, b): return coverage[a] < coverage[b])
    print("--- Least-actuated coverage cells ---")
    for k in sorted_keys.slice(0, limit):
        print("  %4d × %s" % [coverage[k], k])

# Print the most-actuated cells — useful for diagnosing LFU
# starvation (a cell at 1000 hits while neighbors sit at 1 means
# the action enumerator is over-emitting it, or the walker's
# stuck cycling).
func report_most_actuated(limit: int = 10) -> void:
    var sorted_keys: Array = coverage.keys()
    sorted_keys.sort_custom(func(a, b): return coverage[a] > coverage[b])
    print("--- Most-actuated coverage cells ---")
    for k in sorted_keys.slice(0, limit):
        print("  %4d × %s" % [coverage[k], k])

# Dump the winning trajectory if one was found. Each entry is the
# action_key the walker chose at that step; the prefix portion
# came from the archive cell the walk restored from, the suffix
# from the walk itself. Replaying these in sequence from a fresh
# driver should reach victory deterministically.
func report_victory_trajectory(limit: int = 0) -> void:
    if first_victory_walk < 0:
        print("--- Victory trajectory: NONE (probe never won) ---")
        return
    print("--- Victory trajectory (walk #%d, %d actions) ---" % [
        first_victory_walk, first_victory_steps])
    if limit > 0 and first_victory_trajectory.size() > limit:
        for a in first_victory_trajectory.slice(0, limit):
            print("  %s" % a)
        print("  ...(+%d more)" % (first_victory_trajectory.size() - limit))
    else:
        for a in first_victory_trajectory:
            print("  %s" % a)

# Print which canon rooms were never visited at all. The list
# directly tells you which sectors the prober's exploration
# strategy never reached.
func report_unvisited_rooms() -> void:
    var unvisited: Array = []
    for r in range(1, 141):
        if not rooms_seen.has(r):
            unvisited.append(r)
    print("--- Unvisited canon rooms (%d/140) ---" % unvisited.size())
    if unvisited.size() <= 30:
        print("  %s" % str(unvisited))
    else:
        print("  %s  ...(+%d more)" % [str(unvisited.slice(0, 30)), unvisited.size() - 30])

# ----- State hash --------------------------------------------------

# Canonical "who am I now?" identifier for a driver. Mirrors the
# hash used by state_space.gd (BFS) but inlined here to avoid
# coupling — if either side widens its hash, the other doesn't
# silently break. Shape: room + sorted inventory + the five NPC
# states whose interaction defines world-puzzle progress.
#
# Score, lamp battery, and turn counter are intentionally excluded.
# They're per-step monotonic counters (lamp drains, turns
# increment), so including them would make every step produce a
# distinct hash and prevent the graph from ever folding revisits.
# The graph is a model of *position and progress*, not history.
#
# Items carried in `_PROBE_CARRIABLES` (defined on Driver) are
# enumerated here. MARK_ROD_ID (141) is omitted — same rationale
# as the introspection table.
func _state_hash(driver: H.CapturedDriver, room: int) -> String:
    var inv: Array = []
    for pair in driver._PROBE_CARRIABLES:
        if driver.fsm.player.carrying(pair[0]):
            inv.append(str(pair[0]))
    inv.sort()
    var fsm = driver.fsm
    # Phase B widening: deposits + endgame distinguish progression.
    # Without them, "at well-house with empty inventory and 0
    # treasures deposited" collapses with "at well-house with
    # empty inventory and 14 treasures deposited" — the second is
    # nearly-victorious, the first is canonical start. Folding
    # them defeats the archive's whole point of "save promising
    # states and return to them." Endgame phase ("active",
    # "closing", "in_repository", "won") adds another 4×
    # discrimination at the cost of one short token per hash.
    return "r=%d|i=%s|d=%d|e=%s|n=%s,%s,%s,%s,%s" % [
        room,
        "/".join(inv),
        fsm.treasures_deposited(),
        fsm.endgame_state(),
        fsm.bird.get_state(),
        fsm.snake.get_state(),
        fsm.bear.get_state(),
        fsm.troll.get_state(),
        fsm.pirate.get_state(),
    ]

# Group coverage entries by `kind` prefix and print totals.
# Tells you at a glance whether the prober is spending its
# budget on movement, take/drop, or state-changing verbs.
func report_by_kind() -> void:
    var by_kind: Dictionary = {}
    for key in coverage.keys():
        # key format is "<room>:<verb>:<object>?" — extract the verb.
        var verb_part: String = key.split(":")[1]
        by_kind[verb_part] = by_kind.get(verb_part, 0) + coverage[key]
    var sorted: Array = by_kind.keys()
    sorted.sort_custom(func(a, b): return by_kind[a] > by_kind[b])
    print("--- Coverage totals by verb ---")
    for v in sorted:
        print("  %6d × %s" % [by_kind[v], v])
