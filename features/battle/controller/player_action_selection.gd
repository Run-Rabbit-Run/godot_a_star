class_name PlayerActionSelection
extends RefCounted
## What the player is about to do with the active unit: move, attack or aim an ability, or
## aim an ability of the strategist. It shows the overlays, cursor and hovered target, and turns
## a clicked hex into a command; the session alone decides whether the command is legal.

## False while the battle presents events: the cursor then stays neutral.
var enabled := true

var _session: BattleSession
var _map_view: BattleMapView
var _hud: BattleHUD
var _unit_views: BattleUnitViewRegistry
var _content: ContentSnapshot
var _hex_grid: HexGrid
var _movement_search: MovementSearchResult
var _attackable_hexes: Array[Vector2i] = []
var _ability_hexes: Array[Vector2i] = []
var _selected_ability_id := StringName()
## The strategist ability being aimed and the hexes it may land on, possibly outside the grid.
var _strategist_ability_id := StringName()
var _strategist_hexes: Array[Vector2i] = []
## The unit whose options are shown; hover previews use it.
var _acting_unit_id := StringName()
## The last previewed command and state revision, so moving within one hex does not recompute.
var _preview_key := ""
var _preview: ActionPreview
var _previewed_actors: Array[StringName] = []
## The attack type the player chose for the unit with a choice; it applies with the next attack
## and is reset to the unit's own type when another unit is shown.
var _attack_type_unit_id := StringName()
var _attack_damage_type := StringName()


func setup(session: BattleSession, map_view: BattleMapView, hud: BattleHUD, unit_views: BattleUnitViewRegistry, content: ContentSnapshot) -> void:
	_session = session
	_map_view = map_view
	_hud = hud
	_unit_views = unit_views
	_content = content


## The grid was replaced or rebuilt: a movement search made for the previous one is stale.
func set_grid(hex_grid: HexGrid) -> void:
	_hex_grid = hex_grid
	forget_movement()


func forget_movement() -> void:
	_movement_search = null


## Resets the selection to movement and basic attacks of the unit and shows them.
func show_movement_and_attacks(state: UnitSnapshot) -> void:
	_clear_preview()
	_acting_unit_id = state.unit_id
	if _attack_type_unit_id != state.unit_id:
		_attack_type_unit_id = state.unit_id
		_attack_damage_type = state.basic_attack_damage_type
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
	_selected_ability_id = StringName()
	_ability_hexes.clear()
	_forget_strategist()
	_map_view.clear_ability_area()
	_map_view.clear_path()
	_movement_search = _session.get_movement_search(state.unit_id)
	_map_view.show_selected_hex(state.hex)
	var reachable := _movement_search.get_reachable_cells()
	reachable.erase(state.hex)
	if _session.is_unit_ai_controlled(state.unit_id):
		reachable.clear()
	_map_view.show_reachable_cells(reachable)
	_refresh_attack_targets(state)


## Hides every selection overlay; used while the battle presents events.
func clear() -> void:
	if _map_view == null:
		return
	_clear_preview()
	_map_view.clear_ranged_attack_cells()
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
	_selected_ability_id = StringName()
	_ability_hexes.clear()
	_forget_strategist()
	_attackable_hexes.clear()
	_map_view.show_targetable_cells(_attackable_hexes)
	_map_view.clear_ability_area()
	_hud.clear_target()


## The attack type the shown unit's next attack chooses, or "" when it has no choice.
func attack_damage_type() -> StringName:
	var active := _session.get_unit(_acting_unit_id) if _session != null else null
	if active == null or active.attack_damage_types.is_empty() or _attack_type_unit_id != active.unit_id:
		return StringName()
	return _attack_damage_type


## Switches the shown unit's next attack to its following damage type; false without a choice.
func cycle_attack_damage_type() -> bool:
	var active := _session.get_unit(_acting_unit_id) if _session != null else null
	if active == null or active.attack_damage_types.is_empty() or _session.is_unit_ai_controlled(active.unit_id):
		return false
	var types := active.attack_damage_types
	_attack_type_unit_id = active.unit_id
	_attack_damage_type = types[(types.find(_attack_damage_type) + 1) % types.size()]
	_clear_preview()
	return true


