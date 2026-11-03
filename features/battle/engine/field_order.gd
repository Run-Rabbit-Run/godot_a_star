class_name FieldOrder
extends RefCounted
## Order of units by their place on the field: the player's from the top-left, the enemy's
## from the top-right. Rows run horizontally, so "top" is the smaller axial r and "left" the
## smaller q within a row. It picks a phase's default unit, the AI's next unit and the order
## of simultaneous effects; the order units were placed in never matters.


## True when the unit at `a_hex` comes before the unit at `b_hex`; both belong to `faction`.
static func is_before(faction: BattleFaction.Value, a_hex: Vector2i, a_id: StringName, b_hex: Vector2i, b_id: StringName) -> bool:
	if a_hex.y != b_hex.y:
		return a_hex.y < b_hex.y
	if a_hex.x != b_hex.x:
		return a_hex.x < b_hex.x if faction == BattleFaction.Value.PLAYER else a_hex.x > b_hex.x
	# Bodies may share a hex: their ids keep the order stable.
	return String(a_id) < String(b_id)


## The player's units first, then the enemy's, each in field order.
static func sort_ids(ids: Array[StringName], units: Dictionary[StringName, UnitState]) -> Array[StringName]:
	var sorted: Array[StringName] = []
	for unit_id: StringName in ids:
		if units.has(unit_id):
			sorted.append(unit_id)
	sorted.sort_custom(func(left: StringName, right: StringName) -> bool:
		var a: UnitState = units[left]
		var b: UnitState = units[right]
		if a.faction != b.faction:
			return a.faction == BattleFaction.Value.PLAYER
		return is_before(a.faction, a.hex, a.unit_id, b.hex, b.unit_id)
	)
	return sorted
