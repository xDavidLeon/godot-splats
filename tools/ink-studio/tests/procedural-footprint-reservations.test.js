const test = require('node:test');
const assert = require('node:assert/strict');
const {createFootprintReservations} = require('..').load().KIT.procedural;

const at = (point, size=[1,1,1], tangent=[1,0,0]) => ({point,size,tangent});

test('reservation uses oriented volume overlap and preserves space on other levels', () => {
  const field=createFootprintReservations({cellSize:.2});
  const axis=[1,0,1], halfAngle=Math.SQRT1_2;
  const beam=at([0,0,0],[2,.5,.2],axis);
  assert(field.reserve(beam));
  assert(!field.reserve(at([0,.25,0],[.2,.2,.2])));
  assert(field.reserve({...beam,point:[0,.5,0]}));
  assert(field.reserve({...beam,point:[-.3*halfAngle,0,.3*halfAngle]}));
  assert(!field.fits(at([.5,0,.5],[.1,.2,.1])));
});

test('reserve is atomic and authored volumes can overlap in the same field', () => {
  const field=createFootprintReservations({clearance:.12,cellSize:.4});
  field.occupy(at([0,0,0]));
  field.occupy(at([.25,0,0]));
  assert(!field.reserve(at([1.36,0,0])));
  assert(field.reserve(at([1.38,0,0])));
  assert(field.fits(at([-3,0,0])));
  field.occupy(at([300,0,0],[300,.2,2]));
  assert(!field.reserve(at([250,0,0])));
  assert.throws(()=>field.occupy(at([0,0,0],[1,1,1],[0,1,0])),/horizontal/);
});
