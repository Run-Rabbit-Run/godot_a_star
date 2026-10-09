extends Node

const HexStatusPreview := preload("res://features/battle/view/hex_status_preview.gd")
const DamageAbilityPreview := preload("res://features/battle/view/damage_ability_preview.gd")

var fixture = preload("res://features/battle/tests/regression_fixtures.gd").new()
var checks := 0
var failures: Array[String] = []
var only := ""


## Records how often the default area batch falls back to per-cell execution.
class CountingHexHandler extends AbilityEffectHandler:
	var calls := 0

	func affects_hexes() -> bool:
		return true

	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute_hex(_effect: AbilityEffectDefinition, _context: BattleEffectContext, _source: StringName, _hex: Vector2i) -> Array[BattleEvent]:
		calls += 1
		var events: Array[BattleEvent] = []
		return events

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	call_deferred("_run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _run() -> void:
	if only.is_empty() or only == "geometry":
		_test_geometry()
	if only.is_empty() or only == "terrain_reactions":
		_test_terrain_reactions()
	if only.is_empty() or only == "properties":
		_test_properties()
	if only.is_empty() or only == "statuses":
		_test_statuses()
		_test_fixed_status_damage()
	if only.is_empty() or only == "damage_log":
		_test_damage_log()
	if only.is_empty() or only == "file_logging":
		_test_file_logging()
	if only.is_empty() or only == "file_logging_ui":
		await _test_file_logging_ui()
	if only.is_empty() or only == "turn_effect_order":
		_test_turn_effect_order()
	if only.is_empty() or only == "commands":
		_test_commands()
	if only.is_empty() or only == "content":
		_test_content()
	if only.is_empty() or only == "documents":
		_test_documents()
	if only.is_empty() or only == "ai_and_forecast":
		_test_ai_and_forecast()
	if only.is_empty() or only == "doomed_ai":
		_test_doomed_ai()
	if only.is_empty() or only == "summon_control":
		_test_summon_control()
	if only.is_empty() or only == "simulation":
		_test_simulation()
	if only.is_empty() or only == "presentation":
		await _test_presentation()
	if only.is_empty() or only == "editor":
		await _test_editor()
	if only.is_empty() or only == "review_fixes":
		_test_review_fixes()
	if only.is_empty() or only == "review_fixes_ui":
		await _test_review_fixes_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	expect(checks > 0, "Requested test group exists and completed checks")
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("A_star regressions: %d checks, %d failures" % [checks, failures.size()])
	get_tree().create_timer(0.1).timeout.connect(get_tree().quit.bind(0 if failures.is_empty() else 1))
	queue_free()

func _test_file_logging() -> void:
	var session := BattleSessionFactory.create(fixture.request()).session
	var baseline := BattleSessionFactory.create(fixture.request()).session
	var directory := "user://logging_regression_%d" % Time.get_ticks_usec()
	var logger := BattleFileLogger.new()
	expect(not session.has_diagnostic_observer(), "No diagnostic observer by default")
	expect(logger.start(session, directory, true), "File recording starts")
	expect(session.has_diagnostic_observer(), "Recording attaches observer")
	var bad := session.step(null)
	expect(not bad.accepted, "Null command recorded as rejected without logging crash")
	baseline.step(null)
	var ai := AICommandSource.new(null)
	session.set_side_command_source(session.setup.sides[0].side_id, ai)
	baseline.set_side_command_source(baseline.setup.sides[0].side_id, AICommandSource.new(null))
	var command := session.get_next_ai_command()
	var baseline_command := baseline.get_next_ai_command()
	expect(JSON.stringify(BattleLogSerializer.encode(command)) == JSON.stringify(BattleLogSerializer.encode(baseline_command)), "Diagnostics preserve AI choice")
	if command != null:
		session.step(command)
		baseline.step(baseline_command)
	expect(JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state())) == JSON.stringify(BattleLogSerializer.encode(baseline.get_diagnostic_state())), "Recording preserves gameplay and RNG")
	var changed := session.apply_map_mutations([MapMutation.apply_hex_state(Vector2i(999, 999), &"core:fire")])
	expect(not changed.accepted, "Rejected map mutation remains rejected")
	var damage := UnitDamagedEvent.new(&"attacker", &"victim", 3, 0, true)
	damage.base_damage = 6
	damage.calculated_damage = 5
	damage.damage_modifiers.append({"source_id": &"core:armor", "amount": -1})
	logger.write_record("resolution", {"resolution": BattleResolution.success([damage], 0, &""), "state": session.get_diagnostic_state()})
	logger.stop("scene_closed")
	expect(not session.has_diagnostic_observer(), "Stop detaches observer")
	var first_path := logger.path
	var input := FileAccess.open(first_path, FileAccess.READ)
	var records: Array = []
	while input.get_position() < input.get_length():
		var parsed: Variant = JSON.parse_string(input.get_line())
		expect(parsed is Dictionary, "Every line parses as JSON")
		if parsed is Dictionary:
			records.append(parsed)
	input.close()
	expect(records[0].data.coverage == "battle_start" and records[1].kind == "initial_resolution", "Recording includes start and initial events")
	expect(records[0].data.setup.unit_spawns.size() > 0 and records[0].data.unit_definitions.size() > 0, "Header includes effective content and setup")
	expect(records[0].data.state.units.size() > 0 and records[0].data.state.grid.cells.size() > 0, "Header includes full state and terrain")
	expect(records[3].kind == "resolution" and records[3].data.resolution.accepted == false, "Rejected command and reason persisted")
	expect(records[-1].kind == "recording_stopped" and records[-1].data.reason == "scene_closed", "Interrupted recording has explicit footer")
	expect(records[-1].data.analytics.rejected_operations == 2, "Analytics count rejected command and map mutation")
	expect(int(records[-1].data.analytics.damage_by_type.physical) >= 3 and records[-1].data.analytics.defeated_units >= 1, "Analytics count actual damage and defeated targets")
	var serialized_damage: Dictionary = records[-2].data.resolution.events[0]
	expect(serialized_damage.type == "UnitDamagedEvent" and serialized_damage.base_damage == 6 and serialized_damage.calculated_damage == 5 and serialized_damage.damage == 3, "JSON retains damage formula and actual HP loss")
	expect(serialized_damage.damage_modifiers[0].source_id == "core:armor" and serialized_damage.damage_modifiers[0].amount == -1, "JSON retains signed damage modifiers")
	var has_ai := false
	for index in range(records.size()):
		expect(int(records[index].sequence) == index + 1, "Record sequence is consecutive")
		if records[index].kind == "ai_decision":
			has_ai = records[index].data.trace.has("reason")
	expect(has_ai, "AI decision includes explanation")
	expect(logger.start(session, directory, false), "Recording can resume")
	expect(logger.path != first_path, "Resume uses a new file")
	logger.stop("disabled")
	input = FileAccess.open(logger.path, FileAccess.READ)
	expect(JSON.parse_string(input.get_line()).data.coverage == "from_current_state", "Partial coverage is explicit")
	input.close()
	var count_before := records.size()
	session.step(null)
	expect(count_before == records.size() and not logger.is_recording(), "Disabled recorder remains stopped")
	DirAccess.remove_absolute(first_path)
	DirAccess.remove_absolute(logger.path)
	DirAccess.remove_absolute(directory)
	var blocked_directory := "user://blocked_log_%d" % Time.get_ticks_usec()
	var blocker := FileAccess.open(blocked_directory, FileAccess.WRITE)
	blocker.store_string("This is a file, not a directory")
	blocker.close()
	expect(not logger.start(session, blocked_directory), "Unwritable destination does not start recording")
	expect(not logger.error_message.is_empty() and not session.has_diagnostic_observer(), "Recording error is explicit and leaves session detached")
	DirAccess.remove_absolute(blocked_directory)
	var participant := fixture.unit(&"snapshot", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	participant.passive_ability_ids.append(&"core:passive")
	participant.basic_attack_statuses[&"core:wet"] = 2
	participant.turns_started = 3
	var snapshot := UnitSnapshot.new(participant)
	snapshot.passive_ability_ids.clear()
	snapshot.basic_attack_statuses.clear()
	expect(participant.passive_ability_ids.size() == 1 and participant.basic_attack_statuses.size() == 1 and snapshot.turns_started == 3, "Extended diagnostic snapshot is detached from passives and attack statuses")


func _test_file_logging_ui() -> void:
	var flag: Variant = ProjectSettings.get_setting(BattleLoggingController.FEATURE_SETTING, false)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, false)
	var screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	get_tree().root.add_child(screen)
	expect(screen.setup(fixture.request(true)), "Logging UI fixture starts battle")
	await get_tree().process_frame
	await get_tree().process_frame
	var controller := screen.get_node("BattleMap/BattleController") as BattleController
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	expect(controller.get_node_or_null("BattleLoggingController") == null, "Disabled flag creates no recorder subsystem")
	expect(hud.get_node_or_null("HUDRoot/SpeedPanel/Content/BattleFileLogging") == null, "Disabled flag hides recording controls")
	var config_existed := FileAccess.file_exists(BattleLoggingController.CONFIG_PATH)
	var original_config := FileAccess.get_file_as_string(BattleLoggingController.CONFIG_PATH) if config_existed else ""
	var config := ConfigFile.new()
	config.set_value("logging", "enabled", false)
	config.save(BattleLoggingController.CONFIG_PATH)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, true)
	var flagged_screen := (load("res://features/battle/battle_screen.tscn") as PackedScene).instantiate() as BattleScreen
	get_tree().root.add_child(flagged_screen)
	expect(flagged_screen.setup(fixture.request(true)), "Flagged battle starts")
	await get_tree().process_frame
	await get_tree().process_frame
	expect(flagged_screen.get_node_or_null("BattleMap/BattleController/BattleLoggingController") != null, "Enabled flag composes recorder subsystem")
	expect(flagged_screen.get_node_or_null("BattleMap/BattleUI/HUDRoot/SpeedPanel/Content/BattleFileLogging") != null, "Enabled flag shows settings toggle")
	flagged_screen.queue_free()
	await get_tree().process_frame
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, false)
	var directory := "user://logging_ui_%d" % Time.get_ticks_usec()
	var logging := BattleLoggingController.new()
	controller.add_child(logging)
	logging.setup(controller.get("_battle_session"), hud, controller, directory)
	var section := hud.get_node("HUDRoot/SpeedPanel/Content/BattleFileLogging")
	var check := section.get_child(0) as CheckButton
	expect(not check.button_pressed, "Recording initially off")
	check.button_pressed = true
	var logger := logging.get("_logger") as BattleFileLogger
	expect(logger.is_recording(), "Settings toggle starts recording mid-battle")
	var first_path := logger.path
	check.button_pressed = false
	expect(not logger.is_recording(), "Settings toggle stops recording")
	check.button_pressed = true
	var second_path := logger.path
	expect(first_path != second_path, "Settings re-enable creates a separate segment")
	controller.battle_finished.emit(BattleResult.new(&"core:test", 7, BattleOutcome.Value.VICTORY, 1, null))
	expect(not logger.is_recording(), "Battle finish closes recording")
	var input := FileAccess.open(second_path, FileAccess.READ)
	var last: Variant
	while input.get_position() < input.get_length():
		last = JSON.parse_string(input.get_line())
	input.close()
	expect(last.data.reason == "battle_finished", "Battle finish footer is explicit")
	# A stopped battle must retain failure semantics if recording is enabled afterwards.
	controller.battle_failed.disconnect(screen._on_battle_failed)
	controller.battle_failed.emit("Injected runtime failure")
	check.button_pressed = false
	check.button_pressed = true
	var failed_path := logger.path
	expect(not logger.is_recording(), "Enabling after a failed battle produces a closed diagnostic segment")
	input = FileAccess.open(failed_path, FileAccess.READ)
	while input.get_position() < input.get_length():
		last = JSON.parse_string(input.get_line())
	input.close()
	expect(last.data.reason == "battle_failed" and last.data.detail == "Injected runtime failure", "Late recording preserves failure reason and detail")
	if config_existed:
		var restored := FileAccess.open(BattleLoggingController.CONFIG_PATH, FileAccess.WRITE)
		restored.store_string(original_config)
		restored.close()
	else:
		DirAccess.remove_absolute(BattleLoggingController.CONFIG_PATH)
	ProjectSettings.set_setting(BattleLoggingController.FEATURE_SETTING, flag)
	screen.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(first_path)
	DirAccess.remove_absolute(second_path)
	DirAccess.remove_absolute(failed_path)
	DirAccess.remove_absolute(directory)


