# The TCRS splat file format

Format versions 1, 2 and 3. This document, revision 6 (2026-11-19): the format is unchanged; the two optional sections are spelled out as this addon's reader now reads them, and two reference files have them. Revision 5 was wording only. Revision 4 added whose sun a prop's four bakes are lit by.

A TCRS file (`.bytes`) holds one splat asset: a prop, or a boned character with a clip. It is written by `tools/export.js` in this repository from an ink-studio scene, and read by this addon's `splat_clip.gd`. The format was first read by a Unity renderer of the same design, which is why some of its conventions are Unity's.

**This document is the specification, and this repository is its home.** `tools/export.js` implements it. A change to what the exporter writes changes this document in the same commit, with a new revision number above. A reader can be written from this document alone.

## Rules

- **Byte order:** little-endian throughout. `int32` and `uint32` are 4 bytes, `float32` is IEEE 754 single precision.
- **Space:** the file holds ink-studio's own numbers, untouched: metres, Y up, right-handed. A reader converts if its engine differs. Unity's reader flips z; Godot's does not.
- **A version never changes meaning.** Files already built must still read. New data goes in a new section with a new mark, or in a new version number.
- **Sections carry no length.** A reader that meets a mark it does not know cannot skip it: it must stop there and keep what it has read.

## Layout

All versions start the same way.

| Part | Type | Notes |
|---|---|---|
| Mark | 4 bytes | ASCII `TCRS` |
| Version | int32 | 1: a clip. 2: a prop. 3: a clip with light data |
| Splats | int32 | N, more than 0 |
| Palette | int32 | P, more than 0 |
| Bones | int32 | B. 0 for a prop |
| Frames | int32 | F. 0 for a prop |
| Fps | float32 | 0 for a prop |
| Camera | float32 x 7 | Target x y z, distance, pitch, yaw (radians), detail. ink-studio's framing of its own reference render; for reference only |
| Palette | uint32 x P | `0xRRGGBB`, sRGB. Index 0 is the background |
| Splats | float32 x 16 x N | See "A splat" |
| Bones | float32 x 12 x B x F | Frame by frame at Fps; per bone a 3x3 by rows, then its translation |
| References | int32, int32 | R reference frames, S sample splats |
| Sample | int32 x S | Indices of splats |
| Per reference | int32, float32 x 3 x S | A frame, then the sample splats' posed positions at it: the skinning test's answer |

A prop has B = F = R = S = 0, so those parts are empty.

**Version 2 only, next:**

| Part | Type | Notes |
|---|---|---|
| Colour sets | int32 | Always 4 |
| Per set | float32 x N | Each splat's packed colour when the prop is turned k quarter turns about y, in Unity's yaw. Set 0 equals the colour in the splat records |

**Light data, next** in version 3 always, and in version 2 unless the file ends here (props written before light data existed):

| Part | Type | Notes |
|---|---|---|
| Ramps | int32 | Count |
| Per ramp | int32, int32 x length | Palette indices, dark to light |
| Ramp of | int32 x N | The ramp each splat was shaded on, or -1 for one that keeps its colour |
| Sets | int32 | 4 for a prop, 1 for a clip |
| Per set | float32 x N | How bright each splat came out, 0 to 1. Its colour is its ramp's entry at floor(brightness x length) |
| Normals | float32 x 3 x N | Each splat's surface normal |

**Optional sections, last**, in any order, each starting with a four-letter mark:

- `LOOK`, a wardrobe: int32 pieces, then per piece a name; int32 x N, the piece each splat belongs to or -1; int32 regions, then per region a name, int32 count, and that many palette indices, dark to light.
- `CLPS`, more clips on the same rig: int32 clips, then per clip a name, int32 frames, float32 fps, float32 x 12 x B x frames, int32 reference frame, and float32 x 3 x S posed positions unless the reference frame is -1. The first clip is the header's: it has 0 frames here and reference frame -1.

