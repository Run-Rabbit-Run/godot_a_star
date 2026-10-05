extends Node

var fixture = preload("res://features/battle/tests/regression_fixtures.gd").new()
var checks := 0
var failures: Array[String] = []
var only := ""

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
	if only.is_empty() or only == "commands":
		_test_commands()
	if only.is_empty() or only == "content":
		_test_content()
	if only.is_empty() or only == "documents":
		_test_documents()
	if only.is_empty() or only == "ai_and_forecast":
		_test_ai_and_forecast()
	if only.is_empty() or only == "summon_control":
		_test_summon_control()
	if only.is_empty() or only == "simulation":
		_test_simulation()
	if only.is_empty() or only == "presentation":
		await _test_presentation()
	if only.is_empty() or only == "editor":
		await _test_editor()
	await get_tree().process_frame
	await get_tree().process_frame
	expect(checks > 0, "Requested test group exists and completed checks")
	for failure: String in failures:
		printerr("FAIL: ", failure)
	print("A_star regressions: %d checks, %d failures" % [checks, failures.size()])
	get_tree().create_timer(0.1).timeout.connect(get_tree().quit.bind(0 if failures.is_empty() else 1))
	queue_free()

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
	expect(unit.health.current == 96 and unit.statuses.get(&"core:wet", 0) == 3, "Wet amplifies electric damage without decay")
	UnitStatusService.damage(unit, 2, &"fire", events)
	expect(unit.health.current == 96 and unit.statuses.get(&"core:wet", 0) == 1, "Wet absorbs fire one-to-one")
	UnitStatusService.apply(unit, &"core:plasma", 2, events)
	expect(not unit.statuses.has(&"core:wet"), "Plasma removes wet")
	UnitStatusService.damage(unit, 8, &"water", events)
	expect(unit.health.current == 96, "Plasma blocks water damage")
	unit.status_immunities.append(&"core:burning")
	UnitStatusService.apply(unit, &"core:burning", 2, events)
	expect(not unit.statuses.has(&"core:burning"), "Burning immunity blocks only status")
	UnitStatusService.damage(unit, 2, &"fire", events)
	expect(unit.health.current == 94, "Status immunity is not damage immunity")
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
	expect(request != null, "Configured authored battle loads")
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
	var p := fixture.unit(&"p", BattleFaction.Value.PLAYER, Vector2i.ZERO, 5)
	p.statuses[&"core:wet"] = 6
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	grid.set_hex_state(Vector2i(1, 0), &"core:electricity")
	var forecast := MovementImpactForecast.evaluate(UnitSnapshot.new(p), grid, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	expect(forecast.lethal and not forecast.reached, "Forecast sees wet lethal electric crossing")
	expect(p.health.current == 5 and p.statuses[&"core:wet"] == 6, "Forecast does not mutate actual unit")
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
	expect(deterministic_a.status == SimulationRunStatus.Value.COMPLETED, "Configured authored battle completes in headless simulation")
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
	controller.set("_is_presenting", true)
	var revision := (controller.get("_battle_session") as BattleSession).get_state_revision()
	var rejected: BattleResolution = await controller.apply_map_mutations([MapMutation.apply_hex_state(Vector2i.ZERO, &"core:fire")])
	expect(not rejected.accepted and (controller.get("_battle_session") as BattleSession).get_state_revision() == revision, "Concurrent public mutation rejected without state changes")
	controller.set("_is_presenting", false)
	var map := screen.get_node("BattleMap") as BattleMapView
	var grid := HexGrid.new([Vector2i.ZERO, Vector2i(1, 0)])
	grid.set_traversal(Vector2i(1, 0), false, 1)
	map.render_grid(grid)
	expect((map.get_node("TerrainProperties") as Node).get_child_count() > 0, "Blocked terrain receives visible markers")
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
