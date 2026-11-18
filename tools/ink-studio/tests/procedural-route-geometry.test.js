const test = require('node:test');
const assert = require('node:assert/strict');
const { routes } = require('..').load().KIT.procedural;
const box = [[-1,-1],[1,-1],[1,1],[-1,1]];

test('visibility graphs choose the shortest plan path around polygons and keep exact pins', () => {
  const a = [-4, 0.1, 0], b = [4, 0.4, 0],
    path = routes.visibility(a, b, [box]);
  assert.equal(path.status, 'ok');
  const points = path.route.points;
  assert.equal(points.length, 4);
  assert.deepEqual(points[0], a);
  assert.deepEqual(points.at(-1), b);
  assert(points.slice(1, -1).every(p => Math.abs(p[0]) === 1 && Math.abs(p[2]) === 1));
  const run = points.slice(1).reduce((sum, p, i) => sum + Math.hypot(p[0] - points[i][0], p[2] - points[i][2]), 0);
  assert.equal(run, 2 * Math.sqrt(10) + 2);
  assert.equal(routes.visibility([0, 0, 0], b, [box]).status, 'blocked-pin');
  assert.equal(routes.visibility(a, b, [box], { maxTests: 1 }).status, 'budget');
  assert.equal(routes.visibility([0, 0, -1], [3, 0, -1], [box]).route.points.length, 2);
});

test('the visibility test respects concave outlines and corridors between close obstacles', () => {
  const concave = [[0,0],[3,0],[3,2],[2,2],[2,1],[1,1],[1,2],[0,2]],
    p = routes.visibility([1.5, 0, 3], [1.5, 0, 1.2], [concave]),
    q = routes.visibility([-3, 0, 3], [5, 0, 3], [concave, [[-2,3.1],[5,3.1],[5,4],[-2,4]]]);
  assert.equal(p.route.points.length, 2);
  assert.equal(q.route.points.length, 2);
});

test('spline fitting rounds safe corners while retaining a corner that would enter a keep-out', () => {
  const raw = routes.polyline([[-2, 0, 0], [-1, 0, 0], [-1, 0, 1], [2, 0, 1]]),
    options = { radius: 0.7, spacing: 0.035, keepOut: (x, z) => x < -1 && z > 0 },
    rounded = routes.spline(raw, options);
  assert.equal(rounded.status, 'ok');
  assert.equal(rounded.work.retained, 1);
  assert.equal(rounded.work.rounded, 1);
  assert.equal(rounded.quadratics.length, 1);
  assert.deepEqual(rounded.route.points[0], raw.points[0]);
  assert.deepEqual(rounded.route.points.at(-1), raw.points.at(-1));
  for (let i = 0; i <= 300; i++) {
    const [x, , z] = rounded.route.sample(i / 300).point;
    assert(!options.keepOut(x, z));
  }
  assert.equal(routes.spline(raw, { clearance: () => -1 }).status, 'blocked');
});

test('fast marching solves a uniform Eikonal field and traces a route through continuous coordinates', () => {
  const bounds = { min: [-3, -3], max: [3, 3] },
    field = routes.travelTime([[0, 0]], { bounds, cell: 0.06 });
  assert.equal(field.time(0, 0), 0);
  assert(Math.abs(field.time(2.4, 0) - 2.4) < 1e-9);
  assert(Math.abs(field.time(2, 2) - Math.sqrt(8)) < 0.14);
  const start = [-2.15, -1.74],
    plan = field.trace(start, { height: (x, z) => 0.19 * z }),
    output = plan.route.points;
  assert.equal(plan.status, 'ok');
  assert.deepEqual(output[0], [start[0], 0.19 * start[1], start[1]]);
  assert.deepEqual(output.at(-1), [0, 0, 0]);
  for (let i = 1; i < output.length; i++) {
    assert(field.time(output[i][0], output[i][2]) <= field.time(output[i - 1][0], output[i - 1][2]) + 1e-8);
  }
});

test('fast marching traces around a blocked disk, chooses seeded outlets, and reports unreachable cells', () => {
  const bounds = { min: [-5, -4], max: [5, 4] },
    speed = (x, z) => Math.hypot(x, z) > 1.21 ? (z < -2 ? 0.6 : 1) : 0,
    field = routes.travelTime([[4, 0.13], [4, 3.1]], { bounds, cell: 0.18, speed });
  const plan = field.trace([-4, 0]);
  assert.equal(plan.status, 'ok');
  assert(Math.abs(plan.route.length - 8) > 0.1);
  for (let i = 0; i <= 500; i++) {
    const [x, , z] = plan.route.sample(i / 500).point;
    assert(speed(x, z) > 0);
  }
  assert.equal(field.trace([0, 0]).status, 'blocked');
  const wall = routes.travelTime([[3, 0]], { bounds, cell: 0.22, speed: x => Math.abs(x) < 0.14 ? 0 : 1 });
  assert.equal(wall.time(-2, 0), Infinity);
  assert.equal(wall.trace([-2, 0]).status, 'unreachable');
});
