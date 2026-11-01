extends SceneTree
## Runs a check suite: the game regressions by default, another with `--suite=res://...`.

const DEFAULT_SUITE := "res://features/battle/tests/regression_suite.gd"


func _initialize() -> void:
	# Load resource class dependencies in the same order as the normal game.
	load("res://content/packages/core/core_package.tres")
	var path := DEFAULT_SUITE
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--suite="):
			path = argument.trim_prefix("--suite=")
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var suite: Node = script.new()
	root.add_child.call_deferred(suite)
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("FAIL: Regression suite timed out before completion")
		quit(1)
	)
