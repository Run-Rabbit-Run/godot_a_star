class_name SkillLibrary
extends RefCounted
## Project-authored skill definitions and overrides of the built-in skills of one package
## set. The caller passes the packages: the library never reads the project settings itself.
## Built-in resources are copied before applying overrides.

const ROOT := "res://content/authored/skills"
const KINDS := ["active", "passive"]
## Form limits of active skills: key -> [minimum, maximum, caption].
const ACTIVE_LIMITS := {"range": [1, 99, "Дальность"], "area_radius": [0, 8, "Радиус области"], "target_mode": [0, 6, "Цель"], "cooldown_turns": [1, 99, "Перезарядка"], "initial_cooldown_turns": [0, 99, "Начальная перезарядка"]}
const DAMAGE_TYPES := {"physical": "Физический", "electric": "Электрический", "fire": "Огненный", "water": "Водный", "acid": "Кислотный", "plasma": "Плазменный"}

## Effect parameters that keep a built-in skill's structure: the editor shows them read-only.
const FIXED_PARAMETERS := {"core:damage": ["affects_obstacles"], "core:hex_state": ["center_only"], "core:summon": ["unit_id", "center_only"]}
const FIXED_ACTIVE_KEYS := ["target_mode", "uses_attack_range", "returns_next_turn", "melee_attack", "presentation_id"]
## Passive properties the skill documents describe; a built-in passive keeps its other ones.
const PASSIVE_DOCUMENT_KEYS := ["name", "description", "attack_bonus", "damage_type", "status", "levels", "immunity", "retaliation"]

var _packages: Array[ContentPackage] = []
var _builtin: Dictionary = {}
var _units: Dictionary = {}


func _init(packages: Array[ContentPackage]) -> void:
	_packages.assign(packages)
	for package: ContentPackage in packages:
		for unit: UnitDefinition in package.units:
			_units[unit.id] = unit
	_builtin = _build_builtin_documents(packages)

## Package units by ID. Callers must duplicate before changing them.
func units() -> Dictionary:
	return _units

## A package unit by ID, or null; the `find_unit` of AbilityDescription contexts.
func find_unit(id: StringName) -> UnitDefinition:
	return _units.get(id)

static func new_document(kind: String) -> Dictionary:
	var data := {"schema_version": 1, "kind": kind, "id": "custom_skills:s_" + Crypto.new().generate_random_bytes(16).hex_encode(), "name": "Новый навык", "description": ""}
	match kind:
		"active":
			data.merge({"range": 3, "area_radius": 0, "target_mode": 1, "cooldown_turns": 1, "initial_cooldown_turns": 0, "uses_attack_range": false, "returns_next_turn": false, "melee_attack": false, "presentation_id": "", "effects": [new_effect()]})
		"passive":
			data.merge({"attack_bonus": 0, "damage_type": "", "status": "", "levels": 2, "immunity": "", "retaliation": false})
	return data

static func new_effect(type := "core:damage") -> Dictionary:
	match type:
		"core:unit_status": return {"type": type, "parameters": {"status_id": "core:burning", "levels": 2}}
		"core:hex_state": return {"type": type, "parameters": {"state_id": "core:fire"}}
		"core:summon": return {"type": type, "parameters": {"unit_id": "core:electric_turret_unit", "center_only": true}}
	return {"type": "core:damage", "parameters": {"amount": 2, "secondary_amount": 2, "damage_type": "physical", "use_base_attack": false, "affects_obstacles": true}}

static func _effect_document(effect: AbilityEffectDefinition) -> Dictionary:
	return {"type": String(effect.effect_type_id), "parameters": effect.parameters.duplicate(true)}

static func active_document(ability: AbilityDefinition) -> Dictionary:
	var data := {"schema_version": 1, "kind": "active", "id": String(ability.id), "name": ability.display_name, "description": ability.description}
	for key: String in ["range", "area_radius", "target_mode", "cooldown_turns", "initial_cooldown_turns", "uses_attack_range", "returns_next_turn", "melee_attack"]:
		data[key] = ability.get(key)
	data.presentation_id = String(ability.presentation_id)
	data.effects = []
	for effect: AbilityEffectDefinition in ability.effects:
		data.effects.append(_effect_document(effect))
	return data

func builtin_documents() -> Dictionary:
	return _builtin.duplicate(true)

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
		data.description = String(data.get("description", ""))
		for key: String in ["damage_type", "status", "immunity"]:
			data[key] = String(data[key])
		data.retaliation = id == &"core:melee_retaliation"
		documents[String(id)] = data
	return documents

