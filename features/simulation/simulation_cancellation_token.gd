class_name SimulationCancellationToken
extends RefCounted


var _is_cancelled := false


func cancel() -> void:
	_is_cancelled = true


func is_cancelled() -> bool:
	return _is_cancelled