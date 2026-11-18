## Measures what the demo costs while its window is in front, behind another window, and minimised,
## and whether clocks stay truthful there. Windows only (it asks PowerShell for the process's CPU time
## and GPU use). It needs a window, and it gives the keyboard focus to the window that was behind it
## for the second step:
##
##   godot --path . -s res://splats/tools/splat_background.gd
##
## For each step, over a few seconds: frames a second, the process's CPU use (as a share of one
## core) and GPU use, the engine's own count of the time against the wall clock, and how late a
## 2 second timer fires.
extends SceneTree


# region Constants
const STEP_SECONDS: float = 5.0
const SAMPLE: String = """
$p = Get-Process -Id %d
$c0 = $p.TotalProcessorTime.TotalMilliseconds; $t0 = Get-Date
$g = (Get-Counter '\\GPU Engine(pid_%d_*)\\Utilization Percentage' -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue).CounterSamples
$gpu = ($g | Measure-Object CookedValue -Sum).Sum / 3
$p.Refresh(); $c1 = $p.TotalProcessorTime.TotalMilliseconds
$cpu = 100 * ($c1 - $c0) / ((Get-Date) - $t0).TotalMilliseconds
'{0:F1} {1:F1}' -f $cpu, $gpu
"""
const GIVE_FOCUS_AWAY: String = """
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint c);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
$h = [IntPtr]%d
do { $h = [Fg]::GetWindow($h, 2) } while ($h -ne [IntPtr]::Zero -and (-not [Fg]::IsWindowVisible($h) -or [Fg]::GetWindowTextLength($h) -eq 0))
if ($h -ne [IntPtr]::Zero) { [Fg]::SetForegroundWindow($h) | Out-Null }
"""
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region Measuring
func _run() -> void:
	var demo: Node = (load("res://splats/demo/splat_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	print("[splat background] %s on %s; vsync mode %d, screen %.0f Hz" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
			DisplayServer.window_get_vsync_mode(), DisplayServer.screen_get_refresh_rate()])
	await create_timer(1.5).timeout
	root.grab_focus()
	await create_timer(0.5).timeout
	await _step("in front")

	var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id())
	_powershell(GIVE_FOCUS_AWAY % handle)
	await create_timer(0.5).timeout
	await _step("behind another window")

	root.mode = Window.MODE_MINIMIZED
	await create_timer(0.5).timeout
	await _step("minimised")

	root.mode = Window.MODE_WINDOWED
	await create_timer(0.5).timeout
	await _step("restored")
	quit(0)


func _step(name: String) -> void:
	var focused: bool = root.has_focus()
	var minimised: bool = root.mode == Window.MODE_MINIMIZED
	var sampler: Thread = Thread.new()
	var pid: int = OS.get_process_id()
	sampler.start(_powershell.bind(SAMPLE % [pid, pid]))

	var timer_due: int = Time.get_ticks_msec() + 2000
	var timer_late: Array[int] = [-1]
	create_timer(2.0).timeout.connect(func() -> void: timer_late[0] = Time.get_ticks_msec() - timer_due)

	var ticks0: int = Time.get_ticks_usec()
	var unix0: float = Time.get_unix_time_from_system()
	var drawn0: int = Engine.get_frames_drawn()
	var frames: int = 0
	var engine_time: float = 0.0
	var longest: float = 0.0
	var last: int = ticks0
	while Time.get_ticks_usec() - ticks0 < int(STEP_SECONDS * 1000000.0):
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames += 1
		engine_time += root.get_process_delta_time()
		longest = maxf(longest, (now - last) / 1000.0)
		last = now
	var wall: float = (Time.get_ticks_usec() - ticks0) / 1000000.0
	var unix: float = Time.get_unix_time_from_system() - unix0
	var use: String = sampler.wait_to_finish()
	var parts: PackedStringArray = use.strip_edges().replace(",", ".").split(" ", false)
	print("[splat background] %s (focused: %s, minimised: %s): %.0f loops a second, %.0f frames drawn a second, longest gap %.0f ms; CPU %s%% of one core, GPU %s%%" % [
		name, focused, minimised, frames / wall, (Engine.get_frames_drawn() - drawn0) / wall, longest,
		parts[0] if parts.size() > 0 else "?", parts[1] if parts.size() > 1 else "?"])
	print("[splat background]   over %.2f s of wall clock: the system clock counted %.2f s, the engine's frame deltas add to %.2f s, a 2 s timer fired %d ms late" % [
		wall, unix, engine_time, timer_late[0]])


func _powershell(script: String) -> String:
	var output: Array = []
	OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())], output)
	var text: String = ""
	for line: String in "\n".join(output).split("\n", false):
		if not line.strip_edges().is_empty():
			text = line.strip_edges()
	return text
# endregion
