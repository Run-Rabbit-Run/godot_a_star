class_name UnitLibrary
extends RefCounted

const ROOT := "user://unit_library"
const UNITS := ROOT + "/units"
const ASSETS := ROOT + "/assets"
const ACTIVE_ABILITIES := {"core:grenade": "Бросок гранаты"}

static func ensure_folders() -> String:
	for path: String in [UNITS, ASSETS]:
		var error := DirAccess.make_dir_recursive_absolute(path)
		if error != OK:
			return "Не удалось создать %s: %s" % [path, error_string(error)]
	# Seed the writable asset folder once, including in exported builds.
	for index: int in range(8):
		var target := ASSETS.path_join("%s.png" % index)
		if FileAccess.file_exists(target):
			continue
		var texture := load("res://features/battle/art/plateau_units/%s.png" % index) as Texture2D
		if texture == null:
			return "Не найдено стартовое изображение %s." % index
		var error := texture.get_image().save_png(target)
		if error != OK:
			return "Не удалось сохранить %s: %s" % [target, error_string(error)]
	return ""

static func asset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file: String in DirAccess.get_files_at(ASSETS):
		if file.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]:
			names.append(file)
	names.sort()
	return names

static func texture_for(asset: String) -> Texture2D:
	if asset != asset.get_file() or asset.is_empty():
		return null
	var image := Image.load_from_file(ASSETS.path_join(asset))
	return null if image == null or image.is_empty() else ImageTexture.create_from_image(image)

static func new_document() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "custom_units:u_" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"name": "Новый юнит", "image": "0.png", "hp": 10, "damage": 2,
		"attack_type": "melee", "attack_range": 3, "movement": 4,
		"abilities": [], "passives": [],
	}

static func validate(data: Dictionary) -> String:
	for key: String in ["id", "name", "image", "attack_type"]:
		if not data.get(key) is String or String(data[key]).strip_edges().is_empty():
			return "Поле %s должно содержать текст." % key
	var id := String(data.id)
	if not id.begins_with("custom_units:") or not id.trim_prefix("custom_units:").is_valid_identifier():
		return "Некорректный ID юнита: %s" % id
	if String(data.name).length() > 120:
		return "Имя не должно превышать 120 символов."
	for key: String in ["schema_version", "hp", "damage", "attack_range", "movement"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float):
			return "Поле %s должно быть целым числом." % key
		if not is_finite(float(value)) or float(value) != floor(float(value)):
			return "Поле %s должно быть целым числом." % key
	if data.schema_version != 1:
		return "Неизвестная версия формата юнита."
	if data.hp < 1 or data.hp > 9999 or data.damage < 0 or data.damage > 9999:
		return "ОЗ: 1–9999; урон: 0–9999."
	if data.movement < 0 or data.movement > 100 or data.attack_range < 1 or data.attack_range > 20:
		return "Передвижение: 0–100; дальность: 1–20."
	if data.attack_type not in ["melee", "ranged"]:
		return "Неизвестный тип атаки."
	if data.attack_range < 2:
		return "Дальность дальней атаки: 2–20 гексов; ближняя атака всегда на 1 гекс."
	if String(data.image) != String(data.image).get_file() or not data.image in asset_names():
		return "Выберите изображение из папки assets."
	for key: String in ["abilities", "passives"]:
		if not data.get(key) is Array:
			return "Поле %s должно быть списком." % key
		var seen: Array[String] = []
		for value: Variant in data[key]:
			if not value is String:
				return "ID умения должен быть строкой."
			if value in seen:
				return "Умение выбрано дважды: %s" % value
			seen.append(value)
			if key == "abilities" and not ACTIVE_ABILITIES.has(value):
				return "Неизвестное активное умение: %s" % value
			if key == "passives" and not PassiveAbilityCatalog.DEFINITIONS.has(StringName(value)):
				return "Неизвестное пассивное умение: %s" % value
	return ""

static func read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Не удалось прочитать %s" % path}
	if file.get_length() > 65536:
		return {"error": "Файл юнита больше 64 КБ: %s" % path}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": "%s: строка %s: %s" % [path, json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"error": "%s: ожидается объект JSON." % path}
	var data: Dictionary = json.data
	var error := validate(data)
	if not error.is_empty():
		return {"error": "%s: %s" % [path, error]}
	if path.get_file() != String(data.id).trim_prefix("custom_units:") + ".json":
		return {"error": "%s: имя файла должно совпадать с ID без custom_units:." % path}
	return {"error": "", "document": data}

static func save_document(data: Dictionary) -> String:
	var error := validate(data)
	if not error.is_empty():
		return error
	if texture_for(data.image) == null:
		return "Изображение не удалось прочитать."
	var path := UNITS.path_join(String(data.id).trim_prefix("custom_units:") + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Не удалось записать %s" % temporary
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Ошибка записи: %s" % error_string(write_error)
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		var move_error := DirAccess.rename_absolute(path, backup)
		if move_error != OK:
			return "Не удалось сохранить предыдущую версию: %s" % error_string(move_error)
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return "Не удалось завершить сохранение: %s" % error_string(rename_error)
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return ""

static func load_content(packages: Array[ContentPackage]) -> ContentLoadResult:
	var result := ContentLoadResult.new()
	var folder_error := ensure_folders()
	if not folder_error.is_empty():
		result.add_error(folder_error)
		return result
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"custom_units"
	var dependency := ContentPackageDependency.new()
	dependency.package_id = &"core"
	package.manifest.dependencies.append(dependency)
	for filename: String in DirAccess.get_files_at(UNITS):
		if filename.get_extension().to_lower() != "json":
			continue
		var loaded := read_document(UNITS.path_join(filename))
		if not String(loaded.error).is_empty():
			result.add_error(loaded.error)
			continue
		var data: Dictionary = loaded.document
		var unit := UnitDefinition.new()
		unit.id = StringName(data.id)
		unit.display_name = data.name
		unit.presentation_id = StringName(String(data.id) + "_visual")
		unit.base_stats = UnitStatsDefinition.new()
		unit.base_stats.max_health = int(data.hp)
		unit.base_stats.basic_attack_damage = int(data.damage)
		unit.base_stats.basic_attack_range = int(data.attack_range) if data.attack_type == "ranged" else 1
		unit.base_stats.movement_points = int(data.movement)
		unit.ability_ids.assign(data.abilities)
		unit.passive_ability_ids.assign(data.passives)
		var presentation := UnitPresentationDefinition.new()
		presentation.id = unit.presentation_id
		presentation.actor_scene = load("res://features/battle/units/unit_actor.tscn") as PackedScene
		presentation.actor_texture = texture_for(data.image)
		if presentation.actor_texture == null:
			result.add_error("%s: изображение повреждено: %s" % [filename, data.image])
		presentation.portrait_texture = presentation.actor_texture
		package.units.append(unit)
		package.unit_presentations.append(presentation)
	if not result.errors.is_empty():
		return result
	var combined: Array[ContentPackage] = packages.duplicate()
	combined.append(package)
	return ContentLoader.load_packages(combined)
