extends SceneTree

func _initialize() -> void:
	# Load resource class dependencies in the same order as the normal game.
	load("res://content/packages/core/core_package.tres")
	var script: Script = load("res://features/battle/tests/regression_suite.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var suite: Node = script.new()
	root.add_child.call_deferred(suite)
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("FAIL: Regression suite timed out before completion")
		quit(1)
	)