func _test_geometry() -> void:
	for q in range(-4, 5):
		for r in range(-4, 5):
			var hex := Vector2i(q, r)
			expect(HexCoordinateMapper.offset_to_axial(HexCoordinateMapper.axial_to_offset(hex)) == hex, "Coordinates round-trip %s" % hex)
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(3, 0)])
	expect(not grid.has_cell(Vector2i(2, 0)), "Holes remain absent")
	expect(not MovementService.search(grid, Vector2i.ZERO, 10, {}).get_reachable_cells().has(Vector2i(3, 0)), "Movement cannot jump holes")
	grid.set_traversal(Vector2i(1, 0), false, 1)
	expect(grid.has_cell(Vector2i(1, 0)) and not grid.is_traversable(Vector2i(1, 0)), "Blocked cell differs from a hole")
	var copy := grid.duplicate_grid()
	copy.remove_cell(Vector2i.ZERO)
	expect(grid.has_cell(Vector2i.ZERO), "Grid copies are detached")

func _test_terrain_reactions() -> void:
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var state := fixture.state([a, b])
	state.hex_grid.set_hex_state(a, &"core:electrified_water")
	var application := MapMutationService.apply(state, [MapMutation.apply_hex_state(b, &"core:water")])
	expect(application.accepted and state.hex_grid.get_hex_state_id(b) == &"core:electrified_water", "Existing electrified water transforms newly created neighbor water")
	var final_states: Array[String] = []
	for reversed in [false, true]:
		var cells: Array[Vector2i] = []
		cells.assign([b, a] if reversed else [a, b])
		state = fixture.state(cells)
		state.hex_grid.set_hex_state(a, &"core:fire")
		state.hex_grid.set_hex_state(b, &"core:fire")
		var mutations: Array[MapMutation] = []
		for hex: Vector2i in cells:
			mutations.append(MapMutation.apply_hex_state(hex, &"core:electricity"))
		application = MapMutationService.apply(state, mutations)
		expect(application.accepted, "Area reaction accepted")
		final_states.append("%s/%s" % [state.hex_grid.get_hex_state_id(a), state.hex_grid.get_hex_state_id(b)])
	expect(final_states[0] == final_states[1] and final_states[0] == "core:plasma/core:plasma", "Area reactions independent of cell insertion and mutation order")
	state = fixture.state([a, b])
	application = MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:fire"), MapMutation.remove_hex(Vector2i(9, 9))])
	expect(not application.accepted and state.hex_grid.get_hex_state_id(a).is_empty() and state.state_revision == 0, "Invalid batch commits neither terrain nor revisions")
	var occupant := fixture.unit(&"p", BattleFaction.Value.PLAYER, a)
	state = fixture.state([a, b], [occupant])
	expect(not MapMutationService.apply(state, [MapMutation.remove_hex(a)]).accepted, "Cannot remove living occupant cell")
	expect(not MapMutationService.apply(state, [MapMutation.set_traversal(a, false)]).accepted, "Cannot block living occupant cell")
	state.hex_grid.set_hex_state(a, &"core:water")
	var first := MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electricity")])
	var levels := int(occupant.statuses.get(&"core:electrified", 0))
	var hp := occupant.health.current
	MapMutationService.apply(state, [MapMutation.apply_hex_state(a, &"core:electrified_water")])
	expect(not first.events.is_empty() and levels == 3, "Changed terrain exposes occupant once")
	expect(occupant.health.current == hp and occupant.statuses.get(&"core:electrified", 0) == levels, "No-op terrain does not repeat exposure")

func _test_statuses() -> void:
	var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(unit, &"core:wet", 3, events)
	UnitStatusService.damage(unit, 1, &"electric", events)
	expect(unit.health.current == 98 and unit.statuses.get(&"core:wet", 0) == 3, "Wet amplifies electric damage without decay")
	UnitStatusService.damage(unit, 2, &"fire", events)
	expect(unit.health.current == 98 and unit.statuses.get(&"core:wet", 0) == 1, "Wet absorbs fire one-to-one")
	UnitStatusService.apply(unit, &"core:plasma", 2, events)
	expect(not unit.statuses.has(&"core:wet"), "Plasma removes wet")
	UnitStatusService.damage(unit, 8, &"water", events)
	expect(unit.health.current == 98, "Plasma blocks water damage")
	unit.status_immunities.append(&"core:burning")
	UnitStatusService.apply(unit, &"core:burning", 2, events)
	expect(not unit.statuses.has(&"core:burning"), "Burning immunity blocks only status")
	UnitStatusService.damage(unit, 2, &"fire", events)
	expect(unit.health.current == 96, "Status immunity is not damage immunity")
	UnitStatusService.apply(unit, &"core:armor", 8, events)
	UnitStatusService.apply(unit, &"core:acid", 5, events)
	expect(not unit.statuses.has(&"core:armor") and not unit.statuses.has(&"core:acid"), "Acid threshold removes armor and acid")
	events.clear()
	UnitStatusService.end_turn(unit, events)
	var periodic_found := false
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			periodic_found = periodic_found or (event.source_status_id == &"core:plasma" and event.source_hex_state_id.is_empty())
	expect(periodic_found, "Periodic damage identifies status rather than terrain")
	var snapshot := UnitSnapshot.new(unit)
	snapshot.statuses.clear()
	expect(not unit.statuses.is_empty(), "Status snapshots are detached")

