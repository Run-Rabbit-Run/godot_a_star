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
	SET_BACKGROUND,
	SET_NAME,
	PUT_OBSTACLE,
	REMOVE_OBSTACLE,
}


var obstacle: BattleObstacleDefinition
var obstacle_id: StringName

var background_id: StringName
var display_name := ""
var kind: Kind
var placement: UnitPlacementDefinition
var placement_id: StringName
var target_hex: Vector2i
var map_cell: BattleMapCellDefinition
var _before: BattleDocument


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


static func set_background(id: StringName) -> EditCommand:
	var command := EditCommand.new(Kind.SET_BACKGROUND)
	command.background_id = id
	return command


static func rename_document(value: String) -> EditCommand:
	var command := EditCommand.new(Kind.SET_NAME)
	command.display_name = value
	return command


static func put_obstacle(value: BattleObstacleDefinition, replace_id: StringName = &"") -> EditCommand:
	var command := EditCommand.new(Kind.PUT_OBSTACLE)
	command.obstacle = value.duplicate(true) as BattleObstacleDefinition
	command.obstacle_id = replace_id
	return command

static func remove_obstacle(id: StringName) -> EditCommand:
	var command := EditCommand.new(Kind.REMOVE_OBSTACLE)
	command.obstacle_id = id
	return command

func apply(document: BattleDocument) -> bool:
	if document == null or _before != null:
		return false

	_before = document.duplicate_document()

	match kind:
		Kind.PUT_OBSTACLE:
			if not obstacle.validate().is_empty():
				return _restore_failed(document)
			if not obstacle_id.is_empty() and not _remove_obstacle(document, obstacle_id):
				return _restore_failed(document)
			for hex: Vector2i in obstacle.hexes:
				if _find_cell_index(document, hex) < 0 or not document.map_definition.cells[_find_cell_index(document, hex)].traversable:
					return _restore_failed(document)
				for placed: UnitPlacementDefinition in document.battle_definition.unit_placements:
					if placed.start_hex == hex:
						return _restore_failed(document)
				for existing: BattleObstacleDefinition in document.map_definition.obstacles:
					if existing.id == obstacle.id or existing.hexes.has(hex):
						return _restore_failed(document)
			for hex: Vector2i in obstacle.hexes:
				var cell := document.map_definition.cells[_find_cell_index(document, hex)]
				if not cell.hex_state_id.is_empty():
					cell.hex_state_id = &""
					cell.movement_cost = 1
			document.map_definition.obstacles.append(obstacle.duplicate(true) as BattleObstacleDefinition)
		Kind.REMOVE_OBSTACLE:
			if not _remove_obstacle(document, obstacle_id):
				return _restore_failed(document)
		Kind.SET_NAME:
			document.display_name = display_name

		Kind.SET_BACKGROUND:
			document.map_definition.background_id = background_id

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
			for existing: BattleObstacleDefinition in document.map_definition.obstacles:
				if existing.hexes.has(target_hex) and (not map_cell.hex_state_id.is_empty() or not map_cell.traversable):
					return _restore_failed(document)
			var index := _find_cell_index(document, target_hex)
			if index < 0:
				return _restore_failed(document)
			document.map_definition.cells[index] = (
				map_cell.duplicate(true) as BattleMapCellDefinition
			)

		Kind.REMOVE_HEX:
			for existing: BattleObstacleDefinition in document.map_definition.obstacles:
				if existing.hexes.has(target_hex):
					return _restore_failed(document)
			var index := _find_cell_index(document, target_hex)
			if index < 0:
				return _restore_failed(document)
			document.map_definition.cells.remove_at(index)

	return true


func revert(document: BattleDocument) -> bool:
	if document == null or _before == null:
		return false

	var snapshot := _before
	_before = null
	document.copy_from(snapshot)
	return true


func _restore_failed(document: BattleDocument) -> bool:
	document.copy_from(_before)
	_before = null
	return false


func _find_placement(
	document: BattleDocument,
	id: StringName
) -> UnitPlacementDefinition:
	var index := _find_placement_index(document, id)
	return document.battle_definition.unit_placements[index] if index >= 0 else null


func _find_placement_index(document: BattleDocument, id: StringName) -> int:
	for index: int in range(document.battle_definition.unit_placements.size()):
		if document.battle_definition.unit_placements[index].placement_id == id:
			return index
	return -1


func _find_cell_index(document: BattleDocument, hex: Vector2i) -> int:
	for index: int in range(document.map_definition.cells.size()):
		if document.map_definition.cells[index].hex == hex:
			return index
	return -1


func _remove_obstacle(document: BattleDocument, id: StringName) -> bool:
	for index in range(document.map_definition.obstacles.size()):
		if document.map_definition.obstacles[index].id == id:
			document.map_definition.obstacles.remove_at(index)
			return true
	return false
