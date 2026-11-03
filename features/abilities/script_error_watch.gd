class_name ScriptErrorWatch
extends RefCounted
## Counts runtime script errors raised on one thread while an effect run is watched.
## GDScript cannot catch them: a crashed handler simply returns an empty result.
## Godot's logger list has no lock, so one counting logger is installed once on the main
## thread and stays; a watch only reads how the total of its own thread grew.

static var _counter: Counter

var _thread := OS.get_thread_caller_id()
var _baseline := 0


## Script errors of every thread since installation, kept per thread.
class Counter extends Logger:
	var _mutex := Mutex.new()
	var _errors: Dictionary[int, int] = {}

	func count(thread: int) -> int:
		_mutex.lock()
		var value: int = _errors.get(thread, 0)
		_mutex.unlock()
		return value

	## Runs on the thread that raised the error.
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		var thread := OS.get_thread_caller_id()
		_mutex.lock()
		_errors[thread] = int(_errors.get(thread, 0)) + 1
		_mutex.unlock()


## Installs the counter. Call it on the main thread before effects run on other threads.
static func install() -> void:
	if _counter != null:
		return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		push_error("ScriptErrorWatch must be installed on the main thread before effects run on other threads.")
		return
	_counter = Counter.new()
	OS.add_logger(_counter)


static func start() -> ScriptErrorWatch:
	install()
	var watch := ScriptErrorWatch.new()
	watch._baseline = _total(watch._thread)
	return watch


func error_count() -> int:
	return _total(_thread) - _baseline


## Ends the watch and returns the number of script errors seen on the watched thread.
func stop() -> int:
	return error_count()


static func _total(thread: int) -> int:
	return _counter.count(thread) if _counter != null else 0
