/* Turns an ink-studio splat scene into the TCRS splat format (../FORMAT.md is its specification).
   A clip (a puppet and its frames) is version 1. A prop (no puppet: furniture, the room's shell) is version 2: the same layout
   with no bones or frames, then a colour set for each of the four ways it can stand, then its light data.
   A clip with light data (an avatar in the room) is version 3: version 1, then its light data.
   A library, not a command: build.js calls it for every asset in the game's manifest.

   The scene is an ink-studio scene file in the game's repository, built with the pinned ink-studio beside this file.
   The file holds ink-studio's own numbers, untouched (its right-handed world, metres, Y up); a reader converts them if its engine's
   space differs (Godot's does not).

   The format's specification is FORMAT.md, one folder up: change it in the same check-in as anything written here.
   What follows is a summary of it.

   Layout, little-endian:
     "TCRS"  int32 version (1)  int32 splats  int32 palette  int32 bones  int32 frames  float32 fps
     float32 x 7: camera target x y z, dist, pitch, yaw (radians), detail
     uint32 x palette: 0xRRGGBB, index 0 is the background
     float32 x 16 x splats: ink-studio's record (position, density, covariance, packed colour, kind, bone ids and weight)
     float32 x 12 x bones x frames: each bone's 3x3 (by rows) then its translation, frame by frame at fps
     int32 references  int32 samples  int32 x samples: splat indices
     per reference: int32 frame, float32 x 3 x samples: those splats' posed positions (K.bones.posed), the skinning test's answer
   Version 2 only, after that:
     int32 colourSets (4), then float32 x splats per set: each splat's packed colour when the prop is turned k x 90 degrees
     about y in the game (Unity's yaw). Set 0 is also the colour in the splat records.

   Light data (versions 2 and 3), so the game can light a splat again when a lamp is near or the day dims:
     int32 ramps, then per ramp: int32 length, int32 x length palette indices, dark to light
     int32 x splats: the ramp each splat was shaded on, or -1 (glowing and flat splats keep their colour)
     int32 sets (4 for a prop, 1 for a clip), then float32 x splats per set: how bright each splat came out, 0 to 1;
       its colour is its ramp's entry at floor(brightness x length)
     float32 x 3 x splats: each splat's surface normal

   A look (optional, after everything else in a clip), when the scene's world carries W.look: the player's avatar,
   holding every piece it can wear and every colour it can be given:
     "LOOK"  int32 pieces, then per piece: int32 length, its name in UTF-8
     int32 x splats: the piece each splat belongs to, or -1 for a splat that always shows (a desk, a device)
     int32 regions, then per region: int32 length, its name in UTF-8, int32 count, int32 x count palette indices, dark to light
   The game shows the pieces a look wears and gives each region the ramp of the colour the player picked. It finds a splat's
   palette colour by its colour, so a region's colours must each appear once in the palette: the export refuses otherwise.

   More clips (optional, after everything else in a clip), when the scene's world carries W.clips and W.play: one
   character and rig, several named clips. The clip in the header is the first of them.
     "CLPS"  int32 clips, then per clip: int32 length, its name in UTF-8, int32 frames, float32 fps, and
       float32 x 12 x bones x frames (as the header's); the first clip has 0 frames here: its frames are the header's.
       Then int32 frame and float32 x 3 x samples: the header's sample splats posed at one frame of this clip, for the
       skinning test (the first clip has frame -1 and no positions: its references are the header's).
   Sections come in any order; each starts with its four-letter mark.

   The world's one sun is fixed in the game's world: the manifest's "sun", or DEFAULT_SUN below, pointing at the sun, in
   ink-studio's space (metres, Y up, right-handed), which is also Godot's. A prop turned by a yaw sees it turned the other
   way, so each of its four sets is a bake with that sun turned. Set k is for k quarter turns in Unity's yaw (clockwise seen
   from above), as FORMAT.md says; in this right-handed space that is the sun turned by +k quarter turns about y. */
'use strict';
const path = require('node:path');

const FORMAT_VERSION = 1, PROP_VERSION = 2, LIT_CLIP_VERSION = 3;

/** The sun when the manifest names none, pointing at the sun (not normalised), in ink-studio's and Godot's right-handed
    space. Assets built before the manifest could name one were lit by it, so it must not change. */
const DEFAULT_SUN = [-0.3, 0.75, 0.6];