func read_all(root := ROOT) -> Dictionary:
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
		var data: Dictionary = normalized(parser.data)
		var error := validate(data)
		if error.is_empty() and filename != filename_for(data): error = "Имя файла не совпадает с ID."
		if not error.is_empty():
			errors.append(path + ": " + error)
		else:
			if not data.has("description"): data["description"] = ""
			documents[data.id] = data
	return {"documents": documents, "errors": errors}

## Built-in documents with the project's overrides and own skills read from `ROOT`.
func catalog() -> Dictionary:
	var documents := builtin_documents()
	documents.merge(read_all().documents, true)
	return documents

## JSON stores every number as float; integral values become int so drafts compare equal to built-in documents.
static func normalized(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = normalized(value[key])
		return result
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return normalized(item))
	return value

## True when the document repeats a built-in skill exactly, so it needs no override file.
func is_builtin_default(data: Dictionary) -> bool:
	var builtin: Dictionary = _builtin.get(data.get("id", ""), {})
	return not builtin.is_empty() and normalized(data) == builtin

static func passive_definitions(documents: Dictionary) -> Dictionary:
	var result := {}
	for data: Dictionary in documents.values():
		if data.kind != "passive": continue
		var passive := {"name": data.name, "description": String(data.get("description", "")), "attack_bonus": int(data.attack_bonus), "levels": int(data.levels), "retaliation": data.retaliation}
		# An override of a built-in passive edits its text and numbers, never its fixed effect.
		var builtin: Dictionary = PassiveAbilityCatalog.DEFINITIONS.get(StringName(data.id), {})
		for key: String in builtin:
			if key not in PASSIVE_DOCUMENT_KEYS:
				passive[key] = builtin[key]
		for key: String in ["damage_type", "status", "immunity"]:
			if not String(data[key]).is_empty(): passive[key] = StringName(data[key])
		result[StringName(data.id)] = passive
	return result

static func _integer(data: Dictionary, key: String, minimum: int, maximum: int) -> bool:
	var value: Variant = data.get(key)
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func validate(data: Dictionary) -> String:
	if data.get("schema_version") != 1 or data.get("kind") not in KINDS: return "Неизвестная схема или категория."
	for key: String in ["id", "name"]:
		if not data.get(key) is String or String(data[key]).strip_edges().is_empty(): return "Заполните %s." % ("ID" if key == "id" else "название")
	if String(data.name).length() > 120: return "Имя: до 120 символов."
	var parts := String(data.id).split(":")
	if parts.size() != 2 or not parts[0].is_valid_identifier() or not parts[1].is_valid_identifier(): return "Некорректный ID."
	var builtin: Dictionary = {}
	if parts[0] != "custom_skills":
		builtin = _builtin.get(data.id, {})
		if builtin.is_empty() or builtin.kind != data.kind: return "ID не является встроенным навыком этой категории."
	if data.kind == "passive":
		if not _integer(data, "attack_bonus", 0, 9999) or not _integer(data, "levels", 1, 99): return "Бонус урона: 0–9999; уровни: 1–99."
		if not data.get("retaliation") is bool: return "Ответный удар должен быть переключателем."
		for key: String in ["damage_type", "status", "immunity"]:
			if not data.get(key) is String: return "Некорректное поле " + key
		if data.damage_type != "" and not DAMAGE_TYPES.has(data.damage_type): return "Неизвестный тип урона."
		for key: String in ["status", "immunity"]:
			if data[key] != "" and not UnitStatusCatalog.has_status(StringName(data[key])): return "Неизвестное состояние."
		if not builtin.is_empty() and data.retaliation != builtin.retaliation: return "Встроенное умение: ответный удар не меняется."
		return _description_error(data, AbilityDescription.passive_variables(passive_definitions({data.id: data}).values()[0]))
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
	if not builtin.is_empty():
		var structure := _structure_error(data, builtin)
		if not structure.is_empty(): return structure
	# Core rules stay the final authority for anything the form does not phrase itself.
	var ability := to_ability(data)
	var core_error := ability.validate()
	if not core_error.is_empty(): return core_error
	return _description_error(data, AbilityDescription.variables(ability, {"find_unit": find_unit}))

## Built-in skills keep their target, flags, presentation and effect list; only parameters change.
static func _structure_error(data: Dictionary, builtin: Dictionary) -> String:
	for key: String in FIXED_ACTIVE_KEYS:
		if normalized(data[key]) != builtin[key]: return "Встроенное умение: цель, флаги и отображение не меняются."
	if data.effects.size() != builtin.effects.size(): return "Встроенное умение: состав эффектов не меняется."
	for index: int in range(data.effects.size()):
		var effect: Dictionary = data.effects[index]
		var original: Dictionary = builtin.effects[index]
		if effect.type != original.type: return "Встроенное умение: тип эффекта %d не меняется." % (index + 1)
		for key: String in FIXED_PARAMETERS.get(effect.type, []):
			if normalized(effect.parameters.get(key)) != original.parameters.get(key): return "Встроенное умение: эффект %d сохраняет %s." % [index + 1, key]
	return ""

