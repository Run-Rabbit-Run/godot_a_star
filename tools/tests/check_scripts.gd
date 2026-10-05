extends SceneTree

var files: Array[String] = []

func _initialize() -> void:
	# Prime the resource graph through the normal composition roots.
	load("res://content/packages/core/core_package.tres")
	load("res://features/battle/battle_screen.tscn")
	load("res://tools/battles/battle_editor.tscn")
	load("res://tools/battle_ui/battle_ui_editor.tscn")
	_collect("res://features")
	_collect("res://tools")
	files.sort()
	var errors := 0
	for path: String in files:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			errors += 1
			printerr("FAIL: Script could not compile: ", path)
	print("Script compilation: %d scripts, %d failures" % [files.size(), errors])
	call_deferred("quit", 0 if errors == 0 else 1)

func _collect(path: String) -> void:
	for filename: String in DirAccess.get_files_at(path):
		if filename.ends_with(".gd"):
			files.append(path.path_join(filename))
	for directory: String in DirAccess.get_directories_at(path):
		_collect(path.path_join(directory))
