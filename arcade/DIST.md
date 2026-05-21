# Building & shipping the Frame Arcade to itch.io

The cabinet ships as two artifacts:

- A **web build** (HTML5) that plays in-browser via itch.io's
  "HTML5 game" embed — zero install for players.
- A **macOS native build** (universal: arm64 + x86_64) for
  players who want a desktop run.

Both are produced by `arcade/dist.sh` from the same Godot
project. Linux / Windows can be added by extending the export
preset; the existing two were the priority pair for itch.io.

## Prerequisites

1. **Godot 4.6.x** on `PATH`. Check with `godot --version`.
2. **Matching export templates** at
   `~/Library/Application Support/Godot/export_templates/4.6.2.stable/`.
   Either install via Editor → Project → Export → Manage
   Export Templates → Download, or fetch the TPZ directly:
   ```sh
   curl -L https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_export_templates.tpz \
        -o /tmp/templates.tpz
   mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.6.2.stable"
   unzip -q /tmp/templates.tpz -d /tmp/godot_templates_extracted
   mv /tmp/godot_templates_extracted/templates/* \
      "$HOME/Library/Application Support/Godot/export_templates/4.6.2.stable/"
   ```
3. **framec** on `PATH` (or `FRAMEC=/path/to/framec`).

## Build

```sh
cd arcade
./dist.sh        # both presets (web + mac)
./dist.sh web    # web only
./dist.sh mac    # mac only
```

Output:

```
arcade/dist/
├── web/              ← zip the whole folder for itch.io
│   ├── index.html
│   ├── index.pck
│   ├── index.wasm
│   ├── index.js
│   └── index.audio.*.worklet.js
└── mac/
    └── FrameArcade.zip   ← upload directly to itch.io
```

`arcade/dist/` is `.gitignore`'d. The `export_presets.cfg`
under `arcade/godot/` IS committed (it's the build config).

## Local smoke-test before uploading

This is a **single-threaded** web build (`GODOT_THREADS_ENABLED =
false`), so it does **not** require SharedArrayBuffer / cross-origin
isolation — which is exactly what lets it drop onto itch.io without
special embed settings. The included server sends COOP/COEP headers
anyway (harmless parity with a threaded build):

```sh
python3 arcade/dist/serve_web.py
# open http://localhost:8000
```

## Uploading to itch.io

For the **web build**:

1. Project page → Edit game → "Kind of project" → **HTML**.
2. "Embed options" → "This file will be played in the
   browser" → upload a zip of `arcade/dist/web/` (entire
   folder, with `index.html` at the root of the zip).
3. Set viewport to **800 × 600** (matches `project.godot`'s
   `viewport_width` / `viewport_height`). Optionally enable
   "Click to launch in fullscreen" and "Mobile friendly" off.
4. Leave **"SharedArrayBuffer support" unchecked** — this is a
   single-threaded build and doesn't need cross-origin isolation,
   so it boots without the COOP/COEP embed toggle.

For the **macOS build**:

1. Same project page → **add a second uploaded file**.
2. Upload `arcade/dist/mac/FrameArcade.zip`.
3. Tag it as **macOS** so the itch.io app and webpage
   filter correctly.
4. The build is **unsigned** — Gatekeeper will warn first-time
   users. itch.io's app handles this transparently; users
   downloading the zip directly will need to right-click → Open
   the first time. Add a one-line note on the game page so
   players aren't surprised.

## Versioning

Bump `application/short_version` and `application/version` in
[godot/export_presets.cfg](godot/export_presets.cfg) (macOS
preset, both currently `0.1.0`) before each release. The web
build has no embedded version — itch.io tracks file revisions
itself.

## Adding Linux / Windows later

Copy the macOS preset block in `export_presets.cfg`, change
`name` and `platform` to `Linux` or `Windows Desktop`, point
`export_path` to `../dist/linux/FrameArcade.x86_64` or
`../dist/windows/FrameArcade.exe`. Add the corresponding
branch to `dist.sh`. Templates for both are already in the
TPZ (no extra download needed).

## Known wrinkles

- **Web saves use IndexedDB.** Godot maps `user://` to
  IndexedDB on web, so the CCA save file persists *per
  browser-origin*. itch.io's HTML embed runs each game on its
  own origin, so CCA saves there don't collide with anything
  else.
- **No code-signing yet.** `application/min_macos_version` is
  set to `10.12`, but the unsigned bundle still trips
  Gatekeeper. Notarization fields are blank; fill them in
  later under the macOS preset's `notarization/*` keys.
- **The .pck is renamed `index.pck` for web** but
  `FrameArcade.pck` (inside the .app) for mac. That's
  Godot's defaults — no action needed.