A name is an int32 length (1 to 256) and that many bytes of UTF-8.

**A wardrobe** holds every piece whole: a hairstyle and the hair that shows under a hat, a plain top and a patterned one, each with all its splats. A drawer shows the pieces it is told to and the splats of no piece (-1), and nothing else.

- 1 to 1024 pieces. A splat's piece is -1 or an index into them.
- 0 to 256 regions, each of 1 to 256 palette indices. A region is a ramp a drawer may recolour: it replaces those palette entries, dark to light, with as many colours of its own.
- **A splat carries its colour, not its palette index.** So each colour of a region is in the palette once, and a splat of that colour is that region's. The exporter refuses a scene where a region's colour is there twice.
- The light data's ramps are palette indices too, so a recoloured region is relit along its new colours.
- The names are the scene's own. The sample files name a piece `slot:name` (`hair:bun`, `top:stripes`), which the format does not know about.

**More clips** share the header's rig: the same B bones in the same order, and the same S sample splats.

- 1 to 256 clips, each name there once.
- The first is the header's own clip, here only to be named: 0 frames (its fps is not read), reference frame -1. A file with no `CLPS` section has one clip with no name.
- Every later clip has more than 0 frames, an fps above 0, and a reference frame that is -1 or one of its own frames.
- A part a clip hides is parked by its bone, far below the floor (see "A splat"). Mixing two clips' bones for a fade must not mix such a bone: it would carry the part through the picture. This addon gives a bone that either clip parks the new clip's matrix at once.

## A splat

Sixteen floats, ink-studio's own record:

| Index | Meaning |
|---|---|
| 0 to 2 | Position x y z |
| 3 | Density. 1 or more is solid. This addon draws only solid splats; a renderer that sorts and blends may also draw softer ones |
| 4, 5, 6 | Covariance c00, c01, c02 |
| 7 | Packed colour: r + g x 256 + b x 65536, each 0 to 255 |
| 8, 9, 10 | Covariance c11, c12, c22 |
| 11 | Kind. `round(kind) mod 16` is 0 for a plain splat and 12 for one on bones; no other kind is written |
| 12, 13 | Bone, and second bone |
| 14 | The second bone's weight, 0 to 1 |
| 15 | Spare |

A splat on bones is posed as `p' = M1 p + t1`, then moved toward `M2 p + t2` by the weight when the weight is above 0; its covariance becomes `M1 C M1^T`. A posed splat below y = -30 is hidden (ink-studio parks hidden parts at y = -99).

## Quarter turns

A prop's four colour sets and four light sets are bakes with the world's one sun, for the four ways the prop can stand. Set k is for a turn of k x 90 degrees about y in Unity's yaw, which is clockwise seen from above. A right-handed engine turns the other way: in Godot, +90 degrees is set 3.

The sun is the game's own, not part of the format: the exporter takes it from the game's manifest (`"sun": [x, y, z]`, pointing at the sun, in ink-studio's space) and bakes set k with that sun turned by k quarter turns about y. A clip is baked once, under the same sun. A file does not record which sun it was baked with. Without one in the manifest the exporter uses its default, `[-0.3, 0.75, 0.6]`.

## Reference files

Six files every reader must read identically, in `dev/samples/`:

- `mug.bytes`, `teapot.bytes` and `desk-set.bytes`: version 2.
- `avatar-b.bytes`: version 3, 8 bones, 240 frames, no optional section.
- `avatar-a-stand.bytes`: version 3, 8 bones, with `LOOK` (13 pieces, 7 regions) and a `CLPS` that only names its one clip.
- `avatar-a.bytes`: version 3, 9 bones, with `LOOK` (17 pieces, 7 regions) and `CLPS` (6 clips of 240 frames).

`dev/tests/test_splat_clip.gd` holds numbers read from them with an independent script, checks skinning against the posed positions each file stores (for every clip of `avatar-a.bytes`), and builds small files of its own for what a reader must refuse.
