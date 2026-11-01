class_name EditorTrialRunner
extends RefCounted
## Runs a trial battle over the editor and reports how it ended when the author returns.
## The battle plays a snapshot of the document, so nothing from it is written back.

## The editor is visible again; `message` is its status line.
signal returned(message: String, severity: EditorUi.Severity)

var screen: BattleScreen
var return_layer: CanvasLayer
var _host: Node
var _battle_scene: PackedScene
var _editor_ui: Control
var _result: BattleResult
var _error := ""


## The trial battle from `battle_scene` is added to `host` and covers `editor_ui`, hidden meanwhile.
func setup(host: Node, editor_ui: Control, battle_scene: PackedScene) -> void:
	_host = host
	_editor_ui = editor_ui
	_battle_scene = battle_scene


func is_running() -> bool:
	return screen != null


## Starts the battle; returns "" or why it was rejected. A running trial is left as it is.
func start(request: BattleStartRequest) -> String:
	if screen != null:
		return ""
	screen = _battle_scene.instantiate() as BattleScreen
	screen.show_failure_message = false
	if not screen.setup(request):
		var error := screen.initialization_error
		screen.free()
		screen = null
		return "Пробный запуск отклонён: %s" % error

	screen.battle_finished.connect(_on_finished)
	screen.battle_failed.connect(_on_failed)
	_editor_ui.visible = false
	_host.add_child(screen)
	return_layer = CanvasLayer.new()
	return_layer.layer = 100
	_host.add_child(return_layer)
	var back := EditorUi.button("← Вернуться в редактор", return_to_editor)
	back.theme = EditorUi.theme()
	back.position = Vector2(20, 12)
	return_layer.add_child(back)
	return ""


func return_to_editor() -> void:
	if screen == null:
		return
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
	returned.emit("Пробный бой завершён%s; BattleDocument не изменён." % outcome, EditorUi.Severity.INFO)


func _close() -> void:
	if is_instance_valid(return_layer):
		return_layer.queue_free()
	return_layer = null
	screen.queue_free()
	screen = null
	_editor_ui.visible = true


func _on_finished(result: BattleResult) -> void:
	# The battle screen keeps showing the outcome until the author returns.
	# The editor status is hidden meanwhile, so the outcome is reported on return.
	_result = result


func _on_failed(message: String) -> void:
	if screen == null or not screen.has_started():
		_close()
		_result = null
		returned.emit("Пробный бой не запущен: %s" % message, EditorUi.Severity.ERROR)
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
