#!/usr/bin/env python3
"""
check_cca_drift.py — drift detector for the two CCA drivers.

`cca/godot/scripts/driver.gd` and `arcade/godot/scripts/cca_main.gd`
share most of their parser + dispatcher + intercept logic. A handful
of functions intentionally diverge to handle arcade-specific concerns
(ExitDialog, Arcade.return_to_menu(), Cabinet keys footer, etc.).

This script:
  1. Extracts every `func ...` body from both files
  2. Strips comments + collapses whitespace
  3. Reports identical functions, divergent functions, and unique-to-
     each functions
  4. Cross-references the EXPECTED_DIVERGENCES list below — anything
     divergent that ISN'T in that list trips an error exit

Run from anywhere; takes no arguments. Exits non-zero on unexpected
drift so it can wire into a pre-commit hook.

Maintenance: when you intentionally add a new divergent function (or
remove one), update EXPECTED_DIVERGENCES below.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DRIVER = REPO_ROOT / "cca" / "godot" / "scripts" / "driver.gd"
ARCADE = REPO_ROOT / "arcade" / "godot" / "scripts" / "cca_main.gd"

# Functions known to diverge between the two drivers, with the
# concrete reason. The drift check passes only if the divergent set
# EXACTLY MATCHES this list — adding or removing items here is the
# explicit checkpoint that drift was intentional.
EXPECTED_DIVERGENCES = {
    "_build_ui":               "arcade adds the ExitDialog overlay to the UI tree",
    "_check_player_death":     "arcade calls Arcade.return_to_menu(); standalone calls get_tree().quit()",
    "_handle_movement":        "arcade's bumper chain has the ExitDialog cancel path inserted",
    "_handle_ui_verb":         "arcade routes QUIT through ExitDialog instead of the inline yes/no prompt",
    "_intercept_take_scenery": "arcade has a couple of arcade-specific scenery items",
    "_intercept_unlock_chain": "small wording drift around the chain lock prose",
    "_load_game":              "arcade falls back to _print_welcome on bad save magic; standalone returns silently",
    "_print_help":             "arcade adds the Cabinet keys (F5/F9/Esc) footer line",
    "_print_welcome":          "arcade adds the Cabinet keys footer + arcade-specific Continue hint",
    "_process_input":          "arcade routes Esc through ExitDialog; standalone does inline quit prompt",
    "_ready":                  "arcade instantiates ExitDialog and auto-Continues on save-present launch",
    "_run_per_turn_checks":    "arcade tick also pings the Arcade autoload for cabinet UI updates",
}

# Functions that exist only in the arcade driver — these are
# arcade-shell-specific and have no standalone equivalent.
EXPECTED_ARCADE_ONLY = {
    "_hide_exit_dialog",
    "_show_exit_dialog",
    "_input",
}


def extract_funcs(path):
    text = path.read_text()
    funcs = {}
    pattern = re.compile(r"^func\s+(\w+)\s*\([^)]*\)[^:]*:(.*?)(?=^func\s|\Z)",
                         re.DOTALL | re.MULTILINE)
    for m in pattern.finditer(text):
        name = m.group(1)
        body = m.group(2)
        body = re.sub(r"#[^\n]*", "", body)
        body = re.sub(r"\s+", " ", body).strip()
        funcs[name] = body
    return funcs


def main():
    a = extract_funcs(DRIVER)
    b = extract_funcs(ARCADE)

    common = set(a) & set(b)
    only_driver = set(a) - set(b)
    only_arcade = set(b) - set(a)

    identical = {k for k in common if a[k] == b[k]}
    divergent = {k for k in common if a[k] != b[k]}

    print(f"driver.gd: {len(a)} funcs    cca_main.gd: {len(b)} funcs")
    print(f"  shared & identical:  {len(identical)}")
    print(f"  shared & divergent:  {len(divergent)}")
    print(f"  arcade-only:         {len(only_arcade)}")
    print(f"  standalone-only:     {len(only_driver)}")
    print()

    unexpected = []

    # Catch divergence drift
    unexpected_divergent = sorted(divergent - set(EXPECTED_DIVERGENCES))
    if unexpected_divergent:
        print("UNEXPECTED DIVERGENCE — functions now differ that the contract lists as identical:")
        for k in unexpected_divergent:
            print(f"  - {k}")
        unexpected.extend(unexpected_divergent)

    # Catch silent re-convergence (a function intentionally diverged but is now identical again — fine,
    # update the contract)
    reconverged = sorted(set(EXPECTED_DIVERGENCES) - divergent)
    if reconverged:
        print("\nNOTE — functions in EXPECTED_DIVERGENCES that no longer differ:")
        for k in reconverged:
            print(f"  - {k}  (was '{EXPECTED_DIVERGENCES[k]}')")
        print("  → remove from EXPECTED_DIVERGENCES (no longer drifting)")
        unexpected.extend(reconverged)

    # Catch unexpected arcade-only functions
    unexpected_only = sorted(only_arcade - EXPECTED_ARCADE_ONLY)
    if unexpected_only:
        print("\nUNEXPECTED ARCADE-ONLY function (new function in cca_main.gd with no standalone twin):")
        for k in unexpected_only:
            print(f"  - {k}")
        unexpected.extend(unexpected_only)

    removed_arcade_only = sorted(EXPECTED_ARCADE_ONLY - only_arcade)
    if removed_arcade_only:
        print("\nNOTE — EXPECTED_ARCADE_ONLY entries that no longer exist in cca_main.gd:")
        for k in removed_arcade_only:
            print(f"  - {k}")
        unexpected.extend(removed_arcade_only)

    # Catch standalone-only functions (should be zero)
    if only_driver:
        print("\nUNEXPECTED STANDALONE-ONLY function (no arcade twin):")
        for k in sorted(only_driver):
            print(f"  - {k}")
        unexpected.extend(only_driver)

    if unexpected:
        print(f"\nFAIL — {len(unexpected)} drift item(s) need attention.")
        return 1

    print("OK — drift surface matches contract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
