class_name ActionPreview
extends RefCounted
## What one command would do, computed on a forecast copy of the battle: the action itself,
## the reactions it causes and the acting unit's own end-of-turn effects, up to the end of its
## turn. Effects of the next phase are not part of it. Read-only data for the battle UI.


## Health and statuses of one unit before and after the previewed command.
class UnitChange:
	extends RefCounted
	var unit_id: StringName
	var health_before := 0
	var health_after := 0
	var defeated := false
	var statuses_before: Dictionary[StringName, int] = {}
	var statuses_after: Dictionary[StringName, int] = {}


var accepted := false
var actor_id: StringName
## Units whose health or statuses would change.
var units: Dictionary[StringName, UnitChange] = {}
## Hexes whose layers would change: [liquid before, energy before, liquid after, energy after].
var hexes: Dictionary[Vector2i, Array] = {}
## Damage each hit obstacle hex would take.
var obstacle_damage: Dictionary[Vector2i, int] = {}
## Where the acting unit would end up; for a move, whether it reaches the requested hex.
var destination: Vector2i
var reached := true


## Runs the command on `forecast`, which the caller owns and discards afterwards.
static func build(forecast: BattleEngine, command: BattleCommand) -> ActionPreview:
	var preview := ActionPreview.new()
	preview.actor_id = _actor_of(command)
	var actor := forecast.get_unit(preview.actor_id)
	if actor != null:
		preview.destination = actor.hex
	var health: Dictionary[StringName, int] = {}
	var statuses: Dictionary[StringName, Dictionary] = {}
	for unit_id: StringName in forecast.get_turn_order():
		var unit := forecast.get_unit(unit_id)
		health[unit_id] = unit.health.current
		statuses[unit_id] = unit.statuses.duplicate()
	var grid := forecast.get_hex_grid()
	var resolution := forecast.execute(command)
	if not resolution.accepted:
		return preview
	preview.accepted = true
	for event: BattleEvent in resolution.events:
		if event is TurnEndedEvent and event.unit_id == preview.actor_id:
			break
		if event is UnitDamagedEvent:
			var change := preview._change(event.target_id, health, statuses)
			change.health_after = event.target_health_remaining
			change.defeated = event.target_defeated
		elif event is UnitStatusChangedEvent:
			preview._change(event.unit_id, health, statuses).statuses_after = event.statuses.duplicate()
		elif event is UnitMovedEvent and event.unit_id == preview.actor_id and not event.path.is_empty():
			preview.destination = event.path.back()
		elif event is MapMutationEvent and event.obstacle_changed:
			preview.obstacle_damage[event.hex] = event.obstacle_damage
		elif event is MapMutationEvent and event.kind == MapMutationKind.Value.APPLY_HEX_STATE and event.hex_state_changed:
			var previous: Array = preview.hexes.get(event.hex, [grid.get_liquid(event.hex), grid.get_energy(event.hex)])
			preview.hexes[event.hex] = [previous[0], previous[1], event.liquid_id, event.energy_id]
	if command is MoveCommand:
		var mover := preview.units.get(preview.actor_id) as UnitChange
		preview.reached = preview.destination == command.destination and (mover == null or not mover.defeated)
	return preview


func _change(unit_id: StringName, health: Dictionary[StringName, int], statuses: Dictionary[StringName, Dictionary]) -> UnitChange:
	if not units.has(unit_id):
		var change := UnitChange.new()
		change.unit_id = unit_id
		change.health_before = health.get(unit_id, 0)
		change.health_after = change.health_before
		change.statuses_before.assign(statuses.get(unit_id, {}))
		change.statuses_after.assign(change.statuses_before)
		units[unit_id] = change
	return units[unit_id]


static func _actor_of(command: BattleCommand) -> StringName:
	if command is MoveCommand:
		return command.unit_id
	if command is AttackCommand:
		return command.attacker_id
	if command is AttackObstacleCommand:
		return command.attacker_id
	if command is UseAbilityCommand:
		return command.user_id
	if command is EndTurnCommand:
		return command.unit_id
	return StringName()
