extends SceneTree
# SCRATCH — discover the plant→giant-room branch from BridgeBuilt.
const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const WinJourney = preload("res://scripts/win_journey.gd")

var d
var blocked := {}
var logc: Array = []

class Cap:
    extends Driver
    var last := ""
    func _println(t: String) -> void: last = t

func _mk():
    var dr = Cap.new()
    dr.fsm = Cca.new(); dr.fsm.setup_default_aspects(); dr.fsm.dwarves_auto_woken = true
    dr.prompts = Cca.PromptDispatcher.new()
    dr.output = RichTextLabel.new(); dr.output.bbcode_enabled = true
    dr.input = LineEdit.new()
    dr.rng = RandomNumberGenerator.new(); dr.rng.seed = 42; dr.fsm.chance.reseed(42)
    dr._build_verb_synonyms_5()
    return dr

func _bfs(a: int, b: int) -> Array:
    if a == b: return []
    var q := [a]; var prev := {a: [-1, ""]}
    while not q.is_empty():
        var c = q.pop_front()
        for dir in d.room_exits.get(c, {}):
            var n = d.room_exits[c][dir]
            if ("%d:%s" % [c, dir]) in blocked or n in prev: continue
            prev[n] = [c, dir]
            if n == b:
                var p := []; var r = b
                while prev[r][0] != -1: p.push_front(prev[r][1]); r = prev[r][0]
                return p
            q.append(n)
    return []

func _cmd(s: String): logc.append(s); d._process_input(s)

func _nav(goal: int) -> bool:
    blocked = {}
    for _i in range(160):
        var c: int = d.fsm.player_room()
        if c == goal: return true
        var p := _bfs(c, goal)
        if p.is_empty(): return false
        _cmd(p[0])
        if d.fsm.player.get_state() == "dead": return false
        if d.fsm.player_room() == c: blocked["%d:%s" % [c, p[0]]] = true
    return false

func _init():
    print("=== SCRATCH plant branch ===")
    d = _mk()
    # Walk win rail to BridgeBuilt.
    var j = WinJourney._create()
    while not j.is_done():
        var nm: String = j.state_name()
        for cmd in j.commands_from_previous(): d._process_input(String(cmd).to_lower())
        if nm == "BridgeBuilt": break
        j.advance()
    logc.clear()
    print("  at BridgeBuilt, room=%d carrying bottle=%s rod=%s" % [
        d.fsm.player_room(), d.fsm.player.carrying(131), d.fsm.player.carrying(130)])

    # Fill bottle at water source (canon 84), pour on the plant in
    # the WEST pit (canon 25), twice, to grow it huge.
    print("  nav 84 (water): %s" % _nav(84)); _cmd("fill bottle"); print("    fill: %s" % d.last)
    print("  nav 25 (plant): %s room=%d" % [_nav(25), d.fsm.player_room()]); _cmd("pour"); print("    pour1: %s" % d.last)
    print("  nav 84: %s" % _nav(84)); _cmd("fill bottle")
    print("  nav 25: %s room=%d" % [_nav(25), d.fsm.player_room()]); _cmd("pour"); print("    pour2: %s" % d.last)
    # Climb the huge beanstalk: 25 → 26 → 88 → giant room (92).
    _cmd("climb"); print("  climb: '%s' room=%d" % [d.last.substr(0, 40), d.fsm.player_room()])
    print("  nav 92 (giant): %s room=%d" % [_nav(92), d.fsm.player_room()])
    _cmd("take eggs"); print("  eggs carried=%s resp='%s'" % [d.fsm.player.carrying(116), d.last])
    print("=== COMMANDS ===")
    print(", ".join(logc))
    quit(0)
