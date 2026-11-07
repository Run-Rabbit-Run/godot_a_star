extends RefCounted
## Living and mechanical bodies, the `core:heal` effect and «Полевой набор»: a neighboring
## living ally regains health up to its maximum; a mechanical body is never chosen nor healed.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const FIELD_KIT := &"core:field_kit"
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var loaded := ContentLoader.load_packages([core])
	suite.expect(loaded.is_successful, "The core package with the healing kit loads: %s" % "\n".join(loaded.errors))
	if not loaded.is_successful:
		return
	_run_bodies(suite, loaded.snapshot, core)
	var kit := loaded.snapshot.get_ability_definition(FIELD_KIT)
	suite.expect(kit != null, "The core package ships «Полевой набор»")
	if kit == null:
		return
	_run_definition(suite, loaded.snapshot, kit, core)
	_run_targets(suite, fixture, kit)
	_run_heal(suite, fixture, kit)
	_run_repair(suite, fixture)
	_run_log(suite)
	_run_authored(suite, fixture)
	_run_ai(suite, fixture, kit)


func _run_bodies(suite: Node, snapshot: ContentSnapshot, core: ContentPackage) -> void:
	for id: StringName in [&"core:turret_unit", &"core:electric_turret_unit", &"core:health_shuttle_unit"]:
		var construct := snapshot.get_unit_definition(id)
		suite.expect(construct != null and construct.body == UnitBody.MECHANICAL, "%s has a mechanical body" % id)
	var guard := snapshot.get_unit_definition(&"core:debug_player")
	suite.expect(guard != null and guard.body == UnitBody.LIVING, "A unit without a body set is living")
	suite.expect(UnitBody.display_name(UnitBody.LIVING) == "Живой" and UnitBody.display_name(UnitBody.MECHANICAL) == "Механический" and not UnitBody.is_known(&"robot"), "Two bodies are known: living and mechanical")

	var machine := _create(UnitBody.MECHANICAL)
	suite.expect(machine != null and machine.body == UnitBody.MECHANICAL, "The factory gives the unit its definition's body")
	if machine != null:
		var copy := machine.duplicate_state()
		var restored := _create(UnitBody.LIVING)
		restored.copy_from(machine)
		suite.expect(copy.body == UnitBody.MECHANICAL and restored.body == UnitBody.MECHANICAL and UnitSnapshot.new(machine).body == UnitBody.MECHANICAL, "Copies and snapshots keep the body")
	var living := _create(UnitBody.LIVING)
	suite.expect(living != null and living.body == UnitBody.LIVING, "A living definition gives a living unit")

	# A body the rules do not know stops the content load.
	var broken := core.duplicate(true) as ContentPackage
	broken.units[0] = broken.units[0].duplicate(true) as UnitDefinition
	broken.units[0].body = &"robot"
	var refused := ContentLoader.load_packages([broken])
	suite.expect(not refused.is_successful and "\n".join(refused.errors).contains("unknown unit body"), "An unknown body is a content error: %s" % "\n".join(refused.errors))


func _run_definition(suite: Node, snapshot: ContentSnapshot, kit: AbilityDefinition, core: ContentPackage) -> void:
	suite.expect(kit.target_mode == AbilityDefinition.TargetMode.ALLY and kit.range == 1 and kit.area_radius == 0 and not kit.targets_hex() and not kit.melee_attack, "«Полевой набор» targets a neighboring ally")
	suite.expect(kit.cooldown_turns == 1 and kit.initial_cooldown_turns == 0 and kit.validate().is_empty(), "«Полевой набор» has a cooldown of 1 and none at the start")
	var heal := kit.effects[0] if kit.effects.size() == 1 else null
	suite.expect(heal != null and heal.effect_type_id == &"core:heal" and heal.parameters.get("amount") == 2 and HealEffectHandler.body_of(heal) == UnitBody.LIVING, "«Полевой набор» heals 2 HP of a living body")
	suite.expect(snapshot.get_ability_presentation_definition(kit.presentation_id) != null, "«Полевой набор» has a presentation")
	var text := AbilityDescription.render(kit)
	suite.expect(text.contains("2 ОЗ") and text.contains("Механические") and not "{" in text, "The kit describes itself: %s" % text)

	var handler := HealEffectHandler.new()
	suite.expect(handler.validate(_heal_effect(2, "")).is_empty(), "A heal without a body heals living bodies")
	suite.expect(not handler.validate(_heal_effect(0, "living")).is_empty(), "A heal of 0 is refused")
	suite.expect(not handler.validate(_heal_effect(2, "robot")).is_empty(), "A heal of an unknown body is refused")
	suite.expect(handler.validate(_heal_effect(3, "mechanical")).is_empty(), "A repair of mechanical bodies is a valid heal")

	var skills := SkillLibrary.new([core])
	var document: Dictionary = skills.builtin_documents().get(String(FIELD_KIT), {})
	var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
	suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The skill editor reads the built-in kit as valid and unchanged after JSON")
	var stronger := reread.duplicate(true)
	stronger.effects[0].parameters.amount = 3
	suite.expect(skills.validate(stronger).is_empty() and skills.to_ability(stronger).effects[0].parameters.amount == 3, "The skill editor may change how much the kit heals")
	var repair := reread.duplicate(true)
	repair.effects[0].parameters.body = "mechanical"
	suite.expect(skills.validate(repair).contains("body"), "The skill editor keeps the body the kit heals")
	var empty := reread.duplicate(true)
	empty.effects[0].parameters.amount = 0
	suite.expect(skills.validate(empty).contains("восстановление ОЗ"), "A kit healing 0 is refused with the healing caption")


