class_name BattleLogFormatter
extends RefCounted
## Converts authoritative events to plain text without changing battle state.

static func describe(event: BattleEvent, units: Dictionary[StringName, UnitDefinition], content: ContentSnapshot) -> String:
	if event is UnitMovedEvent:
		return "%s перемещается в %s (движение: %d)." % [_unit(event.unit_id, units), _hex(event.path.back()) if not event.path.is_empty() else "—", event.movement_cost]
	if event is UnitDamagedEvent:
		var source := _unit(event.attacker_id, units)
		if not event.source_hex_state_id.is_empty():
			source = HexStateCatalog.get_display_name(event.source_hex_state_id)
		if not event.source_status_id.is_empty():
			source = UnitStatusCatalog.display_name(event.source_status_id)
			if event.source_status_id in [&"core:burning", &"core:plasma", &"core:electrified"]:
				source += " (конец хода)"
		var text := "%s → %s: %d урона (%s), осталось %d ОЗ.\n  Расчёт: %s" % [source, _unit(event.target_id, units), event.damage, _damage_type(event.damage_type), event.target_health_remaining, _damage_formula(event, content)]
		if event.target_defeated:
			text += " %s погибает." % _unit(event.target_id, units)
		return text
	if event is AbilityUsedEvent:
		return "%s применяет «%s» к %s." % [_unit(event.user_id, units), _ability(event.ability_id, content), _unit(event.target_id, units)]
	if event is AreaAbilityUsedEvent:
		return "%s применяет «%s» в %s." % [_unit(event.user_id, units), _ability(event.ability_id, content), _hex(event.target_hex)]
	if event is UnitSummonedEvent:
		return "%s призывает %s в %s." % [_unit(event.summoner_id, units), event.definition.display_name, _hex(event.unit.hex)]
	if event is UnitStatusChangedEvent:
		var changes: PackedStringArray = []
		for id: StringName in event.previous_statuses:
			if not event.statuses.has(id):
				changes.append("%s снят" % UnitStatusCatalog.display_name(id))
		for id: StringName in event.statuses:
			if event.statuses[id] != event.previous_statuses.get(id, 0):
				changes.append("%s ×%d" % [UnitStatusCatalog.display_name(id), event.statuses[id]])
		return "%s: %s." % [_unit(event.unit_id, units), ", ".join(changes)] if not changes.is_empty() else ""
	if event is TurnEndedEvent:
		if event.was_skipped:
			return "Ход %s пропущен из-за паралича; эффекты конца хода применены." % _unit(event.previous_unit_id, units)
		return "%s завершает ход." % _unit(event.previous_unit_id, units)
	if event is MapMutationEvent:
		if event.kind == MapMutationKind.Value.APPLY_HEX_STATE:
			return "Гекс %s: %s." % [_hex(event.hex), HexStateCatalog.get_display_name(event.hex_state_id) if not event.hex_state_id.is_empty() else "состояние снято"]
		var actions := ["добавлен", "удалён", "местность изменена", "проходимость изменена"]
		return "Гекс %s: %s." % [_hex(event.hex), actions[event.kind]]
	return ""


static func _unit(id: StringName, units: Dictionary[StringName, UnitDefinition]) -> String:
	var definition := units.get(id) as UnitDefinition
	return definition.display_name if definition != null else String(id)


static func _ability(id: StringName, content: ContentSnapshot) -> String:
	var definition := content.get_ability_definition(id) if content != null else null
	return definition.display_name if definition != null else String(id)


static func _hex(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]


static func _damage_type(id: StringName) -> String:
	return {&"physical": "физический", &"fire": "огненный", &"electric": "электрический", &"water": "водный", &"acid": "кислотный", &"plasma": "плазменный"}.get(id, String(id))


static func _damage_formula(event: UnitDamagedEvent, content: ContentSnapshot) -> String:
	var origin := "базовая атака"
	if not event.source_ability_id.is_empty():
		origin = "умение: %s" % _ability(event.source_ability_id, content)
	if not event.source_hex_state_id.is_empty():
		origin = "гекс: %s" % HexStateCatalog.get_display_name(event.source_hex_state_id)
	if not event.source_status_id.is_empty():
		origin = "статус: %s" % UnitStatusCatalog.display_name(event.source_status_id)
	var formula := "%d (%s)" % [event.base_damage, origin]
	for modifier: Dictionary in event.damage_modifiers:
		var id: StringName = modifier.source_id
		var amount: int = modifier.amount
		var reason := "защита от дальнего урона"
		if UnitStatusCatalog.has_status(id):
			reason = UnitStatusCatalog.display_name(id)
		elif id != &"ranged_protection":
			reason = "гекс: %s" % HexStateCatalog.get_display_name(id)
		formula += " %s %d (%s)" % ["+" if amount > 0 else "−", absi(amount), reason]
	formula += " = %d." % event.calculated_damage
	if event.calculated_damage > event.damage:
		formula += " Снято %d ОЗ: у цели оставалось %d ОЗ." % [event.damage, event.damage]
	return formula
