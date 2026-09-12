class_name UnitSnapshot
extends RefCounted


var unit_id: StringName
var definition_id: StringName
var faction: BattleFaction.Value
var hex: Vector2i
var turn: TurnSnapshot
var health: HealthSnapshot
var basic_attack_damage: int
var basic_attack_range: int
var ability_ids: Array[StringName] = []
var ability_ranges: Dictionary[StringName, int] = {}


func _init(state: UnitState) -> void:
	unit_id = state.unit_id
	definition_id = state.definition_id
	faction = state.faction
	hex = state.hex
	turn = TurnSnapshot.new(
		state.turn.movement_max,
		state.turn.movement_remaining,
		state.turn.main_action_available
	)
	health = HealthSnapshot.new(
		state.health.maximum,
		state.health.current
	)
	basic_attack_damage = state.basic_attack_damage
	basic_attack_range = state.basic_attack_range
	ability_ids.assign(state.abilities.keys())
	ability_ids.sort()

	for ability_id: StringName in ability_ids:
		var ability := state.get_ability(ability_id)
		ability_ranges[ability_id] = ability.range
