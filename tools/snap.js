#!/usr/bin/env node
/* Reference renders of every splat asset, so a change in the look shows up in review. Run from the game's root (see lib.js):

     node <this folder>/snap.js             render each asset at its manifest times into the kept snapshots (checked in)
     node <this folder>/snap.js --check     render again and compare with the kept pictures; fails on any difference
     node <this folder>/snap.js <id> ...    only those assets

   A picture is ink-studio's own software render of the scene (its camera, the pixel look, one image pixel per art pixel), at
   320 x 320. It shows what the scene authors, not the game's renderer.
   --check writes a side-by-side of each difference (kept | now) to .splat-diffs/ under the game's root; ignore that folder. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { INK, SNAPS, kit, chosen, sun, at } = require('./lib.js');
const R = require(path.join(INK, 'cli', 'render.js'));
const PNG = require(path.join(INK, 'cli', 'png.js'));

// where --check writes its side-by-sides: under the game's root, or anywhere when SPLAT_DIFFS is an absolute path
const DIFFS = path.isAbsolute(process.env.SPLAT_DIFFS || '') ? process.env.SPLAT_DIFFS : at(process.env.SPLAT_DIFFS || '.splat-diffs');
const SIZE = 320;

const args = process.argv.slice(2);
const check = args.includes('--check');
const names = args.filter(a => !a.startsWith('--'));

// Put the world at time t, as ink-studio's command line does: splats on bones stay at rest in the data, so the renderer is given a
// posed copy. The chibi's clips are pure functions of time, so times need not be asked in order.
function pose(K, w, t) {
  if (!w.anim) return;
  if (w.anim.stateful) throw new Error('a stateful scene needs stepping from 0; snap.js only handles clips that are functions of time');
  w.anim.update(1 / 60, t);
  if (w.anim.bones) {
    if (!w.rest) w.rest = w.data;
    w.data = K.KIT.bones.posed({ data: w.rest, anim: w.anim, get posedBuf() { return w.posedBuf; }, set posedBuf(v) { w.posedBuf = v; } });
  }
}

let different = 0, missing = 0, kept = 0;
for (const a of chosen(names)) {
  const times = a.snaps || [0];
  const K = kit();
  // a game that names its sun sees its assets under it; without one a scene keeps its own, as before
  const scene = sun() ? require(at(a.scene))(K, { sun: sun() }) : require(at(a.scene))(K);
  const w = scene.build(scene.seed);
  for (const t of times) {
    pose(K, w, t);
    const im = R.render(w, { t, colored: true, w: SIZE, h: SIZE });
    const file = path.join(SNAPS, `${a.id}@${t}.png`);
    if (!check) {
      fs.mkdirSync(SNAPS, { recursive: true });
      PNG.write(file, im.w, im.h, im.rgb);
      kept++;
      continue;
    }
    if (!fs.existsSync(file)) {
      console.error(`${a.id} at ${t} s: no kept picture (${path.relative(at('.'), file)})`);
      missing++;
      continue;
    }
    const ref = PNG.read(file);
    let pixels = 0;
    if (ref.w !== im.w || ref.h !== im.h) pixels = -1;
    else
      for (let p = 0; p < im.w * im.h; p++)
        if (ref.rgb[p * 3] !== im.rgb[p * 3] || ref.rgb[p * 3 + 1] !== im.rgb[p * 3 + 1] || ref.rgb[p * 3 + 2] !== im.rgb[p * 3 + 2]) pixels++;
    if (pixels === 0) continue;
    different++;
    fs.mkdirSync(DIFFS, { recursive: true });
    const both = R.grid([R.upscale(ref, 3), R.upscale(im, 3)], 2); // kept on the left, now on the right (its font has digits only)
    const diff = path.join(DIFFS, `${a.id}@${t}.png`);
    PNG.write(diff, both.w, both.h, both.rgb);
    console.error(`${a.id} at ${t} s: ` + (pixels < 0 ? `size changed, ${ref.w}x${ref.h} -> ${im.w}x${im.h}` : `${pixels} of ${im.w * im.h} pixels differ`) +
                  `; see ${path.relative(at('.'), diff)}`);
  }
  console.log(`${a.id}: ${check ? 'checked' : 'kept'} at ${times.join(', ')} s`);
}
if (check && (different || missing)) {
  console.error(`${different} picture(s) differ, ${missing} missing. If the change is meant, run snap.js and check the new pictures in.`);
  process.exit(1);
}
if (!check) console.log(`${kept} picture(s) in ${path.relative(at('.'), SNAPS)}/`);
