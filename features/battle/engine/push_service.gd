class_name PushService
extends RefCounted
## Forced movement. A pushed unit slides hex by hex along a straight line, ignoring movement
## costs. A living unit, an obstacle, an impassable hex or the field edge in its way ends the
## push: the pushed unit and what it hit each take collision damage. Hex layers it slides
## onto act on it as on an ordinary move.

const COLLISION_DAMAGE := 1


## Pushes the living target `distance` hexes in one of the six directions. A unit that holds
## its hex stays anchored to it.
static func push(state: BattleState, source_id: StringName, target_id: StringName, direction: Vector2i, distance: int, ability_id: StringName, events: Array[BattleEvent]) -> void:
	var unit := state.unit_states.get(target_id) as UnitState
	if unit == null or unit.health.is_defeated() or unit.holds_hex or distance <= 0 or not HexGrid.DIRECTIONS.has(direction):
		return
	var segment: Array[Vector2i] = [unit.hex]
	for _step in range(distance):
		var next := unit.hex + direction
		var collision := collision_at(state, next)
		if collision != UnitPushedEvent.Collision.NONE:
			var blocker := _living_unit_at(state, next)
			var event := UnitPushedEvent.new(target_id, source_id, segment)
			event.collision = collision
			event.blocker_hex = next
			event.blocker_unit_id = blocker.unit_id if blocker != null else StringName()
			events.append(event)
			_collide(state, unit, blocker, next, collision, source_id, ability_id, events)
			return
		unit.hex = next
		segment.append(next)
		if not state.hex_grid.has_layers(next):
			continue
		# The layers act once the unit is on the hex, as on an ordinary move.
		events.append(UnitPushedEvent.new(target_id, source_id, segment))
		segment = [next]
		HexStateService.expose(unit, state.hex_grid, events)
		if unit.health.is_defeated():
			return
	if segment.size() > 1:
		events.append(UnitPushedEvent.new(target_id, source_id, segment))


## What a pushed unit would hit on entering the hex. Bodies do not stop it.
static func collision_at(state: BattleState, hex: Vector2i) -> UnitPushedEvent.Collision:
	if not state.hex_grid.has_cell(hex):
		return UnitPushedEvent.Collision.EDGE
	if state.hex_grid.has_obstacle(hex):
		return UnitPushedEvent.Collision.OBSTACLE
	if not state.hex_grid.is_traversable(hex):
		return UnitPushedEvent.Collision.IMPASSABLE
	if _living_unit_at(state, hex) != null:
		return UnitPushedEvent.Collision.UNIT
	return UnitPushedEvent.Collision.NONE


## The pushed unit is hit first, then the unit or obstacle it ran into; the edge and
## impassable hexes take nothing.
static func _collide(state: BattleState, unit: UnitState, blocker: UnitState, hex: Vector2i, collision: UnitPushedEvent.Collision, source_id: StringName, ability_id: StringName, events: Array[BattleEvent]) -> void:
	UnitStatusService.damage(unit, _hit(source_id, ability_id), events)
	if collision == UnitPushedEvent.Collision.UNIT and blocker != null:
		UnitStatusService.damage(blocker, _hit(source_id, ability_id), events)
	elif collision == UnitPushedEvent.Collision.OBSTACLE:
		ObstacleService.damage(state, hex, COLLISION_DAMAGE, events)


static func _hit(source_id: StringName, ability_id: StringName) -> DamageRequest:
	return DamageRequest.new(COLLISION_DAMAGE, &"physical").from_unit(source_id).with_ability(ability_id).from_collision()


static func _living_unit_at(state: BattleState, hex: Vector2i) -> UnitState:
	var ids := state.unit_states.keys()
	ids.sort()
	for id: StringName in ids:
		var unit: UnitState = state.unit_states[id]
		if unit.hex == hex and not unit.health.is_defeated():
			return unit
	return null
