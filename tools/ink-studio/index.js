// ink-studio: sculpt with signed distance, bake to pixel-art gaussian splats, and look at the result without a browser.
// The sources are plain scripts (they are concatenated into a web page as they stand), so this file offers them three ways:
//   files()   the library's source files, in the order they must be loaded
//   bundle()  those files as one piece of text, to put in a page or in front of your own scripts
//   load()    the same compiled for Node, with the demo dioramas: { makeBuilder, makeSculpt, KIT, SCENES, ... }
const fs = require('fs'),
  path = require('path'),
  { randomUUID } = require('crypto');
const KIT_DIR = path.join(__dirname, 'src', 'kit'),
  read = f => fs.readFileSync(f, 'utf8').replace(/\nif \(typeof module[^\n]*\n?$/, '\n');
const files = () =>
  ['src/pixel-look.js', 'src/reflection-plane.js', 'src/airflow.js', 'src/light-schedule.js', 'src/sample-coverage.js', 'src/ripple-field.js', 'src/scene-optics.js', 'src/surface-look.js', 'src/builder.js', 'src/sculpt.js']
    .map(f => path.join(__dirname, f))
    .concat(
      fs
        .readdirSync(KIT_DIR)
        .filter(f => f.endsWith('.js'))
        .sort()
        .map(f => path.join(KIT_DIR, f))
    );
const demoFiles = () => [path.join(__dirname, 'demos', 'labscenes.js')];
// the names the bundle defines at top level (add them to your own module.exports)
const EXPORTS =
  'makeBuilder, makeSculpt, basis, flame, motes, pondMat, lilies, courses, PALETTES, PAL_HEX, KIT, PixelLook, SurfaceLook, SceneOptics, VOX';
module.exports = {
  files,
  demoFiles,
  EXPORTS,
  version: require('./package.json').version,
  bundle: () => files().map(read).join('\n'),
  // the seven built-in demo dioramas. They push onto an array called SCENES, which must already exist
  demos: () => demoFiles().map(read).join('\n'),
  // refuse-to-build check: code written after a // comment on the same line never runs. Returns the offending lines
  lint: require('./scripts/lint.js'),
  // a mesh file from disk, by its ending: .obj (with the .mtl beside it), .gltf (with its .bin files), .glb
  readMesh(file, { attributes = false } = {}) {
    const K = module.exports.load().KIT,
      ext = path.extname(file).toLowerCase(),
      dir = path.dirname(file);
    if (ext === '.obj') {
      const text = fs.readFileSync(file, 'utf8'),
        m = /^mtllib\s+(.+)$/m.exec(text),
        mf = m && path.join(dir, m[1].trim());
      const mtl = mf && fs.existsSync(mf) ? fs.readFileSync(mf, 'utf8') : null;
      const mesh = K.mesh.obj(text, mtl, { attributes });
      if (attributes && mtl && mesh.uvs) {
        let name;
        const textures = new Map();
        for (const raw of mtl.split('\n')) {
          const entry = /^(newmtl|map_Kd)\s+(.+)$/.exec(raw.trim());
          if (!entry) continue;
          if (entry[1] === 'newmtl') name = entry[2];
          else if (name && !entry[2].startsWith('-')) {
            const image = path.resolve(path.dirname(mf), entry[2].replace(/^["']|["']$/g, ''));
            const mimeType = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' }[path.extname(image).toLowerCase()];
            if (mimeType && fs.existsSync(image)) textures.set(name, { bytes: fs.readFileSync(image), mimeType });
          }
        }
        mesh.mats = mesh.mats.map(m => ({ ...m, texture: textures.get(m.name) }));
      }
      return mesh;
    }
    if (ext === '.glb') return K.mesh.glb(fs.readFileSync(file));
    if (ext === '.gltf') {
      const g = JSON.parse(fs.readFileSync(file, 'utf8'));
      return K.mesh.gltf(
        g,
        (g.buffers || []).map(b =>
          b.uri && !b.uri.startsWith('data:') ? fs.readFileSync(path.join(dir, decodeURIComponent(b.uri))) : null
        )
      );
    }
    throw new Error('do not know how to read ' + ext + ' (obj, gltf and glb are read)');
  },
  exportGlb: require('./cli/export-glb.js'),
  load() {
    const out = path.join(__dirname, 'dist', 'standalone.js'),
      srcs = files().concat(demoFiles()),
      newest = Math.max(...srcs.map(f => fs.statSync(f).mtimeMs));
    if (!fs.existsSync(out) || fs.statSync(out).mtimeMs < newest) {
      fs.mkdirSync(path.dirname(out), { recursive: true });
      // Parallel consumers may compile together. Publish only complete bundles.
      const temporary = out + '.' + randomUUID() + '.tmp';
      try {
        fs.writeFileSync(
          temporary,
          module.exports.bundle() +
            '\nconst SCENES = [];\n' +
            module.exports.demos() +
            '\nmodule.exports = { SCENES, ' +
            EXPORTS +
            ' };\n'
        );
        fs.renameSync(temporary, out);
      } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
      }
    }
    return require(out);
  }
};
