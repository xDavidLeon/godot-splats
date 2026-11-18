# Splats: a pixel-art Gaussian-splat renderer for Godot, and the tools that build its assets

Assets are written as code for ink-studio, built to "TCRS" `.bytes` files, and drawn by this addon into one small pixel-art picture.

| Part | Where |
|---|---|
| The Godot 4 addon (GDScript, no compute shaders) | this folder: `splat_clip.gd`, `splat_instance.gd`, `splat_scene.gd`, `shaders/` |
| The file format's specification | [FORMAT.md](FORMAT.md) |
| The asset tools (Node 18 or later; Godot ignores the folder) | `tools/build.js`, `tools/snap.js`, `tools/export.js` |
| The pinned ink-studio they use (MIT, Shapeshift Labs) | `tools/ink-studio/`, see its `VENDORED.md` |

## Adding it to a game

Mount this repository at `addons/splats` in the game, as a git submodule pinned to a commit, so the addon's paths are `res://addons/splats/...`:

```
git submodule add https://github.com/xDavidLeon/godot-splats addons/splats
```

A game keeps only its own art sources (ink-studio scene files), its manifest and its built `.bytes` files.

## Building assets

Run from the game's root. The manifest is `splats/assets.json` and the kept reference snapshots are in `splats/snaps/`, unless `SPLAT_MANIFEST` and `SPLAT_SNAPS` say otherwise (paths under the game's root; `SPLAT_ROOT` replaces the current folder).

```
node addons/splats/tools/build.js            # every asset in the manifest; add ids to build only those
node addons/splats/tools/build.js --check    # writes nothing; fails if a .bytes file is not what its scene exports now
node addons/splats/tools/snap.js             # ink-studio's own render of each asset, kept as a reference picture
node addons/splats/tools/snap.js --check     # fails if a picture changed
```

A manifest entry: `{ "id": "desk-mug", "kind": "prop", "scene": "art/desk/mug.js", "out": "splats/desk/mug.bytes", "snaps": [0] }`. A clip has no `kind`, and has `fps` and `secs`. How to write a scene file, and the traps, are in the `splat-authoring` skill.

The manifest may also name the game's sun, beside `"assets"`: `"sun": [x, y, z]`, pointing at the sun, in ink-studio's and Godot's space (Y up, right-handed). Props' four quarter-turn bakes are lit by it, and so are clips and the reference snapshots, so a snapshot shows the light the built file has. A scene may ignore it and keep a light of its own, as a character lit from the front does. Without it props use the exporter's default, `[-0.3, 0.75, 0.6]`, and a clip's scene is given none.

## Where this came from

The renderer is a port of a Unity renderer of the same design (a scene component and three shaders: draw, resolve, present), made in November 2026. Where it differs from that renderer is listed under "Differences from the Unity renderer" below. The projection and the pixel look come from ink-studio's own software renderer (`cli/render.js`, `src/pixel-look.js`).

## Developing it

The demo scenes, the sample assets, the reader's tests and the capture tools are in `dev/`, which Godot ignores, so a game that mounts the addon never imports them. This repository holds no `project.godot`: Godot skips any folder that has one, which would hide the addon from the game. To run anything in `dev/`, assemble a throwaway project outside the repository:

```
python dev/make_project.py <new folder>              # the demo, the tests and the tools
python dev/make_project.py <new folder> --overlay    # the transparent click-through window
```

In the assembled project the addon is at `res://addons/splats`, and `dev/demo`, `dev/samples`, `dev/reference` and `dev/tools` are under `res://splats/`, so the paths below that start with `res://splats/` are paths there. `dev/tests` is at `res://tests/`. The script's opening comment lists the commands.

## Use

1. Put a `SplatInstance` (a `Node3D`) in a 3D scene and set its `asset` to a `.bytes` file. Move, turn, scale or hide it like any node.
2. Add a `SplatScene` node, give it a `Camera3D` (orthographic or perspective) and the node the instances are under, and set `art_size`.
3. Show `SplatScene.get_picture()` on a `TextureRect` or `Sprite2D` with the Nearest texture filter, with `shaders/splat_present.gdshader` as its material.

