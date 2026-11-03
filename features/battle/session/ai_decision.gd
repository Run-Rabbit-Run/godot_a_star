class_name AIDecision
extends RefCounted
## One decision of an automatic command source. The session prepares it on the main thread
## over a detached copy of the battle; `compute()` touches nothing but that copy, so it may run
## on a worker thread while the live battle waits. The session finishes it on the main thread.

var source: CommandSource
## Set by `compute()`; null when the source produced no command.
var command: BattleCommand
## What the source records for diagnostics; empty without an observer.
var trace: Dictionary
## Live state revision the copy was made at: a battle changed since then makes the decision stale.
var state_revision: int
var _planning: BattleSession


func _init(p_source: CommandSource, planning: BattleSession, p_trace: Dictionary, p_state_revision: int) -> void:
	source = p_source
	_planning = planning
	trace = p_trace
	state_revision = p_state_revision


## Plans on the copy once; the copy is released afterwards.
func compute() -> void:
	if _planning == null:
		return
	command = source.next_command(_planning)
	_planning = null