func _test_fixed_status_damage() -> void:
	for spec: Dictionary in [
		{"id": &"core:burning", "amount": 1, "type": &"fire"},
		{"id": &"core:electrified", "amount": 1, "type": &"electric"},
		{"id": &"core:plasma", "amount": 2, "type": &"fire"},
	]:
		for levels: int in [0, 1, 3, 7]:
			var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
			if levels > 0:
				unit.statuses[spec.id] = levels
			var events: Array[BattleEvent] = []
			UnitStatusService.end_turn(unit, events)
			var expected_damage: int = spec.amount if levels > 0 else 0
			expect(unit.health.current == 100 - expected_damage and unit.statuses.get(spec.id, 0) == maxi(0, levels - 1), "Fixed status damage and one-level decay: %s/%d" % [spec.id, levels])
			var hits := 0
			for event: BattleEvent in events:
				if event is UnitDamagedEvent:
					hits += 1
					expect(event.base_damage == expected_damage and event.damage_type == spec.type and event.source_status_id == spec.id and event.source_hex_state_id.is_empty(), "Periodic event preserves fixed base, type and source: %s/%d" % [spec.id, levels])
			expect(hits == (1 if levels > 0 else 0), "Absent status does not damage: %s/%d" % [spec.id, levels])
	for levels: int in [0, 1, 3, 7]:
		var unit := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
		if levels > 0:
			unit.statuses[&"core:wet"] = levels
		var events: Array[BattleEvent] = []
		UnitStatusService.damage(unit, 3, &"electric", events)
		expect(unit.health.current == (96 if levels > 0 else 97) and unit.statuses.get(&"core:wet", 0) == levels, "Wet adds one electric damage without consumption: %d" % levels)
	var protected := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	protected.statuses.assign({&"core:plasma": 3, &"core:wet": 1})
	var events: Array[BattleEvent] = []
	UnitStatusService.end_turn(protected, events)
	expect(protected.health.current == 99 and not protected.statuses.has(&"core:wet"), "Plasma periodic fire damage uses fire absorption")
	var oily := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	oily.statuses[&"core:sticky_oil"] = 3
	UnitStatusService.apply(oily, &"core:burning", 2, events)
	expect(oily.health.current == 95 and not oily.statuses.has(&"core:sticky_oil"), "Oil explosion retains sum-of-levels rule")

func _test_turn_effect_order() -> void:
	for action: String in ["end", "attack", "ability"]:
		var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
		var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
		var state := fixture.state([p.hex, e.hex], [p, e])
		var engine := BattleEngine.new(state)
		p.statuses[&"core:electrified"] = 2
		var command = EndTurnCommand.new(p.unit_id)
		if action == "attack":
			command = AttackCommand.new(p.unit_id, e.unit_id)
		elif action == "ability":
			var ability := fixture.ability(&"test:turn_order", AbilityDefinition.TargetMode.ENEMY)
			p.abilities[ability.id] = ability
			command = UseAbilityCommand.new(p.unit_id, e.unit_id, ability.id)
		var result := engine.execute(command)
		var tick_index := -1
		var boundary_index := -1
		var ticks := 0
		for index in range(result.events.size()):
			var event := result.events[index]
			if event is UnitDamagedEvent and event.source_status_id == &"core:electrified":
				tick_index = index
				ticks += 1
			if event is TurnEndedEvent and event.previous_unit_id == p.unit_id:
				boundary_index = index
		expect(result.accepted and ticks == 1 and tick_index >= 0 and tick_index < boundary_index, "Periodic tick precedes handoff exactly once: %s" % action)
		expect(p.health.current == 99 and p.statuses[&"core:electrified"] == 1, "End tick uses fixed damage and one-level decay: %s" % action)
		p.health.current = 100
		var start_result := engine.execute(EndTurnCommand.new(e.unit_id))
		var premature_tick := false
		for event: BattleEvent in start_result.events:
			if event is UnitDamagedEvent and event.target_id == p.unit_id and not event.source_status_id.is_empty():
				premature_tick = true
		expect(start_result.accepted and engine.get_round_number() == 2 and p.health.current == 100 and not premature_tick, "Starting the next own turn does not apply periodic damage: %s" % action)
	# A skipped unit has its own boundary, after its own tick, before the next round.
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state([p.hex, e.hex], [p, e])
	var engine := BattleEngine.new(state)
	e.statuses.assign({&"core:electrified": 2, &"core:paralysis": 1})
	var result := engine.execute(EndTurnCommand.new(p.unit_id))
	var timeline: Array[String] = []
	var skipped = null
	for event: BattleEvent in result.events:
		if event is TurnEndedEvent:
			timeline.append("end:%s:%d" % [event.previous_unit_id, event.round_number])
			if event.was_skipped:
				skipped = event
		elif event is UnitDamagedEvent:
			timeline.append("tick:%s" % event.target_id)
	expect(timeline == ["end:p:1", "tick:e", "end:e:2"], "Skipped turn tick is between its start handoff and its end handoff")
	expect(skipped != null and skipped.previous_unit_id == e.unit_id and skipped.next_unit_id == p.unit_id, "Skipped turn explicitly identifies paralysis handoff")
	expect(e.health.current == 99 and not e.statuses.has(&"core:paralysis") and engine.get_active_unit_id() == p.unit_id, "Paralysis skip retains tick and decay once")
	var units: Dictionary[StringName, UnitDefinition] = {}
	expect("пропущен из-за паралича" in BattleLogFormatter.describe(skipped, units, null), "Log explicitly explains skipped end-of-turn effects")
	# Direct terrain damage still belongs to the new turn, unlike periodic status damage.
	e.statuses.clear()
	state.hex_grid.set_hex_state(e.hex, &"core:electricity")
	result = engine.execute(EndTurnCommand.new(p.unit_id))
	timeline.clear()
	for event: BattleEvent in result.events:
		if event is TurnEndedEvent:
			timeline.append("handoff")
		elif event is UnitDamagedEvent:
			timeline.append("terrain" if event.source_hex_state_id == &"core:electricity" and event.source_status_id.is_empty() else "periodic")
	expect(timeline == ["handoff", "terrain"], "Beginning terrain exposure follows handoff and does not tick electrified status")
	# The first participant can already be paralyzed when the battle starts.
	p.statuses.assign({&"core:electrified": 2, &"core:paralysis": 1})
	e.statuses.clear()
	state = fixture.state([p.hex, e.hex], [p, e])
	engine = BattleEngine.new(state)
	timeline.clear()
	skipped = null
	for event: BattleEvent in engine.get_initial_resolution().events:
		if event is UnitDamagedEvent:
			timeline.append("tick")
		elif event is TurnEndedEvent:
			timeline.append("handoff")
			skipped = event
	expect(timeline == ["tick", "handoff"] and engine.get_active_unit_id() == e.unit_id, "Initial paralysis resolves end tick before the handoff")
	expect(skipped != null and skipped.was_skipped, "Initial paralysis is explicitly marked as a skipped turn")
	# Lethal periodic damage must also precede the terminal turn boundary.
	e.health.current = 1
	e.statuses[&"core:electrified"] = 2
	result = engine.execute(EndTurnCommand.new(e.unit_id))
	timeline.clear()
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent:
			timeline.append("tick")
		elif event is TurnEndedEvent:
			timeline.append("handoff")
	expect(timeline == ["tick", "handoff"] and result.battle_result != null, "Lethal end tick precedes battle-ending boundary")


