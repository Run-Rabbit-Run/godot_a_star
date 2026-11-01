class_name AtomicFileWriter
extends RefCounted
## Replaces project files so that a failed save leaves the previous version in place.
## The destination folder belongs to the caller: a missing folder is a failed save.


## Writes text through `path.tmp`; returns "" or why the file was not replaced.
static func write_text(path: String, text: String) -> String:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Не удалось открыть %s для записи: %s." % [temporary, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Ошибка записи %s: %s." % [temporary, error_string(error)]
	return _replace(path, temporary)


## Saves a resource through a temporary file of the same format; returns "" or why it failed.
static func save_resource(resource: Resource, path: String) -> String:
	var temporary := "%s.tmp.%s" % [path.get_basename(), path.get_extension()]
	var error := ResourceSaver.save(resource, temporary)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Не удалось записать %s: %s." % [temporary, error_string(error)]
	return _replace(path, temporary)


# The previous file stays as path.bak until the new one is in place and comes back on failure.
static func _replace(path: String, temporary: String) -> String:
	var backup := path + ".bak"
	var existed := FileAccess.file_exists(path)
	if existed:
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return "Не удалось сохранить предыдущую версию %s: %s." % [path, error_string(backup_error)]
	var error := DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if existed:
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temporary)
		return "Не удалось заменить %s: %s." % [path, error_string(error)]
	if existed:
		DirAccess.remove_absolute(backup)
	return ""
