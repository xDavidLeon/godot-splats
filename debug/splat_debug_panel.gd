## A debug panel for judging the splat pixel look while the game runs: the average or the vote inside
## shapes ([member SplatScene.interior]), the dither, and each picture's size in art pixels. It finds
## every [SplatScene] in the tree by itself, stays hidden until [member toggle_key] (F1), and
## [member look_key] (V) switches the look with the panel closed too. Nothing it changes is saved.
##
## [b]It exists only in debug builds.[/b] Nothing in the addon creates it or refers to it: a game
## asks for it with [method add_to], which makes nothing in a release export
## ([method OS.is_debug_build] is false there), and a panel put in the tree some other way frees
## itself in one. A game that wants the script out of its release pack as well can exclude
## [code]addons/splats/debug/*[/code] in its export preset, and then must call [method add_to] by
## the script's path ([code]load("res://addons/splats/debug/splat_debug_panel.gd")[/code]) only when
## the file is there.
# In Unity, this is an IMGUI window that created itself after every scene load when the game's debug
# tools were enabled. It also listed the pictures of that project's second renderer, which was not ported.
class_name SplatDebugPanel
extends CanvasLayer


# region Constants
## The lowest and highest picture the art size slider gives, in art pixels from top to bottom.
const MIN_ART_HEIGHT: int = 90
const MAX_ART_HEIGHT: int = 720
const _LOOK_AGAIN_SECONDS: float = 1.0
# endregion


# region State
## The key that shows and hides the panel.
@export var toggle_key: Key = KEY_F1
## The key that switches the look, whether the panel shows or not.
@export var look_key: Key = KEY_V

## Whether the panel shows.
var open: bool = false:
	set(value):
		open = value
		if _window != null:
			_window.visible = value
			_refresh()

var _scenes: Array[SplatScene] = []
var _defaults: Array[Vector2i] = []
var _next_look: float = 0.0
var _window: PanelContainer
var _look_label: Label
var _average_button: Button
var _vote_button: Button
var _dither_label: Label
var _dither_slider: HSlider
var _rows: VBoxContainer
var _size_labels: Array[Label] = []
var _size_sliders: Array[HSlider] = []
var _refreshing: bool = false
# endregion


# region Lifecycle
func _enter_tree() -> void:
	if not OS.is_debug_build():
		queue_free() # however it got here, a release build has no debug panel


func _ready() -> void:
	if is_queued_for_deletion():
		return
	layer = 100
	_build()
	find_scenes()


func _process(delta: float) -> void:
	_next_look -= delta
	if _next_look <= 0.0:
		# the pictures come and go with the game's scenes, so they are looked up again every second
		_next_look = _LOOK_AGAIN_SECONDS
		find_scenes()
	if open:
		_refresh()
# endregion


# region Input
# No input action of its own, so the game's input map stays as it is: the keys are read raw.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == toggle_key:
		open = not open
	elif key.keycode == look_key:
		set_vote(not is_vote())
	else:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
# endregion


# region Public API
## Makes the panel as a child of [param parent] and hands it back; [code]null[/code], and nothing
## made, in a release export or when [param wanted] is false (the game's own condition: a setting,
## a command-line flag).
static func add_to(parent: Node, wanted: bool = true) -> SplatDebugPanel:
	if not wanted or not OS.is_debug_build() or parent == null:
		return null
	var panel: SplatDebugPanel = SplatDebugPanel.new()
	panel.name = "SplatDebugPanel"
	parent.add_child(panel)
	return panel


## Looks up the tree's [SplatScene]s again. The panel does it by itself every second.
func find_scenes() -> void:
	var found: Array[SplatScene] = []
	if is_inside_tree():
		_gather(get_tree().root, found)
	if found == _scenes:
		return
	# a picture met for the first time: the size it has now is the one "Reset" goes back to
	var defaults: Array[Vector2i] = []
	for scene: SplatScene in found:
		var known: int = _scenes.find(scene)
		defaults.append(_defaults[known] if known >= 0 else scene.art_size)
	_scenes = found
	_defaults = defaults
	_build_rows()


## The pictures the panel changes.
func get_scenes() -> Array[SplatScene]:
	return _scenes


## Whether the inside of a shape takes the vote: the first picture's look, and false with none.
func is_vote() -> bool:
	for scene: SplatScene in _scenes:
		if is_instance_valid(scene):
			return scene.interior == SplatScene.Interior.VOTE
	return false


## Gives every picture the vote, or the average with its dither.
func set_vote(vote: bool) -> void:
	for scene: SplatScene in _scenes:
		if is_instance_valid(scene):
			scene.interior = SplatScene.Interior.VOTE if vote else SplatScene.Interior.AVERAGE
	print("[SplatDebugPanel] Pixel look: %s." % ("vote" if vote else "average with dither"))
	_refresh()


## The dither of the average look: the first picture's.
func get_dither() -> float:
	for scene: SplatScene in _scenes:
		if is_instance_valid(scene):
			return scene.dither
	return 0.021


