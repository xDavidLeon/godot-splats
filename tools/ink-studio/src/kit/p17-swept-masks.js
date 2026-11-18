/* Ordered swept-disc masks with optional feathering, taper and source ownership. */
(function (K) {
  const A = K.procedural,
    evaluators = new WeakMap(),
    EPS = 1e-9;
  const clamp = x => Math.max(0, Math.min(1, x)),
    weight = (d, soft) => {
      if (!soft) return d <= 0 ? 1 : 0;
      const t = clamp(0.5 - d / (2 * soft));
      return t * t * (3 - 2 * t);
    };
  function parameters(spec) {
    const p = Object.assign(
      {
        layer: 'default',
        operation: 'add',
        order: 0,
        width: 1.2,
        softness: 0.06,
        elevation: 0,
        material: 'default',
        pattern: 'flat'
      },
      A.data.clone(spec)
    );
    if (
      typeof p.layer !== 'string' ||
      !p.layer ||
      !['add', 'erase'].includes(p.operation) ||
      !Number.isSafeInteger(p.order) ||
      p.order < 0 ||
      !Number.isFinite(p.width) ||
      p.width <= 0 ||
      p.width > 128 ||
      !Number.isFinite(p.softness) ||
      p.softness < 0 ||
      p.softness > 32 ||
      !Number.isFinite(p.elevation) ||
      typeof p.material !== 'string' ||
      !p.material ||
      typeof p.pattern !== 'string' ||
      !p.pattern
    )
      throw new Error('Invalid brush layer, operation, order, width or appearance');
    if (
      !Array.isArray(p.points) ||
      !p.points.length ||
      p.points.length > 65536 ||
      !p.points.every(a => Array.isArray(a) && a.length === 2 && a.every(v => Number.isFinite(v) && Math.abs(v) <= 1e6))
    )
      throw new Error('Brush strokes require finite 2D points');
    p.points = p.points.map(a => a.slice());
    if (
      p.radii !== undefined &&
      (!Array.isArray(p.radii) ||
        p.radii.length !== p.points.length ||
        !p.radii.every(r => Number.isFinite(r) && r > 0 && r <= 64))
    )
      throw new Error('Brush radii must match the points and be positive');
    p.radii = p.radii ? p.radii.slice() : p.points.map(() => p.width / 2);
    return A.data.freeze(p);
  }
  function point(value) {
    if (!Array.isArray(value) || value.length !== 2 || !Number.isFinite(value[0]) || !Number.isFinite(value[1]))
      throw new Error('Brush queries need a finite 2D point');
    return value;
  }
  function stroke(spec) {
    if (!spec || typeof spec.id !== 'string' || !spec.id) throw Error('A mask stroke needs a stable id');
    const p = parameters(spec),
      segments = [],
      minimum = [Infinity, Infinity],
      maximum = [-Infinity, -Infinity];
    for (let i = 0; i < p.points.length; i++) {
      const a = p.points[i],
        r = p.radii[i] + p.softness;
      for (let j = 0; j < 2; j++) {
        minimum[j] = Math.min(minimum[j], a[j] - r);
        maximum[j] = Math.max(maximum[j], a[j] + r);
      }
      if (i) {
        const b = p.points[i - 1],
          dx = a[0] - b[0],
          dy = a[1] - b[1],
          length = Math.hypot(dx, dy),
          ra = p.radii[i - 1],
          rb = p.radii[i],
          delta = rb - ra,
          k = delta / length,
          end = length < EPS ? (rb >= ra ? 1 : 0) : Math.abs(delta) >= length ? (delta > 0 ? 1 : 0) : null;
        segments.push({ a: b, ra, dx, dy, length, delta, k, root: end === null ? Math.sqrt(1 - k * k) : 1, end });
      }
    }
    const uniform = p.radii.every(r => r === p.radii[0]);
    let known = false,
      lastX,
      lastY,
      lastDistance,
      lastRadius;
    // Public queries validate once. A composed field calls its privately owned
    // evaluators after its own validation, rather than repeating it per stroke.
    function evaluate(x, y, wantRadius = false) {
      if (known && x === lastX && y === lastY) return wantRadius ? lastRadius : lastDistance;
      let best = Infinity,
        radius = p.radii[0];
      if (!segments.length) best = Math.hypot(x - p.points[0][0], y - p.points[0][1]) - radius;
      else if (uniform) {
        let squared = Infinity,
          bx = 0,
          by = 0,
          overflow = Infinity;
        for (const s of segments) {
          const u = x - s.a[0], v = y - s.a[1];
          const t = s.end === null ? clamp((u * s.dx + v * s.dy) / s.length / s.length) : s.end;
          const qx = u - t * s.dx, qy = v - t * s.dy, d = qx * qx + qy * qy;
          if (d === Infinity) overflow = Math.min(overflow, Math.hypot(qx, qy));
          if (d < squared) {
            squared = d;
            bx = qx;
            by = qy;
          }
        }
        best = (squared === Infinity ? overflow : Math.hypot(bx, by)) - radius;
      } else
        for (const s of segments) {
          const u = x - s.a[0], v = y - s.a[1];
          let t = s.end;
          if (t === null) {
            const along = (u * s.dx + v * s.dy) / s.length,
              across = Math.abs(u * s.dy - v * s.dx) / s.length;
            t = clamp((along + (s.k * across) / s.root) / s.length);
          }
          const r = s.ra + t * s.delta,
            value = Math.hypot(u - t * s.dx, v - t * s.dy) - r;
          if (value < best) {
            best = value;
            radius = r;
          }
        }
      known = true;
      lastX = x;
      lastY = y;
      lastDistance = best;
      lastRadius = radius;
      return wantRadius ? radius : best;
    }
    const distance = (q, wantRadius = false) => {
        point(q);
        return evaluate(q[0], q[1], wantRadius);
      },
      result = {
        owner: spec.id,
        parameters: p,
        bounds: A.data.freeze({
          min: [minimum[0], p.elevation - 0.01, minimum[1]],
          max: [maximum[0], p.elevation + 0.01, maximum[1]]
        }),
        distance,
        radius: q => distance(q, true),
        weight: q => weight(distance(q), p.softness)
      };
    evaluators.set(result, evaluate);
    return Object.freeze(result);
  }
  function compose(specs, options = {}) {
    if (!Array.isArray(specs) || specs.length > 4096) throw Error('Mask composition needs at most 4096 strokes');
    const ids = new Set();
    const selected = [];
    let points = 0;
    for (const spec of specs) {
      if (options.layer && spec?.layer !== undefined && spec.layer !== options.layer) continue;
      points += Array.isArray(spec?.points) ? spec.points.length : 0;
      if (points > 262144) throw Error('Mask composition exceeds its point budget');
      const compiled = stroke(spec);
      if (options.layer && compiled.parameters.layer !== options.layer) continue;
      if (ids.has(compiled.owner)) throw Error('Mask stroke ids must be unique');
      ids.add(compiled.owner);
      selected.push(compiled);
    }
    if (new Set(selected.map(s => s.parameters.layer)).size > 1) throw Error('Select one brush layer for composition');
    selected.sort(
      (a, b) => a.parameters.order - b.parameters.order || (a.owner < b.owner ? -1 : a.owner > b.owner ? 1 : 0)
    );
    const strokes = selected,
      fast = strokes.map(s => evaluators.get(s)),
      adds = strokes.map(s => s.parameters.operation === 'add'),
      limits = strokes.map(s => {
        const b = [s.bounds.min[0], s.bounds.max[0], s.bounds.min[2], s.bounds.max[2]];
        return b.concat(Number.EPSILON * 8 * Math.max(1, ...b.map(Math.abs)));
      }),
      bounds = strokes.length ? A.spatial.boxOf(strokes.flatMap(s => [s.bounds.min, s.bounds.max])) : null,
      byId = new Map(strokes.map((s, i) => [s.owner, i]));
    let last = null,
      lastValue = null,
      distanceX,
      distanceY,
      distanceValue,
      distanceCeiling;
    // Signed L-infinity distance to the expanded box is a lower bound on the
    // swept-disc distance, including inside it. Keep a rounding margin so this
    // rejection never substitutes a box distance for the actual stroke field.
    const lower = (i, x, y) => {
      const b = limits[i];
      return Math.max(b[0] - x, x - b[1], b[2] - y, y - b[3]) - b[4];
    };
    const irrelevant = (i, x, y, threshold) =>
      threshold === -Infinity ||
      (threshold !== Infinity && lower(i, x, y) > threshold + 1e-12 * (1 + Math.abs(threshold)));
    function rememberDistance(x, y, d, ceiling = Infinity) {
      distanceX = x;
      distanceY = y;
      distanceValue = d;
      distanceCeiling = d < ceiling ? Infinity : ceiling;
      return d;
    }
    // Min and max both commute with an upper clamp. Keep the exact field
    // inside that limit while skipping distant add and erase operations.
    function distanceAt(x, y, ceiling = Infinity) {
      if (!Number.isFinite(x) || !Number.isFinite(y) || typeof ceiling !== 'number' || Number.isNaN(ceiling)) {
        throw new Error('Brush queries need a finite 2D point and a numeric ceiling');
      }
      if (x === distanceX && y === distanceY && ceiling <= distanceCeiling) return Math.min(distanceValue, ceiling);
      let d = ceiling;
      for (let i = 0; i < fast.length; i++) {
        if (adds[i]) {
          if (!irrelevant(i, x, y, d)) d = Math.min(d, fast[i](x, y));
        } else if (d < ceiling && !irrelevant(i, x, y, -d)) {
          d = Math.min(ceiling, Math.max(d, -fast[i](x, y)));
        }
      }
      return rememberDistance(x, y, d, ceiling);
    }
    function distance(q) {
      point(q);
      return distanceAt(q[0], q[1]);
    }
    function sample(q) {
      point(q);
      if (last && q.every((v, i) => v === last[i])) return Object.assign({}, lastValue);
      let d = Infinity,
        owner = null,
        coverage = 0;
      for (let i = 0; i < strokes.length; i++) {
        const s = strokes[i],
          sd = fast[i](q[0], q[1]),
          w = weight(sd, s.parameters.softness);
        if (s.parameters.operation === 'add') {
          d = Math.min(d, sd);
          coverage = 1 - (1 - coverage) * (1 - w);
          if (sd <= s.parameters.softness) {
            owner = s.owner;
          }
        } else {
          d = Math.max(d, -sd);
          coverage *= 1 - w;
        }
      }
      if (coverage < EPS) owner = null;
      last = q.slice();
      lastValue = { distance: rememberDistance(q[0], q[1], d), weight: coverage, owner };
      return Object.assign({}, lastValue);
    }
    function visibleDistance(id, q) {
      point(q);
      const i = byId.get(id);
      if (i === undefined || !adds[i]) return Infinity;
      const [x, y] = q;
      let d = fast[i](x, y);
      for (let j = i + 1; j < strokes.length; j++) if (!irrelevant(j, x, y, -d)) d = Math.max(d, -fast[j](x, y));
      return d;
    }
    const radiusDistances = new Float64Array(strokes.length),
      radiusValues = new Float64Array(strokes.length);
    function radiusSmooth(q, blend = 0.2) {
      point(q);
      if (!Number.isFinite(blend) || blend <= 0) throw new Error('Radius blending needs a positive distance');
      let nearest = Infinity;
      for (let i = 0; i < strokes.length; i++) {
        if (strokes[i].parameters.operation !== 'add') {
          radiusDistances[i] = Infinity;
          continue;
        }
        const d = fast[i](q[0], q[1]);
        radiusDistances[i] = d;
        radiusValues[i] = fast[i](q[0], q[1], true);
        nearest = Math.min(nearest, d);
      }
      let sum = 0,
        value = 0;
      for (let i = 0; i < strokes.length; i++) {
        const w = Math.max(0, 1 - (radiusDistances[i] - nearest) / blend) ** 2;
        if (w > 0) {
          sum += w;
          value += w * radiusValues[i];
        }
      }
      return sum ? value / sum : 1;
    }
    return {
      radiusSmooth,
      strokes: A.data.freeze(strokes.slice()),
      bounds: bounds && A.data.freeze(bounds),
      sample,
      distance,
      distanceAt,
      weight: q => sample(q).weight,
      contains(q) {
        point(q);
        return distanceAt(q[0], q[1], 0) < 0;
      },
      visibleDistance,
      radius(q) {
        point(q);
        let best = Infinity,
          radius = 1;
        for (let i = 0; i < strokes.length; i++) {
          if (adds[i] && !irrelevant(i, q[0], q[1], best)) {
            const d = fast[i](q[0], q[1]);
            if (d < best) {
              best = d;
              radius = fast[i](q[0], q[1], true);
            }
          }
        }
        return radius;
      },
      owner(q) {
        point(q);
        for (let i = strokes.length - 1; i >= 0; i--) {
          const s = strokes[i],
            b = s.bounds;
          if (q[0] < b.min[0] || q[0] > b.max[0] || q[1] < b.min[2] || q[1] > b.max[2]) continue;
          if (fast[i](q[0], q[1]) <= 0) return adds[i] ? s.owner : null;
        }
        return null;
      }
    };
  }
  A.masks = { stroke, compose };
})(KIT);