## The medic at the origin; a wounded living ally east, a mechanical ally west, a living ally two
## hexes away and an enemy next to the medic.
func _run_targets(suite: Node, fixture: Fixtures, kit: AbilityDefinition) -> void:
	var units := _field(fixture, kit)
	var state := fixture.state(_disk(3), _list(units))
	var engine := BattleEngine.new(state)
	var medic: UnitState = units.medic
	var expected: Array[Vector2i] = [units.wounded.hex]
	suite.expect(AbilityExecutor.get_target_hexes(state, medic.unit_id, FIELD_KIT) == expected, "The kit chooses only the neighboring living ally: %s" % [AbilityExecutor.get_target_hexes(state, medic.unit_id, FIELD_KIT)])
	for target_id: String in ["machine", "far", "enemy", "medic"]:
		var target: UnitState = units[target_id]
		var health_before := target.health.current
		var refused := engine.execute(UseAbilityCommand.new(medic.unit_id, StringName(target_id), FIELD_KIT))
		suite.expect(not refused.accepted and medic.turn.main_action_available and target.health.current == health_before, "The kit refuses %s without spending the action" % target_id)
	suite.expect(units.machine.health.current == 90, "The mechanical ally is not healed")
	suite.expect(not engine.execute(UseAbilityCommand.at_hex(medic.unit_id, units.wounded.hex, FIELD_KIT)).accepted, "The kit chooses a unit, not a hex")

	# A fallen ally is no target.
	units.wounded.health.current = 0
	suite.expect(AbilityExecutor.get_target_hexes(state, medic.unit_id, FIELD_KIT).is_empty(), "A defeated ally is not healed")


func _run_heal(suite: Node, fixture: Fixtures, kit: AbilityDefinition) -> void:
	var units := _field(fixture, kit)
	var state := fixture.state(_disk(3), _list(units))
	var engine := BattleEngine.new(state)
	var medic: UnitState = units.medic
	var wounded: UnitState = units.wounded
	var command := UseAbilityCommand.new(medic.unit_id, wounded.unit_id, FIELD_KIT)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	var change := preview.units.get(wounded.unit_id) as ActionPreview.UnitChange
	suite.expect(preview.accepted and change != null and change.health_before == 95 and change.health_after == 97, "The preview shows the ally's health rising 95 → 97")
	suite.expect(wounded.health.current == 95, "The preview heals nobody")

	var result := engine.execute(command)
	var healed := _healed(result.events)
	suite.expect(result.accepted and wounded.health.current == 97, "The kit heals the neighboring ally by 2: %s" % result.rejection_reason)
	suite.expect(healed.size() == 1 and healed[0].unit_id == wounded.unit_id and healed[0].source_unit_id == medic.unit_id and healed[0].ability_id == FIELD_KIT and healed[0].amount == 2 and healed[0].health_after == 97 and healed[0].health_maximum == 100 and healed[0].body == UnitBody.LIVING, "One healed event names the ally, the medic, the kit and the restored health")
	suite.expect(not result.events.is_empty() and result.events[0] is AbilityUsedEvent and result.events[0].target_id == wounded.unit_id, "The kit is announced as used on the ally")
	suite.expect(not medic.turn.main_action_available and medic.ability_cooldowns.get(FIELD_KIT, 0) == 2 and _turn_ended(result.events, medic.unit_id), "The kit spends the action, starts the cooldown and ends the turn")

	# Health never rises above the maximum.
	units = _field(fixture, kit)
	units.wounded.health.current = 99
	state = fixture.state(_disk(3), _list(units))
	engine = BattleEngine.new(state)
	result = engine.execute(UseAbilityCommand.new(units.medic.unit_id, units.wounded.unit_id, FIELD_KIT))
	healed = _healed(result.events)
	suite.expect(result.accepted and units.wounded.health.current == 100 and healed.size() == 1 and healed[0].amount == 1, "The kit heals no further than the maximum")
	units = _field(fixture, kit)
	units.wounded.health.current = 100
	state = fixture.state(_disk(3), _list(units))
	engine = BattleEngine.new(state)
	result = engine.execute(UseAbilityCommand.new(units.medic.unit_id, units.wounded.unit_id, FIELD_KIT))
	healed = _healed(result.events)
	suite.expect(result.accepted and units.wounded.health.current == 100 and healed.size() == 1 and healed[0].amount == 0, "A healthy ally may be chosen: it gains nothing")


