class_name ObstacleBreakService
extends RefCounted
## What a destroyed flask does to its surroundings. Its hex is already free: a spill or fire
## covers it as well. A flask hit by the burst of another one bursts right away, so a chain
## of flasks resolves within the action that broke the first.

## Hexes a pressure flask throws its living neighbors back.
const PRESSURE_PUSH_DISTANCE := 2


## Returns "" or why the burst could not change the map.
static func burst(state: BattleState, flask: BattleObstacleDefinition, events: Array[BattleEvent]) -> String:
	var hex := flask.hexes[0]
	events.append(ObstacleBrokenEvent.new(flask))
	match flask.terrain_type:
		&"flask":
			var spot: Array[Vector2i] = [hex]
			return _cover(state, spot, flask.contents, events)
		&"big_flask":
			return _cover(state, _area(state, hex), flask.contents, events)
		&"pressure_flask":
			return _blow_away(state, hex, events)
		&"explosive_flask":
			return _explode(state, flask, events)
	return ""


## Fire damage to every living unit around, then fire on the flask's hex and its neighbors,
## then the same damage to the obstacles around: flasks among them burst in turn.
static func _explode(state: BattleState, flask: BattleObstacleDefinition, events: Array[BattleEvent]) -> String:
	var hex := flask.hexes[0]
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var unit := _living_unit_at(state, hex + direction)
		if unit != null:
			UnitStatusService.damage(unit, DamageRequest.new(flask.blast_damage, &"fire").from_obstacle(flask.id), events)
	var error := _cover(state, _area(state, hex), &"core:fire", events)
	if not error.is_empty():
		return error
	var struck: Dictionary[StringName, bool] = {}
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var obstacle := state.hex_grid.get_obstacle(hex + direction)
		if obstacle == null or struck.has(obstacle.id):
			continue
		struck[obstacle.id] = true
		error = ObstacleService.damage(state, hex + direction, flask.blast_damage, events)
		if not error.is_empty():
			return error
	return ""


## Every living neighbor flies straight away from the flask, in the fixed order of directions.
static func _blow_away(state: BattleState, hex: Vector2i, events: Array[BattleEvent]) -> String:
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var unit := _living_unit_at(state, hex + direction)
		if unit == null:
			continue
		var error := PushService.push(state, &"", unit.unit_id, direction, PRESSURE_PUSH_DISTANCE, &"", events)
		if not error.is_empty():
			return error
	return ""


## One map batch: every cell changes before reactions spread, then each occupant is exposed once.
static func _cover(state: BattleState, cells: Array[Vector2i], layer: StringName, events: Array[BattleEvent]) -> String:
	var mutations: Array[MapMutation] = []
	for cell: Vector2i in cells:
		mutations.append(MapMutation.apply_hex_state(cell, layer))
	var result := MapMutationService.apply(state, mutations)
	events.append_array(result.events)
	return result.rejection_reason


## The hex and its existing neighbors.
static func _area(state: BattleState, hex: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [hex]
	for direction: Vector2i in HexGrid.DIRECTIONS:
		if state.hex_grid.has_cell(hex + direction):
			cells.append(hex + direction)
	return cells


static func _living_unit_at(state: BattleState, hex: Vector2i) -> UnitState:
	var ids := state.unit_states.keys()
	ids.sort()
	for id: StringName in ids:
		var unit: UnitState = state.unit_states[id]
		if unit.hex == hex and not unit.health.is_defeated():
			return unit
	return null