## True while a unit's or the strategist's ability is aimed.
func is_aiming_ability() -> bool:
	return not _selected_ability_id.is_empty() or not _strategist_ability_id.is_empty()


## Starts aiming the player's strategist ability; false when it cannot be used now.
func select_strategist_ability(ability_id: StringName) -> bool:
	var hexes := _session.get_strategist_target_hexes(BattleFaction.Value.PLAYER, ability_id)
	if hexes.is_empty():
		return false
	_clear_preview()
	_selected_ability_id = StringName()
	_ability_hexes.clear()
	_attackable_hexes.clear()
	var empty_cells: Array[Vector2i] = []
	_map_view.clear_ranged_attack_cells()
	_map_view.show_reachable_cells(empty_cells)
	_map_view.show_targetable_cells(empty_cells)
	_map_view.clear_ability_area()
	_map_view.clear_path()
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
	_strategist_ability_id = ability_id
	_strategist_hexes = hexes
	_map_view.show_landing_targets(hexes)
	var definition := _content.get_strategist_ability_definition(ability_id)
	_hud.show_strategist_targeting(definition.display_name if definition != null else String(ability_id))
	return true


## Hexes outside the grid the player may click now: the aimed strategist ability's targets.
func get_extra_target_cells() -> Array[Vector2i]:
	return _strategist_hexes.duplicate()


func _forget_strategist() -> void:
	# The aiming hint has no later event to replace it, unlike a unit's attack.
	if not _strategist_ability_id.is_empty() and _hud != null:
		_hud.clear_action()
	_strategist_ability_id = StringName()
	_strategist_hexes.clear()
	if _map_view != null:
		_map_view.clear_landing_targets()


func select_ability(active: UnitSnapshot, ability_id: StringName) -> bool:
	if (
		active == null
		or _session.is_unit_ai_controlled(active.unit_id)
		or active.health.is_defeated()
		or not active.turn.main_action_available
		or not active.ability_ids.has(ability_id)
		or active.ability_cooldowns.get(ability_id, 0) > 0
	):
		return false

	_selected_ability_id = ability_id
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
	_ability_hexes = _session.get_ability_target_hexes(active.unit_id, ability_id)
	var empty_cells: Array[Vector2i] = []
	_map_view.clear_ranged_attack_cells()
	_map_view.show_reachable_cells(empty_cells)
	_map_view.show_targetable_cells(_ability_hexes)
	_map_view.show_ability_targets(_ability_hexes)
	_map_view.clear_ability_area()
	var ability := _content.get_ability_definition(ability_id)
	_hud.show_ability_targeting(ability.display_name, ability.area_radius, ability.target_mode)
	return true


## The command a click on the hex means for the active unit, or null when it means nothing.
func command_at(active: UnitSnapshot, axial_cell: Vector2i) -> BattleCommand:
	if not _strategist_ability_id.is_empty():
		if not _strategist_hexes.has(axial_cell):
			return null
		return UseStrategistAbilityCommand.new(BattleFaction.Value.PLAYER, _strategist_ability_id, axial_cell)
	if not _selected_ability_id.is_empty():
		if not _ability_hexes.has(axial_cell):
			return null
		var selected := active.abilities.get(_selected_ability_id) as AbilitySnapshot
		if selected != null and selected.targets_hex:
			return UseAbilityCommand.at_hex(active.unit_id, axial_cell, _selected_ability_id)
		var ability_target := _session.get_unit_at(axial_cell)
		if ability_target == null:
			return null
		return UseAbilityCommand.new(active.unit_id, ability_target.unit_id, _selected_ability_id)

	var target := _session.get_unit_at(axial_cell)
	if target != null and target.unit_id != active.unit_id:
		return AttackCommand.new(active.unit_id, target.unit_id, attack_damage_type() if active.unit_id == _acting_unit_id else StringName())
	if _hex_grid.has_obstacle(axial_cell):
		return AttackObstacleCommand.new(active.unit_id, axial_cell)
	return MoveCommand.new(active.unit_id, axial_cell)


## Shows what the hex would mean: an ability area, an attack cursor or a movement path, with
## the preview of its result; a hovered opponent also shows its reach.
func hover(axial_cell: Vector2i) -> void:
	_show_overlays(axial_cell)
	_show_preview(axial_cell)


