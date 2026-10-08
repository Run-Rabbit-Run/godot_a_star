class_name BattleLoggingController
extends Node


const FEATURE_SETTING := "feature_flags/battle_file_logging"
const CONFIG_PATH := "user://battle_logging.cfg"
var _logger := BattleFileLogger.new()
var _session: BattleSession
var _check: CheckButton
var _status: Label
var _end_reason := ""
var _end_detail := ""
var _directory := ""


## The flag is checked only at composition: no controls or observer when disabled.
static func is_feature_enabled() -> bool:
	return bool(ProjectSettings.get_setting(FEATURE_SETTING, false))


func setup(session: BattleSession, hud: BattleHUD, controller: BattleController, directory := "") -> void:
	_session = session
	_directory = directory
	_logger.recording_failed.connect(_on_recording_failed)
	var section := VBoxContainer.new()
	section.name = "BattleFileLogging"
	hud.get_node("HUDRoot/SpeedPanel/Content").add_child(section)
	_check = CheckButton.new()
	_check.text = "ЗАПИСЫВАТЬ ЛОГ БОЯ В ФАЙЛ"
	_check.add_theme_font_size_override("font_size", 11)
	section.add_child(_check)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_status)
	_check.toggled.connect(_on_toggled)
	controller.battle_finished.connect(_on_finished)
	controller.battle_failed.connect(_on_failed)
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	var enabled := bool(config.get_value("logging", "enabled", false))
	_check.set_pressed_no_signal(enabled)
	if enabled:
		_begin(true)
	else:
		_refresh_status()


func _on_toggled(enabled: bool) -> void:
	if enabled:
		_begin(false)
	else:
		_logger.stop("disabled")
		_refresh_status()
	var config := ConfigFile.new()
	config.set_value("logging", "enabled", _check.button_pressed)
	if config.save(CONFIG_PATH) != OK:
		_status.text += "\nНе удалось сохранить настройку."


func _begin(from_start: bool) -> void:
	if not _logger.start(_session, _directory, from_start):
		_check.set_pressed_no_signal(false)
	if not _end_reason.is_empty():
		_logger.stop(_end_reason, _end_detail)
	elif _session.is_finished():
		_logger.stop("battle_finished")
	_refresh_status()


func _on_finished(_result: BattleResult) -> void:
	_end_reason = "battle_finished"
	_logger.stop("battle_finished")
	_refresh_status()


func _on_failed(message: String) -> void:
	_end_reason = "battle_failed"
	_end_detail = message
	_logger.stop("battle_failed", message)
	_refresh_status()


func _refresh_status() -> void:
	if not _logger.error_message.is_empty():
		_status.text = _logger.error_message
	elif _logger.is_recording():
		_status.text = "Идёт запись · logs/battles"
	else:
		_status.text = "Лог сохранён · logs/battles" if not _logger.path.is_empty() else "Файлы: logs/battles в папке игры"
	_status.tooltip_text = _logger.path if not _logger.path.is_empty() else BattleFileLogger.default_directory()


func _on_recording_failed(_message: String) -> void:
	_check.set_pressed_no_signal(false)
	_refresh_status()


func _exit_tree() -> void:
	_logger.stop("scene_closed")
