class_name UnitState
extends RefCounted


var unit_id: StringName
var definition_id: StringName
var faction: BattleFaction.Value
var hex: Vector2i
var turn: TurnState
var health: HealthState
var basic_attack_damage: int
var abilities: Dictionary[StringName, AbilityDefinition] = {}


func _init(
	p_unit_id: StringName,
	p_definition_id: StringName,
	p_faction: BattleFaction.Value,
	p_hex: Vector2i,
	p_turn: TurnState,
	p_health: HealthState,
	p_basic_attack_damage: int,
	p_abilities: Array[AbilityDefinition] = []
) -> void:
	unit_id = p_unit_id
	definition_id = p_definition_id
	faction = p_faction
	hex = p_hex
	turn = p_turn
	health = p_health
	basic_attack_damage = maxi(p_basic_attack_damage, 0)

	for ability: AbilityDefinition in p_abilities:
		if ability != null:
			abilities[ability.id] = ability


func get_ability(ability_id: StringName) -> AbilityDefinition:
	return abilities.get(ability_id) as AbilityDefinition
