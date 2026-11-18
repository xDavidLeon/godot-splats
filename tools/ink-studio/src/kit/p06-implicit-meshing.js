/* General bounded implicit surfaces and uncapped triangle clipping. Marching
   tetrahedra keeps a consistent cube diagonal; negative fields face outward.
   The budget controls sampling work, without changing the supplied field. */
(function (K) {
  const A = K.procedural,
    V = K.V;
  A.geometry.implicitSurface = (field, bounds, options) => {
    const o = Object.assign({ resolution: 0.12, maxCells: 30000, edgeRefinements: 0, meta: {} }, options);
    if (
      typeof field !== 'function' ||
      !bounds ||
      !['min', 'max'].every(
        k => Array.isArray(bounds[k]) && bounds[k].length === 3 && bounds[k].every(Number.isFinite)
      ) ||
      bounds.min.some((v, i) => v >= bounds.max[i]) ||
      !Number.isFinite(o.resolution) ||
      o.resolution <= 0 ||
      !Number.isSafeInteger(o.maxCells) ||
      o.maxCells < 8
    )
      throw new Error('Implicit meshes need a finite box, field and sampling budget');
    const size = bounds.max.map((v, i) => v - bounds.min[i]);
    if (!size.every(Number.isFinite) || o.maxCells > 2000000 ||
        !Number.isInteger(o.edgeRefinements) || o.edgeRefinements < 0 || o.edgeRefinements > 12)
      throw new Error('Implicit mesh extent and sampling budget exceed supported limits');
    let step = Math.max(o.resolution, Math.max(...size) / o.maxCells),
      counts = size.map(v => Math.max(1, Math.ceil(v / step)));
    while (counts.reduce((n, v) => n * v, 1) > o.maxCells) {
      step *= 1.15;
      counts = size.map(v => Math.max(1, Math.ceil(v / step)));
    }
    const dimensions = counts.map(n => n + 1),
      stride = dimensions[0] * dimensions[1],
      values = new Float64Array(stride * dimensions[2]),
      at = (x, y, z) => [
        bounds.min[0] + (size[0] * x) / counts[0],
        bounds.min[1] + (size[1] * y) / counts[1],
        bounds.min[2] + (size[2] * z) / counts[2]
      ],
      slot = (x, y, z) => x + dimensions[0] * y + stride * z;
    for (let z = 0; z < dimensions[2]; z++)
      for (let y = 0; y < dimensions[1]; y++)
        for (let x = 0; x < dimensions[0]; x++) {
          const d = field(at(x, y, z));
          if (!Number.isFinite(d)) throw new Error('Implicit mesh field must return finite values');
          values[slot(x, y, z)] = d;
        }
    const builder = A.geometry.builder(),
      corners = [
        [0, 0, 0],
        [1, 0, 0],
        [1, 1, 0],
        [0, 1, 0],
        [0, 0, 1],
        [1, 0, 1],
        [1, 1, 1],
        [0, 1, 1]
      ],
      tets = [
        [0, 5, 1, 6],
        [0, 1, 2, 6],
        [0, 2, 3, 6],
        [0, 3, 7, 6],
        [0, 7, 4, 6],
        [0, 4, 5, 6]
      ];
    const offsets = corners.map(([x, y, z]) => slot(x, y, z));
    const triangle = (a, b, c, inside) => {
      const n = V.cross(V.sub(b, a), V.sub(c, a)),
        mid = V.mul(V.add(V.add(a, b), c), 1 / 3);
      if (V.dot(n, V.sub(mid, inside)) < 0) builder.triangle(a, c, b, o.meta);
      else builder.triangle(a, b, c, o.meta);
    };
    for (let z = 0; z < counts[2]; z++)
      for (let y = 0; y < counts[1]; y++)
        for (let x = 0; x < counts[0]; x++) {
          const base = slot(x, y, z), inside = values[base] < 0;
          // Most cells have one sign. Leave their vertices in the sampled grid.
          let i = 1;
          while (i < offsets.length && (values[base + offsets[i]] < 0) === inside) i++;
          if (i === offsets.length) continue;
          const p = corners.map(c => at(x + c[0], y + c[1], z + c[2])),
            d = offsets.map(offset => values[base + offset]);
          const edge = (a, b) => {
            if (!o.edgeRefinements) return V.mad(p[a], V.sub(p[b], p[a]), d[a] / (d[a] - d[b]));
            if (d[a] >= 0) [a, b] = [b, a];
            const delta = V.sub(p[b], p[a]);
            let low = 0, high = 1;
            for (let i = 0; i < o.edgeRefinements; i++) {
              const mid = (low + high) / 2;
              const value = field(V.mad(p[a], delta, mid));
              if (!Number.isFinite(value)) throw new Error('Implicit mesh field must return finite values');
              if (value < 0) low = mid;
              else high = mid;
            }
            return V.mad(p[a], delta, (low + high) / 2);
          };
          for (const tet of tets) {
            const low = tet.filter(i => d[i] < 0),
              high = tet.filter(i => d[i] >= 0);
            if (!low.length || !high.length) continue;
            const inside = V.mul(
              low.reduce((n, i) => V.add(n, p[i]), [0, 0, 0]),
              1 / low.length
            );
            if (low.length === 1) {
              const a = low[0],
                q = high.map(b => edge(a, b));
              triangle(...q, inside);
            } else if (high.length === 1) {
              const a = high[0],
                q = low.map(b => edge(a, b));
              triangle(...q, inside);
            } else {
              const [a, b] = low,
                [c, e] = high,
                q = [edge(a, c), edge(a, e), edge(b, e), edge(b, c)];
              triangle(q[0], q[1], q[2], inside);
              triangle(q[0], q[2], q[3], inside);
            }
          }
        }
    return Object.assign(builder.finish(), {
      sampling: A.data.freeze({ cells: counts.reduce((n, v) => n * v, 1), counts, resolution: step })
    });
  };
})(KIT);
