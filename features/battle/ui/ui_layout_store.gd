class_name UILayoutStore
extends RefCounted
## Data-only JSON storage and local presentation preference.

const DIRECTORY := "user://battle_ui"
const PREFERENCE := "user://battle_ui/selected.cfg"
const NUMBER_FIELDS := ["font_size", "border_width"]
const COLOR_FIELDS := ["font_color", "background", "border_color", "tint"]
const TEXT_FIELDS := ["text", "asset"]


static func load_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Не удалось прочитать UI: %s" % path}
	if file.get_length() > 2 * 1024 * 1024:
		return {"error": "Файл UI превышает 2 МБ."}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": "JSON, строка %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var error := validate(json.data)
	if not error.is_empty():
		return {"error": error}
	var document := UILayoutDocument.new()
	document.title = json.data.title
	document.elements = json.data.elements.duplicate(true)
	return {"document": document, "error": ""}


static func validate(data: Variant) -> String:
	if not data is Dictionary or data.get("schema") != 1:
		return "Неверная схема UI (ожидается 1)."
	if not data.get("title") is String or not data.get("elements") is Dictionary:
		return "UI должен содержать title и elements."
	if data.elements.size() > 256:
		return "Слишком много элементов UI."
	for id: String in data.elements:
		var entry: Variant = data.elements[id]
		if id.is_empty() or id.begins_with("/") or ".." in id or not entry is Dictionary:
			return "Некорректный элемент: %s" % id
		for key: String in entry:
			var value: Variant = entry[key]
			if key == "rect":
				if not value is Array or value.size() != 4:
					return "rect должен содержать x, y, ширину, высоту: %s" % id
				for number: Variant in value:
					if not _number(number) or absf(float(number)) > 20000:
						return "Неверные координаты: %s" % id
				if value[2] < 1 or value[3] < 1:
					return "Размер должен быть положительным: %s" % id
			elif key in NUMBER_FIELDS:
				if not _number(value) or value < 0 or value > 256:
					return "Неверное числовое свойство: %s/%s" % [id, key]
				if key == "font_size" and value < 1:
					return "Размер шрифта должен быть положительным: %s" % id
			elif key in COLOR_FIELDS:
				if not value is String or not Color.html_is_valid(value):
					return "Неверный цвет: %s/%s" % [id, key]
			elif key in TEXT_FIELDS:
				if not value is String or value.length() > 4096:
					return "Неверный текст: %s/%s" % [id, key]
				if key == "asset" and not value.is_empty() and not (value.begins_with("res://") or value.begins_with(DIRECTORY + "/assets/")):
					return "Ассет должен быть импортирован через редактор: %s" % id
				if key == "asset" and not value.is_empty() and value.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp", "svg"]:
					return "Поддерживаются PNG, JPEG, WebP и SVG: %s" % id
			elif key == "visibility":
				if not value is String or value not in ["inherit", "show", "hide"]:
					return "Неверная видимость: %s" % id
			else:
				return "Неизвестное свойство: %s/%s" % [id, key]
	return ""


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func save_document(path: String, document: UILayoutDocument) -> String:
	var error := validate(document.to_data())
	if not error.is_empty():
		return error
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Не удалось создать папку: %s" % directory
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Не удалось записать UI: %s" % path
	file.store_string(JSON.stringify(document.to_data(), "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Ошибка записи UI: %s" % error_string(write_error)
	# Keep the previous file recoverable until the new file has been renamed.
	var backup := path + ".bak"
	var existed := FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(path, backup) != OK:
		return "Не удалось сохранить предыдущую версию UI."
	if DirAccess.rename_absolute(temporary, path) != OK:
		if existed:
			DirAccess.rename_absolute(backup, path)
		return "Не удалось заменить файл UI."
	if existed:
		DirAccess.remove_absolute(backup)
	return ""


static func selected_path() -> String:
	var config := ConfigFile.new()
	if config.load(PREFERENCE) != OK:
		return ""
	return str(config.get_value("ui", "path", ""))


static func select_profile(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var config := ConfigFile.new()
	config.set_value("ui", "path", path)
	return config.save(PREFERENCE)


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return null if image == null or image.is_empty() else ImageTexture.create_from_image(image)


static func import_asset(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return {"error": "Не удалось открыть изображение."}
	var directory := DIRECTORY + "/assets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var destination := directory + "/" + FileAccess.get_sha256(path) + ".png"
	if image.save_png(ProjectSettings.globalize_path(destination)) != OK:
		return {"error": "Не удалось скопировать изображение."}
	return {"error": "", "path": destination}
