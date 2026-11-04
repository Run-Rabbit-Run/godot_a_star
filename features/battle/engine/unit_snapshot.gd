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
var abilities: Dictionary[StringName, AbilitySnapshot] = {}
var statuses: Dictionary[StringName, int] = {}
var basic_attack_damage_type: StringName
var status_immunities: Array[StringName] = []
var ability_cooldowns: Dictionary[StringName, int] = {}
var passive_ability_ids: Array[StringName] = []
var basic_attack_statuses: Dictionary[StringName, int] = {}
var turns_started := 0
var pending_spear_return: Dictionary = {}
var is_summoned := false
var summoned_by := StringName()
var holds_hex := false
var corpse_removed := false
var takes_turns := true
var max_health_bonus := 0


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
	pending_spear_return = state.pending_spear_return.duplicate(true)
	is_summoned = state.is_summoned
	summoned_by = state.summoned_by
	holds_hex = state.holds_hex
	corpse_removed = state.corpse_removed
	takes_turns = state.takes_turns()
	max_health_bonus = state.max_health_bonus
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
		abilities[ability_id] = AbilitySnapshot.new(state.get_ability(ability_id), state)
