class_name EditorTrialRunner
extends RefCounted
## Shows a trial battle or the opening player view over the editor.
## The battle plays a snapshot of the document, so nothing from it is written back.

## The editor is visible again; `message` is its status line.
signal returned(message: String, severity: EditorUi.Severity)

var screen: BattleScreen
var return_layer: CanvasLayer
var _host: Control
var _battle_scene: PackedScene
var _editor_ui: Control
var _result: BattleResult
var _error := ""
var _preview_surface: SubViewportContainer


## The trial battle from `battle_scene` is added to `host` and covers `editor_ui`, hidden meanwhile.
func setup(host: Control, editor_ui: Control, battle_scene: PackedScene) -> void:
	_host = host
	_editor_ui = editor_ui
	_battle_scene = battle_scene


func is_running() -> bool:
	return screen != null


## Starts the battle; returns "" or why it was rejected. A running trial is left as it is.
func start(request: BattleStartRequest, preview := false, ui_profile_path := "") -> String:
	if screen != null:
		return ""
	screen = _battle_scene.instantiate() as BattleScreen
	screen.show_failure_message = false
	screen.ui_profile_path = ui_profile_path
	if not screen.setup(request, preview):
		var error := screen.initialization_error
		screen.free()
		screen = null
		return "%s: %s" % ["Вид игрока недоступен" if preview else "Пробный запуск отклонён", error]

	screen.battle_finished.connect(_on_finished)
	screen.battle_failed.connect(_on_failed)
	_editor_ui.visible = false
	if preview:
		_mount_preview()
	else:
		_host.add_child(screen)
	return_layer = CanvasLayer.new()
	return_layer.layer = 100
	_host.add_child(return_layer)
	var back := EditorUi.button("← Вернуться в редактор", return_to_editor)
	back.theme = EditorUi.theme()
	return_layer.add_child(back)
	if preview:
		back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		back.position += Vector2(20, -82) - Vector2(0, back.size.y)
	else:
		back.position = Vector2(20, 12)
	return ""


func _mount_preview() -> void:
	_preview_surface = SubViewportContainer.new()
	_preview_surface.name = "PlayerView"
	_preview_surface.stretch = true
	_host.add_child(_preview_surface)
	_preview_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(_preview_surface.size)
	viewport.gui_disable_input = true
	_preview_surface.add_child(viewport)
	viewport.add_child(screen)


func return_to_editor() -> void:
	if screen == null:
		return
	var preview := _preview_surface != null
	_close()
	var outcome := ""
	if _result != null:
		outcome = " (%s)" % ("победа" if _result.outcome == BattleOutcome.Value.VICTORY else "поражение")
	_result = null
	if not _error.is_empty():
		var error := _error
		_error = ""
		returned.emit("Пробный бой остановлен ошибкой: %s; BattleDocument не изменён." % error, EditorUi.Severity.ERROR)
		return
	if preview:
		returned.emit("Возврат из вида игрока.", EditorUi.Severity.INFO)
		return
	returned.emit("Пробный бой завершён%s; BattleDocument не изменён." % outcome, EditorUi.Severity.INFO)


func _close() -> void:
	if is_instance_valid(return_layer):
		return_layer.queue_free()
	return_layer = null
	if _preview_surface != null:
		_preview_surface.queue_free()
		_preview_surface = null
	else:
		screen.queue_free()
	screen = null
	_editor_ui.visible = true


func _on_finished(result: BattleResult) -> void:
	# The battle screen keeps showing the outcome until the author returns.
	# The editor status is hidden meanwhile, so the outcome is reported on return.
	_result = result


func _on_failed(message: String) -> void:
	if screen == null:
		return
	if _preview_surface != null or not screen.has_started():
		var action := "Вид игрока недоступен" if _preview_surface != null else "Пробный бой не запущен"
		_close()
		_result = null
		returned.emit("%s: %s" % [action, message], EditorUi.Severity.ERROR)
		return
	# A battle that stopped mid-play stays visible for diagnosis until the author returns.
	_error = message
	var label := Label.new()
	label.name = "TrialError"
	label.text = "Бой остановлен из-за ошибки:\n%s" % message
	label.position = Vector2(20, 60)
	label.custom_minimum_size.x = 850
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", EditorUi.ERROR)
	return_layer.add_child(label)
