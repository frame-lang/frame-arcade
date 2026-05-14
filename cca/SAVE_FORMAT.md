# CCA save-file format

## Wire format

```
+---+---+---+---+----------------------------+
| C | C | A | 1 |  raw bytes from fsm.save() |
+---+---+---+---+----------------------------+
  4-byte magic   variable-length Frame state
```

- **Magic (4 bytes):** ASCII `CCA1`. Identifies the file as a CCA
  save AND encodes the on-disk Frame domain layout version.
- **Body:** raw `PackedByteArray` returned by
  `Adventure.save_state()` (the Frame `@@[save(save_state)]`
  output). Length is whatever the FSM serializes — typically
  10–20 KB depending on world state.

## Load behavior

`_load_game` in [`driver.gd`](godot/scripts/driver.gd) and
[`cca_main.gd`](../arcade/godot/scripts/cca_main.gd) reads the
first 4 bytes; if they don't match the current magic, the save is
**silently discarded** with the message:

> Saved game is from an older version and is no longer compatible.
> Starting fresh.

The save file is deleted at that point so the next launch reads a
clean slate.

## When to bump the magic

The magic must be bumped any time the FSM domain layout changes in
a way that would make an old save deserialize into a partial /
invalid state. **The symptom of getting this wrong is** a
post-restore crash on the next user action when an FSM method
dispatches against a field that didn't exist when the save was
written.

Concrete triggers to bump:

| Change | Bump? |
|---|---|
| Add a new `@@system` instance to `Adventure` | **Yes** — old save has no field for it; `restore_state` produces a null reference |
| Remove an `@@system` from `Adventure` | **Yes** — old save carries bytes for a now-unknown field |
| Add a `domain:` field to any persisted `@@system` | **Yes** — old save underflows on read |
| Remove a `domain:` field | **Yes** — old save overflows / mis-aligns |
| Rename a `domain:` field | **Yes** — same wire position, different semantics |
| Reorder `domain:` fields | **Maybe** — depends on whether Frame's serializer is name-keyed or position-keyed. If position-keyed, **yes**. |
| Add a *non-domain* method to an `@@system` | No — methods aren't persisted |
| Add a new `state` to an `@@system`'s machine | **Yes** if any save could currently be sitting in a state that the new layout assigns a different index |
| Change a state-machine event signature | No (events aren't serialized — only the current state + domain fields) |
| Add a new `domain:` field to `Adventure` itself | **Yes** |

When in doubt, bump. The cost of bumping is one user message
("starting fresh") on the next launch for anyone with an in-flight
save; the cost of not bumping is a runtime crash.

## How to bump

1. In both [`cca/godot/scripts/driver.gd`](godot/scripts/driver.gd)
   and [`arcade/godot/scripts/cca_main.gd`](../arcade/godot/scripts/cca_main.gd),
   change `_SAVE_MAGIC`:

   ```gdscript
   static var _SAVE_MAGIC: PackedByteArray = PackedByteArray([67, 67, 65, 50])  # "CCA2"
   ```

   Use the next ASCII digit: `CCA1` → `CCA2` → `CCA3` → …

2. Add a row to the version log below noting the bump + reason.

3. Commit. Anyone with an older save will see the friendly reset
   message on their next launch.

## Version log

| Magic | Date | Reason |
|---|---|---|
| `CCA1` | 2026-05-12 | Initial versioned format. Introduced after the multi-dwarf wire-up (`prev_room`, `seen`, `dwarf_total_in_room`, `dwarf_attack_total`, `dwarf_hit_total`, `loaded_from_save`) and pirate-as-dwarf-#6 (Pirate `room`, `prev_room`, `seen`) made every pre-versioning save incompatible. Earlier saves had no magic at all and were deleted by hand during the V1 cleanup. |
| `CCA2` | 2026-05-13 | V1.2 architectural pass. Adventure gained canon-scalar fields (`old_loc`, `old_loc2`, `brief_mode`, `look_detail_count`, `iwest_count`), `chest_hint_done`, `dwarf_first_encounter_done`, `oyster_revealed`. Endgame gained `timer` / `panicked` / `pending_warning` (state-vars hoisted to domain) plus three new closing-cascade states (`$ClosingT25` / `$ClosingT15` / `$ClosingT5`). Hint gained `offered`. DarknessGate gained `warned_room_id`. Wire format also changed under our feet: framec's GDScript backend switched from `JSON.stringify` to `var_to_bytes` (preserves int types — fixes the Array<int> deserialization bug filed as framec Issue #4). All in-flight `CCA1` saves reset gracefully with the friendly "starting fresh" message. |
