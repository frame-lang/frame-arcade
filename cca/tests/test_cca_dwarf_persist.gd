extends SceneTree

# Save/restore round-trip for the canon dwarf-movement state +
# the DFLAG=20 SAVED latch (advent.for STMT 6010 line 777).
#
# Verifies:
#   - Dwarf.prev_room and Dwarf.seen round-trip through
#     @@[persist] / save_state / restore_state.
#   - Pirate.room / prev_room / seen also round-trip (canon
#     dwarf #6).
#   - mark_loaded_from_save() latches: the next dwarf attack tick
#     after a restore snaps DFLAG=20.

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-58s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-58s = %s (expected %s)" % [
            label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== CCA dwarf persist + SAVED latch ===")

    # ---------------------------------------------------------
    # Phase 1: dwarf prev_room + seen round-trip
    # ---------------------------------------------------------
    print("Phase 1: dwarf prev_room + seen round-trip")
    var adv = Cca.new()
    adv.setup_default_aspects()
    adv.wake_dwarves()
    # Force dwarf1 into a known walk + sighting state.
    adv.dwarf_step_to(1, 50)              # cur=50, prev=19
    adv.dwarf_snap_to_player(1)           # snap to player's room (still surface)
    var pre_room: int = adv.dwarf_room_of(1)
    var pre_prev: int = adv.dwarf_prev_room_of(1)
    var pre_seen: bool = adv.dwarf_is_seen(1)
    _expect("dwarf1 pre-save seen",       pre_seen,  true)

    var bytes = adv.save_state()

    # Mutate after save — should be reset on restore.
    adv.dwarf_step_to(1, 99)
    adv.dwarf_unsee(1)
    _expect("dwarf1 mutated room",        adv.dwarf_room_of(1), 99)
    _expect("dwarf1 mutated seen",        adv.dwarf_is_seen(1), false)

    var adv2 = Cca.new()
    adv2.restore_state(bytes)
    _expect("restored dwarf1 room",       adv2.dwarf_room_of(1),       pre_room)
    _expect("restored dwarf1 prev_room",  adv2.dwarf_prev_room_of(1),  pre_prev)
    _expect("restored dwarf1 seen",       adv2.dwarf_is_seen(1),       pre_seen)

    # ---------------------------------------------------------
    # Phase 2: pirate room/prev_room/seen round-trip
    # ---------------------------------------------------------
    print("Phase 2: pirate canon-dwarf-#6 state round-trip")
    var adv3 = Cca.new()
    adv3.setup_default_aspects()
    adv3.wake_dwarves()
    # Activate pirate by carry count, then walk + snap.
    adv3.pirate.treasures_carried(5)
    _expect("pirate stalking",            adv3.pirate.is_stalking(),   true)
    adv3.pirate_step_to(70)
    adv3.pirate_snap_to_player()
    var p_room: int  = adv3.pirate_room()
    var p_prev: int  = adv3.pirate_prev_room()
    var p_seen: bool = adv3.pirate_is_seen()
    _expect("pirate pre-save seen",       p_seen,    true)

    var p_bytes = adv3.save_state()
    var adv4 = Cca.new()
    adv4.restore_state(p_bytes)
    _expect("restored pirate room",       adv4.pirate_room(),       p_room)
    _expect("restored pirate prev_room",  adv4.pirate_prev_room(),  p_prev)
    _expect("restored pirate seen",       adv4.pirate_is_seen(),    p_seen)

    # ---------------------------------------------------------
    # Phase 3: SAVED latch — DFLAG=20 on next attack after restore
    # ---------------------------------------------------------
    print("Phase 3: SAVED latch snaps DFLAG=20 on next attack tick")
    var adv5 = Cca.new()
    adv5.setup_default_aspects()
    adv5.wake_dwarves()
    var s_bytes = adv5.save_state()

    var adv6 = Cca.new()
    adv6.restore_state(s_bytes)
    _expect("post-restore anger still 2 (no attack yet)",
        adv6.get_dwarf_anger(), 2)
    adv6.mark_loaded_from_save()
    _expect("anger unchanged until attack tick",
        adv6.get_dwarf_anger(), 2)

    # Force a dwarf into the player's room + tick. The single
    # dwarf attacks; the latch snaps DFLAG=20 in the same tick.
    adv6.player.move_to(19)
    adv6.dwarf_step_to(1, 19)              # ensure prev==room so attack fires
    adv6.dwarf_step_to(1, 19)              # second call: prev←19, room←19
    adv6.tick()
    _expect("anger snapped to 20 after SAVED-latch attack",
        adv6.get_dwarf_anger(), 20)

    # ---------------------------------------------------------
    # Phase 4: SAVED latch DOESN'T fire when never set
    # ---------------------------------------------------------
    print("Phase 4: fresh game (no restore) leaves anger at 2")
    var adv7 = Cca.new()
    adv7.setup_default_aspects()
    adv7.wake_dwarves()
    adv7.player.move_to(19)
    adv7.dwarf_step_to(1, 19)
    adv7.dwarf_step_to(1, 19)
    adv7.tick()
    _expect("fresh-game anger stays 2 (no SAVED latch)",
        adv7.get_dwarf_anger(), 2)

    if failures == 0:
        print("PASS — dwarf persist + SAVED latch round-trip correctly")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
