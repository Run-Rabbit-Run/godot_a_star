class_name EditorObjectivePanel
extends RefCounted
## Objective controls of the battle editor: the objective card of the field page and the
## commander/protected marks of the selected unit. Shows the document's objective and reports
## an edited copy; the shell turns it into an EditCommand.

signal objective_changed(objective: BattleObjectiveDefinition)

const TYPE_NAMES := {
	BattleObjectiveType.Value.ELIMINATE_FACTION: "Уничтожить противника",
	BattleObjectiveType.Value.SURVIVE_ROUNDS: "Продержаться N раундов",
	BattleObjectiveType.Value.ELIMINATE_TARGETS: "Убить командира",
}

var type_option: OptionButton
var description_edit: LineEdit
var rounds_spin: SpinBox
var round_limit_spin: SpinBox
var summary: Label
var commander_check: CheckButton
var protected_check: CheckButton

var _rounds_row: Array[Control] = []
var _document: BattleDocument
var _placement_id := StringName()
## True while controls are filled from the document, so their signals report nothing.
var _showing := false


## The objective card on the field page.
func build_card(page: VBoxContainer) -> void:
	var card := EditorUi.card(page, "ЦЕЛЬ БОЯ")
	var form := EditorUi.form(card)
	type_option = OptionButton.new()
	for type: int in TYPE_NAMES:
		type_option.add_item(TYPE_NAMES[type])
		type_option.set_item_metadata(type_option.item_count - 1, type)
	EditorUi.row(form, "Цель", type_option, "Условие победы. Уничтожение противника побеждает при любой цели.")
	description_edit = LineEdit.new()
	description_edit.placeholder_text = "Текст цели в бою"
	EditorUi.row(form, "Описание", description_edit, "Строка цели в HUD боя.")
	rounds_spin = EditorUi.spin(1, BattleObjectiveDefinition.MAX_ROUND_LIMIT)
	_rounds_row = [EditorUi.row(form, "Раундов", rounds_spin, "Победа, когда закончился этот раунд."), rounds_spin]
	round_limit_spin = EditorUi.spin(1, BattleObjectiveDefinition.MAX_ROUND_LIMIT)
	EditorUi.row(form, "Лимит раундов", round_limit_spin, "Бой, не выигранный к концу этого раунда, проигран.")
	summary = EditorUi.hint("")
	card.add_child(summary)
	card.add_child(EditorUi.hint("Командиров и защищаемых юнитов отметьте в карточке юнита на вкладке «Инспектор». Гибель защищаемого юнита — поражение при любой цели."))
	type_option.item_selected.connect(func(_index: int) -> void: _report())
	description_edit.text_submitted.connect(func(_text: String) -> void: _report())
	description_edit.focus_exited.connect(_report)
	rounds_spin.value_changed.connect(func(_value: float) -> void: _report())
	round_limit_spin.value_changed.connect(func(_value: float) -> void: _report())


## The marks of the selected unit, placed into the unit card.
func build_marks(card: VBoxContainer) -> void:
	commander_check = CheckButton.new()
	commander_check.text = "Командир"
	commander_check.tooltip_text = "Цель «Убить командира»: юнит противника, которого нужно уничтожить."
	protected_check = CheckButton.new()
	protected_check.text = "Под защитой"
	protected_check.tooltip_text = "Юнит игрока, гибель которого означает поражение."
	var row := HBoxContainer.new()
	row.add_child(commander_check)
	row.add_child(protected_check)
	card.add_child(row)
	commander_check.toggled.connect(func(_value: bool) -> void: _report())
	protected_check.toggled.connect(func(_value: bool) -> void: _report())


## Fills the controls from the document's objective and the selected placement.
func show_state(document: BattleDocument, placement_id: StringName) -> void:
	_document = document
	_placement_id = placement_id
	var objective := _objective()
	_showing = true
	if objective != null:
		for index in range(type_option.item_count):
			if type_option.get_item_metadata(index) == objective.type:
				type_option.select(index)
		if not description_edit.has_focus():
			description_edit.text = objective.description
		round_limit_spin.value = objective.round_limit
		rounds_spin.max_value = objective.round_limit
		rounds_spin.value = objective.rounds
		summary.text = "Командиров: %d · защищаемых: %d" % [objective.target_placement_ids.size(), objective.protected_placement_ids.size()]
	for control: Control in _rounds_row:
		control.visible = objective != null and objective.type == BattleObjectiveType.Value.SURVIVE_ROUNDS
	var faction := _placement_faction(placement_id)
	commander_check.visible = not placement_id.is_empty()
	protected_check.visible = not placement_id.is_empty()
	commander_check.disabled = objective == null or faction != objective.target_faction or objective.type != BattleObjectiveType.Value.ELIMINATE_TARGETS
	protected_check.disabled = objective == null or faction != document.battle_definition.protected_faction
	commander_check.button_pressed = objective != null and objective.target_placement_ids.has(placement_id)
	protected_check.button_pressed = objective != null and objective.protected_placement_ids.has(placement_id)
	_showing = false


## The objective as the controls show it: a copy of the document's objective.
func edited_objective() -> BattleObjectiveDefinition:
	var objective := _objective().duplicate(true) as BattleObjectiveDefinition
	var type: BattleObjectiveType.Value = type_option.get_selected_metadata()
	if type != objective.type and description_edit.text == default_description(objective):
		description_edit.text = ""
	objective.type = type
	objective.round_limit = int(round_limit_spin.value)
	objective.rounds = mini(int(rounds_spin.value), objective.round_limit)
	objective.description = description_edit.text.strip_edges() if not description_edit.text.strip_edges().is_empty() else default_description(objective)
	if not _placement_id.is_empty():
		_mark(objective.target_placement_ids, commander_check.button_pressed and not commander_check.disabled)
		_mark(objective.protected_placement_ids, protected_check.button_pressed and not protected_check.disabled)
	return objective


## The description a new or retyped objective gets.
static func default_description(objective: BattleObjectiveDefinition) -> String:
	match objective.type:
		BattleObjectiveType.Value.SURVIVE_ROUNDS:
			return "Продержаться %d раундов" % objective.rounds
		BattleObjectiveType.Value.ELIMINATE_TARGETS:
			return "Убить командира"
	return "Уничтожить противника"


func _report() -> void:
	if _showing or _objective() == null:
		return
	var edited := edited_objective()
	if BattleDocumentSerializer.to_dictionary(_with(edited)) != BattleDocumentSerializer.to_dictionary(_document):
		objective_changed.emit(edited)


func _with(objective: BattleObjectiveDefinition) -> BattleDocument:
	var copy := _document.duplicate_document()
	copy.battle_definition.primary_objective = objective
	return copy


func _mark(ids: Array[StringName], marked: bool) -> void:
	if marked and not ids.has(_placement_id):
		ids.append(_placement_id)
	elif not marked:
		ids.erase(_placement_id)


func _objective() -> BattleObjectiveDefinition:
	return _document.battle_definition.primary_objective if _document != null else null


func _placement_faction(placement_id: StringName) -> int:
	if _document == null:
		return -1
	for placement: UnitPlacementDefinition in _document.battle_definition.unit_placements:
		if placement.placement_id == placement_id:
			for side: BattleSideDefinition in _document.battle_definition.sides:
				if side.side_id == placement.side_id:
					return side.faction
	return -1