## Repair is the same effect for mechanical bodies; each body takes only its own kind.
func _run_repair(suite: Node, fixture: Fixtures) -> void:
	var medic := fixture.unit(&"medic", PLAYER, Vector2i.ZERO)
	var machine := fixture.unit(&"machine", PLAYER, Vector2i(1, 0))
	machine.body = UnitBody.MECHANICAL
	machine.health.current = 90
	var living := fixture.unit(&"living", PLAYER, Vector2i(-1, 0))
	living.health.current = 90
	var fallen := fixture.unit(&"fallen", PLAYER, Vector2i(0, 1))
	fallen.health.current = 0
	var state := fixture.state(_disk(2), [medic, machine, living, fallen])
	var context := BattleEffectContext.new(state, &"test:repair")
	var events := context.heal(medic.unit_id, machine.unit_id, 3, UnitBody.MECHANICAL)
	suite.expect(machine.health.current == 93 and events.size() == 1 and (events[0] as UnitHealedEvent).body == UnitBody.MECHANICAL, "A repair restores a mechanical body")
	suite.expect(context.heal(medic.unit_id, machine.unit_id, 3, UnitBody.LIVING).is_empty() and machine.health.current == 93, "Healing does not reach a mechanical body")
	suite.expect(context.heal(medic.unit_id, living.unit_id, 3, UnitBody.MECHANICAL).is_empty() and living.health.current == 90, "A repair does not reach a living body")
	suite.expect(context.heal(medic.unit_id, fallen.unit_id, 3, UnitBody.LIVING).is_empty() and fallen.health.is_defeated(), "Healing does not bring the fallen back")
	suite.expect(not context.has_failed(), "Passing over a unit is no effect failure")
	context.heal(medic.unit_id, &"missing", 3, UnitBody.LIVING)
	suite.expect(context.has_failed(), "Healing a missing unit fails the effect")

	var handler := HealEffectHandler.new()
	var heal := _heal_effect(2, "living")
	suite.expect(handler.accepts_target(heal, living) and not handler.accepts_target(heal, machine), "Healing accepts living targets only")
	suite.expect(handler.accepts_target(_heal_effect(2, "mechanical"), machine) and not handler.accepts_target(_heal_effect(2, "mechanical"), living), "Repair accepts mechanical targets only")


func _run_log(suite: Node) -> void:
	var units: Dictionary[StringName, UnitDefinition] = {}
	var heal := BattleLogFormatter.describe(UnitHealedEvent.new(&"ally", &"medic", FIELD_KIT, UnitBody.LIVING, 2, 7, 10), units, null)
	var repair := BattleLogFormatter.describe(UnitHealedEvent.new(&"turret", &"medic", &"test:repair", UnitBody.MECHANICAL, 1, 2, 2), units, null)
	suite.expect(heal.contains("лечит") and heal.contains("+2 ОЗ") and heal.contains("7 / 10"), "The log tells a heal: %s" % heal)
	suite.expect(repair.contains("чинит") and repair.contains("+1 ОЗ"), "The log tells a repair: %s" % repair)