func _test_damage_log() -> void:
	var attacker := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	attacker.basic_attack_damage = 6
	attacker.basic_attack_range = 3
	target.statuses[&"core:armor"] = 1
	var state := fixture.state([attacker.hex, target.hex], [attacker, target])
	state.hex_grid.set_hex_state(target.hex, &"core:steam")
	var engine := BattleEngine.new(state)
	var result := engine.execute(AttackCommand.new(attacker.unit_id, target.unit_id))
	var hit: UnitDamagedEvent
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent and event.attacker_id == attacker.unit_id:
			hit = event
	expect(result.accepted and hit != null, "Ranged attack publishes a damage calculation")
	if hit == null:
		return
	expect(hit.base_damage == 6 and hit.calculated_damage == 2 and hit.damage == 2, "Damage calculation preserves 6 minus steam 3 minus armor 1 equals 2")
	expect(hit.damage_modifiers == [{"source_id": &"core:steam", "amount": -3}, {"source_id": &"core:armor", "amount": -1}], "Damage event identifies ordered actual reductions")
	var units: Dictionary[StringName, UnitDefinition] = {}
	var text := BattleLogFormatter.describe(hit, units, null)
	expect("физический" in text and "6 (базовая атака) − 3 (гекс: Пар) − 1 (Броня) = 2." in text, "Combat log displays damage type and requested formula")
	target.statuses.clear()
	state.hex_grid.set_hex_state(target.hex, &"core:water")
	expect(BattleLogFormatter.describe(hit, units, null) == text, "Later status and terrain changes cannot alter historical formula")
	var ability := fixture.ability(&"test:ranged", AbilityDefinition.TargetMode.ENEMY)
	attacker.abilities[ability.id] = ability
	state.hex_grid.set_hex_state(target.hex, &"core:acid_vapour")
	var context := BattleEffectContext.new(state, ability.id)
	var events := context.apply_damage_events(attacker.unit_id, target.unit_id, 8, &"acid")
	hit = events[0] as UnitDamagedEvent
	expect(hit != null and hit.damage == 2 and hit.damage_modifiers == [{"source_id": &"core:acid_vapour", "amount": -6}], "Ability damage records acidic vapour protection")
	expect("кислотный" in BattleLogFormatter.describe(hit, units, null) and "умение:" in BattleLogFormatter.describe(hit, units, null), "Ability log names damage type and origin")
	# Each interaction is traced before the status is consumed or removed.
	for scenario: Dictionary in [
		{"type": &"fire", "status": &"core:wet", "levels": 2, "delta": -2, "final": 3},
		{"type": &"water", "status": &"core:burning", "levels": 2, "delta": -2, "final": 3},
		{"type": &"water", "status": &"core:plasma", "levels": 1, "delta": -5, "final": 0},
		{"type": &"electric", "status": &"core:wet", "levels": 2, "delta": 1, "final": 6},
		{"type": &"physical", "status": &"core:armor", "levels": 9, "delta": -5, "final": 0},
	]:
		var unit := fixture.unit(&"victim", BattleFaction.Value.ENEMY, Vector2i.ZERO)
		unit.statuses[scenario.status] = scenario.levels
		events.clear()
		UnitStatusService.damage(unit, 5, scenario.type, events)
		hit = events.back() as UnitDamagedEvent
		expect(hit != null and hit.calculated_damage == scenario.final and hit.damage_modifiers == [{"source_id": scenario.status, "amount": scenario.delta}], "Trace matches actual status interaction: %s/%s" % [scenario.type, scenario.status])
		var sum := hit.base_damage
		for modifier: Dictionary in hit.damage_modifiers:
			sum += int(modifier.amount)
		expect(sum == hit.calculated_damage and unit.health.current == 100 - hit.damage, "Trace arithmetic reconciles with actual health loss")
	var fragile := fixture.unit(&"fragile", BattleFaction.Value.ENEMY, Vector2i.ZERO, 2)
	events.clear()
	UnitStatusService.damage(fragile, 6, &"plasma", events, &"", &"core:plasma")
	hit = events.back() as UnitDamagedEvent
	expect(hit.base_damage == 6 and hit.calculated_damage == 6 and hit.damage == 2, "Overkill preserves calculated damage separately from health loss")
	text = BattleLogFormatter.describe(hit, units, null)
	expect("плазменный" in text and "гекс: Плазма" in text and "Снято 2 ОЗ" in text, "Log distinguishes overkill from damage absorption")
	events.clear()
	UnitStatusService.damage(target, 2, &"physical", events, attacker.unit_id, &"", &"", 3, &"", &"core:steam")
	hit = events.back() as UnitDamagedEvent
	expect(hit.damage == 0 and hit.damage_modifiers == [{"source_id": &"core:steam", "amount": -2}], "Protection records absorbed amount rather than unused capacity")


func _test_commands() -> void:
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state([p.hex, e.hex, Vector2i(2, 0)], [p, e])
	var engine := BattleEngine.new(state)
	var hp := e.health.current
	var revision := state.state_revision
	var invalid := engine.execute(AttackCommand.new(e.unit_id, p.unit_id))
	expect(not invalid.accepted and state.state_revision == revision and e.health.current == hp, "Rejected attack is side-effect free")
	var attack := engine.execute(AttackCommand.new(p.unit_id, e.unit_id))
	expect(attack.accepted and engine.get_active_unit_id() == e.unit_id, "Basic attack ends own turn")
	var ability := fixture.ability(&"core:test_ability", AbilityDefinition.TargetMode.ENEMY)
	p.abilities[ability.id] = ability
	engine.execute(EndTurnCommand.new(e.unit_id))
	var ability_result := engine.execute(UseAbilityCommand.new(p.unit_id, e.unit_id, ability.id))
	expect(ability_result.accepted and p.ability_cooldowns[ability.id] == 2, "Ability starts cooldown and ends turn")
	engine.execute(EndTurnCommand.new(e.unit_id))
	expect(engine.get_ability_target_hexes(p.unit_id, ability.id).is_empty(), "Cooldown one blocks next own turn")
	engine.execute(EndTurnCommand.new(p.unit_id))
	engine.execute(EndTurnCommand.new(e.unit_id))
	expect(not engine.get_ability_target_hexes(p.unit_id, ability.id).is_empty(), "Cooldown expires on following own turn")
	engine.set("_terminal_error", "Injected stopped state")
	var stopped_revision := state.state_revision
	expect(not engine.execute(EndTurnCommand.new(p.unit_id)).accepted, "Terminal engine rejects further commands")
	expect(not engine.apply_map_mutations([MapMutation.apply_hex_state(p.hex, &"core:fire")]).accepted and state.state_revision == stopped_revision, "Terminal engine rejects external mutations")
	var p2 := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 1)
	var e2 := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0), 1)
	state = fixture.state([p2.hex, e2.hex], [p2, e2])
	state.hex_grid.set_hex_state(p2.hex, &"core:fire")
	state.hex_grid.set_hex_state(e2.hex, &"core:fire")
	engine = BattleEngine.new(state)
	expect(engine.get_result() != null and engine.get_outcome() == BattleOutcome.Value.DEFEAT, "Simultaneous starting defeat preserves protected-faction policy")

func _test_content() -> void:
	var loaded := fixture.content()
	expect(loaded.is_successful, "All shipped packages and authored logic load: %s" % str(loaded.errors))
	if not loaded.is_successful:
		return
	var snapshot := loaded.snapshot
	var lock := snapshot.content_lock
	lock.packages[0].package_version = "changed"
	expect(snapshot.content_lock.packages[0].package_version != "changed", "Content lock detached from external callers")
	var laser := snapshot.get_ability_definition(&"core:laser")
	var cooldown := laser.initial_cooldown_turns
	laser.initial_cooldown_turns = 77
	expect(snapshot.get_ability_definition(laser.id).initial_cooldown_turns == cooldown, "Snapshot getter does not expose mutable ability")
	var unit := snapshot.get_all_unit_definitions()[0]
	var health := unit.base_stats.max_health
	unit.base_stats.max_health = 999
	expect(snapshot.get_unit_definition(unit.id).base_stats.max_health == health, "Nested stats detached from snapshot getters")
	expect(not snapshot.mod_api.register_effect_handler(&"test:damage", DamageEffectHandler.new()), "Snapshot effect registry frozen")
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"foreign"
	var foreign := UnitDefinition.new()
	foreign.id = &"foreign:unit"
	foreign.display_name = "Foreign"
	foreign.base_stats = UnitStatsDefinition.new()
	foreign.ability_ids.append(&"core:laser")
	package.units.append(foreign)
	var packages := GameContentSettings.read().content_packages.duplicate()
	packages.append(package)
	expect(not ContentLoader.load_packages(packages).is_successful, "Undeclared cross-package reference rejected")
	var hash_before := ContentLoader._create_lock_entry(package).content_hash
	foreign.base_stats.max_health += 1
	expect(ContentLoader._create_lock_entry(package).content_hash != hash_before, "Content fingerprint changes when stats change with same IDs")
	var dependency := ContentPackageDependency.new()
	dependency.package_id = &"core"
	package.manifest.dependencies.append(dependency)
	expect(ContentLoader.load_packages(packages).is_successful, "Declared cross-package reference accepted")
	var data := UnitLibrary.new_document()
	data.attack_range = 1
	data.image = "missing.png"
	expect(UnitLibrary.validate(data).is_empty(), "Melee range one and missing optional image allowed")
	data.image = "../outside.png"
	expect(not UnitLibrary.validate(data).is_empty(), "Unit image cannot leave asset folder")
	data = UnitLibrary.new_document()
	data.passives = ["core:fire_attack", "core:water_attack"]
	expect(not UnitLibrary.validate(data).is_empty(), "Conflicting basic damage types rejected")

func _test_documents() -> void:
	var request := fixture.request()
	expect(request != null, "Regression battle fixture loads")
	if request == null:
		return
	var document := BattleDocument.from_snapshot(request.content_snapshot, request.battle_id)
	expect(document.validate(request.content_snapshot).is_valid, "Valid document accepted")
	var data := BattleDocumentSerializer.to_dictionary(document)
	var roundtrip := BattleDocumentSerializer.from_dictionary(data)
	expect(roundtrip != null and BattleDocumentSerializer.to_dictionary(roundtrip) == data, "Document serialization round-trips")
	var bad := document.duplicate_document()
	bad.battle_definition.map_id = &"core:wrong_map"
	expect(not bad.validate(request.content_snapshot).is_valid and bad.create_start_request(request.content_snapshot, 1) == null, "Map mismatch rejected before startup")
	bad = document.duplicate_document()
	bad.battle_definition.primary_objective = null
	expect(not bad.validate(request.content_snapshot).is_valid, "Missing objective rejected by document validator")
	bad = document.duplicate_document()
	for cell: BattleMapCellDefinition in bad.map_definition.cells:
		if cell.hex == bad.battle_definition.unit_placements[0].start_hex:
			cell.traversable = false
	expect(not bad.validate(request.content_snapshot).is_valid, "Nontraversable placement rejected")
	bad = document.duplicate_document()
	bad.battle_definition.sides[0].faction = 99 as BattleFaction.Value
	expect(not bad.validate(request.content_snapshot).is_valid, "Unknown faction rejected")
	data.map.cells[0].q = 1.5
	expect(BattleDocumentSerializer.from_dictionary(data) == null, "Fractional hex coordinates rejected")
	var save_path := "user://review_regression_document_%d.json" % OS.get_process_id()
	expect(BattleDocumentSerializer.save(document, save_path).is_empty(), "Atomic document save succeeds")
	expect(BattleDocumentSerializer.load_result(save_path).document != null, "Saved document loads")
	DirAccess.remove_absolute(save_path)