func _show_overlays(axial_cell: Vector2i) -> void:
	if not _strategist_ability_id.is_empty():
		_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
		_map_view.clear_path()
		_hud.clear_target()
		return
	if not _selected_ability_id.is_empty():
		_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
		_map_view.clear_path()

		if not _ability_hexes.has(axial_cell):
			_map_view.clear_ability_area()
			_hud.clear_target()
			return

		var active := _session.get_unit(_acting_unit_id)
		var selected := active.abilities.get(_selected_ability_id) as AbilitySnapshot
		if selected == null or (selected.area_radius <= 0 and not selected.targets_hex):
			_map_view.clear_ability_area()
			_show_hovered_target(axial_cell)
			return

		var area := _session.get_ability_affected_hexes(active.unit_id, _selected_ability_id, axial_cell)
		_map_view.show_ability_area(area)
		_hud.show_area_target(area.size())
		return

	_show_hovered_target(axial_cell)
	_update_attack_cursor(axial_cell)

	if _session != null and _session.get_unit_at(axial_cell) != null:
		_map_view.clear_path()
		return

	if _movement_search == null or _movement_search.map_revision != _session.get_map_revision():
		_map_view.clear_path()
		return

	_map_view.show_path(_movement_search.build_path(axial_cell))


func hover_exited() -> void:
	_clear_preview()
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)
	_map_view.clear_path()
	_map_view.clear_ability_area()
	_hud.clear_target()


func _update_attack_cursor(axial_cell: Vector2i) -> void:
	_map_view.set_cursor_mode(BattleMapView.CursorMode.DEFAULT)

	if _session == null or not enabled or not _attackable_hexes.has(axial_cell):
		return

	var active_unit_id := _acting_unit_id
	var active := _session.get_unit(active_unit_id)
	var target := _session.get_unit_at(axial_cell)
	# Attackable hexes come from the session, so an obstacle hex among them is a legal target.
	if active != null and _hex_grid.has_obstacle(axial_cell) and not _session.is_unit_ai_controlled(active_unit_id):
		_map_view.set_cursor_mode(BattleMapView.CursorMode.RANGED if BasicAttackRules.is_shot(active.basic_attack_range, active.hex, axial_cell) else BattleMapView.CursorMode.MELEE)
		return

	if (
		active == null
		or target == null
		or _session.is_unit_ai_controlled(active_unit_id)
		or not active.turn.main_action_available
		or target.faction == active.faction
	):
		return

	_map_view.set_cursor_mode(
		BattleMapView.CursorMode.RANGED
		if BasicAttackRules.is_shot(active.basic_attack_range, active.hex, axial_cell)
		else BattleMapView.CursorMode.MELEE
	)


func _show_hovered_target(axial_cell: Vector2i) -> void:
	if _session == null:
		_hud.clear_target()
		return

	var target := _session.get_unit_at(axial_cell)

	if target == null:
		_hud.clear_target()
		return

	var presentation := _unit_views.presentations.get(target.unit_id) as UnitPresentationDefinition
	_hud.show_target(
		_unit_views.get_display_name(target.unit_id),
		presentation.actor_texture if presentation != null else null,
		("Союзник" if target.faction == BattleFaction.Value.PLAYER else "Противник") + _objective_role(target.unit_id),
		target.health.current,
		target.health.maximum,
		target.basic_attack_damage,
		target.basic_attack_range,
		target.turn.movement_remaining,
		target.turn.movement_max,
		target.turn.main_action_available,
		target.statuses
	)


func _refresh_attack_targets(state: UnitSnapshot) -> void:
	_attackable_hexes.clear()
	_map_view.show_targetable_cells(_attackable_hexes)
	_map_view.clear_ranged_attack_cells()

	if state == null or state.health.is_defeated():
		return

	var opponent_hexes: Array[Vector2i] = []
	for opponent: UnitSnapshot in _session.get_living_opponents(state.faction):
		opponent_hexes.append(opponent.hex)
	# An engaged ranged unit only strikes its neighbors, so it gets the melee highlight.
	var shoots := state.basic_attack_range > 1 and not BasicAttackRules.is_engaged(state.hex, opponent_hexes)
	if shoots:
		var range_cells := _hex_grid.get_cells_in_range(state.hex, state.basic_attack_range)
		var enemy_cells: Array[Vector2i] = []
		for opponent_hex: Vector2i in opponent_hexes:
			if range_cells.has(opponent_hex):
				enemy_cells.append(opponent_hex)
		_map_view.show_ranged_attack_cells(range_cells, enemy_cells)

	if _session.is_unit_ai_controlled(state.unit_id):
		return

	for target: UnitSnapshot in _session.get_attackable_targets(state.unit_id):
		_attackable_hexes.append(target.hex)

	_attackable_hexes.append_array(_session.get_attackable_obstacle_hexes(state.unit_id))
	if not shoots:
		_map_view.show_targetable_cells(_attackable_hexes)


