class_name AbilitySnapshot
extends RefCounted
## Read-only targeting data of one ability as its unit would use it now. Affected cells and
## legal targets are asked from the session, never re-derived from these fields.

var id: StringName
## Effective range: the unit's basic attack range when the ability uses it.
var range: int
var area_radius: int
var target_mode: AbilityDefinition.TargetMode
var targets_hex: bool


func _init(ability: AbilityDefinition, unit: UnitState) -> void:
	id = ability.id
	range = ability.get_range(unit)
	area_radius = ability.area_radius
	target_mode = ability.target_mode
	targets_hex = ability.targets_hex()
