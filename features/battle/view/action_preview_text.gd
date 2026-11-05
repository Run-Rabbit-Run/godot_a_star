class_name ActionPreviewText
extends RefCounted
## Lines of the summary next to the cursor for an ActionPreview.

const MAX_LISTED_HEXES := 3


## Summary lines, and whether the preview warns: the actor or an ally dies, or a route stops short.
static func describe(preview: ActionPreview, units: Dictionary[StringName, UnitDefinition], factions: Dictionary[StringName, int], is_move: bool) -> Dictionary:
	var lines: PackedStringArray = []
	var warning := false
	var actor_faction: int = factions.get(preview.actor_id, -1)
	if is_move and not preview.reached:
		var mover := preview.units.get(preview.actor_id) as ActionPreview.UnitChange
		if mover != null and mover.defeated:
			lines.append("Маршрут смертелен")
		else:
			lines.append("Маршрут оборвётся на %d, %d" % [preview.destination.x, preview.destination.y])
		warning = true
	var ids := preview.units.keys()
	ids.sort()
	# The acting unit first, then the others.
	if ids.has(preview.actor_id):
		ids.erase(preview.actor_id)
		ids.push_front(preview.actor_id)
	for unit_id: StringName in ids:
		var change := preview.units[unit_id] as ActionPreview.UnitChange
		var parts: PackedStringArray = []
		if change.health_after != change.health_before:
			parts.append("%d → %d ОЗ" % [change.health_before, change.health_after])
		if change.defeated:
			parts.append("гибель")
			warning = warning or factions.get(unit_id, -2) == actor_faction
		for status: StringName in change.statuses_after:
			if change.statuses_after[status] > change.statuses_before.get(status, 0):
				parts.append("%s ×%d" % [UnitStatusCatalog.display_name(status), change.statuses_after[status]])
		if parts.is_empty():
			continue
		var definition := units.get(unit_id) as UnitDefinition
		var name := definition.display_name if definition != null else String(unit_id)
		lines.append("%s: %s" % [name, ", ".join(parts)])
	var hexes := preview.hexes.keys()
	hexes.sort()
	if hexes.size() > MAX_LISTED_HEXES:
		lines.append("Изменится гексов: %d" % hexes.size())
	else:
		for hex: Vector2i in hexes:
			var layers: Array = preview.hexes[hex]
			lines.append("Гекс %d, %d: %s → %s" % [hex.x, hex.y, _layers(layers[0], layers[1]), _layers(layers[2], layers[3])])
	var obstacle_damage := 0
	for hex: Vector2i in preview.obstacle_damage:
		obstacle_damage = maxi(obstacle_damage, preview.obstacle_damage[hex])
	if obstacle_damage > 0:
		lines.append("Препятствие: −%d HP" % obstacle_damage)
	for flask: BattleObstacleDefinition in preview.broken_flasks:
		lines.append("%s разобьётся" % ObstacleDescription.display_name(flask))
	return {"lines": lines, "warning": warning}


static func _layers(liquid: StringName, energy: StringName) -> String:
	var names: PackedStringArray = []
	for id: StringName in [liquid, energy]:
		if not id.is_empty():
			names.append(HexStateCatalog.get_display_name(id))
	return " + ".join(names) if not names.is_empty() else "пусто"
