## Checks the transparent click-through window ([code]splats/demo/splat_overlay.tscn[/code]). The
## screen comparison runs anywhere Godot can capture the screen (macOS asks for the Screen Recording
## permission); the hit test and the real input are Windows only, through PowerShell. The overlay scene adds this node itself
## when it is started with [code]--selftest[/code], from the editor's binary or an exported build (which
## does not run [code]-s[/code] scripts), in a project that allows per-pixel transparency and whose
## main scene is the overlay:
##
##   godot --path <project> -- --selftest=<folder>
##   <exported>.exe --log-file <file> -- --selftest=<folder>
##
## It opens a plain green window, puts the overlay over it, and three times (as it opens, after the
## window is moved, and after it is made smaller) it
##   - photographs only that part of the screen ([code]overlay-<step>.png[/code]): green must show round the
##     picture, and every screen pixel must be what the window holds (the mouse outline cuts nothing off);
##   - asks Windows which window is under a point on the picture and under a point beside it
##     (WindowFromPoint, through PowerShell): the first must be the overlay, the second the green window.
## With [code]--real-input[/code] as well, it then sends input from the operating system itself: it moves the
## cursor (and puts it back), clicks on the picture and on a clear pixel, drags the window by the
## picture and turns the wheel over it, and only while the window under the cursor is one of its own
## two. Without it, no real input is sent, and the window's handler is given a click as Godot's own
## event. It exits 0 when everything holds.
extends Node


# region Constants
const MARGIN: int = 60
const SETTLE_SECONDS: float = 1.5
const BACKDROP: Color = Color(0.0, 1.0, 0.0)
const HIT_TEST: String = """
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Hit {
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
}
'@
[Hit]::SetProcessDPIAware() | Out-Null
foreach ($pair in @(%s)) {
  $p = New-Object Hit+P; $p.X = $pair[0]; $p.Y = $pair[1]
  [Hit]::GetAncestor([Hit]::WindowFromPoint($p), 2).ToInt64()
}
"""
const REAL_INPUT: String = """
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class In {
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int data, UIntPtr extra);
}
'@
[In]::SetProcessDPIAware() | Out-Null
$allowed = @(%s)
function Under { $p = New-Object In+P; [In]::GetCursorPos([ref]$p) | Out-Null; [In]::GetAncestor([In]::WindowFromPoint($p), 2).ToInt64() }
$was = New-Object In+P; [In]::GetCursorPos([ref]$was) | Out-Null
$held = $false
foreach ($c in @(%s)) {
  if ($c[0] -eq 'move') { [In]::SetCursorPos($c[1], $c[2]) | Out-Null }
  elseif ($c[0] -eq 'sleep') { Start-Sleep -Milliseconds $c[1] }
  elseif ($c[0] -eq 'probe') { 'under ' + (Under) }
  elseif ($c[0] -eq 'up') { if ($held) { [In]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); $held = $false } }
  elseif ($allowed -notcontains (Under)) { 'ABORT'; break }
  elseif ($c[0] -eq 'down') { [In]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); $held = $true }
  elseif ($c[0] -eq 'wheel') { [In]::mouse_event(0x800, 0, 0, $c[1], [UIntPtr]::Zero) }
}
if ($held) { [In]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero) }
[In]::SetCursorPos($was.X, $was.Y) | Out-Null
"""
# endregion


# region State
var _out: String = ""
var _backdrop_clicks: int = 0
var _backdrop: Window
var _overlay: Node
var _scene: SplatScene
# endregion


# region Lifecycle
func _ready() -> void:
	_run.call_deferred()
# endregion


