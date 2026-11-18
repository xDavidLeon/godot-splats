#!/usr/bin/env node
/* Exports every splat asset in the game's manifest to its .bytes file (the TCRS format, ../FORMAT.md), and nothing else.
   Run from the game's root (see lib.js for where the manifest is looked for):

     node <this folder>/build.js            every asset
     node <this folder>/build.js <id> ...   only those
     node <this folder>/build.js --check    writes nothing: fails if a .bytes file is not what its scene exports now

   The output depends only on the scene, the pinned ink-studio and the manifest's fps and secs, so running it twice gives
   byte-identical files. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { kit, chosen, at, sun } = require('./lib.js');
const { exportClip, exportProp } = require('./export.js');

const args = process.argv.slice(2);
const check = args.includes('--check');
const names = args.filter(a => !a.startsWith('--'));

let stale = 0;
for (const a of chosen(names)) {
  const { bytes, stats } = a.kind === 'prop' ? exportProp(kit(), at(a.scene), { sun: sun() }) : exportClip(kit(), at(a.scene), { fps: a.fps, secs: a.secs, light: a.light === true, sun: sun() });
  const out = at(a.out);
  const before = fs.existsSync(out) ? fs.readFileSync(out) : null;
  const same = before !== null && before.equals(bytes);
  if (check) {
    if (!same) stale++;
  } else if (!same) {
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, bytes);
  }
  const state = check ? (same ? 'up to date' : before ? 'STALE' : 'MISSING') : same ? 'unchanged' : before ? 'rewritten' : 'written';
  const what = a.kind === 'prop'
    ? `${stats.splats} splats, 4 turns (${stats.turned} change colour with the turn)`
    : `${stats.splats} splats (${stats.onBones} on ${stats.bones} bones), ${stats.frames} frames at ${stats.fps} fps`;
  const light = stats.lit === undefined ? '' : `, ${stats.lit} can be lit again` + (stats.wrong ? ` (${stats.wrong} colours do NOT follow from their ramp)` : '');
  const look = stats.pieces === undefined ? '' : `, a wardrobe of ${stats.pieces} pieces and ${stats.regions} colour regions`;
  const clips = stats.clips && stats.clips.length > 1 ? `, clips ${stats.clips.join(' ')}` : '';
  console.log(`${a.id}: ${what}${clips}${light}${look}, ${stats.palette} colours, ${stats.bytes} bytes -> ${a.out} [${state}]`);
}
if (stale) {
  console.error(`${stale} asset(s) differ from their scene; run build.js`);
  process.exit(1);
}