## The authored unit format stores the body; units saved before it are living.
func _run_authored(suite: Node, fixture: Fixtures) -> void:
	var document := UnitLibrary.new_document()
	suite.expect(document.get("body") == "living" and UnitLibrary.validate_structure(document).is_empty(), "A new authored unit is living")
	document.body = "mechanical"
	suite.expect(UnitLibrary.validate_structure(document).is_empty(), "An authored unit may be mechanical")
	document.body = "robot"
	suite.expect(UnitLibrary.validate_structure(document).begins_with("Тело"), "An unknown body is refused by the unit format")
	document.erase("body")
	suite.expect(UnitLibrary.validate_structure(document).is_empty(), "A unit saved before bodies existed is valid")

	var loaded := fixture.content()
	var guard := loaded.snapshot.get_unit_definition(&"custom_units:spear_guard") if loaded.snapshot != null else null
	suite.expect(guard != null and guard.body == UnitBody.LIVING, "The authored spear guard without a body field is living")

	# A library folder of its own: one mechanical unit, one without a body field.
	var directory := "user://body_regressions_%s" % Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var mechanical := UnitLibrary.new_document()
	mechanical.id = "custom_units:body_machine"
	mechanical.body = "mechanical"
	var old := UnitLibrary.new_document()
	old.id = "custom_units:body_old"
	old.erase("body")
	for data: Dictionary in [mechanical, old]:
		AtomicFileWriter.write_text(directory.path_join(String(data.id).trim_prefix("custom_units:") + ".json"), JSON.stringify(data))
	var read := UnitLibrary.read_document(directory.path_join("body_old.json"), {})
	suite.expect(String(read.get("error", "?")).is_empty() and read.document.get("body") == "living", "Reading a unit without a body field makes it living")
	var library := UnitLibrary.load_content(GameContentSettings.read().content_packages, false, directory)
	var machine := library.snapshot.get_unit_definition(&"custom_units:body_machine") if library.snapshot != null else null
	var plain := library.snapshot.get_unit_definition(&"custom_units:body_old") if library.snapshot != null else null
	suite.expect(machine != null and machine.body == UnitBody.MECHANICAL and plain != null and plain.body == UnitBody.LIVING, "The library loads the body of each authored unit: %s" % "\n".join(library.errors))
	for file: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


## The AI does not heal yet; a unit with the kit still finds a legal command.
func _run_ai(suite: Node, fixture: Fixtures, kit: AbilityDefinition) -> void:
	var medic := fixture.unit(&"ai_medic", ENEMY, Vector2i.ZERO)
	_give(medic, kit)
	var wounded := fixture.unit(&"ai_wounded", ENEMY, Vector2i(1, 0))
	wounded.health.current = 50
	var player := fixture.unit(&"player", PLAYER, Vector2i(-3, 0))
	var session := fixture.ai_session(fixture.state(_disk(3), [medic, wounded, player]))
	for profile: AIProfileDefinition in [null, _tactical()]:
		var command := AICommandSource.new(profile).next_command(session)
		suite.expect(command != null and session.preview(command).accepted and wounded.health.current == 50, "The AI with the kit gives a legal command")


