# Splats: a pixel-art Gaussian-splat renderer for Godot, and the tools that build its assets

Assets are written as code for ink-studio, built to "TCRS" `.bytes` files, and drawn by this addon into one small pixel-art picture.

| Part | Where |
|---|---|
| The Godot 4 addon (GDScript, no compute shaders) | this folder: `splat_clip.gd`, `splat_instance.gd`, `splat_scene.gd`, `splat_lamp.gd`, `splat_light.gd`, `splat_particles.gd`, `splat_mark.gd`, `shaders/` |
| A debug panel for the pixel look, debug builds only | `debug/splat_debug_panel.gd` |
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

## A wardrobe

A file may hold a wardrobe (`SplatClip.has_look()`): every piece whole (`SplatClip.pieces`), and colour regions (`SplatClip.regions`), each a ramp of the palette. An instance of it wears a look:

```gdscript
avatar.wear(["body", "top:stripes", "bottom:trousers", "shoes:shoes", "hair:bun", "accessory:glasses-round"],
		{"top": [0x28475c, 0x3f6f8a, 0x5aaab3], "hair": [0x1b1618, 0x2a2226, 0x4a4044]})
```

- **Pieces:** the ones named are drawn, with the splats of no piece. A name the file does not have is passed over.
- **Colours:** a region named takes that ramp, dark to light, with as many colours as the file's own; one not named keeps the file's. A ramp of another length is refused, and nothing changes.
- **Until `wear` is called the whole wardrobe is drawn at once,** in the file's colours: every hairstyle on one head. `wear_everything()` goes back to that.
- **Every instance wears its own look.** The file is read once and shared.
- **A change of look rebuilds nothing.** Every splat of the wardrobe is in the scene's texture from the start; which pieces show, and the palette, are one row of a small texture for each instance, and the instance's light ramps are rows of another. `wear` on a drawn instance writes those rows (0.15 ms, measured; a rebuild of that scene took 14 ms). The price is that the pieces not worn are still handed to the vertex shader, which drops them.
- **Lamps and dusk follow the look:** a recoloured region is lit along its new ramp.
- **The picture's palette has room for 128 colours** (`SplatScene.MAX_PALETTE`), and every look brings its own. Eight looks of the sample avatar and a floor came to 114.

Which pieces make a look, and how one picked colour becomes a ramp, are the game's own business: the names are the art's, and this addon knows none of them. `dev/tools/splat_wardrobe_report.gd` shows one way, for the sample avatar.

## Clips

A file may hold several named clips on its one rig (`SplatClip.takes`; `find` and `index_of` look one up). An instance plays one, or shows two mixed:

```gdscript
avatar.play("typing")                    # on the scene's clock, plus the instance's time_offset
avatar.play("finished", 0.4)             # or at a time of the clip's own, in seconds
avatar.cross_fade("typing", 5.2, "finished", 0.1, 0.25)   # a quarter of the way from one to the other
```

- **A name the file does not have plays its first clip,** so a file with one clip plays it whatever is asked.
- **The instance keeps no clock and no fade.** `cross_fade` is one frame of a change of clip: the clip being left and its time, the new clip and its time, and how much of the new one shows. The caller decides when the change starts, how long it takes and how it eases, calls `cross_fade` each frame with the weight as far as it has got, and then `play`.
- **Bones are mixed entry by entry** (`SplatClip.blend_bones`). A part that either clip hides takes the new clip's pose at once: mixed, it would fly up from where hidden parts are parked.
- **A fade is the CPU's work for that instance only:** its bones for the frame, a hundred or so numbers. Nothing is rebuilt.

## Light

A scene that sets none of this draws its assets' baked colours, as before. All of it needs the files' light data (props, and clips built with `"light": true`); a file without it keeps its colours.

