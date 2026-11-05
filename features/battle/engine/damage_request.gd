class_name DamageRequest
extends RefCounted
## One hit for UnitStatusService.damage(): its amount and type, where it comes from and what
## lessens it before the target's own statuses. Unset sources stay "", unset reductions 0.

var amount: int
var type: StringName
## The unit that dealt the hit.
var source_unit_id: StringName
## The hex layer that dealt the damage.
var source_hex_state_id: StringName
## The ability the hit belongs to.
var source_ability_id: StringName
## The status whose own effect dealt the damage: periodic damage or an oil explosion.
var source_status_id: StringName
## Damage a shot loses to the cover of the target's hex, and the layer that gives the cover.
var ranged_reduction := 0
var cover_hex_state_id: StringName
## Damage a ranged unit loses when it strikes in melee.
var melee_penalty := 0
## A pushed unit ran into something: the hit is the collision, not the source's strike.
var collision := false
## The destroyed flask whose burst dealt the damage.
var source_obstacle_id: StringName


func _init(p_amount: int, p_type: StringName = &"physical") -> void:
	amount = p_amount
	type = p_type


func from_unit(unit_id: StringName) -> DamageRequest:
	source_unit_id = unit_id
	return self


func from_hex_state(hex_state_id: StringName) -> DamageRequest:
	source_hex_state_id = hex_state_id
	return self


func from_status(status_id: StringName) -> DamageRequest:
	source_status_id = status_id
	return self


func with_ability(ability_id: StringName) -> DamageRequest:
	source_ability_id = ability_id
	return self


func with_cover(reduction: int, hex_state_id: StringName) -> DamageRequest:
	ranged_reduction = reduction
	cover_hex_state_id = hex_state_id
	return self


func with_melee_penalty(penalty: int) -> DamageRequest:
	melee_penalty = penalty
	return self


func from_collision() -> DamageRequest:
	collision = true
	return self


func from_obstacle(obstacle_id: StringName) -> DamageRequest:
	source_obstacle_id = obstacle_id
	return self
