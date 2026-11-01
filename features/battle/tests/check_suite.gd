extends Node
## Runs the check groups of one suite. `--only=<group>` selects a single group; the summary
## line is what tools/tests/run_tests.py reads. A suite overrides `_run()` and ends with `_report()`.

var fixture = preload("res://features/battle/tests/regression_fixtures.gd").new()
var checks := 0
var failures: Array[String] = []
var only := ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	call_deferred("_run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


## Whether the group runs: every group without `--only`, otherwise just the named one.
func runs(group: String) -> bool:
	return only.is_empty() or only == group


func _run() -> void:
	await _report("Empty suite")


func _report(title: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	expect(checks > 0, "Requested test group exists and completed checks")
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("%s: %d checks, %d failures" % [title, checks, failures.size()])
	get_tree().create_timer(0.1).timeout.connect(get_tree().quit.bind(0 if failures.is_empty() else 1))
	queue_free()
