class_name SkillLibrary
extends RefCounted
## Project-authored definitions. Built-in resources are copied before applying overrides.

const ROOT := "res://content/authored/skills"
const KINDS := ["active", "passive", "effect"]
## Form limits of active skills: key -> [minimum, maximum, caption].
const ACTIVE_LIMITS := {"range": [1, 99, "Дальность"], "area_radius": [0, 8, "Радиус области"], "target_mode": [0, 6, "Цель"], "cooldown_turns": [1, 99, "Перезарядка"], "initial_cooldown_turns": [0, 99, "Начальная перезарядка"]}
const DAMAGE_TYPES := {"physical": "Физический", "electric": "Электрический", "fire": "Огненный", "water": "Водный", "acid": "Кислотный", "plasma": "Плазменный"}

## Built-in documents and summonable units, read once: packages() reloads every package (~0.6 s).
static var _builtin_cache: Dictionary = {}
static var _units_cache: Dictionary = {}

static func packages() -> Array[ContentPackage]:
	var settings := GameContentSettings.read()
	return settings.content_packages if settings != null else []

## Drops cached built-in data; tools call it when the user asks to re-read content.
static func reload() -> void:
	_builtin_cache.clear()
	_units_cache.clear()

static func _builtin() -> Dictionary:
	if _builtin_cache.is_empty():
		var source := packages()
		for package: ContentPackage in source:
			for unit: UnitDefinition in package.units:
				_units_cache[unit.id] = unit
		_builtin_cache = _build_builtin_documents(source)
	return _builtin_cache

## Package units by ID. Callers must duplicate before changing them.
static func units() -> Dictionary:
	_builtin()
	return _units_cache

static func new_document(kind: String) -> Dictionary:
	var data := {"schema_version": 1, "kind": kind, "id": "custom_skills:s_" + Crypto.new().generate_random_bytes(16).hex_encode(), "name": "Новый навык"}
	match kind:
		"active":
			data.merge({"range": 3, "area_radius": 0, "target_mode": 1, "cooldown_turns": 1, "initial_cooldown_turns": 0, "uses_attack_range": false, "returns_next_turn": false, "melee_attack": false, "presentation_id": "", "effects": [new_effect()]})
		"passive":
			data.merge({"attack_bonus": 0, "damage_type": "", "status": "", "levels": 2, "immunity": "", "retaliation": false})
		"effect":
			data.name = "Новый эффект"
			data["effect"] = new_effect()
	return data

static func new_effect(type := "core:damage") -> Dictionary:
	match type:
		"core:unit_status": return {"type": type, "parameters": {"status_id": "core:burning", "levels": 2}}
		"core:hex_state": return {"type": type, "parameters": {"state_id": "core:fire"}}
		"core:summon": return {"type": type, "parameters": {"unit_id": "core:electric_turret_unit", "center_only": true}}
	return {"type": "core:damage", "parameters": {"amount": 2, "secondary_amount": 2, "damage_type": "physical", "use_base_attack": false, "affects_obstacles": true}}

static func _effect_document(effect: AbilityEffectDefinition) -> Dictionary:
	var params := effect.parameters.duplicate(true)
	if params.get("unit") is UnitDefinition:
		params["unit_id"] = String(params.unit.id)
		params.erase("unit")
	return {"type": String(effect.effect_type_id), "parameters": params}

static func active_document(ability: AbilityDefinition) -> Dictionary:
	var data := {"schema_version": 1, "kind": "active", "id": String(ability.id), "name": ability.display_name}
	for key: String in ["range", "area_radius", "target_mode", "cooldown_turns", "initial_cooldown_turns", "uses_attack_range", "returns_next_turn", "melee_attack"]:
		data[key] = ability.get(key)
	data.presentation_id = String(ability.presentation_id)
	data.effects = []
	for effect: AbilityEffectDefinition in ability.effects:
		data.effects.append(_effect_document(effect))
	return data

static func builtin_documents() -> Dictionary:
	return _builtin().duplicate(true)

static func _build_builtin_documents(source: Array[ContentPackage]) -> Dictionary:
	var documents := {}
	for package: ContentPackage in source:
		for ability: AbilityDefinition in package.abilities:
			documents[String(ability.id)] = active_document(ability)
	for id: StringName in PassiveAbilityCatalog.DEFINITIONS:
		var data := new_document("passive")
		data.id = String(id)
		data.name = PassiveAbilityCatalog.DEFINITIONS[id].name
		data.merge(PassiveAbilityCatalog.DEFINITIONS[id], true)
		for key: String in ["damage_type", "status", "immunity"]:
			data[key] = String(data[key])
		data.retaliation = id == &"core:melee_retaliation"
		documents[String(id)] = data
	for type: String in ["core:damage", "core:unit_status", "core:hex_state", "core:summon"]:
		var data := new_document("effect")
		data.id = "core:effect_" + type.get_slice(":", 1)
		data.name = {"core:damage": "Урон", "core:unit_status": "Состояние юнита", "core:hex_state": "Состояние гекса", "core:summon": "Призыв"}[type]
		data.effect = new_effect(type)
		documents[data.id] = data
	return documents

