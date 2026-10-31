extends RefCounted

func run(suite: Node) -> void:
	var active := SkillLibrary.new_document("active")
	suite.expect(SkillLibrary.validate(active).is_empty(), "New active skill validates")
	for type: String in SkillLibrary.DAMAGE_TYPES:
		active.effects[0].parameters.damage_type = type
		suite.expect(SkillLibrary.validate(active).is_empty(), "Every selectable damage type validates: " + type)
	active.effects[0].parameters.amount = 1.5
	suite.expect(not SkillLibrary.validate(active).is_empty(), "Fractional damage rejected before integer conversion")
	active.effects[0].parameters.amount = 7
	active.effects[0].parameters.secondary_amount = 3
	active.effects.append(SkillLibrary.new_effect("core:unit_status"))
	var ability := SkillLibrary.to_ability(active)
	suite.expect(ability.effects.size() == 2 and ability.effects[0].parameters.amount == 7 and ability.effects[1].parameters.levels == 2, "Ordered damage and status effects survive conversion")
	ability.effects[0].parameters.amount = 90
	suite.expect(active.effects[0].parameters.amount == 7, "Converted ability does not mutate authoring document")
	active.target_mode = AbilityDefinition.TargetMode.PATH
	active.returns_next_turn = true
	suite.expect(not SkillLibrary.validate(active).is_empty(), "Returning skill rejects non-damage effects")
	active.returns_next_turn = false
	active.effects = [SkillLibrary.new_effect("core:summon")]
	suite.expect(not SkillLibrary.validate(active).is_empty(), "Summon requires empty hex target")
	active.target_mode = AbilityDefinition.TargetMode.EMPTY_HEX
	suite.expect(SkillLibrary.validate(active).is_empty(), "Known summon converts to runtime unit definition: " + SkillLibrary.validate(active))
	var passive := SkillLibrary.new_document("passive")
	passive.attack_bonus = 5
	passive.damage_type = "fire"
	passive.status = "core:burning"
	passive.levels = 4
	passive.immunity = "core:electrified"
	passive.retaliation = true
	var definitions := SkillLibrary.passive_definitions({passive.id: passive})
	var definition := UnitDefinition.new()
	definition.base_stats = UnitStatsDefinition.new()
	definition.base_stats.basic_attack_damage = 2
	definition.passive_ability_ids.assign([StringName(passive.id)])
	definition.passive_definitions = definitions
	var spawn := UnitSpawnData.new(&"test:author", &"test:placement", &"test:definition", definition, &"test:side", BattleFaction.Value.PLAYER, BattleControlSource.Value.PLAYER, &"", null, Vector2i.ZERO)
	var state := UnitStateFactory.create(spawn)
	suite.expect(state != null and state.basic_attack_damage == 7, "Authored passive bonus is applied once")
	suite.expect(state.basic_attack_damage_type == &"fire" and state.basic_attack_statuses.get(&"core:burning") == 4, "Authored passive selects attack damage type and status levels")
	suite.expect(state.status_immunities.has(&"core:electrified") and state.melee_retaliation, "Authored immunity and retaliation applied")
	suite.expect(state.duplicate_state().melee_retaliation and state.duplicate_state().retaliation_configured, "Prediction copy preserves retaliation policy")
	var ids: Array[StringName] = [StringName(passive.id), &"core:electric_attack"]
	suite.expect(not PassiveAbilityCatalog.validate(ids, definitions).is_empty(), "Custom and builtin attack damage type conflict rejected")
	var victim: UnitState = suite.fixture.unit(&"victim", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0)]
	var actors: Array[UnitState] = [state, victim]
	var battlefield: BattleState = suite.fixture.state(cells, actors)
	var context := BattleEffectContext.new(battlefield)
	context.target_hex = victim.hex
	var damage := SkillLibrary.new_effect()
	damage.parameters.amount = 9
	damage.parameters.damage_type = "acid"
	DamageEffectHandler.new().execute(SkillLibrary.to_effect(damage), context, state.unit_id, victim.unit_id)
	suite.expect(victim.health.current == 91, "Authored damage amount reaches battle health")
	var status_effect := SkillLibrary.new_effect("core:unit_status")
	status_effect.parameters.levels = 4
	UnitStatusEffectHandler.new().execute(SkillLibrary.to_effect(status_effect), context, state.unit_id, victim.unit_id)
	suite.expect(victim.statuses.get(&"core:burning") == 4, "Authored status levels reach battle state")
	var events: Array[BattleEvent] = []
	UnitStatusService.apply(state, &"core:electrified", 2, events)
	suite.expect(not state.statuses.has(&"core:electrified"), "Authored passive immunity rejects status in combat")
	definition.passive_ability_ids.assign([&"core:melee_retaliation"])
	definition.passive_definitions = {&"core:melee_retaliation": {"retaliation": false}}
	var disabled := UnitStateFactory.create(spawn)
	var before := victim.health.current
	RetaliationService.respond(battlefield, victim, disabled, events)
	suite.expect(victim.health.current == before and not disabled.melee_retaliation, "Builtin retaliation can be disabled by authored override")
	var source := SkillLibrary.packages()
	var original := source[0].abilities[0]
	var override := SkillLibrary.active_document(original)
	override.name = "Changed in authored content"
	var applied := SkillLibrary.apply_to_packages(source, {override.id: override})
	suite.expect(original.display_name != applied[0].abilities[0].display_name, "Builtin override works on copied package")
	suite.expect(original.display_name != override.name, "Builtin resource cache remains unchanged")
	var electric_passive: Dictionary = SkillLibrary.builtin_documents()["core:electric_attack"]
	electric_passive.damage_type = "fire"
	var summon := SkillLibrary.new_document("active")
	summon.effects = [SkillLibrary.new_effect("core:summon")]
	summon.target_mode = AbilityDefinition.TargetMode.EMPTY_HEX
	var summon_packages := SkillLibrary.apply_to_packages(source, {summon.id: summon, electric_passive.id: electric_passive})
	var summoned: UnitDefinition = summon_packages[-1].abilities[0].effects[0].parameters.unit
	suite.expect(summoned.passive_definitions[&"core:electric_attack"].damage_type == &"fire", "Summoned units receive authored passive overrides")
	var custom := SkillLibrary.new_document("active")
	applied = SkillLibrary.apply_to_packages(source, {custom.id: custom, passive.id: passive})
	var loaded := ContentLoader.load_packages(applied)
	suite.expect(loaded.is_successful and loaded.snapshot.get_ability_definition(StringName(custom.id)) != null, "Authored active skill enters shared ContentSnapshot")
	_run_descriptions(suite)
	var copied := SkillLibrary.builtin_documents()
	copied["core:grenade"].name = "Mutated copy"
	suite.expect(SkillLibrary.builtin_documents()["core:grenade"].name != "Mutated copy", "Built-in skill documents are independent copies of the cache")
	var started := Time.get_ticks_usec()
	for index in range(20):
		SkillLibrary.validate(copied["core:electric_turret"])
	suite.expect(Time.get_ticks_usec() - started < 200000, "Validating built-in skills does not reload content packages")
	var root := "user://skill_editor_" + Crypto.new().generate_random_bytes(8).hex_encode()
	suite.expect(SkillLibrary.save_document(custom, root).is_empty(), "Skill JSON saves successfully")
	var reread := SkillLibrary.read_all(root)
	suite.expect(reread.errors.is_empty() and reread.documents.has(custom.id), "Skill JSON reloads with stable ID")
	custom.name = "Renamed skill"
	suite.expect(SkillLibrary.save_document(custom, root).is_empty(), "Existing skill saves through atomic replacement")
	suite.expect(SkillLibrary.read_all(root).documents[custom.id].name == custom.name, "Rename preserves path and ID")
	DirAccess.remove_absolute(root.path_join(SkillLibrary.filename_for(custom)))
	DirAccess.remove_absolute(root)

