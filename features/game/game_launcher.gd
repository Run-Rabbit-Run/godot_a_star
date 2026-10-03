extends Node
## Launches the configured project battle without depending on development tools.

@export var deterministic_seed := 1


func _ready() -> void:
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
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	screen.ui_profile_path = settings.ui_profile_path
	if not screen.setup(result.request):
		_show_error(screen.initialization_error)
		screen.free()
		return
	screen.battle_failed.connect(_show_error)
	add_child(screen)


func _show_error(message: String) -> void:
	push_error("Game startup failed: %s" % message)
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var label := Label.new()
	label.text = "Не удалось запустить бой:\n" + message
	label.position = Vector2(24, 24)
	label.custom_minimum_size.x = 850
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(label)
