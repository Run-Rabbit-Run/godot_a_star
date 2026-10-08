class_name BattleFileLogger
extends RefCounted

signal recording_failed(message: String)

const SCHEMA_VERSION := 1
var path := ""
var error_message := ""
var _file: FileAccess
var _session: BattleSession
var _sequence := 0
var _started_usec := 0
var _counts: Dictionary = {}
var _analytics: Dictionary = {}


static func default_directory() -> String:
	var root := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	return root.path_join("logs/battles")


func start(session: BattleSession, directory := "", from_start := false) -> bool:
	if _file != null or session == null:
		return false
	error_message = ""
	path = ""
	var folder := default_directory() if directory.is_empty() else directory
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		error_message = "Не удалось создать папку логов: %s (ошибка %d)" % [folder, error]
		return false
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	# Exclusive reservation prevents overwriting another recording, including another process.
	var reservation := ""
	for index in range(1000):
		var name := "%s_%d_%d_%d" % [stamp, OS.get_process_id(), Time.get_ticks_usec(), index]
		reservation = folder.path_join(name + ".lock")
		if not FileAccess.file_exists(folder.path_join(name + ".jsonl")) and DirAccess.make_dir_absolute(reservation) == OK:
			path = folder.path_join(name + ".jsonl")
			break
	if path.is_empty():
		error_message = "Не удалось выделить уникальное имя лога."
		return false
	_file = FileAccess.open(path, FileAccess.WRITE)
	DirAccess.remove_absolute(reservation)
	if _file == null:
		error_message = "Не удалось открыть лог: %s (ошибка %d)" % [path, FileAccess.get_open_error()]
		return false
	_session = session
	_sequence = 0
	_counts.clear()
	_analytics = {"commands": {}, "ai_decisions": 0, "accepted_operations": 0, "rejected_operations": 0, "events": {}, "damage_by_type": {}, "damage_by_source": {}, "defeated_units": 0}
	_started_usec = Time.get_ticks_usec()
	_session.diagnostic_record.connect(_on_record)
	var content := session.content_snapshot
	var battle := content.get_battle_definition(session.get_battle_id())
	var abilities: Array = []
	for id: StringName in content.get_ability_definition_ids():
		abilities.append(content.get_ability_definition(id))
	var races: Array = []
	for id: StringName in content.get_race_definition_ids():
		races.append(content.get_race_definition(id))
	write_record("recording_started", {"coverage": "battle_start" if from_start else "from_current_state", "engine": Engine.get_version_info(), "application": ProjectSettings.get_setting("application/config/name"), "content_lock": content.content_lock, "battle": battle, "setup": session.setup, "unit_definitions": content.get_all_unit_definitions(), "ability_definitions": abilities, "race_definitions": races, "state": session.get_diagnostic_state()})
	if from_start:
		write_record("initial_resolution", {"resolution": session.get_initial_resolution()})
	return _file != null


func is_recording() -> bool:
	return _file != null


func write_record(kind: String, data: Dictionary) -> void:
	if _file == null:
		return
	_sequence += 1
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	_collect_analytics(kind, data)
	var record := {"schema_version": SCHEMA_VERSION, "sequence": _sequence, "utc": Time.get_datetime_string_from_system(true) + "Z", "elapsed_usec": Time.get_ticks_usec() - _started_usec, "battle_id": String(_session.get_battle_id()), "seed": _session.get_deterministic_seed(), "round": _session.get_round_number(), "active_unit_id": String(_session.get_active_unit_id()), "state_revision": _session.get_state_revision(), "map_revision": _session.get_map_revision(), "kind": kind, "data": BattleLogSerializer.encode(data)}
	_file.store_line(JSON.stringify(record))
	_file.flush()
	var error := _file.get_error()
	if error != OK:
		error_message = "Запись лога прервана: %s (ошибка %d)" % [path, error]
		_disconnect()
		_file.close()
		_file = null
		push_warning(error_message)
		recording_failed.emit(error_message)


func stop(reason := "disabled", detail := "") -> void:
	if _file != null:
		write_record("recording_stopped", {"reason": reason, "detail": detail, "counts": _counts.duplicate(), "analytics": _analytics, "result": _session.get_result(), "state": _session.get_diagnostic_state()})
	_disconnect()
	if _file != null:
		_file.close()
		_file = null


func _on_record(kind: String, data: Dictionary) -> void:
	write_record(kind, data)


func _disconnect() -> void:
	if _session != null and _session.diagnostic_record.is_connected(_on_record):
		_session.diagnostic_record.disconnect(_on_record)
	_session = null


func _collect_analytics(kind: String, data: Dictionary) -> void:
	if kind == "ai_decision":
		_analytics.ai_decisions += 1
	if kind == "command_requested" and data.command != null:
		_increment(_analytics.commands, String(data.command.get_script().get_global_name()), 1)
	if kind not in ["initial_resolution", "resolution"]:
		return
	var resolution := data.resolution as BattleResolution
	if kind == "resolution":
		var counter := "accepted_operations" if resolution.accepted else "rejected_operations"
		_analytics[counter] += 1
	for event: BattleEvent in resolution.events:
		_increment(_analytics.events, String(event.get_script().get_global_name()), 1)
		if event is UnitDamagedEvent:
			_increment(_analytics.damage_by_type, String(event.damage_type), event.damage)
			var source: StringName = event.source_status_id
			if source.is_empty():
				source = event.source_hex_state_id
			if source.is_empty():
				source = event.source_ability_id
			if source.is_empty():
				source = &"basic_attack"
			_increment(_analytics.damage_by_source, String(source), event.damage)
			if event.target_defeated:
				_analytics.defeated_units += 1


func _increment(counters: Dictionary, key: String, amount: int) -> void:
	counters[key] = int(counters.get(key, 0)) + amount
