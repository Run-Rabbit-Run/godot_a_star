class_name AbilityPresentationDefinition
extends Resource


## How the ability visibly travels to its target. Battle rules never read this, and the
## presentation never infers it from battle rules.
enum Delivery {
	INSTANT,
	PROJECTILE,
	THROWN,
	## Area only: the weapon stays on the landing hex until its return event flies it back.
	RETURNING,
	## Area only: a straight beam along the affected cells.
	BEAM,
}


@export var id: StringName
@export var delivery: Delivery = Delivery.PROJECTILE
@export var projectile_color := Color(0.784, 0.725, 0.604, 1.0)
@export var trail_color := Color(0.604, 0.471, 0.271, 0.86)
## Burst at the center of an area ability.
@export var impact_color := Color(0.878, 0.267, 0.216, 0.92)
