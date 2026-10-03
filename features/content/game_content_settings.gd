class_name GameContentSettings
extends Resource
## Project-owned startup configuration shared by the game and development tools.

const PATH := "res://content/game_content.tres"
const BATTLES := "res://content/authored/battles"
const UI := "res://content/authored/ui"
const EXPORTS := "res://content/authored/exports"

@export var content_packages: Array[ContentPackage] = []
@export_file("*.json") var battle_document_path := ""
@export_file("*.json") var ui_profile_path := ""


static func read() -> GameContentSettings:
	return ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GameContentSettings


static func project_path(path: String) -> String:
	var local := ProjectSettings.localize_path(path).simplify_path()
	return local if local.begins_with("res://content/") else ""


static func select_battle(path: String) -> Error:
	return _select(path, false)


static func select_ui(path: String) -> Error:
	return _select(path, true)


static func _select(path: String, ui: bool) -> Error:
	var local := project_path(path) if not path.is_empty() else ""
	if (not path.is_empty() and local.is_empty()) or (not ui and local.is_empty()):
		return ERR_INVALID_PARAMETER
	if not local.is_empty() and not FileAccess.file_exists(local):
		return ERR_FILE_NOT_FOUND
	var settings := read()
	if settings == null:
		return ERR_CANT_OPEN
	if ui:
		settings.ui_profile_path = local
	else:
		settings.battle_document_path = local
	return ResourceSaver.save(settings, PATH)
