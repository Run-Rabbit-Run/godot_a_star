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
	var turn := TurnState.new(base_stats.movement_points)
	var health := HealthState.new(base_stats.max_health)

	return UnitState.new(
		spawn.unit_id,
		spawn.definition_id,
		spawn.faction,
		spawn.hex,
		turn,
		health,
		base_stats.basic_attack_damage
	)
