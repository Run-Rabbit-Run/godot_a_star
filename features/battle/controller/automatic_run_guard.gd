class_name AutomaticRunGuard
extends RefCounted
## Bounds one uninterrupted stretch of automatic commands in a graphical battle.
## A unit's turn is finite by the rules, so exceeding that bound is a defect; a stretch
## without damage, defeats, summons or map changes for many rounds is a stalemate.

## Accepted moves spend movement and every main action ends the turn, so a turn needs at
## most movement + 1 commands; the margin leaves room for future rules.
const TURN_COMMAND_MARGIN := 8
const ROUNDS_WITHOUT_PROGRESS := 30
## Absolute bound for stretches that keep progressing without player input.
const MAX_ROUNDS := 500

var _turn_key: Array = []
var _turn_commands := 0
var _start_round := -1
var _progress_round := -1


## Called before each automatic command; returns the reason to stop, or "".
func check(active: UnitSnapshot, round_number: int) -> String:
	if _start_round < 0:
		_start_round = round_number
		_progress_round = round_number
	var key := [active.unit_id, active.turns_started]
	if key != _turn_key:
		_turn_key = key
		_turn_commands = 0
	_turn_commands += 1
	var turn_limit := active.turn.movement_max + 1 + TURN_COMMAND_MARGIN
	if _turn_commands > turn_limit:
		return "AI unit %s issued more than %d commands in one turn." % [active.unit_id, turn_limit]
	if round_number - _progress_round >= ROUNDS_WITHOUT_PROGRESS:
		return "Automatic play made no progress for %d rounds: no damage, defeats, summons or map changes." % ROUNDS_WITHOUT_PROGRESS
	if round_number - _start_round >= MAX_ROUNDS:
		return "Automatic play ran %d rounds without player input." % MAX_ROUNDS
	return ""


## Damage, summons and changes of the map itself are progress. Movement and applied or
## decaying states are not: they can repeat forever without bringing the battle closer to an end.
func record(resolution: BattleResolution, round_number: int) -> void:
	for event: BattleEvent in resolution.events:
		var progress: bool = (
			(event is UnitDamagedEvent and event.damage > 0)
			or event is UnitSummonedEvent
			or (event is MapMutationEvent and (event.obstacle_changed or event.kind != MapMutationKind.Value.APPLY_HEX_STATE))
		)
		if progress:
			_progress_round = round_number
			return
