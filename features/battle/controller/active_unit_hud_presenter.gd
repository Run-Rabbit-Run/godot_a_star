class_name ActiveUnitHudPresenter
extends RefCounted
## Fills the HUD panels of the active unit and the turn order from read-only session snapshots.

var _session: BattleSession
var _hud: BattleHUD
var _unit_views: BattleUnitViewRegistry
var _content: ContentSnapshot


func setup(session: BattleSession, hud: BattleHUD, unit_views: BattleUnitViewRegistry, content: ContentSnapshot) -> void:
	_session = session
	_hud = hud
	_unit_views = unit_views
	_content = content


func show(state: UnitSnapshot) -> void:
	_hud.show_round(_session.get_round_number())
	_hud.show_health(state.health.current, state.health.maximum)
	_hud.show_movement(state.turn.movement_remaining, state.turn.movement_max)
	_hud.show_main_action(state.turn.main_action_available)
	var abilities: Array[AbilityDefinition] = []

	if not _session.is_unit_ai_controlled(state.unit_id):
		for ability_id: StringName in state.ability_ids:
			abilities.append(_content.get_ability_definition(ability_id))

	_hud.show_abilities(
		abilities,
		state.turn.main_action_available and not state.health.is_defeated(),
		state.ability_cooldowns,
		{"attack_damage": state.basic_attack_damage, "attack_range": state.basic_attack_range}
	)

	var definition := _unit_views.definitions.get(state.unit_id) as UnitDefinition

	if definition == null:
		push_error("Active unit definition is not registered.")
		return

	_hud.show_active_unit(definition.display_name)
	var presentation := _unit_views.presentations.get(state.unit_id) as UnitPresentationDefinition
	_hud.show_active_portrait(presentation.actor_texture if presentation != null else null)
	_hud.show_combat_stats(state.basic_attack_damage, state.basic_attack_range)
	var opponent_hexes: Array[Vector2i] = []
	for opponent: UnitSnapshot in _session.get_living_opponents(state.faction):
		opponent_hexes.append(opponent.hex)
	# An engaged ranged unit cannot shoot: its button names the melee strike.
	var reach := 1 if BasicAttackRules.is_engaged(state.hex, opponent_hexes) else state.basic_attack_range
	_hud.show_basic_attack_button(reach, state.turn.main_action_available)
	_show_turn_order()


func _show_turn_order() -> void:
	var entries: Array[Dictionary] = []

	for unit_id: StringName in _session.get_turn_order():
		var state := _session.get_unit(unit_id)

		if state == null:
			continue

		var definition := _unit_views.definitions.get(unit_id) as UnitDefinition
		var presentation := _unit_views.presentations.get(unit_id) as UnitPresentationDefinition
		var display_name := String(unit_id)
		var texture: Texture2D

		if definition != null:
			display_name = definition.display_name

		if presentation != null:
			texture = presentation.portrait_texture if presentation.portrait_texture != null else presentation.actor_texture

		entries.append({
			"unit_id": unit_id,
			"short_name": display_name.left(7).to_upper(),
			"texture": texture,
			"faction": state.faction,
			"defeated": state.health.is_defeated(),
		})

	_hud.show_turn_order(entries, _session.get_active_unit_id())
