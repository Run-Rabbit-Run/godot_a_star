class_name BattleScreen
extends Node


signal battle_finished(result: BattleResult)
signal battle_started
signal battle_failed(message: String)


@export var show_failure_message := true
var _failure_emitted := false

@export_file("*.json") var ui_profile_path := ""


@onready var _battle_controller: BattleController = (
	$BattleMap/BattleController
)

var _start_request: BattleStartRequest
var _has_started := false
var _prepared_session: BattleSession
var initialization_error := ""


func _enter_tree() -> void:
	if not ui_profile_path.is_empty():
		($BattleMap/BattleUI as BattleHUD).ui_profile_path = ui_profile_path


func _ready() -> void:
	if _start_request != null:
		_start_battle()


func setup(request: BattleStartRequest) -> bool:
	var validation := BattleStartRequestValidator.validate(request)

	if not validation.is_valid:
		_on_battle_failed(validation.error_message)
		return false

	if _start_request != null or _has_started:
		push_error("BattleScreen setup can only be called once.")
		return false

	var result := BattleSessionFactory.create(request)
	if not result.is_successful:
		_on_battle_failed(result.error_message)
		return false
	_prepared_session = result.session
	_start_request = request

	if is_node_ready():
		return _start_battle()

	return true


func _start_battle() -> bool:
	if _has_started:
		return false

	if not _battle_controller.battle_finished.is_connected(
		_on_battle_finished
	):
		_battle_controller.battle_finished.connect(
			_on_battle_finished
		)

	_battle_controller.battle_failed.connect(_on_battle_failed)
	_battle_controller.battle_started.connect(_on_battle_started)
	if not _battle_controller.setup(_start_request, _prepared_session):
		_on_battle_failed(_battle_controller.initialization_error)
		return false

	var battle := _start_request.content_snapshot.get_battle_definition(_start_request.battle_id)
	var map := _start_request.content_snapshot.get_map_definition(battle.map_id)
	($BattleMap as BattleMapView).set_map_presentation(map)
	return true


func _on_battle_started() -> void:
	_has_started = true
	battle_started.emit()


func _on_battle_failed(message: String) -> void:
	if _failure_emitted:
		return
	_failure_emitted = true
	initialization_error = message
	push_error("Battle startup failed: %s" % message)
	if is_node_ready() and show_failure_message:
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		var label := Label.new()
		label.position = Vector2(24, 60)
		label.text = "Не удалось запустить бой:\n%s" % message
		layer.add_child(label)
	battle_failed.emit(message)


func _on_battle_finished(result: BattleResult) -> void:
	battle_finished.emit(result)