func _show_preview(axial_cell: Vector2i) -> void:
	_clear_preview()
	if _session == null or not enabled:
		return
	var active := _session.get_unit(_acting_unit_id)
	if active == null or _session.is_unit_ai_controlled(active.unit_id):
		return
	var hovered := _session.get_unit_at(axial_cell)
	if hovered != null and hovered.faction != active.faction and _selected_ability_id.is_empty():
		var reach := _session.get_reach(hovered.unit_id)
		_map_view.show_unit_reach(reach.move, reach.attack)
	var command := _previewable_command(active, axial_cell)
	if command == null:
		return
	var key := "%s|%d" % [_command_key(command), _session.get_state_revision()]
	if key != _preview_key:
		_preview_key = key
		_preview = _session.preview(command)
	if not _preview.accepted:
		return
	var factions: Dictionary[StringName, int] = {}
	for unit_id: StringName in _preview.units:
		var snapshot := _session.get_unit(unit_id)
		factions[unit_id] = snapshot.faction if snapshot != null else active.faction
	factions[active.unit_id] = active.faction
	for unit_id: StringName in _preview.units:
		var change := _preview.units[unit_id] as ActionPreview.UnitChange
		var actor := _unit_views.actors.get(unit_id) as UnitActor
		if actor != null and change.health_after < change.health_before:
			actor.show_health_preview(change.health_after, change.defeated)
			_previewed_actors.append(unit_id)
	var summary := ActionPreviewText.describe(_preview, _unit_views.definitions, factions, command is MoveCommand)
	_map_view.show_action_preview(summary.lines, summary.warning)


## The command worth previewing at the hex: an aimed ability target, an attackable target or
## a reachable empty hex; null otherwise.
func _previewable_command(active: UnitSnapshot, axial_cell: Vector2i) -> BattleCommand:
	if not _strategist_ability_id.is_empty():
		return null
	if not _selected_ability_id.is_empty():
		return command_at(active, axial_cell) if _ability_hexes.has(axial_cell) else null
	if _attackable_hexes.has(axial_cell):
		return command_at(active, axial_cell)
	if (
		axial_cell != active.hex
		and _session.get_unit_at(axial_cell) == null
		and not _hex_grid.has_obstacle(axial_cell)
		and _movement_search != null
		and _movement_search.map_revision == _session.get_map_revision()
		and _movement_search.get_cost(axial_cell) > 0
	):
		return MoveCommand.new(active.unit_id, axial_cell)
	return null


func _clear_preview() -> void:
	for unit_id: StringName in _previewed_actors:
		var actor := _unit_views.actors.get(unit_id) as UnitActor
		if is_instance_valid(actor):
			actor.clear_health_preview()
	_previewed_actors.clear()
	if _map_view != null:
		_map_view.clear_unit_reach()
		_map_view.clear_action_preview()


static func _command_key(command: BattleCommand) -> String:
	if command is MoveCommand:
		return "move:%s:%s" % [command.unit_id, command.destination]
	if command is AttackCommand:
		return "attack:%s:%s:%s" % [command.attacker_id, command.target_id, command.damage_type]
	if command is AttackObstacleCommand:
		return "obstacle:%s:%s" % [command.attacker_id, command.target_hex]
	if command is UseAbilityCommand:
		return "ability:%s:%s:%s:%s" % [command.user_id, command.ability_id, command.target_id, command.target_hex]
	return ""


## " · командир" or " · под защитой" for a unit the objective names, otherwise "".
func _objective_role(unit_id: StringName) -> String:
	if _session.get_objective_target_ids().has(unit_id):
		return " · командир"
	if _session.get_protected_unit_ids().has(unit_id):
		return " · под защитой"
	return ""