- **Lamps.** Put a `SplatLamp` (a `Node3D` with a `radius` in metres and a `strength`) under the scene's `instances_root`. The splats near it and facing it step up the colour ramp each was shaded on. It is not a Godot light: only the splat picture reads it, nothing blocks it, and it casts no shadow. `SplatScene.lamp_light` switches every lamp off. Up to 16 light one picture.
- **Dusk.** `SplatScene.dusk` takes every splat down its own ramp by that many whole steps: 0 is the bake, 2 reads as evening. Splats with no ramp (glowing things: a lamp's shade, a screen) keep their colour. A lamp shows at dusk more than by day, when floors and walls are already at the top of their ramps.
- **Floor shadows.** `SplatScene.floor_shadows` darkens the floor (`floor_height`) under every instance, away from `sun`. Keep `sun` equal to the sun the assets were baked with (the manifest's, or the exporter's default, which is the scene's default too). Turn `SplatInstance.casts_shadow` off for the floor itself, for walls, and for what lies on a surface. A shadow is a disc on every `shadow_cell` (5 cm) something stands over, and leaves `shadow_light` (0.8) of the light. Shadows fall within 12.8 m of where the camera looks.

None of it costs a rebuild or any work on the CPU: the rules run in the shaders every frame, so a lamp or a piece of furniture can be dragged, the dusk can fall, and a clip's shadow follows its pose. The same rules are in script as `SplatLight` (`relight`, `added_by_lamps`, `colour_at`, `shadow_cells`), for anything that wants the answer outside the picture; the tests check those, and `dev/tools/splat_light_report.gd` checks the shaders against them.

## Particles

Steam, flames and dust are splat assets like any other: a file says where the particles start and what colour they are. What makes one a cloud is its instance's motion:

```gdscript
steam.asset = "res://splats/fx/steam.bytes"
steam.motion = SplatInstance.Motion.RISE     # or DRIFT, or NONE
steam.motion_reach = 0.18                    # metres: how high a rise goes, how far a drift wanders
steam.motion_wobble = 0.02                   # metres: how wide a rise wobbles on the way up
steam.motion_speed = 1.0                     # how fast its clock runs against the scene's
steam.casts_shadow = false
```

- **Rise** (steam, flames): each splat climbs `motion_reach` on a loop of its own length (2.8 to 7.6 seconds at speed 1), wobbling and shrinking to about half its size, and is gone for the first 4% of the loop and after a point between 75% and 100% of it that is its own.
- **Drift** (dust): each splat wanders within `motion_reach` of where it starts, and is in view for half of a slower cycle of its own.
- **Nothing is simulated, uploaded or rebuilt.** A splat's place is a formula of its own number in the picture and the clock, worked out in the vertex shader (`shaders/splat_pose.gdshaderinc`). The motion is four numbers in the instance's row; it can change every frame.
- **The clock is the scene's** (`SplatScene.fixed_time`, or the engine's), so a frame at a given time is always the same frame. It starts again every hour (`SplatScene.CLOCK_WRAP`), where a cloud jumps once.
- **A particle is solid like every splat here,** so where it would fade out it is dropped for that part of its loop. One smaller than a sample can fall between samples and miss a frame.
- **The sample clouds glow:** they were shaded on no ramp, so lamps and dusk leave them alone. Turn `casts_shadow` off for a cloud; left on, its shadow follows its splats.
- **The rule is in script too,** as `SplatParticles` (`offset_at`, `seed_of`, `rise_phase`, `rise_end`, `drift_shown`), worked in single precision as the shader works it. `dev/tools/splat_fx_report.gd` draws one cloud alone and looks for every splat where the rule puts it.
- **Two renderers do not put every particle in the same place.** A particle's seed is a hash, and its last few bits are how the driver rounds it. On the one GPU tried (NVIDIA), Vulkan (Forward+, Mobile) rounds every step and OpenGL (Compatibility) adds the hash's products in before rounding; `SplatParticles.fused` picks which the script follows, and each matched its renderer for every splat. The clouds look the same; a capture is reproducible on one renderer and one GPU, not across them.

`dev/samples/fx-steam.bytes`, `fx-flames.bytes` and `fx-dust.bytes` are three clouds (38, 270 and 130 splats); `dev/comparisons/fx-particles.gif` shows them in one scene.

## Marks

Lines drawn into the picture on top of what lies under them: an editor's grid, an outline round what is selected, the footprint of a thing being placed.

```gdscript
var lines: Array[SplatMark] = [SplatMark.new(from, to, Vector3.UP, Color8(244, 238, 222, 128))]   # alpha under 255: dotted
lines.append_array(SplatMark.outline(centre, half_u, half_v, Vector3.UP, Color8(255, 217, 77)))    # four sides
scene.set_marks(lines)      # every frame if you like; set_marks([]) takes them away
```

- **A line is a flat strip in the world:** from and to, the normal of the surface it lies on, and a colour. It is `SplatScene.mark_width` art pixels wide (1.6), and its ends go half a width further, so the sides of an outline meet at the corners.
- **Its colour is its own.** The pixel look shows it as it is, outside the palette and never inked. A colour with an alpha under 255 is drawn on every other art pixel, for a lighter line; no line is see-through, and every pixel of the picture is still covered or clear (measured: of 57,600 pixels of `dev/comparisons/fx-marks.png` before it was scaled up, none has an alpha other than 0 or 255).
- **A thing in front of a line hides it.** A line is depth-tested a tenth of a metre nearer the camera than it is, so the surface it lies on does not hatch through it; a line that passes behind a table leg's foot shows over the bottom of the leg for that reason.
- **Lines never rebuild the scene** and are handed to the GPU only when they differ from the last ones. Up to 4096 (`SplatScene.MAX_MARKS`). Where lines cross, the one given last shows.
- **Only the pixels a line covers change, nearly.** An art pixel shows a line when two or more of its four samples are the line's. With one, that sample goes through the pixel look with the others, so a pixel at a line's edge can take another palette colour: in the picture above the lines changed 3,804 pixels, and 998 of those took a colour that is not a line's. The Unity renderer does the same.
- What lines mean is the caller's business: the addon knows nothing of grids, selections or furniture.

## The debug panel

`debug/splat_debug_panel.gd` (`SplatDebugPanel`) is a small panel for judging the pixel look while the game runs. It finds every `SplatScene` in the tree by itself.

```gdscript
SplatDebugPanel.add_to(self)    # null, and nothing made, in a release export
```

- **F1** shows and hides it (`toggle_key`). **V** switches the look between the average and the vote, with the panel closed too (`look_key`).
- Its controls: the look, the dither (the average look only), and a slider for each picture's height in art pixels, 90 to 720, which keeps the picture's shape and takes effect on the next frame; "Reset art sizes" goes back to the sizes the pictures had when the panel found them. Nothing it changes is saved.
- **It exists only in debug builds, and only where a game asks for it.** Nothing in the addon creates it or refers to it. `add_to` makes nothing when `OS.is_debug_build()` is false or its second argument (the game's own condition) is false, and a panel put in the tree some other way frees itself in a release build. Checked by exporting a scene that tries both: the release export made no panel either way, the debug export both.
- The script itself is still in a release pack unless the game's export preset excludes `addons/splats/debug/*`. A game that does that must reach the panel by `load()` and only when the file is there, not by its class name.

`dev/comparisons/fx-panel-average.png` and `fx-panel-vote.png` show it switching the look, and `fx-panel-art-90.png` a picture made 90 art pixels high.

## How it draws

| Pass | Where | What |
|------|-------|------|
| Shadow cells, only with floor shadows | `shaders/splat_shadow_cast.gdshader`, in a 3D `SubViewport` of 512 x 512 | The floor's grid from above, one texel a cell. The same quads as the draw pass: each splat is carried down the sun's ray and marks the cell it lands in. |
| Draw | `shaders/splat_scene_draw.gdshader`, in a 3D `SubViewport` at twice the art size | One quad a splat (a `MultiMesh`). The vertex shader poses each splat by its bone and its instance's transform, moves it by itself if its instance is a particle cloud, and moves its colour along its ramp for the lamps and the dusk. Nothing is sorted: solid splats are cut out at half their Gaussian and written with depth. Then, with floor shadows, one quad (`shaders/splat_shadow.gdshader`) marks the samples that lie in a shadow, depth-tested against the splats. Then, with marks, one quad a line (`shaders/splat_mark_cut.gdshader`) clears the samples a line covers, depth-tested too. |
| Marks' colours, only with marks | `shaders/splat_mark_colour.gdshader`, in a 3D `SubViewport` of the samples' size | The same quads again, with no depth: each line's colour. |
| Resolve | `shaders/splat_resolve.gdshader`, in a 2D `SubViewport` at the art size | ink-studio's palette and ink look: inside a shape, the palette colour nearest the average of a pixel's four samples (or the one they vote for); on a silhouette, the voted colour inked darker. Samples in a floor shadow are darkened first, so a shadow takes the palette too. A sample that is clear in the samples and drawn in the marks' colours is a line's, and a pixel with two or more of them shows the line's colour as it is. Coverage is binary: alpha is 0 or 1. |
| Present | `shaders/splat_present.gdshader` | Nearest-neighbour scale-up, alpha clipped. |

- **No compute or geometry shaders.** Splats, instances, bones, light data and marks are float textures read with `texelFetch` in the vertex shader. It runs in Forward+, Mobile and the Compatibility renderer, with the same picture (but for about one pixel in a hundred where a sample sits between two palette colours, and for where some particles are in their loops: see "Particles").
- **The CPU's work a frame** is the instance matrices and the bones of clips whose frame changed (every frame of a fade), and the marks when they differ. The splat texture is rebuilt only when an instance appears, goes, hides or turns a quarter turn; a change of look or of clip, a particle cloud and marks do not rebuild it.
- **What particles and marks cost,** measured on an RTX 4070 SUPER in the Compatibility renderer, 76,228 splats at 320 x 180: the script 0.033 ms a frame and the passes 0.25 ms on the GPU; with four clouds (476 splats more) 0.035 ms and 0.26 ms; with 34 lines as well 0.039 ms and 0.27 ms, and 0.04 ms more of the engine's CPU time for the lines' own target. A rebuild of that scene takes 8.5 ms and neither causes one. The GPU figures are of a quiet run: on later runs the same scene with nothing added read anywhere from 0.45 to 1.4 ms, so at this size no GPU cost can be pinned on either.

## Differences from the Unity renderer

- **No z flip.** Unity is left-handed, so its reader flips z and its picture is mirrored against ink-studio's. Godot is right-handed like ink-studio, so the file's numbers are used as they are and the picture is the same way round as ink-studio's.
- **A second look for the inside of a shape** (`SplatScene.interior`). The default, `AVERAGE`, is Unity's: the palette colour nearest the average of a pixel's four samples, with an ordered dither. An average of two tones can be nearest a colour that is in neither, which shows as stray pixels in dark hair. `VOTE` takes the colour most samples vote for instead (a tie goes to the one nearest the average; in the average look the silhouette's tie goes to the first sample read; both as in the Unity shader): no strays, no dither, flatter, and less flicker in motion. The average is the default. `dev/comparisons/finding-interior-colour.png` shows ink-studio, the average and the vote; `dev/comparisons/motion-*.gif` show both in motion (average left, vote right), captured by `dev/tools/splat_motion.gd`. The demo's switch, or Tab, flips between them.
- **A prop's quarter turn** is counted in Unity's yaw in the file. `SplatClip.turn_of` converts from Godot's: +90 degrees about y is the file's set 3.
- **`.bytes` files are not Godot resources.** They are read with `FileAccess`. An export preset must list `*.bytes` under "Filters to export non-resource files".
- **Lamps, dusk and floor shadows are worked out on the GPU every frame.** The Unity renderer worked them out on the CPU and rebuilt its buffers whenever a lamp or a thing that casts a shadow moved. So here:
  - A clip is lit and casts its shadow as it is posed; in Unity, as the file holds it at rest.
  - Moving a lamp or a shadow rebuilds nothing, and there is no count of how many splats a lamp changed.
  - A shadow is marked in the samples and darkened by the pixel look, where Unity multiplied the samples' colour. The colours come out the same.
  - Floor shadows are off until `floor_shadows` is set, and the sun, the floor's height, a lamp's reach and strength are the scene's and the lamp's own properties.
- **A look is worn in the shader.** The Unity renderer made a new clip of only the shown splats, recoloured, for every look, and rebuilt its buffers. Here the whole wardrobe stays in the texture and a change of look writes a few rows. So an undressed instance is drawn whole, where Unity's picked the first piece of each kind by its name, and the scene's splat count includes the pieces not worn (`shown_splat_count()` leaves them out).
- **A fade is timed by the caller.** The Unity instance started a 0.3 second eased fade itself whenever its clip changed. Here the instance is handed both clips, their times and the weight.
- **An unknown section at the end of a file stops the read there and keeps what came before** (`SplatClip.unknown_section` names it). The Unity reader refused the file.
- **Marks are drawn twice.** The Unity renderer drew a line's quad straight into the samples with blending off and an alpha of a half, which its pixel look read as "a mark". Here an alpha of a half is a floor shadow's, and a Godot spatial shader cannot replace a colour and its alpha in one draw. So the lines' quads are drawn once over the samples, to clear what they cover (depth-tested), and once into a target of their own for their colours; a sample clear in the first and drawn in the second is a line's. The picture is the same: a line shows over an empty background too, as in Unity. A line lying in a floor shadow is not darkened, as in Unity (`dev/tools/splat_fx_report.gd` counts the same line pixels with the shadows on).
- **A particle's seed is the GPU's.** The formulas are the Unity shader's, number for number, with the seed taken from the splat's number in the scene as there. But the seed is a hash whose last bits depend on how a driver rounds, so the same cloud does not put each particle at the same point of its loop in Unity, in Forward+ and in Compatibility (see "Particles"). A cloud whose instance casts a floor shadow casts it where its splats are, since the shadow pass poses splats as the draw pass does (reasoned, not looked at); in Unity, where the file has them.
- **The debug panel is asked for.** The Unity one created itself after every scene load when the game's debug tools were on, and was an immediate-mode window. Here a game calls `SplatDebugPanel.add_to`, and the panel is ordinary controls on a `CanvasLayer`. It lists every `SplatScene`; the Unity one also listed the pictures of that project's second renderer, which is not ported.
- **One renderer.** The Unity project had a second one for a single avatar in a transparent window, which sorted its splats and blended them, and so could draw splats with a density below 1 as soft dabs. This one draws only solid splats. None of the 63 files that project built has a splat below density 1 (every one of 694,606 is solid), and nor has any sample here, so nothing is lost by it; a file that had some would be drawn without them. What does differ is the edge of a solid splat: blended there, cut out here, which the pixel look then resolves the same way.

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

The tinted ghost: in the Unity renderer an instance could be given a tint, and was then drawn in that colour on every other art pixel, for a thing being placed. Here a thing being placed is drawn as it is, with its footprint as marks.

## Checking it

```sh
python dev/make_project.py <folder>
godot --path <folder> --headless --import
godot --path <folder> --headless -s res://tests/test_runner.gd
godot --path <folder> -s res://splats/tools/splat_report.gd
godot --path <folder> --rendering-method gl_compatibility -s res://splats/tools/splat_report.gd -- --tag=compat
```

The test runner runs every `test_*.gd` in `dev/tests`. The last two need a window. They write `splats/comparisons/` in the assembled project (the ones worth keeping are copied by hand to `dev/comparisons/`): each sample asset beside ink-studio's own render of it (`splats/reference/`), the demo scene, and the demo's splat count and frame time.

The light has a report of its own. It needs a window too, and a furnished room's assets, which this repository does not hold: hand a folder of them to `make_project.py --samples`.

```sh
godot --path <folder> -s res://splats/tools/splat_light_report.gd -- --reference=<folder of reference renders> --look=vote
```

It draws a room by day, at dusk and with a lamp, beside reference renders of the same room when it is given some, checks the shaders' light against `SplatLight`'s rules, and measures a frame and a rebuild.

The particles, the marks and the debug panel have one, which needs a window and the samples (and stands its scene on a floor if `floor.bytes` was handed to `make_project.py --samples`):

```sh
godot --path <folder> -s res://splats/tools/splat_fx_report.gd -- --tag=compat
godot --path <folder> --rendering-method forward_plus -s res://splats/tools/splat_fx_report.gd -- --tag=forward
```

It captures 48 frames of the three sample clouds in one scene, a frame with a dotted grid and two outlines, and the window with the panel open in each look. It checks the shader's particles against `SplatParticles`, that neither particles nor marks rebuild anything, that every pixel with marks is covered or clear, that a dotted line is on every other art pixel and that a thing in front hides a line, and that the panel's keys work; and it prints what a frame costs with and without. It passes in Compatibility, Forward+ and Mobile (2026-11-19, Windows, one NVIDIA GPU).

The wardrobe and the clips have one too, which needs a window and nothing but the samples:

```sh
godot --path <folder> -s res://splats/tools/splat_wardrobe_report.gd -- --reference=<folder with avatar-looks.png>
```

It draws eight looks of the sample avatar in a row (on a floor, if `floor.bytes` was handed to `make_project.py --samples`), under a reference render of the same row when it is given one, and one avatar at its desk through every clip with a fade between, as 180 frames to make a GIF of. It checks that neither a change of look nor of clip rebuilds anything and that each look's colours and pieces are in the picture, and prints what a change of look costs. `dev/comparisons/wardrobe-looks.png` is the row (the Unity render above, this addon below) and `dev/comparisons/clips.gif` the clips.

## Licence

MIT, see [LICENSE](LICENSE). The pinned ink-studio in `tools/ink-studio/` is its authors' work under its own MIT licence (`tools/ink-studio/LICENSE`). The sample assets and pictures in `dev/` are included for testing the addon.