# region Test
func _run() -> void:
	var root: Window = get_tree().root
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--selftest="):
			_out = argument.trim_prefix("--selftest=")
	if _out.is_empty():
		push_error("[overlay test] give a folder: -- --selftest=<folder>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	print("[overlay test] renderer: %s on %s; %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
			"an exported build" if OS.has_feature("template") else "run from the editor's binary"])

	# In Unity, a second top-level window needs a second process or native code; a Godot Window node is one.
	root.gui_embed_subwindows = false
	_backdrop = Window.new()
	_backdrop.title = "Splat overlay test backdrop"
	_backdrop.unfocusable = true
	_backdrop.always_on_top = true # over whatever else is on the desktop; the overlay is raised over it below
	var fill: ColorRect = ColorRect.new()
	fill.color = BACKDROP
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(fill)
	_backdrop.window_input.connect(_on_backdrop_input)
	root.add_child(_backdrop)

	_overlay = get_parent()
	_scene = _overlay.get_splat_scene()
	_scene.fixed_time = 3.0
	await get_tree().process_frame
	var area: Rect2i = DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = area.position + (area.size - root.size) / 2
	var transparent: bool = _overlay.is_transparent()
	var by_pixel: bool = _overlay.click_through == _overlay.ClickThrough.PIXEL
	print("[overlay test] transparent: %s; click-through by %s" % [transparent, "the pixel under the cursor" if by_pixel else "an outline round the picture"])

	var ok: bool = transparent
	ok = await _check("opened") and ok
	root.position += Vector2i(-140, 60)
	ok = await _check("moved") and ok
	_overlay.pixel_scale = 2
	ok = await _check("smaller") and ok

	if OS.get_cmdline_user_args().has("--real-input") and OS.get_name() != "Windows":
		print("[overlay test] real input is sent on Windows only; on %s click, drag and turn the wheel by hand" % OS.get_name())
	elif OS.get_cmdline_user_args().has("--real-input"):
		ok = await _real_input() and ok
	else:
		# the window's own handler, given a click as Godot's input event (not one from the operating system)
		var before: int = _overlay.clicks_caught
		for pressed: bool in [true, false]:
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = Vector2(root.size) * 0.5
			root.push_input(click)
		await get_tree().process_frame
		var counted: bool = _overlay.clicks_caught == before + 1
		print("[overlay test] a click given to the window as Godot's own event is counted by its handler: %s (no real click was sent)" % counted)
		ok = ok and counted

	print("[overlay test] %s" % ("PASSED" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)


# The window as it stands now: what the screen shows of it, and which window is under two points.
func _check(step: String) -> bool:
	var root: Window = get_tree().root
	var screen: int = root.current_screen
	var origin: Vector2i = DisplayServer.screen_get_position(screen)
	await get_tree().process_frame
	_backdrop.size = root.size + Vector2i(MARGIN, MARGIN) * 2
	_backdrop.position = root.position - Vector2i(MARGIN, MARGIN)
	root.always_on_top = false
	root.always_on_top = true
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	# the window behind may take a moment to be on the screen: wait until its corner is
	var corner: Vector2i = _backdrop.position - origin + Vector2i(12, 12)
	for tries: int in 20:
		if _near(DisplayServer.screen_get_image(screen).get_pixelv(corner), BACKDROP):
			break
		await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw

	# 1. the screen, where the two windows are and nowhere else
	var shot: Image = DisplayServer.screen_get_image(screen)
	var held: Image = root.get_texture().get_image()
	shot.get_region(Rect2i(_backdrop.position - origin, _backdrop.size)).save_png(_out.path_join("overlay-%s.png" % step))
	var cut: int = 0
	var wrong: int = 0
	var clear: int = 0
	var kinds: Dictionary[String, int] = {}
	for y: int in held.get_height():
		for x: int in held.get_width():
			var mine: Color = held.get_pixel(x, y)
			var seen: Color = shot.get_pixelv(root.position - origin + Vector2i(x, y))
			if mine.a < 0.5 and _near(seen, BACKDROP):
				clear += 1
			if mine.a >= 0.5 and _near(seen, BACKDROP) and not _near(mine, BACKDROP):
				cut += 1
			elif not _near(seen, Color(mine.r, mine.g, mine.b) if mine.a >= 0.5 else BACKDROP):
				wrong += 1
				var kind: String = "screen %s where the window holds %s, alpha %.2f" % [seen.to_html(false), mine.to_html(false), mine.a]
				kinds[kind] = kinds.get(kind, 0) + 1
	var whole: bool = cut == 0 and wrong == 0 and clear > 0
	print("[overlay test] %s: window %s at %s; %d screen pixels show the window behind; the picture is cut off at %d; %d others are not what the window holds" % [
		step, root.size, root.position, clear, cut, wrong])
	var most: Array[String] = kinds.keys()
	most.sort_custom(func(a: String, b: String) -> bool: return kinds[a] > kinds[b])
	for kind: String in most.slice(0, 3):
		print("[overlay test]   %d x %s" % [kinds[kind], kind])

	# 2. which window Windows gives the mouse to: on the picture, and beside it. By pixel that depends
	# on where the cursor is, so it is only asked with the cursor put there (see _real_input).
	if _overlay.click_through == _overlay.ClickThrough.PIXEL:
		return whole
	if OS.get_name() != "Windows":
		print("[overlay test] %s: the hit test is Windows only; not run on %s" % [step, OS.get_name()])
		return whole
	var points: Array[Vector2i] = _two_points()
	var overlay_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id())
	var backdrop_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, _backdrop.get_window_id())
	var found: PackedStringArray = _numbers(_powershell(HIT_TEST % ("@(%d,%d),@(%d,%d)" % [points[0].x, points[0].y, points[1].x, points[1].y])))
	if found.size() < 2:
		print("[overlay test] %s: the hit test did not answer" % step)
		return false
	var catches: bool = found[0].to_int() == overlay_handle
	var passes: bool = found[1].to_int() == backdrop_handle
	print("[overlay test] %s: under a point on the picture: %s; under a point beside it: %s" % [step,
		"the overlay" if catches else "NOT the overlay",
		"the window behind" if passes else ("the overlay: a click would NOT pass through" if found[1].to_int() == overlay_handle else "some other window")])
	return whole and catches and passes


