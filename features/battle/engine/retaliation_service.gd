class_name RetaliationService
extends RefCounted

## A living, unparalyzed defender responds once. Responses never trigger responses.
static func respond(state: BattleState, attacker: UnitState, defender: UnitState, events: Array[BattleEvent]) -> void:
	if attacker == null or defender == null or attacker.health.is_defeated() or defender.health.is_defeated():
		return
	var enabled := defender.melee_retaliation if defender.retaliation_configured else defender.passive_ability_ids.has(&"core:melee_retaliation")
	if not enabled or defender.statuses.get(&"core:paralysis", 0) > 0:
		return
	if HexGrid.get_distance(attacker.hex, defender.hex) > 1:
		return
	UnitStatusService.damage(attacker, defender.basic_attack_damage, defender.basic_attack_damage_type, events, defender.unit_id, &"", &"core:melee_retaliation")
	for status: StringName in defender.basic_attack_statuses:
		UnitStatusService.apply(attacker, status, defender.basic_attack_statuses[status], events)
	events.append_array(DamageType.react(state, attacker.hex, defender.basic_attack_damage_type))
