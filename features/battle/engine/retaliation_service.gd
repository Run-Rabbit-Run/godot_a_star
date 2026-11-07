class_name RetaliationService
extends RefCounted

## A living, unparalyzed defender responds once. Responses never trigger responses.
## Returns "" or why the map could not react to the response.
static func respond(state: BattleState, attacker: UnitState, defender: UnitState, events: Array[BattleEvent]) -> String:
	if attacker == null or defender == null or attacker.health.is_defeated() or defender.health.is_defeated():
		return ""
	var enabled := defender.melee_retaliation if defender.retaliation_configured else defender.passive_ability_ids.has(&"core:melee_retaliation")
	if not enabled or defender.statuses.get(UnitStatusCatalog.PARALYSIS, 0) > 0:
		return ""
	if HexGrid.get_distance(attacker.hex, defender.hex) > 1:
		return ""
	# A response is a melee strike, so a ranged defender deals half damage.
	var penalty := BasicAttackRules.melee_penalty(defender.basic_attack_range, defender.basic_attack_damage)
	# The response is the defender's next attack: a targeting glitch weakens it and is spent.
	var glitch := UnitStatusService.consume(defender, UnitStatusCatalog.TARGETING_GLITCH, events)
	var strike := DamageRequest.new(defender.basic_attack_damage, defender.basic_attack_damage_type).from_unit(defender.unit_id).with_ability(&"core:melee_retaliation")
	UnitStatusService.damage(attacker, strike.with_melee_penalty(penalty).with_weakening(glitch, UnitStatusCatalog.TARGETING_GLITCH), events)
	for status: StringName in defender.basic_attack_statuses:
		UnitStatusService.apply(attacker, status, defender.basic_attack_statuses[status], events)
	return DamageType.react(state, attacker.hex, defender.basic_attack_damage_type, events)
