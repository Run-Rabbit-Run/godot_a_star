extends Node
## Launches the configured project battle and offers the player to replay or leave it.
## Development tools are not involved; the battle itself stays in BattleScreen.

@export var deterministic_seed := 1
## Tests turn this off and start a fixed request through start().
@export var start_configured_battle := true
## Leaves the game; tests replace it so they can press the button without quitting.
var quit_game: Callable = func() -> void: get_tree().quit()

var _request: BattleStartRequest
var _ui_profile_path := ""
var _screen: BattleScreen
var _overlay: CanvasLayer
var _restarting := false


func _ready() -> void:
	if not start_configured_battle:
		return
	var settings := GameContentSettings.read()
	if settings == null or settings.battle_document_path.is_empty():
		_show_error("Не задан стартовый бой: content/game_content.tres.")
		return
	var result := ProjectBattleLoader.load_battle(
		settings.content_packages, settings.battle_document_path, deterministic_seed
	)
	if result.request == null:
		_show_error(result.error_message)
		return
	start(result.request, settings.ui_profile_path)


## Starts the battle; replays reuse the same request, so they repeat the same battle.
func start(request: BattleStartRequest, ui_profile_path := "") -> bool:
	_request = request
	_ui_profile_path = ui_profile_path
	return _open_screen()


## Replaces the current battle with a fresh one. The old screen leaves the tree first,
## so its map cannot reset the new one's cursor or input.
func restart() -> void:
	if _restarting or _request == null:
		return
	_restarting = true
	var old := _screen
	_screen = null
	_clear_overlay()
	if is_instance_valid(old):
		old.queue_free()
		await old.tree_exited
	_restarting = false
	_open_screen()


func _open_screen() -> bool:
	_clear_overlay()
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	screen.show_failure_message = false
	screen.ui_profile_path = _ui_profile_path
	if not screen.setup(_request):
		_show_error(screen.initialization_error)
		screen.free()
		return false
	screen.battle_failed.connect(func(message: String) -> void:
		# BattleScreen has already logged the failure; only the player-facing text remains.
		_show_message(("Бой остановлен из-за ошибки:\n" if screen.has_started() else "Не удалось запустить бой:\n") + message)
	)
	screen.battle_finished.connect(_on_battle_finished)
	_screen = screen
	add_child(screen)
	# A battle that cannot end has no draw rule; the player can always replay or leave.
	screen.add_menu_action("НАЧАТЬ БОЙ ЗАНОВО", restart)
	screen.add_menu_action("ВЫЙТИ ИЗ ИГРЫ", _quit)
	return true


func _on_battle_finished(result: BattleResult) -> void:
	var panel := BattleResultPanel.create(result)
	panel.restart_requested.connect(restart)
	panel.quit_requested.connect(_quit)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(panel)
	dim.add_child(center)
	_set_overlay(dim, 150)


func _quit() -> void:
	quit_game.call()


func _show_error(message: String) -> void:
	push_error("Game startup failed: %s" % message)
	_show_message("Не удалось запустить бой:\n" + message)


func _show_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(24, 24)
	label.custom_minimum_size.x = 850
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_overlay(label, 200)


## One overlay at a time: a replay clears the previous result or failure message.
func _set_overlay(content: Control, layer: int) -> void:
	_clear_overlay()
	_overlay = CanvasLayer.new()
	_overlay.name = "Overlay"
	_overlay.layer = layer
	_overlay.add_child(content)
	add_child(_overlay)


func _clear_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
