const test = require('node:test'), assert = require('node:assert/strict');
const { periodicCoordinates } = require('..').load().KIT.procedural;
const { wrap, delta, unwrap } = periodicCoordinates;
const near = (a, b) => assert(Math.abs(a - b) < 1e-12, `${a} != ${b}`);

test('wrapped coordinates use a half-open period and signed steps cross the seam', () => {
  assert.equal(wrap(-24, 12), 0);
  assert.equal(wrap(-5, 12), 7);
  assert.equal(wrap(2, 1), 0);
  near(delta(.03, .97), .06);
  near(delta(3.97, -4.97), -.06);
  assert.equal(delta(6, 0, 12), -6);
});

test('unwrapping puts each station in the smallest covering interval in its input order', () => {
  assert.deepEqual(unwrap([1, 11, 0, 13], 12), [13, 11, 12, 13]);
  assert.deepEqual(unwrap([3, 2, 4], 12), [3, 2, 4]);
  assert.deepEqual(unwrap([0, 6], 12), [0, 6]);
  assert.deepEqual(unwrap([]), []);
  assert.deepEqual(unwrap(new Float32Array([1, .25, .75])), [1, 1.25, .75]);
  near(wrap(unwrap([.99, .01]).reduce((sum, u) => sum + u / 2, 0)), 0);
});