func _run_descriptions(suite: Node) -> void:
	var builtin := SkillLibrary.builtin_documents()
	var invalid := builtin.values().filter(func(data: Dictionary) -> bool:
		return data.kind != "effect" and (String(data.description).is_empty() or not SkillLibrary.validate(data).is_empty())
	)
	suite.expect(invalid.is_empty(), "Every built-in skill has a valid description: %s" % str(invalid.map(func(data: Dictionary) -> String: return data.id)))
	var grenade := SkillLibrary.to_ability(builtin["core:grenade"])
	suite.expect(AbilityDescription.render(grenade).contains("2 урона (физический)"), "Description shows the fixed damage and its type: " + AbilityDescription.render(grenade))
	var sweep := SkillLibrary.to_ability(builtin["core:spear_sweep"])
	suite.expect(AbilityDescription.render(sweep, {"attack_damage": 7}).contains("7 урона"), "Base-attack damage takes the acting unit's final attack")
	suite.expect(AbilityDescription.render(sweep).contains("урон атаки"), "Without a unit the base-attack damage is named instead of counted")
	var turret := AbilityDescription.variables(SkillLibrary.to_ability(builtin["core:electric_turret"]))
	var summon_hp := turret.filter(func(entry: Dictionary) -> bool: return entry.key == "summon_hp")
	suite.expect(summon_hp.size() == 1 and summon_hp[0].value == "3", "Summon variables expose the summoned unit's health")
	var twice := SkillLibrary.new_document("active")
	twice.effects.append(SkillLibrary.new_effect())
	twice.effects[1].parameters.amount = 9
	twice.description = "{damage} и {damage_2}"
	suite.expect(AbilityDescription.render(SkillLibrary.to_ability(twice)) == "2 и 9", "Repeated effects of one kind get numbered variables")
	twice.description = "{unknown}"
	suite.expect(SkillLibrary.validate(twice).begins_with("Описание: переменная {unknown}"), "Unknown description variables are rejected")
	twice.description = "x".repeat(AbilityDescription.MAX_LENGTH + 1)
	suite.expect(not SkillLibrary.validate(twice).is_empty(), "Overlong descriptions are rejected")
	suite.expect(AbilityDescription.render_passive(PassiveAbilityCatalog.DEFINITIONS[&"core:attack_training"]).begins_with("+3 к урону"), "Passive description shows its attack bonus")
	var passive := SkillLibrary.new_document("passive")
	passive.description = "{status}"
	suite.expect(SkillLibrary.validate(passive).begins_with("Описание: переменная {status}"), "Passive variables exist only for properties it sets")
	passive.status = "core:burning"
	passive.description = "{status} ×{levels}"
	suite.expect(SkillLibrary.validate(passive).is_empty() and SkillLibrary.passive_definitions({passive.id: passive}).values()[0].description == passive.description, "Passive description reaches runtime definitions")
	var round_trip := SkillLibrary.active_document(SkillLibrary.to_ability(builtin["core:laser"]))
	suite.expect(round_trip.description == builtin["core:laser"].description, "Description survives document and ability conversion")
	var legacy := SkillLibrary.new_document("active")
	legacy.erase("description")
	suite.expect(SkillLibrary.validate(legacy).is_empty(), "Skill JSON without a description stays valid")
	var root := "user://skill_descriptions_" + Crypto.new().generate_random_bytes(8).hex_encode()
	SkillLibrary.save_document(legacy, root)
	var reread: Dictionary = SkillLibrary.read_all(root).documents.get(legacy.id, {})
	suite.expect(reread.get("description") == "", "Reading old skill JSON adds an empty description")
	DirAccess.remove_absolute(root.path_join(SkillLibrary.filename_for(legacy)))
	DirAccess.remove_absolute(root)


