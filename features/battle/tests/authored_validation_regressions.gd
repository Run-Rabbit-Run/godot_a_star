extends RefCounted
## Authored unit and skill documents: repairable references and validation messages in the editor language.

const MISSING_SKILL := "custom_skills:s_missing_reference"


func run(suite: Node) -> void:
	var skills: SkillLibrary = suite.fixture.skills()
	var folder := "user://unit_references_" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var data := UnitLibrary.new_document()
	data.abilities = [MISSING_SKILL]
	var path := folder.path_join(String(data.id).trim_prefix("custom_units:") + ".json")
	_write(path, data)
	var result := UnitLibrary.read_document(path, skills.catalog())
	suite.expect(not String(result.error).is_empty() and result.has("document"), "A broken skill reference keeps the unit document open for repair")
	suite.expect(result.has("document") and not UnitLibrary.validate(result.document, skills.catalog()).is_empty(), "A broken skill reference still fails full validation and loading")
	data.hp = "много"
	_write(path, data)
	suite.expect(not UnitLibrary.read_document(path, skills.catalog()).has("document"), "Structural errors never open a partial unit document")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	var nameless := UnitLibrary.new_document()
	nameless.name = " "
	suite.expect(UnitLibrary.validate(nameless, skills.catalog()) == "Поле «Имя» должно содержать текст.", "Unit validation names fields in Russian")

	var returning := SkillLibrary.new_document("active")
	returning.returns_next_turn = true
	suite.expect(skills.validate(returning).begins_with("Возврат оружия"), "Returning weapon rule is explained in the editor language")
	var summon := SkillLibrary.new_document("active")
	summon.effects = [SkillLibrary.new_effect("core:summon")]
	suite.expect(skills.validate(summon).begins_with("Призыв"), "Summon rule is explained in the editor language")
	var short := SkillLibrary.new_document("active")
	short.range = 0
	suite.expect(skills.validate(short).begins_with("Дальность"), "Zero range names the field instead of a core message")
	var unknown_state := SkillLibrary.new_document("active")
	unknown_state.effects = [SkillLibrary.new_effect("core:hex_state")]
	unknown_state.effects[0].parameters.state_id = "core:unknown"
	suite.expect(skills.validate(unknown_state).begins_with("Эффект гекса"), "Unknown hex state is reported in the editor language")


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