static func _description_error(data: Dictionary, variables: Array[Dictionary]) -> String:
	var description: Variant = data.get("description", "")
	if not description is String: return "Описание должно быть текстом."
	if String(description).length() > AbilityDescription.MAX_LENGTH: return "Описание: до %d символов." % AbilityDescription.MAX_LENGTH
	var unknown := AbilityDescription.unknown_tokens(String(description), variables)
	if not unknown.is_empty(): return "Описание: переменная {%s} не относится к этому умению." % unknown[0]
	return ""

func to_effect(data: Dictionary) -> AbilityEffectDefinition:
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = StringName(data.type)
	effect.parameters = data.parameters.duplicate(true)
	for key: String in ["amount", "secondary_amount", "levels", "distance"]:
		if effect.parameters.has(key): effect.parameters[key] = int(effect.parameters[key])
	return effect

func validate_effect(data: Dictionary) -> String:
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
		"core:push":
			if not _integer(params, "distance", 1, PushEffectHandler.MAX_DISTANCE): return "Эффект толчка: дальность — целое число 1–%d." % PushEffectHandler.MAX_DISTANCE
	var handler: AbilityEffectHandler
	match data.type:
		"core:damage": handler = DamageEffectHandler.new()
		"core:unit_status": handler = UnitStatusEffectHandler.new()
		"core:hex_state": handler = HexStateEffectHandler.new()
		"core:summon": handler = SummonEffectHandler.new()
		"core:push": handler = PushEffectHandler.new()
		_: return "Неизвестный обработчик эффекта."
	var effect := to_effect(data)
	var error := handler.validate(effect)
	if not error.is_empty(): return error
	for unit_id: StringName in handler.get_unit_references(effect):
		var unit := find_unit(unit_id)
		if unit == null: return "Призыв: выберите существующего призываемого юнита."
		error = handler.validate_unit_reference(effect, unit)
		if not error.is_empty(): return error
	return ""

func to_ability(data: Dictionary) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.id = StringName(data.id)
	ability.display_name = data.name
	ability.description = String(data.get("description", ""))
	ability.presentation_id = StringName(data.presentation_id)
	for key: String in ["range", "area_radius", "target_mode", "cooldown_turns", "initial_cooldown_turns", "uses_attack_range", "returns_next_turn", "melee_attack"]:
		ability.set(key, data[key])
	for effect: Dictionary in data.effects: ability.effects.append(to_effect(effect))
	return ability

static func filename_for(data: Dictionary) -> String:
	return String(data.id).replace(":", "__") + ".json"

## A built-in skill saved with its original values removes the override file instead of writing a copy.
func save_document(data: Dictionary, root := ROOT) -> String:
	var error := validate(data)
	if not error.is_empty(): return error
	var path := root.path_join(filename_for(data))
	if is_builtin_default(data):
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(path)
			if remove_error != OK: return "Не удалось удалить переопределение: " + error_string(remove_error)
		return ""
	var mkdir := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if mkdir != OK: return "Не удалось создать папку: " + error_string(mkdir)
	return AtomicFileWriter.write_text(path, JSON.stringify(data, "\t") + "\n")

## This library's packages with the documents applied, plus a `custom_skills` package.
func apply_to_packages(documents: Dictionary) -> Array[ContentPackage]:
	var result: Array[ContentPackage] = []
	var passives := passive_definitions(documents)
	for original: ContentPackage in _packages:
		var package := original.duplicate(true) as ContentPackage
		for index: int in range(package.abilities.size()):
			var id := String(package.abilities[index].id)
			if documents.has(id): package.abilities[index] = to_ability(documents[id])
		# Package files hold their units as external resources, which duplicate(true) shares with
		# the loader cache: each unit is copied before it takes this library's passives.
		for index: int in range(package.units.size()):
			package.units[index] = package.units[index].duplicate(true) as UnitDefinition
			package.units[index].passive_definitions = passives.duplicate(true)
		result.append(package)
	var custom := ContentPackage.new()
	custom.manifest = ContentPackageManifest.new()
	custom.manifest.package_id = &"custom_skills"
	for package: ContentPackage in _packages:
		var dependency := ContentPackageDependency.new()
		dependency.package_id = package.manifest.package_id
		custom.manifest.dependencies.append(dependency)
	for data: Dictionary in documents.values():
		if data.kind == "active" and String(data.id).begins_with("custom_skills:"):
			custom.abilities.append(to_ability(data))
	result.append(custom)
	return result
