/* What build.js and snap.js share. Everything goes through the pinned ink-studio beside this file (see its VENDORED.md),
   never a checkout somewhere else, and through the game's one manifest.

   These tools live in the splat library and are run from a game's root folder:
     the game's root   the folder the command is run in, or SPLAT_ROOT
     the manifest      splats/assets.json under the root, or SPLAT_MANIFEST (a path under the root)
     kept snapshots    splats/snaps under the root, or SPLAT_SNAPS (a path under the root)
   Paths in the manifest are relative to the game's root.

   The manifest may name the game's sun, beside "assets": "sun": [x, y, z], pointing at the sun, in ink-studio's and Godot's
   space (Y up, right-handed). Props' four bakes, clips and the reference snapshots are all lit by it; a scene may ignore
   it and keep a light of its own. Without it props use the exporter's default and a clip's scene is given none. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(process.env.SPLAT_ROOT || process.cwd());
const INK = path.join(__dirname, 'ink-studio');
const MANIFEST = path.join(ROOT, process.env.SPLAT_MANIFEST || 'splats/assets.json');
const SNAPS = path.join(ROOT, process.env.SPLAT_SNAPS || 'splats/snaps');
const NAME = path.relative(ROOT, MANIFEST).replace(/\\/g, '/');

let loaded;
/** ink-studio's toolkit: { makeBuilder, makeSculpt, KIT, ... }. Compiled once into ink-studio/dist (ignored by git). */
const kit = () => loaded || (loaded = require(path.join(INK, 'index.js')).load());

/** The manifest's "sun", checked, or undefined when it names none (the exporter then uses its default). */
let sunRead = false, sunValue;
function sun() {
  if (sunRead) return sunValue;
  sunRead = true;
  if (!fs.existsSync(MANIFEST)) return undefined;
  const value = JSON.parse(fs.readFileSync(MANIFEST, 'utf8')).sun;
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length !== 3 || !value.every(v => typeof v === 'number' && Number.isFinite(v)) || !value.some(v => v !== 0))
    throw new Error(NAME + ': "sun" is three numbers, [x, y, z], pointing at the sun, and not all zero');
  return (sunValue = value);
}

/** The manifest's assets, each checked: { id, scene, out, kind ('clip' by default, or 'prop'), fps, secs, snaps: [seconds] }. */
function assets() {
  if (!fs.existsSync(MANIFEST)) throw new Error('no manifest at ' + MANIFEST + ': run from the game\'s root, or set SPLAT_ROOT and SPLAT_MANIFEST');
  const list = JSON.parse(fs.readFileSync(MANIFEST, 'utf8')).assets;
  if (!Array.isArray(list) || !list.length) throw new Error(NAME + ' lists no assets');
  const seen = new Set();
  for (const a of list) {
    for (const key of ['id', 'scene', 'out'])
      if (typeof a[key] !== 'string' || !a[key]) throw new Error(NAME + ': an asset needs "' + key + '"');
    if (a.kind !== undefined && a.kind !== 'clip' && a.kind !== 'prop') throw new Error(NAME + ': ' + a.id + ': kind is clip or prop');
    if (seen.has(a.id)) throw new Error(NAME + ': two assets are called ' + a.id);
    seen.add(a.id);
    if (!fs.existsSync(path.join(ROOT, a.scene))) throw new Error(NAME + ': ' + a.id + ': no scene at ' + a.scene);
  }
  return list;
}

/** Only the assets named on the command line, or all of them. An unknown name is an error, never an empty run. */
function chosen(names) {
  const all = assets();
  if (!names.length) return all;
  return names.map(n => {
    const a = all.find(x => x.id === n);
    if (!a) throw new Error('no asset called ' + n + ' in ' + NAME + ' (it has: ' + all.map(x => x.id).join(', ') + ')');
    return a;
  });
}

module.exports = { ROOT, INK, SNAPS, kit, assets, chosen, sun, at: p => path.join(ROOT, p) };
