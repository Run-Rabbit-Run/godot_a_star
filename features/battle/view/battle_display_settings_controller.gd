class_name BattleDisplaySettingsController
extends Node


const DISPLAY_CONFIG_PATH := "user://display_settings.cfg"
const DISPLAY_CONFIG_SECTION := "display"
const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
]


var _resolution_option: OptionButton
var _fullscreen_check: CheckButton
var _display_status_label: Label
var _selected_resolution := Vector2i(1920, 1080)
var _fullscreen_enabled := false
var _external_restart_requested := false


func setup(
	resolution_option: OptionButton,
	fullscreen_check: CheckButton,
	display_status_label: Label
) -> void:
	_resolution_option = resolution_option
	_fullscreen_check = fullscreen_check
	_display_status_label = display_status_label
	_populate_options_and_load_settings()
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	call_deferred("_apply_display_settings", false)


func _populate_options_and_load_settings() -> void:
	_resolution_option.clear()

	for resolution: Vector2i in SUPPORTED_RESOLUTIONS:
		var index := _resolution_option.item_count
		_resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		_resolution_option.set_item_metadata(index, resolution)

	var config := ConfigFile.new()
	var load_error := config.load(DISPLAY_CONFIG_PATH)

	if load_error == OK:
		_selected_resolution = Vector2i(
			int(config.get_value(
				DISPLAY_CONFIG_SECTION,
				"width",
				_selected_resolution.x
			)),
			int(config.get_value(
				DISPLAY_CONFIG_SECTION,
				"height",
				_selected_resolution.y
			))
		)
		_fullscreen_enabled = bool(config.get_value(
			DISPLAY_CONFIG_SECTION,
			"fullscreen",
			false
		))

	var selected_index := SUPPORTED_RESOLUTIONS.find(_selected_resolution)

	if selected_index == -1:
		_selected_resolution = SUPPORTED_RESOLUTIONS[0]
		selected_index = 0

	_resolution_option.select(selected_index)
	_fullscreen_check.set_pressed_no_signal(_fullscreen_enabled)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_option.item_count:
		return

	_selected_resolution = _resolution_option.get_item_metadata(index)
	_save_display_settings()
	_apply_display_settings()


func _on_fullscreen_toggled(enabled: bool) -> void:
	_fullscreen_enabled = enabled
	_save_display_settings()
	_apply_display_settings()


func _apply_display_settings(restart_if_embedded := true) -> void:
	if DisplayServer.get_name() == "headless":
		return

	if _is_editor_managed_run():
		if restart_if_embedded:
			_restart_outside_editor()
		else:
			_display_status_label.text = (
				"ЗАПУСК ИЗ РЕДАКТОРА · ИЗМЕНЕНИЕ ПЕРЕОТКРОЕТ ИГРУ"
			)
		return

	if _fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_selected_resolution)
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if OS.has_feature("windows")
			else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		call_deferred("_update_display_status")
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_apply_windowed_resolution")


func _apply_windowed_resolution() -> void:
	if DisplayServer.get_name() == "headless" or _fullscreen_enabled:
		return

	DisplayServer.window_set_size(_selected_resolution)
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var centered_position := usable_rect.position + Vector2i(
		(usable_rect.size.x - _selected_resolution.x) / 2,
		(usable_rect.size.y - _selected_resolution.y) / 2
	)
	DisplayServer.window_set_position(centered_position)
	_update_display_status()


func _is_editor_managed_run() -> bool:
	return EngineDebugger.is_active()


func _restart_outside_editor() -> void:
	if _external_restart_requested:
		return

	_external_restart_requested = true
	_display_status_label.text = "ПЕРЕЗАПУСК В ОТДЕЛЬНОМ ОКНЕ…"
	var process_id := OS.create_process(
		OS.get_executable_path(),
		PackedStringArray([
			"--path",
			ProjectSettings.globalize_path("res://"),
		])
	)

	if process_id <= 0:
		_external_restart_requested = false
		_display_status_label.text = (
			"НЕ УДАЛОСЬ ОТКРЫТЬ ОТДЕЛЬНОЕ ОКНО"
		)
		return

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _update_display_status() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var actual_size := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	var mode_name := (
		"ПОЛНЫЙ ЭКРАН"
		if mode in [
			DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
		]
		else "ОКНО"
	)
	_display_status_label.text = "ТЕКУЩИЙ РЕЖИМ: %d × %d · %s" % [
		actual_size.x,
		actual_size.y,
		mode_name,
	]
	print("Display settings applied: %dx%d, %s" % [
		actual_size.x,
		actual_size.y,
		mode_name,
	])


func _save_display_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"width",
		_selected_resolution.x
	)
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"height",
		_selected_resolution.y
	)
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"fullscreen",
		_fullscreen_enabled
	)
	var save_error := config.save(DISPLAY_CONFIG_PATH)

	if save_error != OK:
		push_warning("Display settings could not be saved. Error: %d" % save_error)