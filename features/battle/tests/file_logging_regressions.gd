extends RefCounted
## Battle file logging: recording and its files, the settings toggle and the feature flag.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_file_logging(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var session := BattleSessionFactory.create(fixture.request()).session
	var baseline := BattleSessionFactory.create(fixture.request()).session
	var directory := "user://logging_regression_%d" % Time.get_ticks_usec()
	var logger := BattleFileLogger.new()
	suite.expect(not session.has_diagnostic_observer(), "No diagnostic observer by default")
	suite.expect(logger.start(session, directory, true), "File recording starts")
	suite.expect(session.has_diagnostic_observer(), "Recording attaches observer")
	var bad := session.step(null)
	suite.expect(not bad.accepted, "Null command recorded as rejected without logging crash")
	baseline.step(null)
	var ai := AICommandSource.new(null)
	session.set_side_command_source(session.setup.sides[0].side_id, ai)
	baseline.set_side_command_source(baseline.setup.sides[0].side_id, AICommandSource.new(null))
	var command := session.get_next_ai_command()
	var baseline_command := baseline.get_next_ai_command()
	suite.expect(JSON.stringify(BattleLogSerializer.encode(command)) == JSON.stringify(BattleLogSerializer.encode(baseline_command)), "Diagnostics preserve AI choice")
	if command != null:
		session.step(command)
		baseline.step(baseline_command)
	suite.expect(JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state())) == JSON.stringify(BattleLogSerializer.encode(baseline.get_diagnostic_state())), "Recording preserves gameplay and RNG")
	var changed := session.apply_map_mutations([MapMutation.apply_hex_state(Vector2i(999, 999), &"core:fire")])
	suite.expect(not changed.accepted, "Rejected map mutation remains rejected")
	var damage := UnitDamagedEvent.new(&"attacker", &"victim", 3, 0, true)
	damage.base_damage = 6
	damage.calculated_damage = 5
	damage.damage_modifiers.append({"source_id": &"core:armor", "amount": -1})
	logger.write_record("resolution", {"resolution": BattleResolution.success([damage], 0, &""), "state": session.get_diagnostic_state()})
	logger.stop("scene_closed")
	suite.expect(not session.has_diagnostic_observer(), "Stop detaches observer")
	var first_path := logger.path
	var input := FileAccess.open(first_path, FileAccess.READ)
	var records: Array = []
	while input.get_position() < input.get_length():
		var parsed: Variant = JSON.parse_string(input.get_line())
		suite.expect(parsed is Dictionary, "Every line parses as JSON")
		if parsed is Dictionary:
			records.append(parsed)
	input.close()
	suite.expect(records[0].data.coverage == "battle_start" and records[1].kind == "initial_resolution", "Recording includes start and initial events")
	suite.expect(records[0].data.setup.unit_spawns.size() > 0 and records[0].data.unit_definitions.size() > 0, "Header includes effective content and setup")
	suite.expect(records[0].data.state.units.size() > 0 and records[0].data.state.grid.cells.size() > 0, "Header includes full state and terrain")
	suite.expect(records[3].kind == "resolution" and records[3].data.resolution.accepted == false, "Rejected command and reason persisted")
	suite.expect(records[-1].kind == "recording_stopped" and records[-1].data.reason == "scene_closed", "Interrupted recording has explicit footer")
	suite.expect(records[-1].data.analytics.rejected_operations == 2, "Analytics count rejected command and map mutation")
	suite.expect(int(records[-1].data.analytics.damage_by_type.physical) >= 3 and records[-1].data.analytics.defeated_units >= 1, "Analytics count actual damage and defeated targets")
	var serialized_damage: Dictionary = records[-2].data.resolution.events[0]
	suite.expect(serialized_damage.type == "UnitDamagedEvent" and serialized_damage.base_damage == 6 and serialized_damage.calculated_damage == 5 and serialized_damage.damage == 3, "JSON retains damage formula and actual HP loss")
	suite.expect(serialized_damage.damage_modifiers[0].source_id == "core:armor" and serialized_damage.damage_modifiers[0].amount == -1, "JSON retains signed damage modifiers")
	var has_ai := false
	for index in range(records.size()):
		suite.expect(int(records[index].sequence) == index + 1, "Record sequence is consecutive")
		if records[index].kind == "ai_decision":
			has_ai = records[index].data.trace.has("reason")
	suite.expect(has_ai, "AI decision includes explanation")
	suite.expect(logger.start(session, directory, false), "Recording can resume")
	suite.expect(logger.path != first_path, "Resume uses a new file")
	logger.stop("disabled")
	input = FileAccess.open(logger.path, FileAccess.READ)
	suite.expect(JSON.parse_string(input.get_line()).data.coverage == "from_current_state", "Partial coverage is explicit")
	input.close()
	var count_before := records.size()
	session.step(null)
	suite.expect(count_before == records.size() and not logger.is_recording(), "Disabled recorder remains stopped")
	DirAccess.remove_absolute(first_path)
	DirAccess.remove_absolute(logger.path)
	DirAccess.remove_absolute(directory)
	var blocked_directory := "user://blocked_log_%d" % Time.get_ticks_usec()
	var blocker := FileAccess.open(blocked_directory, FileAccess.WRITE)
	blocker.store_string("This is a file, not a directory")
	blocker.close()
	suite.expect(not logger.start(session, blocked_directory), "Unwritable destination does not start recording")
	suite.expect(not logger.error_message.is_empty() and not session.has_diagnostic_observer(), "Recording error is explicit and leaves session detached")
	DirAccess.remove_absolute(blocked_directory)
	var participant := fixture.unit(&"snapshot", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	participant.passive_ability_ids.append(&"core:passive")
	participant.basic_attack_statuses[&"core:wet"] = 2
	participant.turns_started = 3
	var snapshot := UnitSnapshot.new(participant)
	snapshot.passive_ability_ids.clear()
	snapshot.basic_attack_statuses.clear()
	suite.expect(participant.passive_ability_ids.size() == 1 and participant.basic_attack_statuses.size() == 1 and snapshot.turns_started == 3, "Extended diagnostic snapshot is detached from passives and attack statuses")


func run_file_logging_ui(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var flag: Variant = ProjectSettings.get_setting(BattleLoggingController.FEATURE_SETTING, false)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, false)
	var screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	suite.get_tree().root.add_child(screen)
	suite.expect(screen.setup(fixture.request(true)), "Logging UI fixture starts battle")
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller := screen.get_node("BattleMap/BattleController") as BattleController
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	suite.expect(controller.get_node_or_null("BattleLoggingController") == null, "Disabled flag creates no recorder subsystem")
	suite.expect(hud.find_child("BattleFileLogging", true, false) == null, "Disabled flag hides recording controls")
	var config_existed := FileAccess.file_exists(BattleLoggingController.CONFIG_PATH)
	var original_config := FileAccess.get_file_as_string(BattleLoggingController.CONFIG_PATH) if config_existed else ""
	var config := ConfigFile.new()
	config.set_value("logging", "enabled", false)
	config.save(BattleLoggingController.CONFIG_PATH)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, true)
	var flagged_screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	suite.get_tree().root.add_child(flagged_screen)
	suite.expect(flagged_screen.setup(fixture.request(true)), "Flagged battle starts")
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	suite.expect(flagged_screen.get_node_or_null("BattleMap/BattleController/BattleLoggingController") != null, "Enabled flag composes recorder subsystem")
	suite.expect(flagged_screen.find_child("BattleFileLogging", true, false) != null, "Enabled flag shows settings toggle")
	flagged_screen.queue_free()
	await suite.get_tree().process_frame
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, false)
	var directory := "user://logging_ui_%d" % Time.get_ticks_usec()
	var logging := BattleLoggingController.new()
	controller.add_child(logging)
	logging.setup(controller.get("_battle_session"), hud, controller, directory)
	var section := hud.find_child("BattleFileLogging", true, false)
	var check := section.get_child(0) as CheckButton
	suite.expect(not check.button_pressed, "Recording initially off")
	check.button_pressed = true
	var logger := logging.get("_logger") as BattleFileLogger
	suite.expect(logger.is_recording(), "Settings toggle starts recording mid-battle")
	var first_path := logger.path
	check.button_pressed = false
	suite.expect(not logger.is_recording(), "Settings toggle stops recording")
	check.button_pressed = true
	var second_path := logger.path
	suite.expect(first_path != second_path, "Settings re-enable creates a separate segment")
	controller.battle_finished.emit(BattleResult.new(&"core:test", 7, BattleOutcome.Value.VICTORY, 1, null))
	suite.expect(not logger.is_recording(), "Battle finish closes recording")
	var input := FileAccess.open(second_path, FileAccess.READ)
	var last: Variant
	while input.get_position() < input.get_length():
		last = JSON.parse_string(input.get_line())
	input.close()
	suite.expect(last.data.reason == "battle_finished", "Battle finish footer is explicit")
	# A stopped battle must retain failure semantics if recording is enabled afterwards.
	controller.battle_failed.disconnect(screen._on_battle_failed)
	controller.battle_failed.emit("Injected runtime failure")
	check.button_pressed = false
	check.button_pressed = true
	var failed_path := logger.path
	suite.expect(not logger.is_recording(), "Enabling after a failed battle produces a closed diagnostic segment")
	input = FileAccess.open(failed_path, FileAccess.READ)
	while input.get_position() < input.get_length():
		last = JSON.parse_string(input.get_line())
	input.close()
	suite.expect(last.data.reason == "battle_failed" and last.data.detail == "Injected runtime failure", "Late recording preserves failure reason and detail")
	if config_existed:
		var restored := FileAccess.open(BattleLoggingController.CONFIG_PATH, FileAccess.WRITE)
		restored.store_string(original_config)
		restored.close()
	else:
		DirAccess.remove_absolute(BattleLoggingController.CONFIG_PATH)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, flag)
	screen.queue_free()
	await suite.get_tree().process_frame
	DirAccess.remove_absolute(first_path)
	DirAccess.remove_absolute(second_path)
	DirAccess.remove_absolute(failed_path)
	DirAccess.remove_absolute(directory)


## Owner decision: production builds never compose the recorder, whatever the base flag value.
func run_file_logging_flag(suite: Node) -> void:
	var setting := BattleLoggingController.FEATURE_SETTING
	var project := ConfigFile.new()
	suite.expect(project.load("res://project.godot") == OK, "project.godot is readable")
	suite.expect(project.get_value("feature_flags", "battle_file_logging.release", "missing") == false, "Release builds override the logging flag to false")
	var flag: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, true)
	suite.expect(BattleLoggingController.is_feature_enabled() == not OS.has_feature("release"), "Release override applies only to release builds")
	# Any feature tag of the running build must win over the base value, as the release tag does in production.
	var override := setting + "." + ("debug" if OS.has_feature("debug") else "release")
	var previous: Variant = ProjectSettings.get_setting(override) if ProjectSettings.has_setting(override) else null
	ProjectSettings.set_setting(override, false)
	suite.expect(not BattleLoggingController.is_feature_enabled(), "Feature-tag override disables the recorder")
	ProjectSettings.set_setting(override, previous)
	suite.expect(BattleLoggingController.is_feature_enabled() == not OS.has_feature("release"), "Removing the override restores the base value")
	ProjectSettings.set_setting(setting, flag)
