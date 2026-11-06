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


## `attack_type` is the type the unit's next attack takes, "" for a unit without a choice.
func show(state: UnitSnapshot, attack_type := StringName()) -> void:
	_hud.show_round(_session.get_round_number(), _session.get_active_faction())
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
		{"attack_damage": state.basic_attack_damage, "attack_range": state.basic_attack_range, "find_unit": _content.get_unit_definition}
	)

	var definition := _unit_views.definitions.get(state.unit_id) as UnitDefinition

	if definition == null:
		push_error("Active unit definition is not registered.")
		return

	_hud.show_active_unit(definition.display_name)
	var presentation := _unit_views.presentations.get(state.unit_id) as UnitPresentationDefinition
	_hud.show_active_portrait(presentation.actor_texture if presentation != null else null)
	_hud.show_combat_stats(state.basic_attack_damage, state.basic_attack_range, int(state.statuses.get(UnitStatusCatalog.ATTACK_CHARGE, 0)))
	var types: Array[StringName] = []
	if not _session.is_unit_ai_controlled(state.unit_id):
		types = state.attack_damage_types
	_hud.show_attack_type(types, attack_type if not attack_type.is_empty() else state.basic_attack_damage_type, state.turn.main_action_available and not state.health.is_defeated())
	var opponent_hexes: Array[Vector2i] = []
	for opponent: UnitSnapshot in _session.get_living_opponents(state.faction):
		opponent_hexes.append(opponent.hex)
	# An engaged ranged unit or a sniper that moved cannot shoot: its button names the melee strike.
	var shot_blocked := BasicAttackRules.is_engaged(state.hex, opponent_hexes) or BasicAttackRules.sniper_moved(state.sniper_shot, state.turn.movement_spent)
	var reach := 1 if shot_blocked else state.basic_attack_range
	_hud.show_basic_attack_button(reach, state.turn.main_action_available, state.sniper_shot)
	_show_turn_order(state.unit_id)
	show_strategist()


## The player's strategist abilities with the reason each is unavailable now.
func show_strategist() -> void:
	var entries: Array[Dictionary] = []
	for ability_id: StringName in _session.get_strategist_ability_ids():
		var definition := _content.get_strategist_ability_definition(ability_id)
		entries.append({
			"id": ability_id,
			"name": definition.display_name if definition != null else String(ability_id),
			"description": definition.description if definition != null else "",
			"reason": _session.get_strategist_unavailable_reason(BattleFaction.Value.PLAYER, ability_id),
		})
	var commands := _session.get_active_faction() == BattleFaction.Value.PLAYER and not _session.is_finished() and not _session.is_active_unit_ai_controlled()
	_hud.show_strategist(entries, commands)


## The acting faction's units first, then the other faction's, each in field order.
func _show_turn_order(shown_unit_id: StringName) -> void:
	var entries: Array[Dictionary] = []
	var acting := _session.get_active_faction()
	var order: Array[StringName] = []
	for in_phase: bool in [true, false]:
		for unit_id: StringName in _session.get_turn_order():
			var state := _session.get_unit(unit_id)
			if state != null and (state.faction == acting) == in_phase:
				order.append(unit_id)

	for unit_id: StringName in order:
		var state := _session.get_unit(unit_id)
		# Objects take no turns, so the turn order does not list them.
		if not state.takes_turns:
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
			"acted": _session.has_spent_turn(unit_id),
		})

	_hud.show_turn_order(entries, shown_unit_id)