`res://splats/demo/splat_demo.tscn` does exactly this; run it with F6.

## How it draws

| Pass | Where | What |
|------|-------|------|
| Draw | `shaders/splat_scene_draw.gdshader`, in a 3D `SubViewport` at twice the art size | One quad a splat (a `MultiMesh`). The vertex shader poses each splat by its bone and its instance's transform. Nothing is sorted: solid splats are cut out at half their Gaussian and written with depth. |
| Resolve | `shaders/splat_resolve.gdshader`, in a 2D `SubViewport` at the art size | ink-studio's palette and ink look: inside a shape, the palette colour nearest the average of a pixel's four samples (or the one they vote for); on a silhouette, the voted colour inked darker. Coverage is binary: alpha is 0 or 1. |
| Present | `shaders/splat_present.gdshader` | Nearest-neighbour scale-up, alpha clipped. |

- **No compute or geometry shaders.** Splats, instances and bones are float textures read with `texelFetch` in the vertex shader. It runs in Forward+ and in the Compatibility renderer, with the same picture.
- **The CPU's work a frame** is the instance matrices and the bones of clips whose frame changed. The splat texture is rebuilt only when an instance appears, goes, hides or turns a quarter turn.

## Differences from the Unity renderer

- **No z flip.** Unity is left-handed, so its reader flips z and its picture is mirrored against ink-studio's. Godot is right-handed like ink-studio, so the file's numbers are used as they are and the picture is the same way round as ink-studio's.
- **A second look for the inside of a shape** (`SplatScene.interior`). The default, `AVERAGE`, is Unity's: the palette colour nearest the average of a pixel's four samples, with an ordered dither. An average of two tones can be nearest a colour that is in neither, which shows as stray pixels in dark hair. `VOTE` takes the colour most samples vote for instead (a tie goes to the one nearest the average; in the average look the silhouette's tie goes to the first sample read; both as in the Unity shader): no strays, no dither, flatter, and less flicker in motion. The average is the default. `dev/comparisons/finding-interior-colour.png` shows ink-studio, the average and the vote; `dev/comparisons/motion-*.gif` show both in motion (average left, vote right), captured by `dev/tools/splat_motion.gd`. The demo's switch, or Tab, flips between them.
- **A prop's quarter turn** is counted in Unity's yaw in the file. `SplatClip.turn_of` converts from Godot's: +90 degrees about y is the file's set 3.
- **`.bytes` files are not Godot resources.** They are read with `FileAccess`. An export preset must list `*.bytes` under "Filters to export non-resource files".

## Web export

Tried on 2026-11-18 with Godot 4.7.2: the demo scene, exported for the web (single-threaded, WebGL 2) and opened in a Chromium browser, draws the same picture as the desktop renderers (`dev/comparisons/demo-web.jpg`), with the clips playing and no errors in the console. Its frame rate was not measured: the browser pane it ran in was throttled.

- **Use the standard Godot editor to export, not the .NET one.** The .NET build ships no web export templates.
- **The preset needs `*.bytes`** under "Filters to export non-resource files", or the assets are left out of the pack.
- The export was made from a stand-alone copy of the demo (the addon, `splats/demo`, `splats/samples`, and a `project.godot` whose main scene is the demo), as `dev/make_project.py` now makes; nothing in a game's `project.godot` was touched. The demo's pack is 4.2 MB; the engine's `.wasm` is 39.5 MB before compression.

## Transparent click-through window

`res://splats/demo/splat_overlay.tscn` shows the picture in a borderless, always-on-top window with nothing round it, and the mouse reaches the window only where the picture is drawn. Drag the avatar to move it, turn the mouse wheel over it to resize it in whole art pixels; Escape or a right click closes it. Checked on 2026-11-18 with Godot 4.7.2 in exported builds, on Windows 11 by this repository's own test and on macOS 27 (an Apple M5 at 2x) with a separate harness. Not checked on Linux.

- **The project must allow it:** `display/window/per_pixel_transparency/allowed` and `display/window/size/transparent`, read at start-up. A project without them opens the scene as an ordinary window, and the scene says so. `python dev/make_project.py <new folder> --overlay` makes a stand-alone copy that does, with export presets.
- **Two ways to catch the mouse** (`click_through`; the C key, or `-- --click=pixel` or `--click=outline`):
  - **By pixel, the default.** Each frame the window asks where the cursor is and lets the mouse through the whole window (`Window.mouse_passthrough`) unless the art pixel under it is covered. Exact to the art pixel, and nothing is cut off what is drawn. This is what UniWindowController does in Unity.
  - **By outline.** The picture's outline is handed to the system as a polygon (`DisplayServer.window_set_mouse_passthrough`). Windows also clips what the window draws to that polygon, and the outline is simplified, so it is taken two art pixels outside the picture (`outline_margin`); clicks in that margin are caught.
- **Checked by `dev/tools/splat_overlay_test.gd`**, which the overlay starts itself with `-- --selftest=<folder>`:
  - As it opens, after a move and after a resize, a green window behind must show round the picture on a capture of only that part of the screen (`dev/comparisons/overlay-screen.png`), and every screen pixel must be what the window holds.
  - With `--real-input` (Windows only) it sends real input from the operating system: a click on the picture must reach the overlay and not the window behind, a click on a clear pixel must reach the window behind and not the overlay, a drag by the picture must move the window with the cursor, and a wheel turn must resize it. The cursor is put back, and nothing is sent unless one of the test's own two windows is under it.
- **Not on Vulkan.** Everything above passes, pixel for pixel, in Compatibility (OpenGL) and in Forward+ and Mobile on Direct3D 12 (`--rendering-driver d3d12`, or `rendering/rendering_device/driver.windows`). On Vulkan, Godot's default for Forward+ and Mobile on Windows, transparent pixels of the window come out on screen with grey added (`dev/comparisons/overlay-screen-vulkan.png`), although the window's own image is clean. It is the driver's presentation of a transparent window (seen on an NVIDIA RTX 4070 SUPER): turning off the window's 3D pass or its clear colour changes nothing.
- **macOS passes on every renderer** (Forward+ and Mobile on Metal, Forward+ on Vulkan through MoltenVK, Compatibility on OpenGL and on ANGLE), by pixel and by outline: no screen pixel differs from the window's own image, and clicks, a drag and the wheel behave. Vulkan is clean there, unlike on Windows. Three things differ:
  - An exported macOS app ignores `--rendering-method` and `--rendering-driver`; the renderer and driver come from the project's settings.
  - By pixel, the cursor is reported in whole points, so on a Retina screen the catching area was up to a point off at three edges. The overlay takes the middle of the reported point on macOS, which the Mac session then measured: every edge is within half a point.
  - A borderless window cannot be minimised on macOS.
- **By pixel, the cursor is asked for once a frame.** With the frame rate capped low to save power, the switch to catching is late by up to one frame (100 ms at 10 frames a second).
- Not tried: Linux, several monitors, and Windows display scaling other than this machine's.

## Not ported

Floor shadows, relighting by lamps and dusk (the light data is read but not used), the wardrobe (`LOOK`) and extra clips (`CLPS`): both sections are read past, clip cross-fades, particles, and the editing overlays (the tinted ghost and the marks).

## Checking it

```sh
python dev/make_project.py <folder>
godot --path <folder> --headless --import
godot --path <folder> --headless -s res://tests/test_runner.gd
godot --path <folder> -s res://splats/tools/splat_report.gd
godot --path <folder> --rendering-method gl_compatibility -s res://splats/tools/splat_report.gd -- --tag=compat
```

The test runner runs every `test_*.gd` in `dev/tests`. The last two need a window. They write `splats/comparisons/` in the assembled project (the ones worth keeping are copied by hand to `dev/comparisons/`): each sample asset beside ink-studio's own render of it (`splats/reference/`), the demo scene, and the demo's splat count and frame time.

## Licence

MIT, see [LICENSE](LICENSE). The pinned ink-studio in `tools/ink-studio/` is its authors' work under its own MIT licence (`tools/ink-studio/LICENSE`). The sample assets and pictures in `dev/` are included for testing the addon.