## The battle view: the body tag of a hovered unit, the healing badge and log line, the aiming
## hints of the new targets and the glitch on the active unit's damage.
func run_presentation(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(fixture.spear_request()), "Healing view battle setup accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(600):
		await suite.get_tree().process_frame
		if not controller.get("_is_presenting"):
			break
	var session: BattleSession = controller.get("_battle_session")
	var selection: PlayerActionSelection = controller.get("_selection")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var body := hud.get("_target_body_label") as Label
	hud.show_target("Турель", null, "Союзник", 2, 2, 2, 2, 0, 0, true, {}, UnitBody.MECHANICAL)
	suite.expect(body.visible and body.text == "МЕХАНИЧЕСКИЙ", "The target panel tags a mechanical body: %s" % body.text)
	hud.show_target("Страж", null, "Противник", 9, 14, 3, 1, 3, 5, true)
	suite.expect(body.text == "ЖИВОЙ", "The target panel tags a living body by default")
	var active := session.get_unit(session.get_active_unit_id())
	hud.show_target("Турель", null, "Союзник", 2, 2, 2, 2, 0, 0, true, {}, UnitBody.MECHANICAL)
	selection.hover(active.hex)
	suite.expect(body.text == UnitBody.display_name(active.body).to_upper(), "Hovering a unit shows its body: %s" % body.text)

	var action := hud.get("_action_label") as Label
	hud.show_ability_targeting("Полевой набор", 0, AbilityDefinition.TargetMode.ALLY)
	suite.expect(action.text == "ВЫБЕРИТЕ СОЮЗНИКА: ПОЛЕВОЙ НАБОР", "Aiming at an ally asks for an ally: %s" % action.text)
	hud.show_ability_targeting("Огненный росчерк", 0, AbilityDefinition.TargetMode.ARC)
	suite.expect(action.text == "ВЫБЕРИТЕ СТОРОНУ: ОГНЕННЫЙ РОСЧЕРК", "Aiming a side asks for a side: %s" % action.text)
	var stats := hud.get("_combat_stats_label") as Label
	hud.show_combat_stats(3, 1, 1, 1)
	suite.expect(stats.text.contains("3+1−1"), "The active unit's damage shows its charge and glitch: %s" % stats.text)
	hud.show_combat_stats(3, 1)
	suite.expect(stats.text.contains("УРОН  3 "), "Without either the damage is plain: %s" % stats.text)

	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	var registry: BattleUnitViewRegistry = controller.get("_unit_views")
	var actor := registry.actors.get(active.unit_id) as UnitActor
	var events: Array[BattleEvent] = [UnitHealedEvent.new(active.unit_id, active.unit_id, FIELD_KIT, UnitBody.LIVING, 2, active.health.current, active.health.maximum)]
	var shown := await queue.present(BattleResolution.success(events, session.get_state_revision(), active.unit_id), registry.actors, registry.definitions, screen.get_node("BattleMap") as BattleMapView, hud)
	var badge_text := ""
	if actor != null:
		for child: Node in actor.get_parent().get_children():
			var number := child.get_node_or_null("Number") as Label
			if child is PanelContainer and number != null and number.text.begins_with("+"):
				badge_text = number.text
	suite.expect(shown and badge_text == "+2 ОЗ", "A heal rises as a green «+2 ОЗ» over the unit: %s" % badge_text)
	var log_text := (hud.get_node("HUDRoot/BattleLogPanel/Content/Entries") as RichTextLabel).get_parsed_text()
	suite.expect(log_text.contains("лечит") and log_text.contains("+2 ОЗ"), "The battle log tells the heal")
	screen.queue_free()
	await suite.get_tree().process_frame


static func _tactical() -> AIProfileDefinition:
	var profile := AIProfileDefinition.new()
	profile.policy_id = AICommandSource.TACTICAL_POLICY
	return profile


## medic (0,0), wounded (1,0) at 95/100, machine (-1,0) at 90/100, far (2,0) at 90/100, enemy (0,1).
static func _field(fixture: Fixtures, kit: AbilityDefinition) -> Dictionary:
	var medic := fixture.unit(&"medic", PLAYER, Vector2i.ZERO)
	_give(medic, kit)
	var wounded := fixture.unit(&"wounded", PLAYER, Vector2i(1, 0))
	wounded.health.current = 95
	var machine := fixture.unit(&"machine", PLAYER, Vector2i(-1, 0))
	machine.body = UnitBody.MECHANICAL
	machine.health.current = 90
	var far := fixture.unit(&"far", PLAYER, Vector2i(2, 0))
	far.health.current = 90
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(0, 1))
	enemy.health.current = 90
	return {"medic": medic, "wounded": wounded, "machine": machine, "far": far, "enemy": enemy}


static func _list(units: Dictionary) -> Array[UnitState]:
	var list: Array[UnitState] = []
	list.assign(units.values())
	return list


static func _give(unit: UnitState, ability: AbilityDefinition) -> void:
	unit.abilities[ability.id] = ability
	unit.ability_cooldowns[ability.id] = 0


static func _heal_effect(amount: int, body: String) -> AbilityEffectDefinition:
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = &"core:heal"
	effect.parameters = {"amount": amount}
	if not body.is_empty():
		effect.parameters["body"] = body
	return effect


static func _create(body: StringName) -> UnitState:
	var definition := UnitDefinition.new()
	definition.base_stats = UnitStatsDefinition.new()
	definition.base_stats.basic_attack_damage = 2
	definition.body = body
	var spawn := UnitSpawnData.new(&"test:unit", &"test:placement", &"test:definition", definition, &"test:side", PLAYER, BattleControlSource.Value.PLAYER, &"", null, Vector2i.ZERO)
	return UnitStateFactory.create(spawn)


static func _healed(events: Array[BattleEvent]) -> Array[UnitHealedEvent]:
	var healed: Array[UnitHealedEvent] = []
	for event: BattleEvent in events:
		if event is UnitHealedEvent:
			healed.append(event)
	return healed


static func _turn_ended(events: Array[BattleEvent], unit_id: StringName) -> bool:
	for event: BattleEvent in events:
		if event is TurnEndedEvent and event.unit_id == unit_id:
			return true
	return false


static func _disk(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells
