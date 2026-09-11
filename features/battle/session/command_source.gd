class_name CommandSource
extends RefCounted


func is_automatic() -> bool:
	return false


func next_command(_session: BattleSession) -> BattleCommand:
	return null