/** The sun as a prop sees it when the game has turned it k quarter turns (the file's set k), in ink-studio's space. */
function sunFor(k, sun = DEFAULT_SUN) {
  const a = (k * Math.PI) / 2, c = Math.round(Math.cos(a)), s = Math.round(Math.sin(a)), [x, y, z] = sun;
  // the sun turned by +a about y, right-handed: x' = x cos a + z sin a, z' = -x sin a + z cos a
  return [x * c + z * s, y, -x * s + z * c];
}

const f32 = a => Buffer.from(a.buffer, a.byteOffset, a.byteLength);
const i32 = a => Buffer.from(Int32Array.from(a).buffer);

/** Listens to a bake (ink-studio's K.light.capture): which ramp each splat was shaded on, how bright, and its normal. */
function listen(kit, into) {
  return (B, S) => { into.cap = kit.KIT.light.capture(B, S); };
}

/** The light data of one or more bakes of the same scene (one per turn). Checks that a ramp and a brightness do give the colour. */
function lightSection(sceneFile, worlds, caps) {
  const W = worlds[0], cap = caps[0], n = W.count;
  const ramps = cap.ramps, rampOf = new Int32Array(n).fill(-1), normals = new Float32Array(n * 3);
  let lit = 0, wrong = 0;
  for (let i = 0; i < n; i++) {
    if (!cap.ramp[i]) continue;
    rampOf[i] = cap.ramp[i] - 1;
    normals.set(cap.n[i], i * 3);
    lit++;
  }
  const sets = worlds.map((w, k) => {
    const c = caps[k], t = new Float32Array(n);
    if (c.ramps.length !== ramps.length) throw new Error(sceneFile + ': turn ' + k + ' was shaded on different ramps');
    for (let i = 0; i < n; i++) {
      if (rampOf[i] < 0) continue;
      if (!c.ramp[i] || c.ramp[i] - 1 !== rampOf[i]) throw new Error(sceneFile + ': splat ' + i + ' changed ramp at turn ' + k);
      t[i] = Math.min(1, Math.max(0, c.t[i]));
      const ramp = ramps[rampOf[i]], index = Math.min(ramp.length - 1, Math.max(0, Math.floor(c.t[i] * ramp.length)));
      const colour = w.pal[ramp[index]], packed = ((colour >> 16) & 255) + ((colour >> 8) & 255) * 256 + (colour & 255) * 65536;
      if (packed !== w.data[i * 16 + 7]) wrong++;
    }
    return t;
  });
  const parts = [i32([ramps.length])];
  for (const ramp of ramps) parts.push(i32([ramp.length]), i32(ramp));
  parts.push(i32(rampOf), i32([sets.length]));
  for (const t of sets) parts.push(f32(t));
  parts.push(f32(normals));
  return { parts, lit, wrong };
}

const str = s => { const b = Buffer.from(s, 'utf8'); return Buffer.concat([i32([b.length]), b]); };

/** The look section: which splats are which piece, and which palette colours are which region's ramp. */
function lookSection(sceneFile, W) {
  const names = Object.keys(W.look.pieces), pieceOf = new Int32Array(W.count).fill(-1);
  names.forEach((name, p) => {
    for (const i of W.look.pieces[name]) {
      if (pieceOf[i] !== -1) throw new Error(sceneFile + ': splat ' + i + ' is in two pieces, ' + names[pieceOf[i]] + ' and ' + name);
      pieceOf[i] = p;
    }
  });
  const parts = [Buffer.from('LOOK', 'ascii'), i32([names.length]), ...names.map(str), i32(pieceOf)];
  const regions = Object.entries(W.look.regions);
  parts.push(i32([regions.length]));
  for (const [name, indices] of regions) {
    for (const index of indices)
      if (W.pal.filter(c => c === W.pal[index]).length !== 1)
        throw new Error(sceneFile + ': the ' + name + " region's colour 0x" + W.pal[index].toString(16) + ' is in the palette more than once, so the game could not tell its splats apart');
    parts.push(str(name), i32([indices.length]), i32(indices));
  }
  return { parts, pieces: names.length, regions: regions.length };
}

