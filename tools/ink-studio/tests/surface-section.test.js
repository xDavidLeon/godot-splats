const test=require('node:test'),assert=require('node:assert/strict');
const K=require('..').load().KIT,P=K.procedural;
const near=(a,b)=>assert(K.V.dist(a,b)<1e-8);

test('the same section depth maps to the far face of a varying carrier',()=>{
  const chart=P.surface.plane({id:'panel',origin:[0,0,0],u:[6,0,0],v:[0,3,0]});
  const s=P.surfaceSection(chart,{center:[.5,.5],units:[6,3],thickness:([u])=>.2+.6*u,offset:.03});
  assert.equal(s.referenceDepth,.5);
  for(const x of [-2,0,2]){
    const uv=[.5+x/6,.5],point=chart.sample(uv).p;
    near(s.map([x,0,-s.referenceDepth]),K.V.add(point,[0,0,.03-(.2+.6*uv[0])]));
    for(const z of [-.55,-.22,0,.14])near(s.project(s.map([x,.18,z])),[x,.18,z]);
  }
});

test('periodic sections keep their local coordinates across a chart seam',()=>{
  const r=2,units=[2*Math.PI*r,3];
  const chart=P.surface.cylinder({id:'pipe',origin:[0,0,0],radius:r,height:3});
  const s=P.surfaceSection(chart,{center:[.99,.42],units,thickness:()=>.18,periodicU:true});
  for(const x of [-.4,.55])near(s.project(s.map([x,.16,-.14])),[x,.16,-.14]);
  assert.throws(()=>P.surfaceSection(chart,{center:[.5,.5],units,thickness:()=>0}),/thickness/);
});