func _test_ai_and_forecast() -> void:
	var request := fixture.request()
	if request == null:
		return
	var session := BattleSessionFactory.create(request).session
	var copied_setup := session.setup
	copied_setup.unit_spawns.clear()
	copied_setup.sides[0].side_id = &"changed"
	expect(not session.setup.unit_spawns.is_empty() and session.setup.sides[0].side_id != &"changed", "Session setup does not expose internal spawns or sides")
	var active := session.get_unit(session.get_active_unit_id())
	var opponent := session.get_living_opponents(active.faction)[0]
	var ability := fixture.ability(&"core:hex_only", AbilityDefinition.TargetMode.HEX)
	ability.range = 99
	# Synthetic query snapshot isolates the previously wrong command constructor.
	active.ability_ids = [ability.id]
	active.ability_area_radii[ability.id] = 0
	active.ability_target_modes[ability.id] = AbilityDefinition.TargetMode.HEX
	active.ability_hex_targets[ability.id] = true
	var source := AICommandSource.new(load("res://features/battle/definitions/debug_basic_enemy_ai.tres"))
	var state: BattleState = session.get("_state")
	state.unit_states[active.unit_id].abilities[ability.id] = ability
	var command := source._choose_ability_command(session, active, [opponent])
	expect(command is UseAbilityCommand and command.targets_hex, "AI emits hex command for zero-radius HEX ability")
	if command != null:
		expect(session.step(command).accepted, "Engine accepts AI zero-radius hex command")
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 2)
	p.statuses[&"core:wet"] = 6
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	grid.set_hex_state(Vector2i(1, 0), &"core:electricity")
	var forecast := MovementImpactForecast.evaluate(UnitSnapshot.new(p), grid, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	expect(forecast.lethal and not forecast.reached, "Forecast sees wet lethal electric crossing")
	expect(p.health.current == 2 and p.statuses[&"core:wet"] == 6, "Forecast does not mutate actual unit")
	p = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 100, 3)
	grid.set_hex_state(Vector2i(1, 0), &"core:oil")
	forecast = MovementImpactForecast.evaluate(UnitSnapshot.new(p), grid, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	expect(not forecast.reached, "Forecast sees oil shortening route")
	p = fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 1, 1)
	p.status_immunities.append(&"core:burning")
	p.statuses[&"core:wet"] = 4
	grid.set_hex_state(Vector2i(1, 0), &"core:fire")
	var search := MovementService.search(grid, p.hex, 1, {})
	var chosen := EnemyBrain.choose_move(p.unit_id, p.hex, Vector2i(2, 0), search, grid, 1, 1, UnitSnapshot.new(p))
	expect(chosen != null and chosen.destination == Vector2i(1, 0), "AI accepts fire crossing protected by wet and burning immunity")

func _ai_session(state: BattleState) -> BattleSession:
	state.turn_service.start()
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	return BattleSession.new(setup, state, BattleEngine.new(state, false), null)


func _test_doomed_ai() -> void:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var enemy := fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 3)
	enemy.statuses[&"core:electrified"] = 4
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	var session := _ai_session(fixture.state(cells, [enemy, player]))
	var source := AICommandSource.new(null)
	source.decision_trace = {}
	var before := JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state()))
	var command := source.next_command(session)
	expect(command is MoveCommand and command.destination == Vector2i(2, 0), "Doomed unit moves into attack range before end-of-turn death")
	expect(source.decision_trace.reason == "doomed_maximum_damage", "Doomed damage plan is explained in AI trace")
	expect(before == JSON.stringify(BattleLogSerializer.encode(session.get_diagnostic_state())), "Speculative actions do not mutate live units, map, turns, revisions or RNG")
	expect(session.step(command).accepted and enemy.health.current == 1, "Doomed movement survives until action")
	command = source.next_command(session)
	expect(command is AttackCommand and command.target_id == player.unit_id, "Doomed unit attacks after approaching")
	var resolution := session.step(command)
	expect(resolution.accepted and player.health.current == 18 and enemy.health.is_defeated(), "Attack damages opponent before actor dies at end of turn")

	# Maximize actual HP removed, even if a nearer target is already attackable.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 4)
	enemy.basic_attack_damage = 7
	enemy.statuses[&"core:electrified"] = 4
	var armored := fixture.unit(&"armor", BattleFaction.Value.PLAYER, Vector2i(1, 0), 20)
	armored.statuses[&"core:armor"] = 6
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	var detour: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 0), Vector2i(3, 0)]
	session = _ai_session(fixture.state(detour, [enemy, armored, player]))
	var plan := AILastActionPlanner.plan(session)
	expect(plan.command is MoveCommand and plan.enemy_damage == 7 and plan.followup_command is AttackCommand and plan.followup_command.target_id == player.unit_id, "Doomed AI prefers 7 damage after movement over 1 damage to adjacent armor")

	# Abilities compete with ordinary attacks using the real executor and cooldown legality.
	var blast := fixture.ability(&"core:last_blast", AbilityDefinition.TargetMode.HEX, 0)
	blast.effects[0].parameters.amount = 9
	enemy.abilities[blast.id] = blast
	enemy.ability_cooldowns[blast.id] = 0
	plan = AILastActionPlanner.plan(session)
	expect(plan.command is UseAbilityCommand and plan.enemy_damage == 9, "Doomed AI chooses a damaging ability over weaker ordinary attack")
	enemy.ability_cooldowns[blast.id] = 2
	plan = AILastActionPlanner.plan(session)
	expect(plan.enemy_damage == 7 and plan.followup_command is AttackCommand, "Last-action planner respects ability cooldown")
	enemy.ability_cooldowns[blast.id] = 0
	enemy.abilities.erase(blast.id)
	var ignition := fixture.ability(&"core:ignite_oil", AbilityDefinition.TargetMode.HEX)
	ignition.effects[0].effect_type_id = &"core:unit_status"
	ignition.effects[0].parameters = {"status_id": &"core:burning", "levels": 1}
	enemy.abilities[ignition.id] = ignition
	player.statuses[&"core:sticky_oil"] = 9
	plan = AILastActionPlanner.plan(session)
	expect(plan.command is UseAbilityCommand and plan.enemy_damage == 10, "Status-only ignition competes via real immediate oil explosion damage")
	player.statuses.clear()
	enemy.abilities.erase(ignition.id)
	blast.area_radius = 10
	enemy.abilities[blast.id] = blast
	var ally := fixture.unit(&"ally", BattleFaction.Value.ENEMY, Vector2i(3, -1), 20)
	session.get("_state").unit_states[ally.unit_id] = ally
	session.get("_state").hex_grid.add_cell(ally.hex, &"core:default", 1, true)
	plan = AILastActionPlanner.plan(session)
	expect(plan.followup_command is AttackCommand, "Doomed planner rejects stronger area attack hitting a living ally")
	enemy.abilities.erase(blast.id)

	# No action is in reach: advance instead of dying in place.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 1)
	enemy.statuses[&"core:electrified"] = 4
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(4, 0), 20)
	session = _ai_session(fixture.state(cells, [enemy, player]))
	plan = AILastActionPlanner.plan(session)
	expect(plan.command is MoveCommand and plan.command.destination == Vector2i(1, 0) and plan.reason == "doomed_advance_toward_enemy", "Doomed AI advances when no damage can be dealt this turn")
	expect(session.step(plan.command).accepted, "Desperate approach is a legal command")

	# A safe option keeps normal survival policy, while route death cannot promise an attack.
	enemy.statuses.clear()
	expect(AILastActionPlanner.plan(session).is_empty(), "Living unit does not enter desperate policy")
	enemy.statuses[&"core:electrified"] = 4
	var state: BattleState = session.get("_state")
	state.hex_grid.set_hex_state(Vector2i(2, 0), &"core:fire")
	plan = AILastActionPlanner.plan(session)
	expect(plan.command is EndTurnCommand, "No movement is issued when no reachable progress remains")

	# A lethal crossing is excluded from maximum-damage plans.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 3)
	enemy.statuses[&"core:electrified"] = 2
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(3, 0), 20)
	state = fixture.state(cells, [enemy, player])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:acid")
	session = _ai_session(state)
	plan = AILastActionPlanner.plan(session)
	expect(plan.reason != "doomed_maximum_damage", "Unit dying on route is never scored as reaching an attack")
	var predicted := session.create_prediction_engine()
	predicted.get_unit(enemy.unit_id).statuses.clear()
	predicted.get_unit(enemy.unit_id).abilities.clear()
	expect(enemy.statuses.get(&"core:electrified", 0) == 2, "Forecast runtime collections are independent")

	# A fire victim can save itself in water: desperate mode must not override that option.
	enemy = fixture.unit(&"doomed", BattleFaction.Value.ENEMY, Vector2i.ZERO, 1, 1)
	enemy.statuses[&"core:burning"] = 2
	player = fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i(4, 0), 20)
	state = fixture.state(cells, [enemy, player])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:water")
	session = _ai_session(state)
	expect(AILastActionPlanner.plan(session).is_empty(), "Reachable water survival preserves ordinary safe movement policy")
	command = source.next_command(session)
	expect(command is MoveCommand and command.destination == Vector2i(1, 0), "Normal policy uses the safe water route")

	# Reuse record 43 geometry/statuses with 1 HP to retain lethal fixed-damage coverage.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://features/battle/tests/fixtures/chudishcherog_doomed_state.json"))
	var participants: Dictionary[StringName, UnitState] = {}
	var order: Array[StringName] = []
	var map_cells: Array[Vector2i] = []
	for cell: Dictionary in data.grid.cells:
		map_cells.append(Vector2i(int(cell.hex.x), int(cell.hex.y)))
	for unit: Dictionary in data.units:
		var value := fixture.unit(StringName(unit.unit_id), int(unit.faction) as BattleFaction.Value, Vector2i(int(unit.hex.x), int(unit.hex.y)), int(unit.health.maximum), int(unit.turn.movement_max))
		value.health.current = int(unit.health.current)
		value.turn.movement_remaining = int(unit.turn.movement_remaining)
		value.turn.main_action_available = bool(unit.turn.main_action_available)
		value.turns_started = int(unit.turns_started)
		value.basic_attack_damage = int(unit.basic_attack_damage)
		value.basic_attack_range = int(unit.basic_attack_range)
		value.basic_attack_damage_type = StringName(unit.basic_attack_damage_type)
		for id: String in unit.statuses:
			value.statuses[StringName(id)] = int(unit.statuses[id])
		for id: String in unit.basic_attack_statuses:
			value.basic_attack_statuses[StringName(id)] = int(unit.basic_attack_statuses[id])
		for id: String in unit.status_immunities:
			value.status_immunities.append(StringName(id))
		participants[value.unit_id] = value
	for id: String in data.turn_order:
		order.append(StringName(id))
	state = BattleState.new(&"core:logged_doom", HexGrid.new(map_cells), participants, order, ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "Defeat enemies"), BattleFaction.Value.PLAYER), 1)
	for cell: Dictionary in data.grid.cells:
		var hex := Vector2i(int(cell.hex.x), int(cell.hex.y))
		state.hex_grid.set_hex_state(hex, StringName(cell.state_id))
		state.hex_grid.set_traversal(hex, bool(cell.traversable), int(cell.movement_cost))
	session = _ai_session(state)
	while state.turn_service.get_round_number() != int(data.round) or state.turn_service.get_active_unit_id() != StringName(data.active_unit_id):
		state.turn_service.advance_turn()
	state.random.state = int(data.rng_state)
	participants[StringName(data.active_unit_id)].health.current = 1
	source.decision_trace = {}
	command = source.next_command(session)
	expect(command is MoveCommand and source.decision_trace.reason == "doomed_maximum_damage", "Recorded Chudishcherog state now produces a last attack approach instead of EndTurn")
	expect(session.step(command).accepted, "Recorded last attack approach executes legally")
	command = source.next_command(session)
	expect(command is AttackCommand and command.target_id == &"plateau:battle:author:placement_1", "Recorded Chudishcherog reaches Tesla for an attack")
	resolution = session.step(command)
	expect(resolution.accepted and participants[&"plateau:battle:author:placement_1"].health.current == 0, "Recorded Chudishcherog deals remaining 3 HP of damage to Tesla before dying")
	expect(participants[&"plateau:battle:author:placement_4"].health.is_defeated(), "Recorded Chudishcherog still obeys lethal end-of-turn status rules")


