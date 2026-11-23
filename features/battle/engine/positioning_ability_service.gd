class_name PositioningAbilityService
extends RefCounted


static func can_target(state: BattleState, actor: UnitState, operation: StringName, center: Vector2i) -> bool:
	match operation:
		&"ram":
			return not actor.holds_hex and _ram_path(state, actor.hex, center).size() == HexGrid.get_distance(actor.hex, center)
		&"grapple":
			return center != actor.hex and not actor.holds_hex and AbilityMovementService.occupant_at(state, center) != null and not _grapple_path(state, actor.hex, center).is_empty()
		&"swap":
			var target := AbilityMovementService.occupant_at(state, center)
			return target != null and target != actor and not actor.holds_hex and AbilityMovementService.may_displace(target) and state.hex_grid.is_traversable(actor.hex) and state.hex_grid.is_traversable(center)
		&"fissure":
			return not FissureService.plan(state, FissureService.line(actor.hex, center)).is_empty()
		&"dash":
			return not actor.holds_hex and _dash_path(state, actor.hex, center).has(center)
	return true


static func apply(state: BattleState, operation: StringName, actor: UnitState, center: Vector2i, cells: Array[Vector2i], ability_id: StringName, events: Array[BattleEvent]) -> String:
	match operation:
		&"attract":
			return _shift_area(state, actor, actor.hex, cells, true, ability_id, events)
		&"shot_push", &"shot_pull":
			var target := AbilityMovementService.occupant_at(state, center)
			_shoot(state, target, actor, actor.basic_attack_damage, ability_id, events)
			return _shift_area(state, actor, center, cells, operation == &"shot_pull", ability_id, events)
		&"ram":
			return _ram(state, actor, center, ability_id, events)
		&"grapple":
			return _travel(state, actor, _grapple_path(state, actor.hex, center), events)
		&"recoil":
			_shoot(state, AbilityMovementService.occupant_at(state, center), actor, actor.basic_attack_damage + 1, ability_id, events)
			return PushService.push(state, actor.unit_id, actor.unit_id, -_step_towards(actor.hex, center), 1, ability_id, events)
		&"swap":
			var target := AbilityMovementService.occupant_at(state, center)
			var destinations: Dictionary[StringName, Vector2i] = {actor.unit_id: center, target.unit_id: actor.hex}
			return AbilityMovementService.relocate(state, destinations, events)
		&"fissure":
			return FissureService.create(state, actor, cells, events)
		&"intercept":
			UnitStatusService.apply(actor, UnitStatusCatalog.INTERCEPT_READY, 1, events)
			return ""
		&"dash":
			return _dash(state, actor, center, ability_id, events)
	return "Unsupported positioning operation."


static func _shift_area(state: BattleState, actor: UnitState, center: Vector2i, cells: Array[Vector2i], inward: bool, ability_id: StringName, events: Array[BattleEvent]) -> String:
	var targets: Array[UnitState] = []
	for unit: UnitState in state.unit_states.values():
		if AbilityMovementService.may_displace(unit) and unit.hex != center and cells.has(unit.hex):
			targets.append(unit)
	targets.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		var da := HexGrid.get_distance(center, a.hex)
		var db := HexGrid.get_distance(center, b.hex)
		return IdOrder.is_before(a.unit_id, b.unit_id) if da == db else (da < db if inward else da > db)
	)
	var destinations: Dictionary[StringName, Vector2i] = {}
	for unit: UnitState in targets:
		var direction := _step_towards(unit.hex, center)
		destinations[unit.unit_id] = direction if inward else -direction
	for unit: UnitState in targets:
		var error := PushService.push(state, actor.unit_id, unit.unit_id, destinations[unit.unit_id], 1, ability_id, events)
		if not error.is_empty():
			return error
	return ""


static func _ram(state: BattleState, actor: UnitState, center: Vector2i, ability_id: StringName, events: Array[BattleEvent]) -> String:
	var start := actor.hex
	var path := _ram_path(state, start, center)
	var error := _travel(state, actor, path, events)
	if not error.is_empty() or actor.health.is_defeated() or actor.statuses.has(UnitStatusCatalog.PARALYSIS) or HexGrid.get_distance(actor.hex, center) != 1:
		return error
	var target := AbilityMovementService.occupant_at(state, center)
	if target == null:
		return ""
	_hit(target, actor, 1 + HexGrid.get_distance(start, actor.hex), &"physical", ability_id, events)
	return PushService.push(state, actor.unit_id, target.unit_id, center - actor.hex, 1, ability_id, events)


