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
var ability_area_radii: Dictionary[StringName, int] = {}
var statuses: Dictionary[StringName, int] = {}
var basic_attack_damage_type: StringName
var status_immunities: Array[StringName] = []
var ability_cooldowns: Dictionary[StringName, int] = {}
var ability_hex_targets: Dictionary[StringName, bool] = {}
var ability_target_modes: Dictionary[StringName, int] = {}
var passive_ability_ids: Array[StringName] = []
var basic_attack_statuses: Dictionary[StringName, int] = {}
var turns_started := 0


func _init(state: UnitState) -> void:
	unit_id = state.unit_id
	definition_id = state.definition_id
	faction = state.faction
	hex = state.hex
	statuses.assign(state.statuses)
	status_immunities.assign(state.status_immunities)
	basic_attack_damage_type = state.basic_attack_damage_type
	ability_cooldowns.assign(state.ability_cooldowns)
	passive_ability_ids.assign(state.passive_ability_ids)
	basic_attack_statuses.assign(state.basic_attack_statuses)
	turns_started = state.turns_started
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
		ability_ranges[ability_id] = ability.get_range(state)
		ability_hex_targets[ability_id] = ability.targets_hex()
		ability_target_modes[ability_id] = ability.target_mode
		ability_area_radii[ability_id] = ability.area_radius
