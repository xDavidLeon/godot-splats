# Scene optics

Ink Studio can capture the objects around a planar mirror, move their reflected colours with a ripple field, and composite fog, mist or beams against scene depth. Each tool works independently. The [beacon pool](../examples/beacon-pool.js) uses all three with sculpted geometry.

```sh
ink-studio render examples/beacon-pool.js --t 0.94 --raw --out pool.png
ink-studio sheet examples/beacon-pool.js --t 0.4,0.94,1.5 --raw --out pool-motion.png
```

Use `--reflections off` or `--atmosphere off` to inspect each effect separately. The software renderer supports perspective and orthographic views, and the effects run before palette quantization.

## Planar reflections

```js
const mirror = K.reflection.plane({ id: 'pool', at: [0, 0, 0], normal: [0, 1, 0] });
const water = K.reflection.material({ r: [1, 2, 3], a: 0.65 }, 'pool', {
  f0: 0.3,
  color: '#b8e0ea',
  distortion: 10,
  blur: 0.7
});
// Use water when adding the flat basin surface to S, then bake.
const world = B.finish({ cam, reflections: [mirror] });
```

The receiving material limits the reflected area, including irregular outlines. Put the receiving surface on the mirror plane and point the plane normal toward the objects and camera. The renderer samples a single mirrored view per visible, referenced plane. Splat centres behind the plane are excluded. Use `bias` in world units to exclude splats very close to the plane, or use `select(index, x, y, z, world)` to control which animated splats appear in the capture.

`K.reflection.material` adds a `planarReflection` layer named `mirror`. The layer takes the usual finish tint, `strength`, Fresnel `f0` and `power`, and optional finish masks. `distortion` controls how much a normal perturbation shifts the reflection in art pixels. `blur` is a small reflection filter radius in art pixels. Any finish normal, including `waves`, `noise` and ripple rings, can perturb the capture. Empty reflected pixels reveal the other finish layers and the base colour.

The existing `reflection` finish type supplies a three-colour sky. It can be layered underneath a planar mirror. `K.reflection.reflectedView(matrix, plane)` supplies the mirrored column-major world-to-view transform to other renderers. `K.reflection.captureView(matrix, plane, eye)` also supplies the clipping equation `[nx, ny, nz, -dot(at, normal)]` and the clip bias. It returns `null` if the eye is on or behind the reflecting side's bias. Use `SurfaceLook.shade` with a `reflection(layer, normal, geometricNormal)` callback returning `{ rgb, coverage }` in 0–1.

## Ripple sources

```js
const ripples = K.ripple.field({ scale: 0.48, amplitude: 0.4, speed: 1.2, damping: 0.25 });
const finish = K.surface.preset('rippling-water', { r: [1, 2, 3] }, { normal: ripples.normal });
// This can also be called later, after the world is baked.
const drop = ripples.add({ at: [1, 0, -0.5], start: 0.3, strength: 1 });
```

Drop coordinates use the material's pattern space, which defaults to the sculpt's rest coordinates. The optional material `origin` and `scale` shift and scale that space. The ripple plane defaults to XZ. Set `axis` and `cross` to two perpendicular XYZ directions for another plane. `scale` sets the wavelength, `width` sets the width around the travelling wavefront, and `speed` is distance per second. Set `repeat` on a drop for a repeating source.

Add and remove sources while rendering without rebaking. `remove(drop)` removes one source, `clear()` removes all, and `prune(time, reach)` retires non-repeating drops whose last rings have travelled beyond the given maximum radius. `sample(position, time, footprint)` returns the normal offset. Use a declarative `{ type: 'rings', amplitude, scale, drops }` normal for data-authored scenes.

A renderer can call `field.frame(time, storage)` once per frame and upload the
result. `axes` contains the two world-space tangents, `shape` contains
`[amplitude, wavelength, packetHalfWidth, damping]`, and each of the first
`count` entries in `drops` packs `[u, v, wavefrontRadius, strength]`.
Optional `Float32Array` storage needs four slots per active source. A field's
`capacity` defaults to 64 and can be lowered to fit a host's buffer.
`K.ripple.sampleFrame(frame, position, footprint, out)` evaluates the same
world-space slope as the surface normal sampler, within float packing precision.
Shader hosts can include `K.ripple.glsl` and sum `inkRippleSlope` for each drop
at a tangent-plane position. The host chooses how that slope affects its
material or reflected view.

## Atmosphere

```js
const world = B.finish({
  cam,
  atmosphere: [
    K.atmosphere.fog({ top: 0.2, near: 3, density: 0.14, color: '#6e889f' }),
    K.atmosphere.sphere({ at: [-1, 0.3, -2], radius: 1.4, density: 0.3, color: '#93a4b0' }),
    K.atmosphere.box({ min: [-2, 0, -1], max: [-0.3, 0.5, 3], density: 0.2 }),
    K.atmosphere.shaft({ from: [0, 3, -0.8], to: [1.4, 0, 1], radius: 0.22,
      density: 0.5, color: '#ffdb94' })
  ]
});
```

Fog can occupy a height slab with `bottom` and `top`, or cover the whole view. Sphere and box volumes let mist stay around an object or in a defined region. A shaft is a capped cylinder of tinted atmosphere. Combine volumes freely. Integration accounts for overlaps in camera-depth order and stops at the nearest opaque surface. Use `near` or `far` to bound a volume by camera ray distance. Colours accept a palette index, a hex string, or 0–1 RGB.

Hosts can use `K.atmosphere.prepare(world.atmosphere, world.pal)` and `K.atmosphere.trace(volumes, eye, unitDirection, distance)`. Trace returns premultiplied RGB and remaining transmittance `[r, g, b, t]`, so the final colour is the returned RGB plus `t` times the scene RGB.
