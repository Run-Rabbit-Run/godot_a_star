class_name StrategistAbilityExecutor
extends RefCounted
## Rules of the strategist's abilities: who may use one now, where, and the use itself. Only the
## player faction has a strategist. It acts in its side's phase, once per phase, and its effects
## form one transaction like a unit's ability.


## The source the strategist's effects and summons name: "strategist:player".
static func source_id(faction: BattleFaction.Value) -> StringName:
	return StringName("strategist:%s" % String(BattleFaction.Value.find_key(faction)).to_lower())


## Why the faction's strategist cannot use the ability now, or "".
static func unavailable_reason(state: BattleState, faction: BattleFaction.Value, ability_id: StringName) -> String:
	if faction != BattleFaction.Value.PLAYER:
		return "У этой стороны нет стратега."
	var ability := state.strategist_abilities.get(ability_id) as StrategistAbilityDefinition
	if ability == null:
		return "Стратег не знает этого умения."
	if state.turn_service.get_active_faction() != faction:
		return "Стратег действует только в фазу своей стороны."
	if state.turn_service.is_strategist_used():
		return "Стратег уже применил умение в этой фазе."
	if ability.one_at_a_time and has_living_summon(state, faction, ability_id):
		return "Нельзя применить, пока цел юнит прошлого применения."
	if target_hexes(state, ability).is_empty():
		return "Нет гексов для применения."
	return ""


## Hexes the ability may target now; empty while the strategist cannot use it.
static func get_target_hexes(state: BattleState, faction: BattleFaction.Value, ability_id: StringName) -> Array[Vector2i]:
	if not unavailable_reason(state, faction, ability_id).is_empty():
		var none: Array[Vector2i] = []
		return none
	return target_hexes(state, state.strategist_abilities[ability_id])


## Hexes of the target mode on the current map, in a stable order.
static func target_hexes(state: BattleState, _ability: StrategistAbilityDefinition) -> Array[Vector2i]:
	# FIELD_EDGE: every missing coordinate that touches the battlefield, holes included.
	var found: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in state.hex_grid.get_cells():
		for direction: Vector2i in HexGrid.DIRECTIONS:
			var neighbor := cell + direction
			if not state.hex_grid.has_cell(neighbor):
				found[neighbor] = true
	var hexes: Array[Vector2i] = []
	hexes.assign(found.keys())
	hexes.sort()
	return hexes


static func has_living_summon(state: BattleState, faction: BattleFaction.Value, ability_id: StringName) -> bool:
	for unit: UnitState in state.unit_states.values():
		if unit.faction == faction and unit.summoned_by == ability_id and not unit.health.is_defeated():
			return true
	return false


static func execute(state: BattleState, command: UseStrategistAbilityCommand) -> AbilityExecutionResult:
	if state == null or command == null:
		return AbilityExecutionResult.rejected("Strategist command and state are required.")
	var reason := unavailable_reason(state, command.faction, command.ability_id)
	if not reason.is_empty():
		return AbilityExecutionResult.rejected(reason)
	var ability: StrategistAbilityDefinition = state.strategist_abilities[command.ability_id]
	var error := ability.validate()
	if not error.is_empty():
		return AbilityExecutionResult.rejected(error)
	if not target_hexes(state, ability).has(command.target_hex):
		return AbilityExecutionResult.rejected("Strategist ability target is unavailable.")
	for effect: AbilityEffectDefinition in ability.effects:
		var handler := state.mod_api.get_effect_handler(effect.effect_type_id)
		if handler == null:
			return AbilityExecutionResult.rejected("Missing ability effect handler.")
		error = handler.validate(effect)
		if not error.is_empty():
			return AbilityExecutionResult.rejected(error)
	# A transaction copy that the live battle adopts only when every effect succeeded.
	var scratch := state if state.is_detached else state.duplicate_for_prediction()
	var events: Array[BattleEvent] = [StrategistAbilityUsedEvent.new(command.faction, ability.id, command.target_hex)]
	var context := BattleEffectContext.new(scratch, ability.id)
	context.target_hex = command.target_hex
	context.acting_faction = command.faction
	var cells: Array[Vector2i] = [command.target_hex]
	var no_targets: Array[StringName] = []
	events.append_array(AbilityEffectPipeline.apply_effects(context, scratch, ability.effects, source_id(command.faction), cells, no_targets))
	if context.has_failed():
		return AbilityExecutionResult.failed(context.get_failure(), scratch == state)
	scratch.turn_service.mark_strategist_used()
	if scratch != state:
		state.adopt(scratch)
	return AbilityExecutionResult.success(events)
