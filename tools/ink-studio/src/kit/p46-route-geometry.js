/* Visibility paths in planar obstacles and sampled clearance-aware corner splines. */
(function (K) {
  const P = K.procedural,
    V = K.V,
    EPS = 1e-9,
    point = (p, n) => Array.isArray(p) && p.length === n && p.every(x => Number.isFinite(x) && Math.abs(x) <= 1e6),
    limit = (n, min, max) => Number.isSafeInteger(n) && n >= min && n <= max,
    positive = x => Number.isFinite(x) && x > EPS,
    clamp = t => Math.max(0, Math.min(1, t)),
    plan = p => [p[0], p[2]],
    area2 = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]),
    dist2 = (a, b) => (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2,
    interpolate = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t],
    bounds = (a, b) => [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])],
    overlap = (a, b) => a[0] <= b[2] + EPS && b[0] <= a[2] + EPS && a[1] <= b[3] + EPS && b[1] <= a[3] + EPS;

  function visibility(start, end, obstacles, { maxVertices = 600, maxTests = 2500000 } = {}) {
    if (
      !point(start, 3) || !point(end, 3) || V.dist(start, end) <= EPS ||
      !Array.isArray(obstacles) || obstacles.length > 500 ||
      !limit(maxVertices, 2, 3000) || !limit(maxTests, 1, 30000000)
    ) throw new Error('Visibility paths need distinct finite pins, polygons, and work limits');
    const first = plan(start), last = plan(end), vertices = [first, last],
      polygons = [], work = { pairs: 0, tests: 0 },
      exhausted = Symbol('visibility budget');
    for (const polygon of obstacles) {
      if (!Array.isArray(polygon) || polygon.length < 3 || polygon.length > maxVertices + 1 || !polygon.every(p => point(p, 2)))
        throw new Error('Visibility obstacles must be simple polygons with at least three XZ points');
      const loop = polygon.slice();
      if (dist2(loop[0], loop.at(-1)) <= EPS ** 2) loop.pop();
      if (loop.length < 3 || loop.some((p, i) => dist2(p, loop[(i + 1) % loop.length]) <= EPS ** 2) ||
        Math.abs(loop.reduce((sum, p, i) => sum + area2(loop[0], p, loop[(i + 1) % loop.length]), 0)) <= EPS)
        throw new Error('Visibility obstacles need a nondegenerate boundary');
      if (vertices.length + loop.length > maxVertices) throw new Error('Visibility graph exceeds its vertex budget');
      vertices.push(...loop);
      const box = [Infinity, Infinity, -Infinity, -Infinity];
      for (const p of loop) {
        box[0] = Math.min(box[0], p[0]);
        box[1] = Math.min(box[1], p[1]);
        box[2] = Math.max(box[2], p[0]);
        box[3] = Math.max(box[3], p[1]);
      }
      polygons.push({ loop, box });
    }
    function check() {
      if (++work.tests > maxTests) throw exhausted;
    }
    function inside(p, { loop, box }) {
      if (!overlap(bounds(p, p), box)) return false;
      let odd = false;
      for (let i = 0; i < loop.length; i++) {
        check();
        const a = loop[i], b = loop[(i + 1) % loop.length];
        if (Math.abs(area2(a, b, p)) <= EPS * Math.sqrt(dist2(a, b)) && overlap(bounds(a, b), bounds(p, p))) return false;
        if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])) odd = !odd;
      }
      return odd;
    }
    function clear(a, b) {
      work.pairs++;
      const box = bounds(a, b),
        dx = b[0] - a[0], dz = b[1] - a[1],
        sq = dx * dx + dz * dz;
      if (sq <= EPS * EPS) return !polygons.some(polygon => inside(a, polygon));
      for (const polygon of polygons) {
        if (!overlap(box, polygon.box)) continue;
        const parameters = [0, 1], { loop } = polygon;
        for (let i = 0; i < loop.length; i++) {
          check();
          const c = loop[i], d = loop[(i + 1) % loop.length],
            ex = d[0] - c[0], ez = d[1] - c[1], rx = c[0] - a[0], rz = c[1] - a[1],
            determinant = dx * ez - dz * ex;
          if (Math.abs(determinant) > EPS * Math.sqrt(sq * (ex * ex + ez * ez))) {
            const t = (rx * ez - rz * ex) / determinant, u = (rx * dz - rz * dx) / determinant;
            if (t > 0 && t < 1 && u >= -EPS && u <= 1 + EPS) parameters.push(t);
          } else if (Math.abs(dx * rz - dz * rx) <= EPS * Math.sqrt(sq)) {
            parameters.push(clamp((rx * dx + rz * dz) / sq), clamp(((d[0] - a[0]) * dx + (d[1] - a[1]) * dz) / sq));
          }
        }
        parameters.sort((a, b) => a - b);
        for (let i = 1; i < parameters.length; i++) {
          if (parameters[i] - parameters[i - 1] <= EPS) continue;
          if (inside(interpolate(a, b, (parameters[i] + parameters[i - 1]) / 2), polygon)) return false;
        }
      }
      return true;
    }
    const result = (status, data = {}) => Object.freeze({ status, ...data, work: Object.freeze({ ...work }) });
    try {
      if ([first, last].some(p => polygons.some(polygon => inside(p, polygon)))) return result('blocked-pin');
      if (clear(first, last)) return result('ok', { route: P.routes.polyline([start, end]) });
      const size = vertices.length,
        costs = new Float64Array(size).fill(Infinity), parent = new Int32Array(size).fill(-1), visited = new Uint8Array(size),
        queue = new ProceduralHeap((a, b) => a.cost < b.cost || (a.cost === b.cost && a.id < b.id));
      costs[0] = 0;
      queue.push({ id: 0, cost: 0 });
      while (queue.size) {
        const { id, cost } = queue.pop();
        if (visited[id]) continue;
        visited[id] = 1;
        if (id === 1) {
          const path = [1];
          for (let i = parent[1]; i >= 0; i = parent[i]) path.push(i);
          path.reverse();
          let travelled = 0;
          const points = [start];
          for (let i = 1; i < path.length - 1; i++) {
            const a = vertices[path[i - 1]], b = vertices[path[i]],
              step = Math.sqrt(dist2(a, b));
            travelled += step;
            if (step <= EPS || dist2(b, last) <= EPS ** 2) continue;
            points.push([b[0], start[1] + (end[1] - start[1]) * travelled / cost, b[1]]);
          }
          points.push(end);
          return result('ok', { route: P.routes.polyline(points) });
        }
        for (let i = 1; i < size; i++) {
          if (visited[i]) continue;
          const next = cost + Math.sqrt(dist2(vertices[i], vertices[id]));
          if (next >= costs[i] || !clear(vertices[id], vertices[i])) continue;
          costs[i] = next;
          parent[i] = id;
          queue.push({ id: i, cost: next });
        }
      }
      return result('unreachable');
    } catch (error) {
      if (error === exhausted) return result('budget');
      throw error;
    }
  }

  function spline(route, { radius = 0.5, spacing = 0.1, clearance, minClearance = 0, keepOut, height,
    maxDeviation = Infinity, maxSlope = Infinity, attempts = 8, maxTests = 1500000 } = {}) {
    const input = route?.points;
    if (
      !Array.isArray(input) || input.length < 2 || input.length > 4097 || !input.every(p => point(p, 3)) ||
      !positive(radius) || !positive(spacing) || !Number.isFinite(minClearance) || minClearance < 0 ||
      !(maxDeviation >= 0) || !(maxSlope >= 0) ||
      [clearance, keepOut, height].some(fn => fn !== undefined && typeof fn !== 'function') ||
      !limit(attempts, 1, 32) || !limit(maxTests, 1, 6000000)
    ) throw new Error('Route splines need a polyline, sample and clearance controls, and a work budget');
    const exhausted = Symbol('spline budget'),
      work = { tests: 0, rounded: 0, retained: 0 },
      result = (status, data = {}) => Object.freeze({ status, ...data, work: Object.freeze({ ...work }) }),
      lerp = (a, b, t) => V.mad(a, V.sub(b, a), t);
    function permitted(p) {
      if (work.tests >= maxTests) throw exhausted;
      work.tests++;
      const [x, y, z] = p;
      if (height) {
        const ground = height(x, z);
        if (!Number.isFinite(ground) || Math.abs(y - ground) > maxDeviation) return false;
      }
      return (!clearance || clearance(x, y, z) >= minClearance) && (!keepOut || !keepOut(x, z, y));
    }
    function safe(a, b) {
      const length = V.dist(a, b), run = Math.hypot(b[0] - a[0], b[2] - a[2]);
      if (Math.abs(b[1] - a[1]) > (run || EPS) * maxSlope + EPS) return false;
      const steps = Math.max(2, Math.ceil(length / spacing));
      for (let i = 0; i <= steps; i++) if (!permitted(i === steps ? b : lerp(a, b, i / steps))) return false;
      return true;
    }
    function fitted(a, b, c, amount) {
      const u = V.dist(a, b), v = V.dist(b, c);
      if (u <= EPS || v <= EPS) return null;
      const lead = lerp(b, a, Math.min(u * 0.45, amount) / u),
        tail = lerp(b, c, Math.min(v * 0.45, amount) / v),
        count = Math.max(3, Math.ceil((V.dist(lead, b) + V.dist(b, tail)) / spacing));
      if (count > 4096) throw exhausted;
      const points = [];
      for (let i = 0; i <= count; i++) {
        const t = i / count, p = lerp(lerp(lead, b, t), lerp(b, tail, t), t);
        if (i && !safe(points[i - 1], p)) return null;
        points.push(p);
      }
      return { points, controls: [lead, b.slice(), tail] };
    }
    try {
      const output = [input[0]], quadratics = [];
      for (let i = 1; i < input.length; i++) {
        if (!safe(input[i - 1], input[i])) return result('blocked');
      }
      for (let i = 1; i < input.length - 1; i++) {
        const a = input[i - 1], b = input[i], c = input[i + 1],
          directions = [V.norm(V.sub(b, a)), V.norm(V.sub(c, b))];
        let bend = null;
        const turn = V.dot(...directions);
        if (turn > -1 + EPS && turn < 1 - EPS) {
          for (let k = 0, trim = radius; k < attempts && trim > EPS; k++, trim *= 0.5) {
            bend = fitted(a, b, c, trim);
            if (bend) break;
          }
        }
        if (bend) {
          output.push(...bend.points);
          quadratics.push(bend.controls);
          work.rounded++;
        } else {
          output.push(b);
          work.retained++;
        }
        if (output.length >= 4097) return result('budget');
      }
      output.push(input.at(-1));
      if (output.some((p, i) => i > 0 && !safe(output[i - 1], p))) return result('blocked');
      return result('ok', { route: P.routes.polyline(output), quadratics: P.data.freeze(quadratics) });
    } catch (error) {
      if (error === exhausted) return result('budget');
      throw error;
    }
  }

  Object.assign(P.routes, { visibility, spline });
})(KIT);
