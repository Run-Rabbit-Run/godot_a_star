class_name BattleGridLayoutSettings
extends RefCounted

const DEFAULT_PATH := "res://content/authored/battle_grid_layout.cfg"


static func load_default(path: String = DEFAULT_PATH) -> int:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return 0
	if error != OK:
		push_warning("Could not read grid layout: %s" % error_string(error))
		return 0
	var value: Variant = config.get_value("grid", "offset_y", 0)
	if not value is int or value < BattleMapDefinition.MIN_GRID_OFFSET_Y or value > BattleMapDefinition.MAX_GRID_OFFSET_Y:
		push_warning("Invalid default grid height in %s" % path)
		return 0
	return value


static func resolve_offset(map: BattleMapDefinition, default_offset: int) -> int:
	return map.grid_offset_y if map.has_custom_grid_offset else default_offset


static func save_default(value: int, path: String = DEFAULT_PATH) -> Error:
	if value < BattleMapDefinition.MIN_GRID_OFFSET_Y or value > BattleMapDefinition.MAX_GRID_OFFSET_Y:
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("grid", "offset_y", value)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return error
	var existed := FileAccess.file_exists(path)
	var backup := path + ".bak"
	if existed:
		error = DirAccess.rename_absolute(path, backup)
		if error != OK:
			DirAccess.remove_absolute(temporary)
			return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if existed:
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temporary)
		return error
	if existed:
		DirAccess.remove_absolute(backup)
	return OK