static func read_all(root := ROOT) -> Dictionary:
	var documents := {}
	var errors: Array[String] = []
	if not DirAccess.dir_exists_absolute(root):
		return {"documents": documents, "errors": errors}
	for filename: String in DirAccess.get_files_at(root):
		if filename.get_extension() != "json": continue
		var path := root.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 262144:
			errors.append("Не удалось прочитать или файл больше 256 КБ: " + path)
			continue
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
			errors.append("Некорректный JSON: " + path)
			continue
		var data: Dictionary = parser.data
		var error := validate(data)
		if error.is_empty() and filename != filename_for(data): error = "Имя файла не совпадает с ID."
		if not error.is_empty():
			errors.append(path + ": " + error)
		else:
			documents[data.id] = data
	return {"documents": documents, "errors": errors}

static func catalog() -> Dictionary:
	var documents := builtin_documents()
	documents.merge(read_all().documents, true)
	return documents

static func names(kind: String) -> Dictionary:
	var result := {}
	for data: Dictionary in catalog().values():
		if data.kind == kind: result[data.id] = data.name
	return result

static func passive_definitions(documents: Dictionary) -> Dictionary:
	var result := {}
	for data: Dictionary in documents.values():
		if data.kind != "passive": continue
		var passive := {"name": data.name, "attack_bonus": int(data.attack_bonus), "levels": int(data.levels), "retaliation": data.retaliation}
		for key: String in ["damage_type", "status", "immunity"]:
			if not String(data[key]).is_empty(): passive[key] = StringName(data[key])
		result[StringName(data.id)] = passive
	return result

static func _integer(data: Dictionary, key: String, minimum: int, maximum: int) -> bool:
	var value: Variant = data.get(key)
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func validate(data: Dictionary) -> String:
	if data.get("schema_version") != 1 or data.get("kind") not in KINDS: return "Неизвестная схема или категория."
	for key: String in ["id", "name"]:
		if not data.get(key) is String or String(data[key]).strip_edges().is_empty(): return "Заполните %s." % ("ID" if key == "id" else "название")
	if String(data.name).length() > 120: return "Имя: до 120 символов."
	var parts := String(data.id).split(":")
	if parts.size() != 2 or not parts[0].is_valid_identifier() or not parts[1].is_valid_identifier(): return "Некорректный ID."
	if parts[0] != "custom_skills":
		var builtin := _builtin().get(data.id, {}) as Dictionary
		if builtin.is_empty() or builtin.kind != data.kind: return "ID не является встроенным навыком этой категории."
	if data.kind == "effect":
		if not data.get("effect") is Dictionary: return "Эффект должен быть объектом."
		return validate_effect(data.effect)
	if data.kind == "passive":
		if not _integer(data, "attack_bonus", 0, 9999) or not _integer(data, "levels", 1, 99): return "Бонус урона: 0–9999; уровни: 1–99."
		if not data.get("retaliation") is bool: return "Ответный удар должен быть переключателем."
		for key: String in ["damage_type", "status", "immunity"]:
			if not data.get(key) is String: return "Некорректное поле " + key
		if data.damage_type != "" and not DAMAGE_TYPES.has(data.damage_type): return "Неизвестный тип урона."
		for key: String in ["status", "immunity"]:
			if data[key] != "" and not UnitStatusCatalog.has_status(StringName(data[key])): return "Неизвестное состояние."
		return ""
	for key: String in ACTIVE_LIMITS:
		var limit: Array = ACTIVE_LIMITS[key]
		if not _integer(data, key, limit[0], limit[1]): return "%s: целое число %d–%d." % [limit[2], limit[0], limit[1]]
	for key: String in ["uses_attack_range", "returns_next_turn", "melee_attack"]:
		if not data.get(key) is bool: return "Некорректный переключатель: " + key
	if not data.get("presentation_id") is String: return "Некорректный ID представления."
	if not data.get("effects") is Array or data.effects.is_empty() or data.effects.size() > 32: return "Навык должен содержать от 1 до 32 эффектов."
	for value: Variant in data.effects:
		if not value is Dictionary: return "Некорректный эффект."
		var error := validate_effect(value)
		if not error.is_empty(): return error
	var types: Array = data.effects.map(func(effect: Dictionary) -> Variant: return effect.type)
	if data.returns_next_turn and (int(data.target_mode) != AbilityDefinition.TargetMode.PATH or int(data.area_radius) != 0 or types.any(func(type: Variant) -> bool: return type != "core:damage")):
		return "Возврат оружия: цель «Путь», радиус 0 и только эффекты урона."
	if types.has("core:summon") and (int(data.target_mode) != AbilityDefinition.TargetMode.EMPTY_HEX or int(data.area_radius) != 0 or types.size() != 1):
		return "Призыв: цель «Пустой гекс», радиус 0 и единственный эффект."
	# Core rules stay the final authority for anything the form does not phrase itself.
	return to_ability(data).validate()

