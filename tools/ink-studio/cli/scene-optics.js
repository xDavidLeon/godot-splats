const SceneOptics = require('../src/scene-optics.js');

function cameraRays(view, eye, W, H, focal, ortho) {
  const origin = eye.slice(),
    direction = [0, 0, 0];
  const ray = { origin, direction, axial: 1 };
  return (x, y) => {
    const u = (x - W / 2) / focal,
      v = (y - H / 2) / focal;
    ray.axial = ortho ? 1 : 1 / Math.hypot(u, v, 1);
    for (let i = 0; i < 3; i++) {
      const j = i * 4;
      const offset = u * view[j] + v * view[j + 1];
      origin[i] = eye[i] + (ortho ? offset : 0);
      direction[i] = ortho ? -view[j + 2] : (offset - view[j + 2]) * ray.axial;
    }
    return ray;
  };
}

function surfacePoint(ray, normal, x, y, z, axialDepth, radius) {
  const { origin, direction, axial } = ray;
  const facing = normal[0] * direction[0] + normal[1] * direction[1] + normal[2] * direction[2];
  if (Math.abs(facing) < 1e-7) return [x, y, z];
  const distance = (normal[0] * (x - origin[0]) + normal[1] * (y - origin[1]) + normal[2] * (z - origin[2])) / facing;
  if (distance < 0 || Math.abs(distance * axial - axialDepth) > radius) return [x, y, z];
  return origin.map((n, i) => n + distance * direction[i]);
}

function reflectionSampler(planes, render, view, eye, scale) {
  const definitions = new Map(),
    captures = new Map();
  for (const value of planes) {
    const plane = SceneOptics.plane(value);
    if (definitions.has(plane.id)) throw new RangeError('Duplicate reflection plane ' + plane.id);
    if (SceneOptics.planeDistance(plane, ...eye) > plane.bias) definitions.set(plane.id, plane);
    else definitions.set(plane.id, null);
  }
  const rgb = [0, 0, 0],
    reflected = { rgb, coverage: 0 };
  function sample(layer, x, y, dx, dy, dz) {
    const plane = definitions.get(layer.plane);
    if (!plane) return null;
    if (!captures.has(plane.id)) captures.set(plane.id, render(plane));
    const frame = captures.get(plane.id);
    const distortion = (layer.distortion ?? 5) * scale;
    x += distortion * (view[0] * dx + view[4] * dy + view[8] * dz);
    y += distortion * (view[1] * dx + view[5] * dy + view[9] * dz);
    const blur = (layer.blur ?? 0) * scale;
    let red = 0,
      green = 0,
      blue = 0,
      alpha = 0;
    function tap(tx, ty, weight) {
      tx = Math.floor(tx);
      ty = Math.floor(ty);
      if (tx < 0 || tx >= frame.w || ty < 0 || ty >= frame.h) return;
      const p = ty * frame.w + tx,
        j = p * 3;
      red += frame.rgb[j] * weight;
      green += frame.rgb[j + 1] * weight;
      blue += frame.rgb[j + 2] * weight;
      alpha += frame.coverage[p] * weight;
    }
    tap(x, y, blur ? 0.4 : 1);
    if (blur) {
      tap(x - blur, y, 0.15);
      tap(x + blur, y, 0.15);
      tap(x, y - blur, 0.15);
      tap(x, y + blur, 0.15);
    }
    if (alpha <= 1e-6) return null;
    rgb[0] = Math.min(1, red / alpha);
    rgb[1] = Math.min(1, green / alpha);
    rgb[2] = Math.min(1, blue / alpha);
    reflected.coverage = alpha;
    return reflected;
  }
  sample.has = id => !!definitions.get(id);
  return sample;
}

function applyAtmosphere(volumes, col, depths, rayAt, W, H, horizon) {
  const light = [0, 0, 0, 1];
  for (let y = 0; y < H; y++)
    for (let x = 0; x < W; x++) {
      const i = y * W + x,
        p = i * 3;
      const { origin, direction, axial } = rayAt(x + 0.5, y + 0.5);
      const stop = (Number.isFinite(depths[i]) ? depths[i] : horizon) / axial;
      SceneOptics.trace(volumes, origin, direction, stop, light);
      for (let c = 0; c < 3; c++) col[p + c] = light[c] + light[3] * col[p + c];
    }
}

module.exports = { cameraRays, surfacePoint, reflectionSampler, applyAtmosphere };
