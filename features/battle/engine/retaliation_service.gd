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
	return strike(state, attacker, defender, &"core:melee_retaliation", events)


## An ordinary strike at melee distance without opening another reaction.
static func strike(state: BattleState, target: UnitState, striker: UnitState, ability_id: StringName, events: Array[BattleEvent]) -> String:
	# A response is a melee strike, so a ranged defender deals half damage.
	var penalty := BasicAttackRules.melee_penalty(striker.basic_attack_range, striker.basic_attack_damage)
	# The response is the defender's next attack: a targeting glitch weakens it and is spent.
	var glitch := UnitStatusService.consume(striker, UnitStatusCatalog.TARGETING_GLITCH, events)
	var hit := DamageRequest.new(striker.basic_attack_damage, striker.basic_attack_damage_type).from_unit(striker.unit_id).with_ability(ability_id)
	UnitStatusService.damage(target, hit.with_melee_penalty(penalty).with_weakening(glitch, UnitStatusCatalog.TARGETING_GLITCH), events)
	for status: StringName in striker.basic_attack_statuses:
		UnitStatusService.apply(target, status, striker.basic_attack_statuses[status], events)
	return DamageType.react(state, target.hex, striker.basic_attack_damage_type, events)
