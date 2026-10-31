extends RefCounted
## Review regressions of the unit and skill editors: repairable references, undo steps, attack range and effect types.

const MISSING_SKILL := "custom_skills:s_missing_reference"


func run(suite: Node) -> void:
	var folder := "user://unit_references_" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var data := UnitLibrary.new_document()
	data.abilities = [MISSING_SKILL]
	var path := folder.path_join(String(data.id).trim_prefix("custom_units:") + ".json")
	_write(path, data)
	var result := UnitLibrary.read_document(path)
	suite.expect(not String(result.error).is_empty() and result.has("document"), "A broken skill reference keeps the unit document open for repair")
	suite.expect(result.has("document") and not UnitLibrary.validate(result.document).is_empty(), "A broken skill reference still fails full validation and loading")
	data.hp = "много"
	_write(path, data)
	suite.expect(not UnitLibrary.read_document(path).has("document"), "Structural errors never open a partial unit document")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	var nameless := UnitLibrary.new_document()
	nameless.name = " "
	suite.expect(UnitLibrary.validate(nameless) == "Поле «Имя» должно содержать текст.", "Unit validation names fields in Russian")

	var returning := SkillLibrary.new_document("active")
	returning.returns_next_turn = true
	suite.expect(SkillLibrary.validate(returning).begins_with("Возврат оружия"), "Returning weapon rule is explained in the editor language")
	var summon := SkillLibrary.new_document("active")
	summon.effects = [SkillLibrary.new_effect("core:summon")]
	suite.expect(SkillLibrary.validate(summon).begins_with("Призыв"), "Summon rule is explained in the editor language")
	var short := SkillLibrary.new_document("active")
	short.range = 0
	suite.expect(SkillLibrary.validate(short).begins_with("Дальность"), "Zero range names the field instead of a core message")
	var unknown_state := SkillLibrary.new_document("active")
	unknown_state.effects = [SkillLibrary.new_effect("core:hex_state")]
	unknown_state.effects[0].parameters.state_id = "core:unknown"
	suite.expect(SkillLibrary.validate(unknown_state).begins_with("Эффект гекса"), "Unknown hex state is reported in the editor language")


func run_editor(suite: Node) -> void:
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	editor.embedded = true
	suite.add_child(editor)
	await suite.get_tree().process_frame
	var original: String = editor._document.name
	for text: String in ["А", "Ар", "Арб"]:
		editor._change("name", text)
	editor._undo_edit()
	suite.expect(editor._document.name == original, "Typing a unit name is undone in one step")
	editor._redo_edit()
	suite.expect(editor._document.name == "Арб", "Redo restores the whole typed unit name")

	var melee := UnitLibrary.new_document()
	melee.attack_range = 1
	editor._set_document(melee)
	editor._set_attack_type(1)
	suite.expect(editor._document.attack_type == "ranged" and editor._document.attack_range == 2 and UnitLibrary.validate(editor._document).is_empty(), "Switching to ranged attack keeps a valid range")
	editor._undo_edit()
	suite.expect(editor._document.attack_type == "melee" and editor._document.attack_range == 1, "Undo restores attack type and range together")

	var broken := UnitLibrary.new_document()
	broken.abilities = [MISSING_SKILL]
	editor._set_document(broken)
	var popup := editor._active_menu.get_popup()
	var listed := -1
	for index in range(popup.item_count):
		if popup.get_item_metadata(index) == MISSING_SKILL:
			listed = index
	suite.expect(listed >= 0 and popup.is_item_checked(listed), "A missing skill reference is listed as a checked item")
	if listed >= 0:
		popup.index_pressed.emit(listed)
	suite.expect(editor._document.abilities.is_empty() and UnitLibrary.validate(editor._document).is_empty(), "Unchecking the missing skill repairs the unit")
	editor.queue_free()
	await suite.get_tree().process_frame

	var skills := preload("res://tools/skills/skill_editor.tscn").instantiate() as SkillEditor
	skills.embedded = true
	suite.add_child(skills)
	await suite.get_tree().process_frame
	var skill: Dictionary = SkillLibrary.builtin_documents()["core:laser"]
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


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _find_option(root: Node, first_item: String) -> OptionButton:
	for child: Node in root.find_children("*", "OptionButton", true, false):
		var option := child as OptionButton
		if option.item_count > 0 and option.get_item_text(0) == first_item and not option.is_queued_for_deletion():
			return option
	return null
