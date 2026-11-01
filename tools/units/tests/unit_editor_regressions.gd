extends RefCounted
## Unit editor: typing undo, attack type, repairable skill references, tooltips and ability dropdowns.

const MISSING_SKILL := "custom_skills:s_missing_reference"


func run(suite: Node) -> void:
	await _check_editing(suite)
	await _check_ability_dropdowns(suite)


func _check_editing(suite: Node) -> void:
	var library: SkillLibrary = suite.fixture.skills()
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
	suite.expect(editor._document.attack_type == "ranged" and editor._document.attack_range == 2 and UnitLibrary.validate(editor._document, library.catalog()).is_empty(), "Switching to ranged attack keeps a valid range")
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
	suite.expect(editor._document.abilities.is_empty() and UnitLibrary.validate(editor._document, library.catalog()).is_empty(), "Unchecking the missing skill repairs the unit")
	var trained := UnitLibrary.new_document()
	trained.damage = 5
	trained.passives = ["core:attack_training"]
	editor._set_document(trained)
	suite.expect(editor._skill_tooltip(editor._skills["core:spear_sweep"]).contains("8 урона"), "Unit editor skill tooltip uses the unit's attack with passive bonus")
	suite.expect(editor._skill_tooltip(editor._skills["core:attack_training"]).begins_with("+3 к урону"), "Unit editor passive tooltip shows its description")
	editor.queue_free()
	await suite.get_tree().process_frame


func _check_ability_dropdowns(suite: Node) -> void:
	var skills: SkillLibrary = suite.fixture.skills()
	var editor := preload("res://tools/units/unit_editor.tscn").instantiate() as UnitEditor
	suite.add_child(editor)
	await suite.get_tree().process_frame
	var active: MenuButton = editor.get("_active_menu")
	var passive: MenuButton = editor.get("_passive_menu")
	suite.expect(active != null and passive != null, "Two ability dropdowns exist")
	var popup := active.get_popup()
	suite.expect(not popup.hide_on_checkable_item_selection, "Multiple selection leaves dropdown open")
	for index in range(popup.item_count):
		if popup.get_item_metadata(index) in ["core:spear_throw", "core:spear_sweep"]:
			popup.index_pressed.emit(index)
	var data: Dictionary = editor.get("_document")
	suite.expect(data.abilities.has("core:spear_throw") and data.abilities.has("core:spear_sweep"), "Dropdown selects multiple active abilities")
	editor.call("_undo_edit")
	suite.expect((editor.get("_document") as Dictionary).abilities.size() == 1, "Dropdown selection supports undo")
	editor.call("_redo_edit")
	suite.expect((editor.get("_document") as Dictionary).abilities.size() == 2, "Dropdown selection supports redo")
	for index in range(passive.get_popup().item_count):
		if passive.get_popup().get_item_metadata(index) == "core:melee_retaliation":
			passive.get_popup().index_pressed.emit(index)
	suite.expect((editor.get("_document") as Dictionary).passives.has("core:melee_retaliation"), "Passive dropdown selects retaliation")
	suite.expect(UnitLibrary.validate(editor.get("_document"), skills.catalog()).is_empty(), "Selected active and passive IDs validate")
	editor.queue_free()
	await suite.get_tree().process_frame