/** Builds the scene and returns { bytes, stats }. kit is ink-studio's load(); the result depends only on the scene and the options. */
function exportClip(kit, sceneFile, { fps = 30, secs = 8, light = false, sun } = {}) {
  const heard = {};
  // A clip is baked once, under the game's sun when the manifest names one (a scene may ignore it and keep a light of its
  // own, as a character lit from the front does). With no sun named the scene is given what it always was, so its file is the same.
  const opts = {};
  if (sun) opts.sun = sun;
  if (light) opts.onSculpt = listen(kit, heard);
  const scene = require(path.resolve(sceneFile))(kit, sun || light ? opts : undefined);
  const W = scene.build(scene.seed);
  const anim = W.anim;
  if (!anim || !anim.bones || !anim.boned) throw new Error(sceneFile + ': the scene has no puppet, so nothing rides on bones');

  // only plain splats (kind 0) and splats on bones (kind 12) are drawn by the game's renderer; anything else is refused, not dropped
  const kinds = {};
  for (let i = 0; i < W.count; i++) {
    const kind = Math.round(W.data[i * 16 + 11]) % 16;
    kinds[kind] = (kinds[kind] || 0) + 1;
  }
  const unsupported = Object.keys(kinds).filter(k => k !== '0' && k !== '12');
  if (unsupported.length)
    throw new Error(sceneFile + ': kinds the game cannot draw: ' + unsupported.map(k => k + ' (' + kinds[k] + ')').join(', '));

  const nb = anim.bones.length / 12, frames = Math.round(fps * secs);
  const boned = Array.from(anim.boned);
  // the skinning test's sample: 256 splats spread over those on bones
  const samples = [];
  for (let s = 0; s < 256; s++) samples.push(boned[Math.floor((s * boned.length) / 256)]);

  // one clip's frames, sampled from time 0 (clips are pure functions of time), with the samples' posed positions at some frames
  const take = (count, refFrames) => {
    const bones = new Float32Array(count * nb * 12), refs = [];
    anim.update(0, 0);
    for (let f = 0; f < count; f++) {
      if (f > 0) anim.update(1 / fps, f / fps);
      bones.set(anim.bones, f * nb * 12);
      if (refFrames.includes(f)) {
        const posed = kit.KIT.bones.posed(W), pos = new Float32Array(samples.length * 3);
        samples.forEach((i, s) => { pos[s * 3] = posed[i * 16]; pos[s * 3 + 1] = posed[i * 16 + 1]; pos[s * 3 + 2] = posed[i * 16 + 2]; });
        refs.push({ frame: f, pos });
      }
    }
    return { bones, refs };
  };
  const { bones, refs } = take(frames, [0, Math.round(frames * 0.37), Math.round(frames * 0.7)]);
  // the other clips of the same character, if the scene has any
  const more = [];
  if (W.clips && W.clips.length > 1) {
    if (!W.play) throw new Error(sceneFile + ': the scene lists clips but cannot play them (W.play)');
    for (const c of W.clips.slice(1)) {
      W.play(c.name);
      const count = Math.round(fps * c.secs), ref = Math.round(count * 0.37);
      more.push(Object.assign({ name: c.name, frames: count }, take(count, [ref])));
    }
    W.play(W.clips[0].name);
    anim.update(0, 0);
  }

  const cam = W.cam || {};
  const head = Buffer.alloc(4 + 4 * 6 + 4 * 7);
  let o = 0;
  head.write('TCRS', o, 'ascii'); o += 4;
  for (const v of [light ? LIT_CLIP_VERSION : FORMAT_VERSION, W.count, W.pal.length, nb, frames]) { head.writeInt32LE(v, o); o += 4; }
  head.writeFloatLE(fps, o); o += 4;
  const T = cam.target || [0, 0, 0];
  for (const v of [T[0], T[1], T[2], cam.dist || 0, cam.pitch || 0, cam.yaw || 0, W.detail || 0]) { head.writeFloatLE(v, o); o += 4; }
  const pal = Buffer.alloc(W.pal.length * 4);
  W.pal.forEach((c, i) => pal.writeUInt32LE(c >>> 0, i * 4));
  const parts = [head, pal, f32(W.data.subarray(0, W.count * 16)), f32(bones), i32([refs.length, samples.length]), i32(samples)];
  for (const r of refs) parts.push(i32([r.frame]), f32(r.pos));
  let lit;
  if (light) {
    if (!heard.cap) throw new Error(sceneFile + ': the scene never called opts.onSculpt, so its light was not heard');
    lit = lightSection(sceneFile, [W], [heard.cap]);
    parts.push(...lit.parts);
  }
  let look;
  if (W.look) {
    look = lookSection(sceneFile, W);
    parts.push(...look.parts);
  }
  if (W.clips && W.clips.length) {
    const f1 = v => { const b = Buffer.alloc(4); b.writeFloatLE(v, 0); return b; };
    parts.push(Buffer.from('CLPS', 'ascii'), i32([W.clips.length]), str(W.clips[0].name), i32([0]), f1(fps), i32([-1]));
    for (const c of more) parts.push(str(c.name), i32([c.frames]), f1(fps), f32(c.bones), i32([c.refs[0].frame]), f32(c.refs[0].pos));
  }
  const bytes = Buffer.concat(parts);
  return { bytes, stats: { splats: W.count, onBones: boned.length, bones: nb, frames, fps, palette: W.pal.length, bytes: bytes.length, lit: lit && lit.lit, wrong: lit && lit.wrong, pieces: look && look.pieces, regions: look && look.regions, clips: W.clips ? W.clips.map(c => c.name) : undefined } };
}

