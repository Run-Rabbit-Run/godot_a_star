extends RefCounted
## AtomicFileWriter: a save either replaces the file whole or leaves the previous version.


func run(suite: Node) -> void:
	var directory := "user://atomic_files_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	_check_text(suite, directory)
	_check_resource(suite, directory)
	_remove_tree(directory)


func _check_text(suite: Node, directory: String) -> void:
	var path := directory.path_join("document.json")
	suite.expect(AtomicFileWriter.write_text(path, "first").is_empty() and _read(path) == "first", "A new file is written whole")
	suite.expect(_leftovers(path).is_empty(), "A new file leaves no temporary or backup copy")
	_write_raw(path + ".bak", "stale")
	suite.expect(AtomicFileWriter.write_text(path, "second").is_empty() and _read(path) == "second", "An existing file is replaced despite a stale backup")
	suite.expect(_leftovers(path).is_empty(), "A successful replacement removes the backup")
	# A folder in place of the backup makes preserving the previous version fail.
	DirAccess.make_dir_recursive_absolute(path + ".bak")
	_write_raw(path + ".bak/keep.txt", "keep")
	var error := AtomicFileWriter.write_text(path, "third")
	suite.expect(not error.is_empty() and _read(path) == "second", "A failed backup leaves the previous file untouched")
	suite.expect(not FileAccess.file_exists(path + ".tmp"), "A failed save removes its temporary file")
	_remove_tree(path + ".bak")
	# A folder in place of the destination makes the replacement itself fail.
	var blocked := directory.path_join("blocked")
	DirAccess.make_dir_recursive_absolute(blocked)
	suite.expect(not AtomicFileWriter.write_text(blocked, "data").is_empty() and DirAccess.dir_exists_absolute(blocked) and not FileAccess.file_exists(blocked + ".tmp"), "A failed replacement reports the error and cleans up")
	var missing := directory.path_join("missing/document.json")
	suite.expect(not AtomicFileWriter.write_text(missing, "data").is_empty() and not DirAccess.dir_exists_absolute(missing.get_base_dir()), "A missing folder is an error and is not created")


func _check_resource(suite: Node, directory: String) -> void:
	var path := directory.path_join("settings.tres")
	var settings := GameContentSettings.new()
	settings.battle_document_path = "res://first.json"
	suite.expect(AtomicFileWriter.save_resource(settings, path).is_empty(), "A resource is saved through a temporary file")
	settings.battle_document_path = "res://second.json"
	suite.expect(AtomicFileWriter.save_resource(settings, path).is_empty(), "An existing resource is replaced")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameContentSettings
	suite.expect(loaded != null and loaded.battle_document_path == "res://second.json", "The replaced resource loads with the new values")
	suite.expect(_leftovers(path).is_empty() and not FileAccess.file_exists(directory.path_join("settings.tmp.tres")), "Resource replacement leaves no temporary or backup copy")


func _leftovers(path: String) -> Array[String]:
	var found: Array[String] = []
	for suffix: String in [".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix) or DirAccess.dir_exists_absolute(path + suffix):
			found.append(path + suffix)
	return found


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