func run_editor(suite: Node) -> void:
	var editor := preload("res://tools/skills/skill_editor.tscn").instantiate() as SkillEditor
	editor.embedded = true
	suite.add_child(editor)
	await suite.get_tree().process_frame
	suite.expect(editor._list.item_count > 0 and editor._kind == "active", "Editor opens with active catalog and property form")
	var data := SkillLibrary.new_document("active")
	editor._set_document(data)
	editor._change("range", 8)
	editor._undo_edit()
	suite.expect(editor._document.range == 3, "Undo restores document value")
	editor._redo_edit()
	suite.expect(editor._document.range == 8, "Redo restores edited value")
	editor._effect_change("amount", 11)
	suite.expect(editor._document.effects[0].parameters.amount == 11, "Effect form edits owned authoring data")
	editor._undo_edit()
	suite.expect(editor._document.effects[0].parameters.amount == 2, "Effect edits participate in undo")
	var turret: Dictionary = SkillLibrary.builtin_documents()["core:electric_turret"]
	var started := Time.get_ticks_usec()
	editor._set_document(turret)
	for value in range(2, 12):
		editor._change("range", value)
	suite.expect(Time.get_ticks_usec() - started < 300000, "Opening and editing a summon skill stays interactive")
	editor._set_document(SkillLibrary.new_document("passive"))
	suite.expect(editor._kind == "passive" and editor._list.item_count > 0, "Passive mode has catalog and form")
	editor._set_document(SkillLibrary.new_document("effect"))
	suite.expect(editor._kind == "effect" and editor._list.item_count >= 4, "Effect mode opens built-in templates")
	editor._change("name", "Changed")
	editor.request_close(func() -> void: pass)
	suite.expect(editor._confirm.visible, "Closing a modified draft requests discard confirmation")
	editor.queue_free()
	await suite.get_tree().process_frame