func _test_summon_control() -> void:
	var request := fixture.request()
	if request == null:
		return
	var session := BattleSessionFactory.create(request).session
	var state: BattleState = session.get("_state")
	var active := state.unit_states[session.get_active_unit_id()] as UnitState
	var ability := request.content_snapshot.get_ability_definition(&"core:electric_turret")
	active.abilities[ability.id] = ability
	var targets := session.get_ability_target_hexes(active.unit_id, ability.id)
	expect(not targets.is_empty(), "Summon has an empty target")
	if targets.is_empty():
		return
	var result := session.step(UseAbilityCommand.at_hex(active.unit_id, targets[0], ability.id))
	var summoned := StringName()
	for event: BattleEvent in result.events:
		if event is UnitSummonedEvent:
			summoned = event.unit.unit_id
	expect(result.accepted and not summoned.is_empty(), "Summon creates registered participant")
	var side_ids: Dictionary = session.get("_unit_side_ids")
	var profile := request.content_snapshot.get_ai_profile_definition(&"core:basic_enemy_ai")
	expect(session.set_side_command_source(side_ids[active.unit_id], AICommandSource.new(profile)), "Can change side command source after summon")
	expect(session.is_unit_ai_controlled(summoned), "Summon follows changed side control")

func _test_simulation() -> void:
	var request := fixture.request()
	if request == null:
		return
	var profile := request.content_snapshot.get_ai_profile_definition(&"core:basic_enemy_ai")
	var run := SimulationRunner.new().run(SimulationRequest.new(request, profile, 1, 100))
	expect(run.status == SimulationRunStatus.Value.LIMIT_REACHED or run.status == SimulationRunStatus.Value.COMPLETED, "Simulation has explicit bounded result")
	var deterministic_a := SimulationRunner.new().run(SimulationRequest.new(request, profile, 500, 100))
	var deterministic_b := SimulationRunner.new().run(SimulationRequest.new(request, profile, 500, 100))
	expect(deterministic_a.status == deterministic_b.status and deterministic_a.command_count == deterministic_b.command_count and deterministic_a.round_number == deterministic_b.round_number, "Same seed and content produce same simulation summary")
	expect(deterministic_a.status == SimulationRunStatus.Value.COMPLETED, "Regression battle completes in headless simulation")
	var campaign_packages: Array[ContentPackage] = [load("res://content/packages/core/core_package.tres"), load("res://content/packages/ember_pack/ember_pack.tres")]
	var content := ContentLoader.load_packages(campaign_packages).snapshot
	var campaign := CampaignSession.create(content, &"ember_pack:two_battles")
	expect(campaign != null, "Core campaign can be created")
	if campaign != null:
		var unfinished := BattleResult.new(campaign.get_current_battle_id(), 7, BattleOutcome.Value.IN_PROGRESS, 1, null)
		var current := campaign.current_scenario_id
		expect(not campaign.complete_battle(unfinished).accepted and campaign.current_scenario_id == current and campaign.completed_scenario_ids.is_empty(), "Campaign refuses unfinished battle without changing progress")
	var token := SimulationCancellationToken.new()
	token.cancel()
	run = SimulationRunner.new().run(SimulationRequest.new(request, profile, 100, 100, token))
	expect(run.status == SimulationRunStatus.Value.CANCELLED, "Cancellation before start respected")
	var speed := BattlePlaybackSettings.new()
	expect(not speed.set_speed(NAN) and not speed.set_speed(INF) and not speed.set_speed(0), "Nonfinite and nonpositive speeds rejected")

func _test_presentation() -> void:
	var scene := load("res://features/battle/battle_screen.tscn") as PackedScene
	var screen := scene.instantiate() as BattleScreen
	var request := fixture.request(true)
	if request == null:
		screen.free()
		return
	expect(screen.setup(request), "BattleScreen accepts validated request")
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var controller := screen.get_node("BattleMap/BattleController") as BattleController
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	hud.show_target("Test", null, "Противник", 10, 20, 2, 1, 4, 4, true, {&"core:burning": 2})
	expect("Нет активных эффектов" not in (hud.get("_target_effects_label") as Label).text, "Target HUD displays actual statuses")
	hud.set_interaction_enabled(false)
	expect(not (hud.get("_speed_4_button") as Button).disabled, "Playback speed remains available during presentation")
	var log_panel := hud.get_node("HUDRoot/BattleLogPanel") as PanelContainer
	var log_button := hud.get_node("HUDRoot/BattleLogButton") as Button
	var log_entries := hud.get_node("HUDRoot/BattleLogPanel/Content/Entries") as RichTextLabel
	expect(not log_panel.visible and not log_button.button_pressed, "Battle log starts hidden")
	var before_log := log_entries.get_parsed_text()
	hud.append_battle_log("Hidden event [b]plain text[/b]")
	log_button.button_pressed = true
	expect(log_panel.visible and "Hidden event [b]plain text[/b]" in log_entries.get_parsed_text(), "Opening log retains hidden events as literal text")
	expect(not log_button.disabled, "Log is available during presentation")
	log_button.button_pressed = false
	log_button.button_pressed = true
	expect(log_entries.get_parsed_text() == before_log + "Hidden event [b]plain text[/b]\n", "Toggling log preserves history without duplicate entries")
	expect(log_panel.get_global_rect().end.x < (hud.get_node("HUDRoot/StrategistPanel") as Control).get_global_rect().position.x, "Log is to the left of round information")
	var logged_round: int = hud.get("_logged_round")
	var before_round := log_entries.get_parsed_text()
	hud.log_round(logged_round)
	expect(log_entries.get_parsed_text() == before_round, "Repeated round refresh does not duplicate its heading")
	var log_units: Dictionary[StringName, UnitDefinition] = {}
	var victim := UnitDefinition.new()
	victim.display_name = "Victim"
	log_units[&"victim"] = victim
	var damage := UnitDamagedEvent.new(&"source", &"victim", 4, 0, true)
	damage.source_status_id = &"core:burning"
	var damage_text := BattleLogFormatter.describe(damage, log_units, null)
	expect(UnitStatusCatalog.display_name(&"core:burning") in damage_text and "Victim" in damage_text and "4" in damage_text and "погибает" in damage_text, "Damage log identifies periodic source, damage and defeat")
	var status_unit := fixture.unit(&"victim", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	var status_text := BattleLogFormatter.describe(UnitStatusChangedEvent.new(status_unit, {&"core:burning": 1}), log_units, null)
	expect("снят" in status_text, "Log reports removed statuses")
	controller.set("_is_presenting", true)
	var revision := (controller.get("_battle_session") as BattleSession).get_state_revision()
	var rejected: BattleResolution = await controller.apply_map_mutations([MapMutation.apply_hex_state(Vector2i.ZERO, &"core:fire")])
	expect(not rejected.accepted and (controller.get("_battle_session") as BattleSession).get_state_revision() == revision, "Concurrent public mutation rejected without state changes")
	controller.set("_is_presenting", false)
	var map := screen.get_node("BattleMap") as BattleMapView
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0)])
	grid.set_traversal(Vector2i(1, 0), false, 1)
	map.render_grid(grid)
	var markers := map.get_node("TerrainProperties") as Node2D
	expect(markers.get_child_count() > 0, "Blocked terrain receives visible markers")
	expect(markers.get_child_count() == 1, "Plain cells receive no marker nodes")
	var marker_labels := markers.find_children("*", "Label", true, false)
	var upright := (marker_labels[0] as Label).scale * map.scale if not marker_labels.is_empty() else Vector2.ZERO
	expect(not marker_labels.is_empty() and is_equal_approx(upright.x, upright.y), "Marker text keeps upright proportions on the scaled board")
	var hex_state_art := map.get_node("HexStateVisuals") as Node2D
	expect(markers.z_index == hex_state_art.z_index and markers.get_index() > hex_state_art.get_index(), "Markers draw above hex-state art")
	var selected: Array[Vector2i] = []
	var router := screen.get_node("BattleMap/BattleInputRouter") as BattleInputRouter
	router.setup(grid)
	router.hex_selected.connect(func(hex: Vector2i) -> void: selected.append(hex))
	router.set_interaction_enabled(true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map.get_canvas_transform() * map.hex_to_global_position(Vector2i.ZERO)
	router.set("_has_hovered_hex", false)
	router.call("_unhandled_input", click)
	expect(selected.size() == 1 and selected[0] == Vector2i.ZERO, "Click computes fresh hex without prior hover")
	# Failure injection exercises complete state restore without emitting a test error log.
	controller.battle_failed.disconnect(screen._on_battle_failed)
	var failure_count := [0]
	controller.battle_failed.connect(func(_message: String) -> void: failure_count[0] += 1)
	var bad := BattleResolution.success([], revision, "", null)
	bad.terminal_error = "Injected terminal failure"
	var stopped: bool = await controller.call("_present_resolution", bad, controller.get("_unit_actors"), controller.get("_unit_views").definitions, map, hud)
	expect(not stopped and controller.get("_runtime_failed"), "Terminal failure stops graphical playback")
	expect(map.get_node("TerrainLayer").get_used_cells().size() == (controller.get("_battle_session") as BattleSession).get_hex_grid().get_cells().size(), "Failure repairs full visual map from authoritative grid")
	controller.call("_fail_runtime", "Repeated failure")
	expect(failure_count[0] == 1, "Failure emitted exactly once")
	var parent := Node2D.new()
	var actor := Node2D.new()
	var sprite := Sprite2D.new()
	get_tree().root.add_child(parent)
	parent.add_child(actor)
	actor.add_child(sprite)
	var animator := UnitMovementAnimator.new()
	var profile := UnitMovementProfile.new()
	profile.seconds_per_hex = 0.05
	var tween := animator.create_motion(actor, sprite, [Vector2(100, 0)], profile)
	parent.scale = Vector2(2, 3)
	parent.position = Vector2(20, 10)
	await tween.finished
	expect(actor.position.is_equal_approx(Vector2(100, 0)) and actor.global_position.is_equal_approx(Vector2(220, 10)), "Movement follows resized/transformed battlefield parent")
	parent.queue_free()
	screen.queue_free()
	await get_tree().process_frame

func _test_editor() -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	get_tree().root.add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var document: BattleDocument = editor.get("_document")
	expect(document != null, "Editor loads configured document")
	if document != null:
		expect(not editor.has_unsaved_changes(), "Loaded editor document is clean")
		var original_name := document.battle_definition.primary_objective.description
		document.battle_definition.primary_objective.description = "Unsaved change"
		var called := [false]
		editor.call("_guard_discard", func() -> void: called[0] = true)
		expect(not called[0] and editor.has_unsaved_changes(), "Unsaved document is not replaced before confirmation")
		editor.call("_confirm_discard")
		expect(called[0], "Confirmed discard executes pending action")
		document.battle_definition.primary_objective.description = original_name
		var occupied := document.battle_definition.unit_placements[0].start_hex
		editor.call("_select_hex", occupied)
		(editor.get("_traversable_check") as CheckButton).button_pressed = false
		editor.call("_apply_selected_hex")
		expect((editor.call("_find_cell", occupied) as BattleMapCellDefinition).traversable, "Editor cannot block occupied cell")
		editor.set("_document", null)
		(editor.get("_side_option") as OptionButton).clear()
		editor.call("_reload_unit_library")
		expect((editor.get("_side_option") as OptionButton).item_count > 0, "Recovery populates sides")
		var settings := GameContentSettings.read()
		var expected := BattleDocumentSerializer.load_result(settings.battle_document_path).document
		expect((editor.get("_document") as BattleDocument).document_id == expected.document_id, "Recovery loads configured document rather than debug battle")
	editor.queue_free()
	await get_tree().process_frame


func _test_properties() -> void:
	for seed in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var cells: Array[Vector2i] = []
		var costs: Dictionary[Vector2i, int] = {}
		for q in range(-2, 3):
			for r in range(-2, 3):
				var hex := Vector2i(q, r)
				if hex == Vector2i.ZERO or rng.randf() > 0.2:
					cells.append(hex)
					costs[hex] = rng.randi_range(1, 4)
		var grid := HexGrid.new(cells, costs)
		var budget := rng.randi_range(1, 10)
		var movement := MovementService.search(grid, Vector2i.ZERO, budget, {})
		for destination: Vector2i in movement.get_reachable_cells():
			var path := movement.build_path(destination)
			var paid := 0
			var connected: bool = not path.is_empty() and path[0] == Vector2i.ZERO and path.back() == destination
			for index in range(1, path.size()):
				connected = connected and grid.has_cell(path[index]) and HexGrid.get_distance(path[index - 1], path[index]) == 1
				paid += grid.get_movement_cost(path[index])
			expect(connected and paid <= budget and paid == movement.get_cost(destination), "Seed %d: reachable route obeys geometry and weighted budget" % seed)


## Regressions for the 2026-10-05 second review: engine, terrain batches, content and previews.
func _test_review_fixes() -> void:
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var e := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var dead := fixture.unit(&"x", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	dead.health.current = 0
	var registry: Dictionary[StringName, UnitState] = {}
	for participant: UnitState in [p, e, dead]:
		registry[participant.unit_id] = participant
	var order: Array[StringName] = [dead.unit_id]
	var cells: Array[Vector2i] = [p.hex, e.hex, dead.hex]
	var objectives := ObjectiveSystem.new(EliminateFactionObjective.new(BattleFaction.Value.ENEMY, "Defeat enemies"), BattleFaction.Value.PLAYER)
	var stuck := BattleState.new(&"core:test", HexGrid.new(cells), registry, order, objectives, 7)
	expect(not BattleEngine.new(stuck).get_initial_resolution().terminal_error.is_empty(), "Initial resolution reports a turn order that cannot start")

	var state := fixture.state([Vector2i.ZERO, Vector2i(1, 0)])
	state.hex_grid.set_hex_state(Vector2i.ZERO, &"core:electricity")
	var unchanged := MapMutationService.apply(state, [MapMutation.apply_hex_state(Vector2i.ZERO, &"core:electricity")])
	expect(unchanged.accepted and unchanged.events.is_empty() and state.map_revision == 0 and state.state_revision == 0, "Unchanged terrain keeps map and state revisions")
	expect(HexStateCatalog.get_damage_type(&"core:acid_vapour") == &"acid" and HexStateCatalog.get_damage_type(&"core:steam") == &"physical", "Hex damage types are explicit")

	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var user := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i(2, 0))
	var enemy := fixture.unit(&"e", BattleFaction.Value.ENEMY, Vector2i(5, 0))
	state = fixture.state([a, b, user.hex, enemy.hex], [user, enemy])
	state.hex_grid.set_hex_state(a, &"core:fire")
	state.hex_grid.set_hex_state(b, &"core:fire")
	var ability := fixture.ability(&"core:test_field", AbilityDefinition.TargetMode.HEX, 1)
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:hex_state"
	effect.parameters = {"state_id": "core:electricity"}
	ability.effects.assign([effect])
	user.abilities[ability.id] = ability
	var used := BattleEngine.new(state).execute(UseAbilityCommand.at_hex(user.unit_id, a, ability.id))
	expect(used.accepted and state.hex_grid.get_hex_state_id(a) == &"core:plasma" and state.hex_grid.get_hex_state_id(b) == &"core:plasma", "Area terrain ability resolves through one handler batch")
	var counting := CountingHexHandler.new()
	var hexes: Array[Vector2i] = [a, b]
	counting.execute_hexes(effect, null, &"", hexes)
	expect(counting.calls == 2, "Default handler batch still resolves every cell")

	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var ember: ContentPackage = load("res://content/packages/ember_pack/ember_pack.tres")
	var invalid := ContentLoader.load_packages([core, ember, _review_campaign_package(true)])
	var joined := "\n".join(invalid.errors)
	expect(not invalid.is_successful and "several transitions" in joined and "outside campaign" in joined, "Campaign rejects ambiguous outcomes and routes outside its scenarios")
	expect(ContentLoader.load_packages([core, ember, _review_campaign_package(false)]).is_successful, "Closed campaign graph loads")

	var request := fixture.request()
	if request != null:
		var session := BattleSessionFactory.create(request).session
		expect(session.get_battle_id() == request.battle_id and session.get_deterministic_seed() == request.deterministic_seed, "Session exposes identity without copying setup")
		var document := BattleDocument.from_snapshot(request.content_snapshot, request.battle_id)
		document.battle_definition.unit_placements[0].modifiers = {"bonus": 1}
		var validation := document.validate(request.content_snapshot)
		expect(validation.is_valid and not validation.warnings.is_empty(), "Reserved placement fields produce a warning")

	var presented := fixture.request(true)
	if presented != null:
		var snapshot := presented.content_snapshot
		var battle := snapshot.get_battle_definition(presented.battle_id)
		var definition := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		var first_copy := snapshot.get_unit_presentation_definition(definition.presentation_id)
		var second_copy := snapshot.get_unit_presentation_definition(definition.presentation_id)
		var bounds := first_copy.visible_rect()
		var cached := UnitPresentationDefinition._alpha_bounds_by_texture.size()
		expect(first_copy != second_copy and first_copy.actor_texture == second_copy.actor_texture, "Presentation copies share imported textures")
		expect(second_copy.visible_rect() == bounds and UnitPresentationDefinition._alpha_bounds_by_texture.size() == cached, "Presentation copies reuse texture alpha bounds")

	var hex_preview := HexStatusPreview.create_request()
	expect(hex_preview != null, "Hex status preview request builds")
	if hex_preview != null:
		var snapshot := hex_preview.content_snapshot
		var battle := snapshot.get_battle_definition(hex_preview.battle_id)
		var map := snapshot.get_map_definition(battle.map_id)
		var states_on_starts := 0
		for placement: UnitPlacementDefinition in battle.unit_placements:
			for cell: BattleMapCellDefinition in map.cells:
				if cell.hex == placement.start_hex and not cell.hex_state_id.is_empty():
					states_on_starts += 1
		var first_unit := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		expect(states_on_starts == battle.unit_placements.size(), "Hex status preview puts a state under every unit")
		expect(first_unit.base_stats.armor_levels == 3 and first_unit.ability_ids.has(&"core:create_fire"), "Hex status preview applies armor and creation abilities")
		expect(BattleSessionFactory.create(hex_preview).is_successful, "Hex status preview battle starts")

	var damage_preview := DamageAbilityPreview.create_request()
	expect(damage_preview != null, "Damage preview request builds")
	if damage_preview != null:
		var snapshot := damage_preview.content_snapshot
		var battle := snapshot.get_battle_definition(damage_preview.battle_id)
		var unit := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		expect(snapshot.get_ability_definition(&"core:laser").initial_cooldown_turns == 1 and unit.ability_ids.has(&"core:laser") and battle.unit_placements.back().placement_id == &"preview:turret", "Damage preview applies its overrides")
		expect(BattleSessionFactory.create(damage_preview).is_successful, "Damage preview battle starts")


func _review_campaign_package(broken: bool) -> ContentPackage:
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"review"
	for dependency_id: StringName in [&"core", &"ember_pack"]:
		var dependency := ContentPackageDependency.new()
		dependency.package_id = dependency_id
		package.manifest.dependencies.append(dependency)
	var first := _review_scenario(&"review:first", &"ember_pack:crossing_battle")
	var second := _review_scenario(&"review:second", &"ember_pack:ash_gate_battle")
	var outside := _review_scenario(&"review:outside", &"ember_pack:ash_gate_battle")
	first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, second.id))
	first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.DEFEAT, &""))
	if broken:
		first.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, outside.id))
	second.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, outside.id if broken else &""))
	outside.transitions.append(_review_transition(ScenarioTransitionDefinition.Outcome.VICTORY, &""))
	package.scenarios.assign([first, second, outside])
	var campaign := CampaignDefinition.new()
	campaign.id = &"review:campaign"
	campaign.entry_scenario_id = first.id
	campaign.scenario_ids.assign([first.id, second.id])
	package.campaigns.append(campaign)
	return package


func _review_scenario(id: StringName, battle_id: StringName) -> ScenarioDefinition:
	var scenario := ScenarioDefinition.new()
	scenario.id = id
	scenario.battle_id = battle_id
	return scenario


func _review_transition(outcome: ScenarioTransitionDefinition.Outcome, target: StringName) -> ScenarioTransitionDefinition:
	var transition := ScenarioTransitionDefinition.new()
	transition.outcome = outcome
	transition.target_scenario_id = target
	transition.ends_campaign = target.is_empty()
	return transition


## Editor regressions: drawing cache, window closing with an embedded unit editor, stopped trials.
func _test_review_fixes_ui() -> void:
	var editor := (load("res://tools/battles/battle_editor.tscn") as PackedScene).instantiate() as BattleEditorShell
	get_tree().root.add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var document: BattleDocument = editor.get("_document")
	expect(document != null, "Editor loads configured document for review checks")
	if document == null:
		editor.queue_free()
		await get_tree().process_frame
		return

	var view := editor.get("_view") as EditorBattleView
	var definition_id := document.battle_definition.unit_placements[0].definition_id
	var presentation: UnitPresentationDefinition = view.call("_presentation_for", definition_id)
	expect(presentation != null and view.call("_presentation_for", definition_id) == presentation, "Editor drawing resolves presentations once per snapshot")

	editor.call("_open_unit_editor")
	await get_tree().process_frame
	var unit_editor := editor.get("_unit_editor") as UnitEditor
	expect(unit_editor != null, "Battle editor tracks the embedded unit editor")
	if unit_editor != null:
		var draft: Dictionary = unit_editor.get("_document")
		draft["name"] = "Unsaved review draft"
		var unit_confirm := unit_editor.get("_confirm") as ConfirmationDialog
		unit_editor.notification(NOTIFICATION_WM_CLOSE_REQUEST)
		expect(not unit_confirm.visible, "Embedded unit editor leaves window closing to its host")
		editor.request_quit()
		expect(unit_confirm.visible and not (editor.get("_discard_dialog") as ConfirmationDialog).visible, "Closing the window asks the embedded unit editor first")
		unit_confirm.hide()
		unit_editor.set("_pending", Callable())
		unit_editor.set("_document", (unit_editor.get("_saved") as Dictionary).duplicate(true))
		unit_editor.call("_leave")
		await get_tree().process_frame
		expect(editor.get("_unit_editor") == null, "Closed unit editor is released")

	editor.call("_start_trial")
	var trial := editor.get("_trial_screen") as BattleScreen
	expect(trial != null, "Trial starts from the configured document")
	if trial != null:
		if not trial.has_started():
			await trial.battle_started
		trial.battle_failed.emit("Injected runtime failure")
		var layer := editor.get("_trial_return_layer") as CanvasLayer
		expect(editor.get("_trial_screen") == trial and layer != null and layer.has_node("TrialError"), "Stopped trial stays visible with its error")
		editor.call("_return_from_trial")
		expect((editor.get("_status") as Label).text.contains("остановлен ошибкой"), "Editor status reports the stopped trial")
	editor.queue_free()
	await get_tree().process_frame
