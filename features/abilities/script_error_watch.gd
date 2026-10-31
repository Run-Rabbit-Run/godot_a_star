class_name ScriptErrorWatch
extends Logger
## Counts runtime script errors raised on one thread while an effect run is watched.
## GDScript cannot catch them: a crashed handler simply returns an empty result.

var _thread := OS.get_thread_caller_id()
var _errors := 0


static func start() -> ScriptErrorWatch:
	var watch := ScriptErrorWatch.new()
	OS.add_logger(watch)
	return watch


func error_count() -> int:
	return _errors


## Stops watching and returns the number of script errors seen on the watched thread.
func stop() -> int:
	OS.remove_logger(self)
	return _errors


## Only the watched thread writes the counter, so errors of other threads cannot race it.
func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_SCRIPT and OS.get_thread_caller_id() == _thread:
		_errors += 1
