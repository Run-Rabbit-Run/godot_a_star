class_name DebugBattleLauncher
extends Node


signal battle_finished(result: BattleResult)


@export var battle_definition: BattleDefinition
@export var deterministic_seed := 1

@onready var _battle_screen: BattleScreen = %BattleScreen


func _ready() -> void:
	if not _battle_screen.battle_finished.is_connected(
		_on_battle_finished
	):
		_battle_screen.battle_finished.connect(
			_on_battle_finished
		)

	var request := BattleStartRequest.new(
		battle_definition,
		deterministic_seed
	)

	if not _battle_screen.setup(request):
		push_error("Debug battle could not be started.")


func _on_battle_finished(result: BattleResult) -> void:
	battle_finished.emit(result)