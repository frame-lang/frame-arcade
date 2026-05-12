extends SceneTree

# Verifies canon EXAMINE/READ flavor for the in-scene-only objects
# (advent.dat section 5 objects 13/23/26/27/29/37/40/25):
#
#   READ TABLET   @ canon 101 → msg #196 (long tablet readout)
#   EXAMINE MIRROR @ canon 109 → cave-mirror flavor
#   EXAMINE FIGURE @ canon 35 / 110 → shadowy-figure flavor
#   EXAMINE STALACTITE @ canon 111 → stalactite flavor
#   EXAMINE DRAWINGS @ canon 97 → drawings flavor
#   EXAMINE VOLCANO @ canon 126 → volcano flavor
#   EXAMINE CARPET / MOSS @ canon 96 → soft-room flavor
#   EXAMINE PLANT @ canon 23 → phony-plant flavor

const H = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect_any_match(label: String, lines: Array, needle: String) -> void:
    for line in lines:
        if needle in line:
            print("  ok   %-58s found '%s'" % [label, needle])
            return
    print("  FAIL %-58s no line contained '%s' (%d lines)" % [
        label, needle, lines.size()])
    failures += 1

func _capture_at(d: H.CapturedDriver, room: int, input: String) -> Array:
    d.fsm.player.move_to(room)
    var pre: int = d.captured.size()
    d._process_input(input)
    return d.captured.slice(pre)

func _init():
    print("=== CCA scenery EXAMINE/READ — section-5 flavor objects ===")

    var d := H.make_driver()

    # ----- TABLET @ 101 -----
    _expect_any_match("READ TABLET @ 101 → canon msg #196",
        _capture_at(d, 101, "read tablet"),
        "Congratulations on bringing light into the dark-room")
    _expect_any_match("EXAMINE TABLET @ 101 → same canon prose",
        _capture_at(d, 101, "examine tablet"),
        "Congratulations on bringing light into the dark-room")

    # ----- Scenery EXAMINE — canon obj prop=0 = ">$<" (no flavor) -----
    # Canon falls through to msg #76 "Peculiar. Nothing unexpected
    # happens." for mirror / stalactite / drawings / volcano / carpet.
    _expect_any_match("EXAMINE MIRROR @ 109 → canon msg #76",
        _capture_at(d, 109, "examine mirror"), "Peculiar")

    # ----- SHADOWY FIGURE @ 35 — has canon prop=0 prose -----
    _expect_any_match("EXAMINE FIGURE @ 35 → shadowy-figure flavor",
        _capture_at(d, 35, "examine figure"),
        "trying to attract your attention")
    _expect_any_match("EXAMINE SHADOW @ 110 → shadowy-figure flavor",
        _capture_at(d, 110, "examine shadow"),
        "trying to attract your attention")

    _expect_any_match("EXAMINE STALACTITE @ 111 → canon msg #76",
        _capture_at(d, 111, "examine stalactite"), "Peculiar")
    _expect_any_match("EXAMINE DRAWINGS @ 97 → canon msg #76",
        _capture_at(d, 97, "examine drawings"), "Peculiar")
    _expect_any_match("EXAMINE VOLCANO @ 126 → canon msg #76",
        _capture_at(d, 126, "examine volcano"), "Peculiar")
    _expect_any_match("EXAMINE GEYSER @ 126 → canon msg #76",
        _capture_at(d, 126, "examine geyser"), "Peculiar")
    _expect_any_match("EXAMINE CARPET @ 96 → canon msg #76",
        _capture_at(d, 96, "examine carpet"), "Peculiar")
    _expect_any_match("EXAMINE MOSS @ 96 → canon msg #76",
        _capture_at(d, 96, "examine moss"), "Peculiar")

    # ----- PHONY PLANT @ 23 — canon obj#PLANT prop=200 verbatim -----
    _expect_any_match("EXAMINE PLANT @ 23 → canon obj#PLANT prop=200",
        _capture_at(d, 23, "examine plant"),
        "huge beanstalk growing out of the west pit")

    # ----- MESSAGE @ 140 (second-maze stash mirror) -----
    _expect_any_match("READ MESSAGE @ 140 → canon msg #191",
        _capture_at(d, 140, "read message"),
        "not the maze where the pirate leaves")
    _expect_any_match("EXAMINE MESSAGE @ 140 → same canon msg",
        _capture_at(d, 140, "examine message"),
        "not the maze where the pirate leaves")

    if failures == 0:
        print("PASS — section-5 scenery flavor honors canon")
    else:
        print("FAIL — %d assertion(s) failed" % failures)
    quit(failures)