# A screen point well inside the picture (nearest its middle), and one in the window well clear of it.
func _two_points() -> Array[Vector2i]:
	var root: Window = get_tree().root
	var picture: Image = _scene.get_picture().get_image()
	var scale: int = _overlay.pixel_scale
	var on_picture: Vector2i = Vector2i(-1, -1)
	var beside: Vector2i = Vector2i(-1, -1)
	var centre: Vector2 = Vector2(picture.get_size()) * 0.5
	var best: float = INF
	for y: int in range(4, picture.get_height() - 4):
		for x: int in range(4, picture.get_width() - 4):
			var inside: bool = true
			var outside: bool = true
			for dy: int in range(-4, 5):
				for dx: int in range(-4, 5):
					if picture.get_pixel(x + dx, y + dy).a >= 0.5:
						outside = false
					else:
						inside = false
			if inside and Vector2(x, y).distance_to(centre) < best:
				best = Vector2(x, y).distance_to(centre)
				on_picture = Vector2i(x, y)
			if outside and beside.x < 0:
				beside = Vector2i(x, y)
	return [root.position + on_picture * scale + Vector2i(scale, scale) / 2, root.position + beside * scale + Vector2i(scale, scale) / 2]


# Real input from the operating system: the cursor is moved (and put back), and the left button and
# the wheel are sent, only while the window under the cursor is one of this test's two.
func _real_input() -> bool:
	var root: Window = get_tree().root
	var overlay_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id())
	var backdrop_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, _backdrop.get_window_id())
	var allowed: String = "%d,%d" % [overlay_handle, backdrop_handle]
	var click: String = "@('move',%d,%d),@('sleep',500),@('probe',0),@('down',0),@('sleep',80),@('up',0),@('sleep',300)"
	var ok: bool = true

	# a click on the picture is the overlay's
	var points: Array[Vector2i] = _two_points()
	var mine: int = _overlay.clicks_caught
	var behind: int = _backdrop_clicks
	var said: PackedStringArray = await _send(allowed, click % [points[0].x, points[0].y])
	var caught: bool = _overlay.clicks_caught == mine + 1 and _backdrop_clicks == behind
	print("[overlay test] real click on the picture: %s (under the cursor: %s; the overlay counted %d, the window behind %d)" % [
		"caught by the overlay" if caught else "NOT caught as it should be", _who(said, overlay_handle, backdrop_handle), _overlay.clicks_caught - mine, _backdrop_clicks - behind])
	ok = ok and caught

	# a click on a clear pixel of the window goes to the window behind
	mine = _overlay.clicks_caught
	behind = _backdrop_clicks
	said = await _send(allowed, click % [points[1].x, points[1].y])
	# Judged by where the click arrived. By pixel, WindowFromPoint still names the overlay while it lets
	# the mouse through, so what is "under the cursor" is reported but not required.
	var passed: bool = _overlay.clicks_caught == mine and _backdrop_clicks == behind + 1
	print("[overlay test] real click on a clear pixel: %s (under the cursor: %s; the overlay counted %d, the window behind %d)" % [
		"reached the window behind" if passed else "did NOT reach the window behind", _who(said, overlay_handle, backdrop_handle), _overlay.clicks_caught - mine, _backdrop_clicks - behind])
	ok = ok and passed

	# a drag by the picture moves the window with the cursor
	var from: Vector2i = root.position
	var grab: Vector2i = points[0]
	var path: String = "@('move',%d,%d),@('sleep',500),@('down',0),@('sleep',120)" % [grab.x, grab.y]
	for n: int in range(1, 9):
		path += ",@('move',%d,%d),@('sleep',60)" % [grab.x + n * 10, grab.y + n * 5]
	path += ",@('sleep',150),@('up',0),@('sleep',300)"
	said = await _send(allowed, path)
	var dragged: bool = root.position - from == Vector2i(80, 40)
	print("[overlay test] real drag by the picture, 80 right and 40 down: the window moved %s: %s" % [root.position - from, "it follows" if dragged else "it does NOT follow"])
	ok = ok and dragged

	# the wheel over the picture resizes the window
	points = _two_points()
	var scale: int = _overlay.pixel_scale
	said = await _send(allowed, "@('move',%d,%d),@('sleep',500),@('wheel',120),@('sleep',500)" % [points[0].x, points[0].y])
	var resized: bool = _overlay.pixel_scale == scale + 1
	print("[overlay test] real wheel turn over the picture: scale %d -> %d, window %s: %s" % [scale, _overlay.pixel_scale, root.size, "it resizes" if resized else "it does NOT resize"])
	ok = ok and resized
	if said.has("ABORT"):
		print("[overlay test] input was held back: another window was under the cursor")
	return ok


func _on_backdrop_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_backdrop_clicks += 1


func _who(said: PackedStringArray, overlay_handle: int, backdrop_handle: int) -> String:
	if said.has("under %d" % overlay_handle):
		return "the overlay"
	if said.has("under %d" % backdrop_handle):
		return "the window behind"
	return "another window, or no answer"


# Runs the input script beside the main loop, so the windows keep handling what it sends.
func _send(allowed: String, commands: String) -> PackedStringArray:
	var sender: Thread = Thread.new()
	sender.start(_powershell.bind(REAL_INPUT % [allowed, commands]))
	while sender.is_alive():
		await get_tree().process_frame
	var lines: PackedStringArray = PackedStringArray()
	for line: String in (sender.wait_to_finish() as String).split("\n", false):
		lines.append(line.strip_edges())
	await get_tree().process_frame
	return lines


func _powershell(script: String) -> String:
	var output: Array = []
	OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())], output)
	return "\n".join(output)


# Only the lines that are a number: PowerShell may say other things too.
func _numbers(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n", false):
		if line.strip_edges().is_valid_int():
			found.append(line.strip_edges())
	return found


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.06
# endregion
