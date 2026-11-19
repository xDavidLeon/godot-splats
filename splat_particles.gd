## The particle rules of the splat renderer, in plain script: where a splat of a cloud is at a time
## on the clock, and whether it is drawn then.
##
## A cloud ([member SplatInstance.motion]) is an ordinary asset whose splats each move by themselves.
## Nothing is simulated and nothing is kept from one frame to the next: a splat's place is a formula
## of its own number in the scene, which gives it a seed, and the clock. So a frame at a given time
## is always the same frame, and a cloud costs the CPU nothing.
## [br][br]
## [b]A rise[/b] (steam, flames) climbs [code]reach[/code] metres on a loop of its own length,
## between 2.8 and 7.6 seconds at speed 1, wobbling sideways and shrinking as it goes. It is not
## drawn for the first 4% of its loop, nor after a point between 75% and 100% that is its own, by
## when it has between 0.55 and 0.4 of its size.
## [br][br]
## [b]A drift[/b] (dust) wanders within [code]reach[/code] metres of where it starts, each way, and
## is drawn for half of a slower cycle of its own.
## [br][br]
## A particle is solid like any splat, so where one would fade out it is dropped for that part of
## its cycle.
## [br][br]
## [SplatScene] applies these rules on the GPU every frame ([code]splat_pose.gdshaderinc[/code]).
## The functions here are the same rules for anything that wants the answer in script, and they are
## what the tests check. They are worked in single precision, as a shader works: a seed is a hash,
## and in double precision it would be another seed.
## [br][br]
## [b]A seed is not the same on every GPU.[/b] It has about eleven bits, and how a driver rounds the
## hash decides the last few of them. On the one GPU this was checked on (NVIDIA), Vulkan rounds
## every step, as these functions do, and OpenGL adds each product of the hash's dot product in
## before rounding, as they do with [member fused] on: [code]dev/tools/splat_fx_report.gd[/code]
## found every splat where these functions put it, each way. So in two renderers some particles of a
## cloud are at different points of their loops, and on another GPU they may be where neither way
## puts them. The cloud looks the same.
# In Unity, these are the motion branch of the scene's draw shader, whose formulas follow the
# particles.js of the pixelart-gaussiansplat project (MIT).
class_name SplatParticles
extends RefCounted


# region Constants
## Added to a splat's number before it is hashed.
const SEED_OFFSET: float = 3.0
## A rise is not drawn before this much of its loop.
const RISE_FROM: float = 0.04
## A rise is drawn until at least this much of its loop, and at most the whole of it.
const RISE_UNTIL: float = 0.75
## How much of its size a rise has lost at the top of its loop.
const RISE_SHRINK: float = 0.6
# endregion


# region State
## How the seed's dot product is rounded: after every step (off, the default: what Vulkan did on the
## GPU this was checked on), or with each product added in before rounding (on: what OpenGL did).
static var fused: bool = false

static var _single: PackedFloat32Array = PackedFloat32Array([0.0])
# endregion


# region Public API
## Three numbers in 0 to 1 from one, the same every time: a particle's own seed. [param number] is
## the splat's number in the scene's picture (its instance's first splat plus its own index) plus
## [constant SEED_OFFSET].
static func seed_of(number: float) -> Vector3:
	var px: float = _fract(_f(number * _f(0.1031)))
	var py: float = _fract(_f(number * _f(0.1030)))
	var pz: float = _fract(_f(number * _f(0.0973)))
	var ax: float = _f(py + _f(33.33))
	var ay: float = _f(pz + _f(33.33))
	var az: float = _f(px + _f(33.33))
	var d: float = _f(_f(_f(px * ax) + _f(py * ay)) + _f(pz * az))
	if fused:
		# each product exact, added in before rounding
		d = _f(pz * az + _f(py * ay + _f(px * ax)))
	px = _f(px + d)
	py = _f(py + d)
	pz = _f(pz + d)
	return Vector3(
			_fract(_f(_f(px + py) * pz)),
			_fract(_f(_f(px + pz) * py)),
			_fract(_f(_f(py + pz) * px)))


## Where a splat of a cloud is at [param seconds] on the scene's clock: x, y and z are how far it has
## moved from where the asset has it, in the asset's space, and w is how much of its size it keeps.
## A w of 0 means it is not drawn at that time.
## [br][param splat] is its number in the scene's picture. [param reach], [param wobble] and
## [param speed] are its instance's [member SplatInstance.motion_reach],
## [member SplatInstance.motion_wobble] and [member SplatInstance.motion_speed].
static func offset_at(motion: SplatInstance.Motion, splat: int, seconds: float, reach: float, wobble: float = 0.0, speed: float = 1.0) -> Vector4:
	if motion == SplatInstance.Motion.NONE:
		return Vector4(0.0, 0.0, 0.0, 1.0)
	var r: Vector3 = seed_of(splat + SEED_OFFSET)
	var t: float = _f(_f(fmod(seconds, SplatScene.CLOCK_WRAP)) * _f(speed))
	if motion == SplatInstance.Motion.RISE:
		var k: float = rise_phase(r, t)
		if k < _f(RISE_FROM) or k > rise_end(r):
			return Vector4.ZERO
		return Vector4(
				_f(_f(wobble) * _f(sin(_f(_f(9.0 * k) + _f(40.0 * r.z)))) * k),
				_f(k * _f(reach)),
				_f(_f(wobble) * _f(cos(_f(_f(7.0 * k) + _f(40.0 * r.x)))) * k),
				_f(1.0 - _f(_f(RISE_SHRINK) * k)))
	if not drift_shown(r, t):
		return Vector4.ZERO
	return Vector4(
			_f(_f(reach) * _f(sin(_f(_f(_f(0.3) * t) + _f(40.0 * r.x))))),
			_f(_f(reach) * _f(sin(_f(_f(_f(0.22) * t) + _f(40.0 * r.y))))),
			_f(_f(reach) * _f(cos(_f(_f(_f(0.27) * t) + _f(40.0 * r.z))))),
			1.0)


## How far through its loop a rise with the seed [param r] is at [param t] seconds of its cloud's
## clock, 0 to 1.
static func rise_phase(r: Vector3, t: float) -> float:
	return _fract(_f(_f(_f(_f(t * _f(0.22)) * _f(_f(0.6) + r.x))) + r.y))


## How far through its loop a rise with the seed [param r] is last drawn.
static func rise_end(r: Vector3) -> float:
	return _f(_f(RISE_UNTIL) + _f(_f(0.25) * r.z))


## How long a rise's loop is, in seconds of its cloud's clock.
static func rise_seconds(r: Vector3) -> float:
	return 1.0 / (0.22 * (0.6 + r.x))


## Whether a drift with the seed [param r] is drawn at [param t] seconds of its cloud's clock.
static func drift_shown(r: Vector3, t: float) -> bool:
	return _f(_f(_f(0.5) * _f(sin(_f(_f(t * _f(_f(0.3) + _f(_f(0.4) * r.z))) + _f(60.0 * r.x))))) + _f(0.5)) >= _f(0.5)
# endregion


# region Helpers
# A number as a shader's float holds it.
static func _f(value: float) -> float:
	_single[0] = value
	return _single[0]


static func _fract(value: float) -> float:
	return _f(value - floorf(value))
# endregion
