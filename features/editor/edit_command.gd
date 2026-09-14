class_name EditCommand
extends RefCounted


enum Kind {
	ADD_PLACEMENT,
	MOVE_PLACEMENT,
	UPDATE_PLACEMENT,
	DUPLICATE_PLACEMENT,
	REMOVE_PLACEMENT,
	ADD_HEX,
	UPDATE_HEX,
	REMOVE_HEX,
}


var kind: Kind
var placement: UnitPlacementDefinition
var placement_id: StringName
var target_hex: Vector2i
var map_cell: BattleMapCellDefinition
var _before: EditorDocument


func _init(p_kind: Kind) -> void:
	kind = p_kind


static func add_placement(value: UnitPlacementDefinition) -> EditCommand:
	var command := EditCommand.new(Kind.ADD_PLACEMENT)
	command.placement = value.duplicate(true) as UnitPlacementDefinition
	return command


static func move_placement(
	p_placement_id: StringName,
	p_target_hex: Vector2i
) -> EditCommand:
	var command := EditCommand.new(Kind.MOVE_PLACEMENT)
	command.placement_id = p_placement_id
	command.target_hex = p_target_hex
	return command


static func update_placement(value: UnitPlacementDefinition) -> EditCommand:
	var command := EditCommand.new(Kind.UPDATE_PLACEMENT)
	command.placement = value.duplicate(true) as UnitPlacementDefinition
	command.placement_id = value.placement_id
	return command


static func duplicate_placement(
	p_placement_id: StringName,
	new_id: StringName,
	p_target_hex: Vector2i
) -> EditCommand:
	var command := EditCommand.new(Kind.DUPLICATE_PLACEMENT)
	command.placement_id = p_placement_id
	command.target_hex = p_target_hex
	command.placement = UnitPlacementDefinition.new()
	command.placement.placement_id = new_id
	return command


static func remove_placement(p_placement_id: StringName) -> EditCommand:
	var command := EditCommand.new(Kind.REMOVE_PLACEMENT)
	command.placement_id = p_placement_id
	return command


static func add_hex(
	hex: Vector2i,
	terrain_id: StringName = &"core:default",
	movement_cost: int = 1,
	traversable: bool = true
) -> EditCommand:
	var command := EditCommand.new(Kind.ADD_HEX)
	command.target_hex = hex
	command.map_cell = BattleMapCellDefinition.new(
		hex,
		movement_cost,
		terrain_id,
		traversable
	)
	return command


static func update_hex(value: BattleMapCellDefinition) -> EditCommand:
	var command := EditCommand.new(Kind.UPDATE_HEX)
	command.target_hex = value.hex
	command.map_cell = value.duplicate(true) as BattleMapCellDefinition
	return command


static func remove_hex(hex: Vector2i) -> EditCommand:
	var command := EditCommand.new(Kind.REMOVE_HEX)
	command.target_hex = hex
	return command


func apply(document: EditorDocument) -> bool:
	if document == null or _before != null:
		return false

	_before = document.duplicate_document()

	match kind:
		Kind.ADD_PLACEMENT:
			document.battle_definition.unit_placements.append(
				placement.duplicate(true) as UnitPlacementDefinition
			)

		Kind.MOVE_PLACEMENT:
			var moved := _find_placement(document, placement_id)
			if moved == null:
				return _restore_failed(document)
			moved.start_hex = target_hex

		Kind.UPDATE_PLACEMENT:
			var index := _find_placement_index(document, placement_id)
			if index < 0:
				return _restore_failed(document)
			document.battle_definition.unit_placements[index] = placement.duplicate(true)

		Kind.DUPLICATE_PLACEMENT:
			var source := _find_placement(document, placement_id)
			if source == null:
				return _restore_failed(document)
			var copy := source.duplicate(true) as UnitPlacementDefinition
			copy.placement_id = placement.placement_id
			copy.start_hex = target_hex
			document.battle_definition.unit_placements.append(copy)

		Kind.REMOVE_PLACEMENT:
			var index := _find_placement_index(document, placement_id)
			if index < 0:
				return _restore_failed(document)
			document.battle_definition.unit_placements.remove_at(index)

		Kind.ADD_HEX:
			for cell: BattleMapCellDefinition in document.map_definition.cells:
				if cell.hex == target_hex:
					return _restore_failed(document)
			document.map_definition.cells.append(
				map_cell.duplicate(true) as BattleMapCellDefinition
			)

		Kind.UPDATE_HEX:
			var index := _find_cell_index(document, target_hex)
			if index < 0:
				return _restore_failed(document)
			document.map_definition.cells[index] = (
				map_cell.duplicate(true) as BattleMapCellDefinition
			)

		Kind.REMOVE_HEX:
			var index := _find_cell_index(document, target_hex)
			if index < 0:
				return _restore_failed(document)
			document.map_definition.cells.remove_at(index)

	return true


func revert(document: EditorDocument) -> bool:
	if document == null or _before == null:
		return false

	var snapshot := _before
	_before = null
	document.copy_from(snapshot)
	return true


func _restore_failed(document: EditorDocument) -> bool:
	document.copy_from(_before)
	_before = null
	return false


func _find_placement(
	document: EditorDocument,
	id: StringName
) -> UnitPlacementDefinition:
	var index := _find_placement_index(document, id)
	return document.battle_definition.unit_placements[index] if index >= 0 else null


func _find_placement_index(document: EditorDocument, id: StringName) -> int:
	for index: int in range(document.battle_definition.unit_placements.size()):
		if document.battle_definition.unit_placements[index].placement_id == id:
			return index
	return -1


func _find_cell_index(document: EditorDocument, hex: Vector2i) -> int:
	for index: int in range(document.map_definition.cells.size()):
		if document.map_definition.cells[index].hex == hex:
			return index
	return -1