static func to_effect(data: Dictionary) -> AbilityEffectDefinition:
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = StringName(data.type)
	effect.parameters = data.parameters.duplicate(true)
	for key: String in ["amount", "secondary_amount", "levels"]:
		if effect.parameters.has(key): effect.parameters[key] = int(effect.parameters[key])
	if effect.effect_type_id == &"core:summon":
		var id := StringName(effect.parameters.get("unit_id", ""))
		effect.parameters.erase("unit_id")
		var unit: UnitDefinition = units().get(id)
		if unit != null: effect.parameters["unit"] = unit.duplicate(true)
	return effect

static func validate_effect(data: Dictionary) -> String:
	if not data.get("type") is String or not data.get("parameters") is Dictionary: return "Некорректный формат эффекта."
	var params: Dictionary = data.parameters
	for key: String in ["amount", "secondary_amount", "levels"]:
		if params.has(key) and not _integer(params, key, 1, 9999): return "Эффект: %s — целое число 1–9999." % {"amount": "урон основной цели", "secondary_amount": "урон остальных целей", "levels": "уровни состояния"}[key]
	match data.type:
		"core:damage":
			if not DAMAGE_TYPES.has(params.get("damage_type", "physical")): return "Эффект урона: неизвестный тип урона."
		"core:unit_status":
			if not UnitStatusCatalog.has_status(StringName(str(params.get("status_id", "")))): return "Эффект состояния: выберите известное состояние юнита."
		"core:hex_state":
			if not HexStateCatalog.has_state(StringName(str(params.get("state_id", "")))): return "Эффект гекса: выберите известное состояние гекса."
		"core:summon":
			if to_effect(data).parameters.get("unit") == null: return "Призыв: выберите существующего призываемого юнита."
	var handler: AbilityEffectHandler
	match data.type:
		"core:damage": handler = DamageEffectHandler.new()
		"core:unit_status": handler = UnitStatusEffectHandler.new()
		"core:hex_state": handler = HexStateEffectHandler.new()
		"core:summon": handler = SummonEffectHandler.new()
		_: return "Неизвестный обработчик эффекта."
	return handler.validate(to_effect(data))

static func to_ability(data: Dictionary) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.id = StringName(data.id)
	ability.display_name = data.name
	ability.presentation_id = StringName(data.presentation_id)
	for key: String in ["range", "area_radius", "target_mode", "cooldown_turns", "initial_cooldown_turns", "uses_attack_range", "returns_next_turn", "melee_attack"]:
		ability.set(key, data[key])
	for effect: Dictionary in data.effects: ability.effects.append(to_effect(effect))
	return ability

static func filename_for(data: Dictionary) -> String:
	return String(data.id).replace(":", "__") + ".json"

static func save_document(data: Dictionary, root := ROOT) -> String:
	var error := validate(data)
	if not error.is_empty(): return error
	var mkdir := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if mkdir != OK: return "Не удалось создать папку: " + error_string(mkdir)
	var path := root.path_join(filename_for(data))
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "Не удалось записать файл."
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return "Ошибка записи: " + error_string(write_error)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(path, path + ".bak")
		if backup_error != OK: return "Ошибка резервного сохранения: " + error_string(backup_error)
	var rename_error := DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK:
		if FileAccess.file_exists(path + ".bak"): DirAccess.rename_absolute(path + ".bak", path)
		return "Ошибка завершения сохранения: " + error_string(rename_error)
	if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
	return ""

static func apply_to_packages(source: Array[ContentPackage], documents: Dictionary) -> Array[ContentPackage]:
	var result: Array[ContentPackage] = []
	var passives := passive_definitions(documents)
	for original: ContentPackage in source:
		var package := original.duplicate(true) as ContentPackage
		for index: int in range(package.abilities.size()):
			var id := String(package.abilities[index].id)
			if documents.has(id): package.abilities[index] = to_ability(documents[id])
			_apply_summon_passives(package.abilities[index], passives)
		for unit: UnitDefinition in package.units: unit.passive_definitions = passives.duplicate(true)
		result.append(package)
	var custom := ContentPackage.new()
	custom.manifest = ContentPackageManifest.new()
	custom.manifest.package_id = &"custom_skills"
	for package: ContentPackage in source:
		var dependency := ContentPackageDependency.new()
		dependency.package_id = package.manifest.package_id
		custom.manifest.dependencies.append(dependency)
	for data: Dictionary in documents.values():
		if data.kind == "active" and String(data.id).begins_with("custom_skills:"):
			var ability := to_ability(data)
			_apply_summon_passives(ability, passives)
			custom.abilities.append(ability)
	result.append(custom)
	return result

static func _apply_summon_passives(ability: AbilityDefinition, passives: Dictionary) -> void:
	for effect: AbilityEffectDefinition in ability.effects:
		var unit: Variant = effect.parameters.get("unit")
		if unit is UnitDefinition: unit.passive_definitions = passives.duplicate(true)
