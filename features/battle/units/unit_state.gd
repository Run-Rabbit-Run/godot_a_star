class_name UnitState
extends RefCounted


var unit_id: StringName
var definition_id: StringName
var faction: BattleFaction.Value
var hex: Vector2i
var turn: TurnState
var health: HealthState
var basic_attack_damage: int
var basic_attack_range: int
var abilities: Dictionary[StringName, AbilityDefinition] = {}
var statuses: Dictionary[StringName, int] = {}
var passive_ability_ids: Array[StringName] = []
var basic_attack_damage_type: StringName = &"physical"
var basic_attack_statuses: Dictionary[StringName, int] = {}
var status_immunities: Array[StringName] = []
var ability_cooldowns: Dictionary[StringName, int] = {}
var turns_started := 0
var melee_retaliation := false
var retaliation_configured := false
var pending_spear_return: Dictionary = {}


func _init(
	p_unit_id: StringName,
	p_definition_id: StringName,
	p_faction: BattleFaction.Value,
	p_hex: Vector2i,
	p_turn: TurnState,
	p_health: HealthState,
	p_basic_attack_damage: int,
	p_basic_attack_range: int = 1,
	p_abilities: Array[AbilityDefinition] = []
) -> void:
	unit_id = p_unit_id
	definition_id = p_definition_id
	faction = p_faction
	hex = p_hex
	turn = p_turn
	health = p_health
	basic_attack_damage = maxi(p_basic_attack_damage, 0)
	basic_attack_range = maxi(p_basic_attack_range, 1)

	for ability: AbilityDefinition in p_abilities:
		if ability != null:
			abilities[ability.id] = ability.duplicate(true) as AbilityDefinition
			ability_cooldowns[ability.id] = ability.initial_cooldown_turns


func start_cooldown_turn() -> void:
	if turns_started > 0:
		for id: StringName in ability_cooldowns:
			ability_cooldowns[id] = maxi(0, ability_cooldowns[id] - 1)
	turns_started += 1


func get_ability(ability_id: StringName) -> AbilityDefinition:
	return abilities.get(ability_id) as AbilityDefinition


## Runtime collections are detached. Ability definitions are read-only during a battle,
## so the copy shares them instead of deep-copying every definition per forecast.
func duplicate_state() -> UnitState:
	var copy := UnitState.new(unit_id, definition_id, faction, hex, TurnState.new(turn.movement_max), HealthState.new(health.maximum), basic_attack_damage, basic_attack_range)
	copy.abilities.assign(abilities)
	copy.health.current = health.current
	copy.turn.movement_remaining = turn.movement_remaining
	copy.turn.main_action_available = turn.main_action_available
	copy.statuses.assign(statuses)
	copy.passive_ability_ids.assign(passive_ability_ids)
	copy.basic_attack_damage_type = basic_attack_damage_type
	copy.basic_attack_statuses.assign(basic_attack_statuses)
	copy.status_immunities.assign(status_immunities)
	copy.ability_cooldowns.assign(ability_cooldowns)
	copy.turns_started = turns_started
	copy.melee_retaliation = melee_retaliation
	copy.retaliation_configured = retaliation_configured
	copy.pending_spear_return = pending_spear_return.duplicate(true)
	return copy


## Takes every runtime value of another state of the same unit, keeping this object.
func copy_from(other: UnitState) -> void:
	hex = other.hex
	turn.movement_max = other.turn.movement_max
	turn.movement_remaining = other.turn.movement_remaining
	turn.main_action_available = other.turn.main_action_available
	health.maximum = other.health.maximum
	health.current = other.health.current
	basic_attack_damage = other.basic_attack_damage
	basic_attack_range = other.basic_attack_range
	abilities.assign(other.abilities)
	statuses.assign(other.statuses)
	passive_ability_ids.assign(other.passive_ability_ids)
	basic_attack_damage_type = other.basic_attack_damage_type
	basic_attack_statuses.assign(other.basic_attack_statuses)
	status_immunities.assign(other.status_immunities)
	ability_cooldowns.assign(other.ability_cooldowns)
	turns_started = other.turns_started
	melee_retaliation = other.melee_retaliation
	retaliation_configured = other.retaliation_configured
	pending_spear_return = other.pending_spear_return.duplicate(true)