/** A prop: no puppet, four colour sets. The four bakes must put every splat in the same place, or it is refused. */
function exportProp(kit, sceneFile, { sun = DEFAULT_SUN } = {}) {
  const factory = require(path.resolve(sceneFile));
  const heard = [{}, {}, {}, {}];
  const worlds = [0, 1, 2, 3].map(k => { const scene = factory(kit, { sun: sunFor(k, sun), onSculpt: listen(kit, heard[k]) }); return scene.build(scene.seed); });
  if (heard.some(h => !h.cap)) throw new Error(sceneFile + ': the scene never called opts.onSculpt, so its light was not heard');
  const W = worlds[0];
  if (W.anim && W.anim.bones) throw new Error(sceneFile + ': a prop has no puppet; export it as a clip');
  for (let i = 0; i < W.count; i++) {
    const kind = Math.round(W.data[i * 16 + 11]) % 16;
    if (kind !== 0) throw new Error(sceneFile + ': splat ' + i + ' is kind ' + kind + '; a prop holds plain splats only');
  }
  const sets = worlds.map((w, k) => {
    if (w.count !== W.count) throw new Error(sceneFile + ': turn ' + k + ' baked ' + w.count + ' splats, turn 0 ' + W.count);
    const colours = new Float32Array(W.count);
    for (let i = 0; i < W.count; i++) {
      const q = i * 16;
      for (const o of [0, 1, 2, 3, 4, 5, 6, 8, 9, 10])
        if (w.data[q + o] !== W.data[q + o]) throw new Error(sceneFile + ': splat ' + i + ' moved between turn 0 and turn ' + k);
      colours[i] = w.data[q + 7];
    }
    return colours;
  });

  const cam = W.cam || {};
  const head = Buffer.alloc(4 + 4 * 6 + 4 * 7);
  let o = 0;
  head.write('TCRS', o, 'ascii'); o += 4;
  for (const v of [PROP_VERSION, W.count, W.pal.length, 0, 0]) { head.writeInt32LE(v, o); o += 4; }
  head.writeFloatLE(0, o); o += 4;
  const T = cam.target || [0, 0, 0];
  for (const v of [T[0], T[1], T[2], cam.dist || 0, cam.pitch || 0, cam.yaw || 0, W.detail || 0]) { head.writeFloatLE(v, o); o += 4; }
  const pal = Buffer.alloc(W.pal.length * 4);
  W.pal.forEach((c, i) => pal.writeUInt32LE(c >>> 0, i * 4));
  const parts = [head, pal, f32(W.data.subarray(0, W.count * 16)), i32([0, 0]), i32([sets.length])];
  for (const c of sets) parts.push(f32(c));
  const lit = lightSection(sceneFile, worlds, heard.map(h => h.cap));
  parts.push(...lit.parts);
  const bytes = Buffer.concat(parts);
  let turned = 0;
  for (let i = 0; i < W.count; i++) if (sets.some(c => c[i] !== sets[0][i])) turned++;
  return { bytes, stats: { splats: W.count, onBones: 0, bones: 0, frames: 0, fps: 0, palette: W.pal.length, bytes: bytes.length, turned, lit: lit.lit, wrong: lit.wrong } };
}

module.exports = { exportClip, exportProp, sunFor, DEFAULT_SUN, FORMAT_VERSION, PROP_VERSION, LIT_CLIP_VERSION };