## Gives every picture that dither, 0 to 0.3.
func set_dither(value: float) -> void:
	for scene: SplatScene in _scenes:
		if is_instance_valid(scene):
			scene.dither = clampf(value, 0.0, 0.3)
	_refresh()


## Makes one of [method get_scenes] that many art pixels high, between [constant MIN_ART_HEIGHT]
## and [constant MAX_ART_HEIGHT], and as wide as keeps the shape it had when the panel found it.
## The scene draws at the new size from its next frame.
func set_art_height(index: int, height: int) -> void:
	if index < 0 or index >= _scenes.size() or not is_instance_valid(_scenes[index]):
		return
	var shape: Vector2i = _defaults[index]
	var high: int = clampi(height, MIN_ART_HEIGHT, MAX_ART_HEIGHT)
	_scenes[index].art_size = Vector2i(maxi(1, roundi(high * shape.x / float(maxi(1, shape.y)))), high)
	_refresh()


## Every picture back to the size it had when the panel found it.
func reset_art_sizes() -> void:
	for i: int in _scenes.size():
		if is_instance_valid(_scenes[i]):
			_scenes[i].art_size = _defaults[i]
	_refresh()
# endregion


# region Signal Handlers
func _on_dither_changed(value: float) -> void:
	if not _refreshing:
		set_dither(value)


func _on_size_changed(value: float, index: int) -> void:
	if not _refreshing:
		set_art_height(index, roundi(value))
# endregion


# region Helpers
func _gather(node: Node, into: Array[SplatScene]) -> void:
	if node is SplatScene:
		into.append(node)
	for child: Node in node.get_children():
		_gather(child, into)


func _build() -> void:
	_window = PanelContainer.new()
	_window.position = Vector2(12, 12)
	_window.custom_minimum_size = Vector2(330, 0)
	_window.visible = open
	var backing: StyleBoxFlat = StyleBoxFlat.new()
	backing.bg_color = Color(0.1, 0.09, 0.09, 1.0)
	backing.set_content_margin_all(10)
	_window.add_theme_stylebox_override(&"panel", backing)
	add_child(_window)
	var column: VBoxContainer = VBoxContainer.new()
	_window.add_child(column)

	var title: Label = Label.new()
	title.text = "Splat pixel look (%s)" % OS.get_keycode_string(toggle_key)
	column.add_child(title)
	_look_label = Label.new()
	column.add_child(_look_label)
	var looks: HBoxContainer = HBoxContainer.new()
	column.add_child(looks)
	_average_button = Button.new()
	_average_button.text = "Average + dither"
	_average_button.toggle_mode = true
	_average_button.pressed.connect(set_vote.bind(false))
	looks.add_child(_average_button)
	_vote_button = Button.new()
	_vote_button.text = "Vote"
	_vote_button.toggle_mode = true
	_vote_button.pressed.connect(set_vote.bind(true))
	looks.add_child(_vote_button)

	_dither_label = Label.new()
	column.add_child(_dither_label)
	_dither_slider = HSlider.new()
	_dither_slider.min_value = 0.0
	_dither_slider.max_value = 0.3
	_dither_slider.step = 0.001
	_dither_slider.value_changed.connect(_on_dither_changed)
	column.add_child(_dither_slider)

	_rows = VBoxContainer.new()
	column.add_child(_rows)
	var reset: Button = Button.new()
	reset.text = "Reset art sizes"
	reset.pressed.connect(reset_art_sizes)
	column.add_child(reset)


# A label and a slider for each picture.
func _build_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_size_labels.clear()
	_size_sliders.clear()
	for i: int in _scenes.size():
		var label: Label = Label.new()
		_rows.add_child(label)
		_size_labels.append(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = MIN_ART_HEIGHT
		slider.max_value = MAX_ART_HEIGHT
		slider.step = 1.0
		slider.value_changed.connect(_on_size_changed.bind(i))
		_rows.add_child(slider)
		_size_sliders.append(slider)
	if _scenes.is_empty():
		var none: Label = Label.new()
		none.text = "No splat picture in this scene."
		_rows.add_child(none)
	_refresh()


# What the panel shows, from what the pictures hold now.
func _refresh() -> void:
	if _window == null:
		return
	_refreshing = true
	var vote: bool = is_vote()
	_look_label.text = "Colour inside shapes (%s): %s" % [OS.get_keycode_string(look_key), "vote" if vote else "average + dither"]
	_average_button.set_pressed_no_signal(not vote)
	_vote_button.set_pressed_no_signal(vote)
	_dither_label.text = "Dither %.3f (average look only)" % get_dither()
	_dither_slider.editable = not vote
	_dither_slider.value = get_dither()
	for i: int in mini(_scenes.size(), _size_labels.size()):
		if not is_instance_valid(_scenes[i]):
			continue
		var art: Vector2i = _scenes[i].art_size
		_size_labels[i].text = "%s: %d x %d art pixels" % [_scenes[i].name, art.x, art.y]
		_size_sliders[i].value = art.y
	_refreshing = false
# endregion
