class_name BasicAttackRules
extends RefCounted
## Ordinary attack rules shared by the engine, AI and battle UI: a ranged unit cannot shoot
## while an enemy stands next to it, nor a sniper after it has moved this turn; it strikes an
## adjacent target in melee for half damage.

## Modifier source of the halved melee strike in UnitDamagedEvent.damage_modifiers.
const RANGED_MELEE_PENALTY := &"ranged_melee_penalty"


## True when one of the opponent hexes is next to this hex.
static func is_engaged(hex: Vector2i, opponent_hexes: Array[Vector2i]) -> bool:
	for opponent_hex: Vector2i in opponent_hexes:
		if HexGrid.get_distance(hex, opponent_hex) == 1:
			return true
	return false


## True when a sniper may not shoot: it has spent movement points this turn.
static func sniper_moved(sniper_shot: bool, movement_spent: int) -> bool:
	return sniper_shot and movement_spent > 0


## True when an ordinary attack from `from` may hit `to`: within range, and a shot past the
## neighbors only while the attacker may shoot — it is not engaged and no sniper that moved.
static func reaches(attack_range: int, from: Vector2i, to: Vector2i, shot_blocked: bool) -> bool:
	var distance := HexGrid.get_distance(from, to)
	return distance <= attack_range and (distance <= 1 or not shot_blocked)


## True when the attack is a shot rather than a melee strike.
static func is_shot(attack_range: int, from: Vector2i, to: Vector2i) -> bool:
	return attack_range > 1 and HexGrid.get_distance(from, to) > 1


## True when an attack may strike with `requested` type: "" keeps the unit's current type,
## another type must be one of the unit's choices.
static func may_choose(current: StringName, choices: Array[StringName], requested: StringName) -> bool:
	return requested.is_empty() or requested == current or choices.has(requested)


## Damage a ranged unit loses on a melee strike: half, rounded down, at least 1 remains.
static func melee_penalty(attack_range: int, damage: int) -> int:
	if attack_range <= 1 or damage <= 0:
		return 0
	return damage - maxi(1, floori(damage / 2.0))
