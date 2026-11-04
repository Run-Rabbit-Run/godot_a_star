class_name CorpseRemovedEvent
extends BattleEvent
## The body of a defeated unit was destroyed with the hex it lay on.

var unit_id: StringName
var hex: Vector2i


func _init(p_unit_id: StringName, p_hex: Vector2i) -> void:
	unit_id = p_unit_id
	hex = p_hex