## Includes the start, but never the enemy cell. A different occupant blocks the charge.
static func _ram_path(state: BattleState, start: Vector2i, center: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var direction := AbilityExecutor.get_line_direction(start, center)
	if direction == Vector2i.ZERO:
		return path
	path.append(start)
	for step in range(1, HexGrid.get_distance(start, center)):
		var hex := start + direction * step
		if not state.hex_grid.is_traversable(hex) or AbilityMovementService.occupant_at(state, hex) != null:
			return []
		path.append(hex)
	return path


static func _grapple_path(state: BattleState, start: Vector2i, center: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	for hex: Vector2i in AbilityExecutor.get_path_hexes(state.hex_grid, start, center):
		if HexGrid.get_distance(path.back(), hex) != 1 or not state.hex_grid.is_traversable(hex) or AbilityMovementService.occupant_at(state, hex) != null:
			break
		path.append(hex)
	return path if path.size() > 1 else []


static func _dash_path(state: BattleState, start: Vector2i, center: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var direction := AbilityExecutor.get_line_direction(start, center)
	if direction == Vector2i.ZERO or AbilityMovementService.occupant_at(state, center) != null:
		return path
	for step in range(1, HexGrid.get_distance(start, center) + 1):
		var hex := start + direction * step
		if not state.hex_grid.is_traversable(hex):
			return []
		path.append(hex)
	return path


static func _dash(state: BattleState, actor: UnitState, center: Vector2i, ability_id: StringName, events: Array[BattleEvent]) -> String:
	for hex: Vector2i in _dash_path(state, actor.hex, center):
		var target := AbilityMovementService.occupant_at(state, hex)
		if target != null:
			if target.faction != actor.faction:
				_hit(target, actor, 1, &"electric", ability_id, events)
				var reaction_error := DamageType.react(state, hex, &"electric", events)
				if not reaction_error.is_empty():
					return reaction_error
			continue
		var error := _step(state, actor, hex, events)
		if not error.is_empty() or actor.health.is_defeated() or actor.statuses.has(UnitStatusCatalog.PARALYSIS):
			return error
	return ""


static func _travel(state: BattleState, actor: UnitState, path: Array[Vector2i], events: Array[BattleEvent]) -> String:
	for index in range(1, path.size()):
		var error := _step(state, actor, path[index], events)
		if not error.is_empty() or actor.health.is_defeated() or actor.statuses.has(UnitStatusCatalog.PARALYSIS):
			return error
	return ""


static func _step(state: BattleState, actor: UnitState, next: Vector2i, events: Array[BattleEvent]) -> String:
	var path: Array[Vector2i] = [actor.hex, next]
	actor.hex = next
	events.append(UnitMovedEvent.new(actor.unit_id, path, 0))
	return AbilityMovementService.enter(state, actor, events)


static func _hit(target: UnitState, actor: UnitState, damage: int, type: StringName, ability_id: StringName, events: Array[BattleEvent]) -> void:
	if target != null:
		UnitStatusService.damage(target, DamageRequest.new(damage, type).from_unit(actor.unit_id).with_ability(ability_id), events)


static func _shoot(state: BattleState, target: UnitState, actor: UnitState, damage: int, ability_id: StringName, events: Array[BattleEvent]) -> void:
	if target == null:
		return
	var layer := state.hex_grid.get_liquid(target.hex)
	var cover := HexStateCatalog.ranged_reduction(layer) if actor.basic_attack_range > 1 else 0
	var hit := DamageRequest.new(damage, &"physical").from_unit(actor.unit_id).with_ability(ability_id)
	UnitStatusService.damage(target, hit.with_cover(cover, layer), events)


## Closest axial direction, with fixed direction order breaking exact ties.
static func _step_towards(start: Vector2i, center: Vector2i) -> Vector2i:
	var delta := center - start
	var best_score := 0
	var best := Vector2i.ZERO
	for step: Vector2i in HexGrid.DIRECTIONS:
		var score := step.x * delta.x + step.y * delta.y + (step.x + step.y) * (delta.x + delta.y)
		if score > best_score:
			best_score = score
			best = step
	return best
