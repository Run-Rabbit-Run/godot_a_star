class_name ActionPreview
extends RefCounted
## What one command would do, computed on a forecast copy of the battle: the action itself and
## the reactions it causes, up to the end of the acting unit's turn. Effects of the phase
## boundaries, periodic damage included, are not part of it. Read-only data for the battle UI.


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
## Flasks that would burst, in the order they break.
var broken_flasks: Array[BattleObstacleDefinition] = []
## Where the acting unit would end up; for a move, whether it reaches the requested hex.
var destination: Vector2i
var reached := true


## Runs the command on `forecast`, which the caller owns and discards afterwards; `before` is
## the unchanged engine it was forked from and supplies the values before the command.
static func build(forecast: BattleEngine, before: BattleEngine, command: BattleCommand) -> ActionPreview:
	var preview := ActionPreview.new()
	preview.actor_id = actor_of(command)
	var actor := before.get_unit(preview.actor_id)
	if actor != null:
		preview.destination = actor.hex
	var resolution := forecast.execute(command)
	if not resolution.accepted:
		return preview
	preview.accepted = true
	for event: BattleEvent in resolution.events:
		if event is TurnEndedEvent and event.unit_id == preview.actor_id:
			break
		if event is UnitDamagedEvent:
			var change := preview._change(event.target_id, before)
			change.health_after = event.target_health_remaining
			change.defeated = event.target_defeated
		elif event is UnitStatusChangedEvent:
			preview._change(event.unit_id, before).statuses_after = event.statuses.duplicate()
		elif event is UnitHealthChangedEvent:
			# A lost aura can cost health as surely as a hit.
			preview._change(event.unit_id, before).health_after = event.health_after
		elif event is UnitHealedEvent:
			preview._change(event.unit_id, before).health_after = event.health_after
		elif event is UnitMovedEvent and event.unit_id == preview.actor_id and not event.path.is_empty():
			preview.destination = event.path.back()
		elif event is MapMutationEvent and event.obstacle_changed:
			preview.obstacle_damage[event.hex] = event.obstacle_damage
		elif event is ObstacleBrokenEvent:
			preview.broken_flasks.append(event.obstacle)
		elif event is MapMutationEvent and event.kind == MapMutationKind.Value.APPLY_HEX_STATE and event.hex_state_changed:
			var previous: Array = preview.hexes.get(event.hex, before.get_hex_layers(event.hex))
			preview.hexes[event.hex] = [previous[0], previous[1], event.liquid_id, event.energy_id]
	if command is MoveCommand:
		var mover := preview.units.get(preview.actor_id) as UnitChange
		preview.reached = preview.destination == command.destination and (mover == null or not mover.defeated)
	return preview


func _change(unit_id: StringName, before: BattleEngine) -> UnitChange:
	if not units.has(unit_id):
		var change := UnitChange.new()
		change.unit_id = unit_id
		# A unit summoned by the command has no earlier state: it starts at its full health.
		var unit := before.get_unit(unit_id)
		change.health_before = unit.health.current if unit != null else 0
		change.health_after = change.health_before
		if unit != null:
			change.statuses_before.assign(unit.statuses)
		change.statuses_after.assign(change.statuses_before)
		units[unit_id] = change
	return units[unit_id]


## The unit a command acts with, or "" for a command of no single unit.
static func actor_of(command: BattleCommand) -> StringName:
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
	# EndPhaseCommand and the strategist's commands belong to a faction, not to a unit.
	return StringName()
