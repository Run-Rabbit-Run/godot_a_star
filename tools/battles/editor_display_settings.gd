class_name EditorDisplaySettings
extends VBoxContainer


const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

var _resolution := OptionButton.new()
var _fullscreen := CheckButton.new()
var _status := Label.new()
var _windowed_size := Vector2i(1920, 1080)


func _ready() -> void:
	var caption := Label.new()
	caption.text = "Разрешение окна редактора"
	add_child(caption)
	for dimensions: Vector2i in RESOLUTIONS:
		_add_resolution(dimensions)
	add_child(_resolution)
	_fullscreen.text = "Полноэкранный режим"
	add_child(_fullscreen)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	add_child(_status)
	_resolution.item_selected.connect(_on_resolution_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	get_window().size_changed.connect(_sync_window)
	_sync_window()


func _add_resolution(dimensions: Vector2i) -> int:
	var index := _resolution.item_count
	_resolution.add_item("%d × %d" % [dimensions.x, dimensions.y])
	_resolution.set_item_metadata(index, dimensions)
	return index


func _is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func _sync_window() -> void:
	# An embedded game window is sized by the Godot editor, not this process.
	if OS.get_cmdline_args().has("--wid") or get_window().is_embedded():
		_resolution.disabled = true
		_fullscreen.disabled = true
		_status.text = "Для изменения окна отключите в Godot встраивание игры (Embed Game on Play)."
		return
	var window := get_window()
	var fullscreen := _is_fullscreen()
	_fullscreen.set_pressed_no_signal(fullscreen)
	if not fullscreen and window.mode == Window.MODE_WINDOWED:
		_windowed_size = window.size
	var selected := -1
	for index in range(_resolution.item_count):
		if _resolution.get_item_metadata(index) == _windowed_size:
			selected = index
			break
	if selected < 0:
		selected = _add_resolution(_windowed_size)
	_resolution.select(selected)
	_status.text = (
		"Полный экран: %d × %d. Выбранный размер применяется при выходе в окно."
		if fullscreen else "Текущее окно: %d × %d"
	) % [window.size.x, window.size.y]


func _on_resolution_selected(index: int) -> void:
	_windowed_size = _resolution.get_item_metadata(index)
	if not _is_fullscreen():
		_apply_windowed_size(_windowed_size)


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		get_window().mode = Window.MODE_FULLSCREEN
		call_deferred("_sync_window")
	else:
		_apply_windowed_size(_windowed_size)


func _apply_windowed_size(dimensions: Vector2i) -> void:
	get_window().mode = Window.MODE_WINDOWED
	# Keep the requested size across the mode-change size notification.
	call_deferred("_finish_windowed_size", dimensions)


func _finish_windowed_size(dimensions: Vector2i) -> void:
	var window := get_window()
	window.size = dimensions
	if DisplayServer.get_name() != "headless":
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = usable.position + Vector2i(
			maxi(0, (usable.size.x - dimensions.x) / 2),
			maxi(0, (usable.size.y - dimensions.y) / 2)
		)
	_sync_window()
