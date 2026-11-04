extends RefCounted
## Skill editor: fixed structure of built-in skills, undo, description variables, reset and closing.


func run(suite: Node) -> void:
	await _check_editing(suite)
	await _check_typing_undo(suite)


func _check_editing(suite: Node) -> void:
	var skills: SkillLibrary = suite.fixture.skills()
	var editor := preload("res://tools/skills/skill_editor.tscn").instantiate() as SkillEditor
	editor.embedded = true
	suite.add_child(editor)
	await suite.get_tree().process_frame
	suite.expect(editor._list.item_count > 0 and editor._kind == "active" and not editor._document.is_empty(), "Editor opens the first active skill")
	suite.expect(editor._category.tab_count == 2, "Editor lists only active and passive skills")
	var captions := editor.find_children("*", "BaseButton", true, false).map(func(button: Node) -> String: return String(button.get("text")))
	suite.expect(not captions.has("Новый") and not captions.has("Копия") and not captions.has("Добавить ▾"), "Editor offers no way to create skills or effects")
	var builtin := skills.builtin_documents()
	editor._set_document(builtin["core:grenade"])
	var type_selectors := editor._form.find_children("*", "OptionButton", true, false).filter(func(option: OptionButton) -> bool:
		return option.item_count > 0 and option.get_item_text(0) == "Урон"
	)
	suite.expect(type_selectors.is_empty(), "Effect cards have no effect type selector")
	editor._change("range", 8)
	editor._undo_edit()
	suite.expect(editor._document.range == 3, "Undo restores document value")
	editor._redo_edit()
	suite.expect(editor._document.range == 8, "Redo restores edited value")
	editor._effect_change(0, "amount", 11)
	suite.expect(editor._document.effects[0].parameters.amount == 11, "Effect card edits owned authoring data")
	editor._undo_edit()
	suite.expect(editor._document.effects[0].parameters.amount == 2, "Effect edits participate in undo")
	editor._description.text = "Взрыв: "
	editor._description.set_caret_column(editor._description.text.length())
	editor._insert_variable("damage")
	suite.expect(editor._document.description == "Взрыв: {damage}", "Inserted variable lands in the description")
	suite.expect(editor._preview.text.contains("Взрыв: 2"), "Preview fills description variables: " + editor._preview.text)
	editor._change("description", "{nonexistent}")
	suite.expect(editor._validation.text.begins_with("✗ Описание"), "Unknown description variable is reported in the status bar")
	suite.expect(not editor._reset.disabled, "A changed built-in skill can be reset")
	editor._reset_to_builtin()
	suite.expect(skills.is_builtin_default(editor._document) and editor._reset.disabled, "Reset restores the built-in values")
	editor._undo_edit()
	suite.expect(editor._document.description == "{nonexistent}", "Reset is one undo step")
	editor._set_document(builtin["core:spear_sweep"])
	editor._preview_attack.value = 9
	suite.expect(editor._preview_context.visible and editor._preview.text.contains("9 урона"), "Preview uses the example unit attack for base-attack damage")
	editor._set_document(builtin["core:shove"])
	var push_spins := editor._form.find_children("*", "SpinBox", true, false).filter(func(spin: SpinBox) -> bool:
		return spin.max_value == PushEffectHandler.MAX_DISTANCE and spin.value == 2
	)
	suite.expect(push_spins.size() == 1, "The push effect card edits its distance")
	(push_spins[0] as SpinBox).value = 4
	suite.expect(editor._document.effects[1].parameters.distance == 4 and editor._preview.text.contains("дальность толчка — 4") and editor._validation.text.begins_with("✓"), "A changed push distance reaches the draft and its description")
	var turret: Dictionary = builtin["core:electric_turret"]
	var started := Time.get_ticks_usec()
	editor._set_document(turret)
	for value in range(2, 12):
		editor._change("range", value)
	suite.expect(Time.get_ticks_usec() - started < 300000, "Opening and editing a summon skill stays interactive")
	editor._set_document(builtin["core:attack_training"])
	suite.expect(editor._kind == "passive" and editor._list.item_count > 0 and editor._preview.text.contains("+3 к урону"), "Passive skill opens with its description preview")
	editor._change("name", "Changed")
	editor.request_close(func() -> void: pass)
	suite.expect(editor._confirm.visible, "Closing a modified draft requests discard confirmation")
	editor.queue_free()
	await suite.get_tree().process_frame


func _check_typing_undo(suite: Node) -> void:
	var library: SkillLibrary = suite.fixture.skills()
	var skills := preload("res://tools/skills/skill_editor.tscn").instantiate() as SkillEditor
	skills.embedded = true
	suite.add_child(skills)
	await suite.get_tree().process_frame
	var skill: Dictionary = library.builtin_documents()["core:laser"]
	skills._set_document(skill)
	for text: String in ["Л", "Лу", "Луч"]:
		skills._change("name", text)
	skills._undo_edit()
	suite.expect(skills._document.name == skill.name, "Typing a skill name is undone in one step")
	for text: String in ["Б", "Бь", "Бьёт"]:
		skills._change("description", text)
	skills._undo_edit()
	suite.expect(skills._document.description == skill.description, "Typing a skill description is undone in one step")
	skills.queue_free()
	await suite.get_tree().process_frame
