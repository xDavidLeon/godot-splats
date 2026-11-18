// Bind the common shader to the software renderer's camera and splat buffers.
const SurfaceLook = require('../src/surface-look.js');

function surfaceShading(world, options, camera) {
  if (options.surface === false || !world.surfaceData || !world.surfaces?.length) return null;
  const { data, surfaceData } = world;
  const { eye, parallel, footprint, time, reflection } = camera;
  const { STRIDE } = SurfaceLook;
  const liveLight = world.surfaceLight === undefined ? undefined : SurfaceLook.prepareLightTrack(world.surfaceLight)(time);
  const materials = world.surfaces.map(({ settings, light }) => SurfaceLook.prepare(settings, world.pal, liveLight ?? light));
  const planarMaterials = materials.map(
    material =>
      reflection && material.layers.some(layer => layer.type === 'planarReflection' && reflection.has(layer.plane))
  );
  const sample = {
    position: [0, 0, 0],
    normal: [0, 0, 0],
    view: [0, 0, 0],
    footprint,
    time,
    visibility: 1
  };
  const rgb = [0, 0, 0];
  const result = [0, 0, 0, 1, 0];
  const rotation = i => {
    const offset = i * 16;
    return Math.round(data[offset + 11]) % 16 === 5 ? time * data[offset + 13] : 0;
  };
  const has = i => surfaceData[i * STRIDE] > 0;

  function normalAt(i, normal) {
    const angle = rotation(i);
    if (!angle) return normal;
    const c = Math.cos(angle),
      s = Math.sin(angle);
    return [c * normal[0] + s * normal[2], normal[1], c * normal[2] - s * normal[0]];
  }

  function planar(i) {
    return !!planarMaterials[surfaceData[i * STRIDE] - 1];
  }

  function surfaceNormal(i) {
    const offset = i * STRIDE;
    return normalAt(i, [surfaceData[offset + 1], surfaceData[offset + 2], surfaceData[offset + 3]]);
  }

  function shade(i, x, y, z, centerX, centerY, centerZ, r, g, b, sx, sy) {
    const offset = i * STRIDE;
    const { position, normal, view } = sample;
    const prepared = materials[surfaceData[offset] - 1];
    const dab = i * 16;
    const dx = x - centerX,
      dz = z - centerZ;
    const angle = rotation(i);
    const c = Math.cos(angle),
      s = Math.sin(angle);
    position[0] = data[dab] + c * dx - s * dz;
    position[1] = data[dab + 1] + y - centerY;
    position[2] = data[dab + 2] + s * dx + c * dz;
    normal[0] = surfaceData[offset + 1];
    normal[1] = surfaceData[offset + 2];
    normal[2] = surfaceData[offset + 3];
    sample.visibility = surfaceData[offset + 4];
    const tx = surfaceData[offset + 5],
      ty = surfaceData[offset + 6],
      tz = surfaceData[offset + 7];
    sample.tangent = tx || ty || tz ? [tx, ty, tz] : undefined;
    const vx = parallel ? parallel[0] : eye[0] - x;
    const vz = parallel ? parallel[2] : eye[2] - z;
    view[0] = c * vx - s * vz;
    view[1] = parallel ? parallel[1] : eye[1] - y;
    view[2] = s * vx + c * vz;
    const [lx, ly, lz] = prepared.sun;
    sample.lightDirection = angle ? [c * lx - s * lz, ly, s * lx + c * lz] : undefined;
    sample.reflection =
      planar(i) && sx !== undefined
        ? (layer, n, original) => {
            const dx = n[0] - original[0],
              dz = n[2] - original[2];
            return reflection(layer, sx, sy, c * dx + s * dz, n[1] - original[1], c * dz - s * dx);
          }
        : undefined;
    rgb[0] = r;
    rgb[1] = g;
    rgb[2] = b;
    return SurfaceLook.shade(prepared, sample, rgb, result);
  }

  return { has, normalAt, surfaceNormal, planar, shade };
}

module.exports = surfaceShading;
