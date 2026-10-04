class_name UnitStateFactory
extends RefCounted


static func create(spawn: UnitSpawnData) -> UnitState:
	if spawn == null:
		push_error("UnitStateFactory requires UnitSpawnData.")
		return null

	if spawn.unit_id.is_empty():
		push_error("UnitSpawnData unit_id must not be empty.")
		return null

	if spawn.unit_definition == null:
		push_error("UnitSpawnData requires a UnitDefinition.")
		return null

	if spawn.unit_definition.base_stats == null:
		push_error("UnitDefinition base_stats is not assigned.")
		return null

	var base_stats := spawn.unit_definition.base_stats
	var stats_error := base_stats.validate()
	if not stats_error.is_empty():
		push_error(stats_error)
		return null
	var passive_ids := spawn.unit_definition.passive_ability_ids
	var passive_error := PassiveAbilityCatalog.validate(passive_ids)
	if not passive_error.is_empty():
		push_error(passive_error)
		return null
	var turn := TurnState.new(base_stats.movement_points)
	var health := HealthState.new(base_stats.max_health)

	var state := UnitState.new(
		spawn.unit_id,
		spawn.definition_id,
		spawn.faction,
		spawn.hex,
		turn,
		health,
		base_stats.basic_attack_damage + PassiveAbilityCatalog.attack_bonus(passive_ids),
		base_stats.basic_attack_range,
		spawn.abilities
	)
	if base_stats.armor_levels > 0:
		state.statuses[&"core:armor"] = base_stats.armor_levels
	state.passive_ability_ids.assign(passive_ids)
	for id: StringName in passive_ids:
		var passive: Dictionary = PassiveAbilityCatalog.DEFINITIONS[id]
		if passive.has("damage_type"):
			state.basic_attack_damage_type = passive.damage_type
		if passive.has("status"):
			state.basic_attack_statuses[passive.status] = 2
		if passive.has("immunity"):
			state.status_immunities.append(passive.immunity)
	return state
