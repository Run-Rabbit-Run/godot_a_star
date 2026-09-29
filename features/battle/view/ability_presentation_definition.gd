class_name AbilityPresentationDefinition
extends Resource


## How the ability visibly travels to its target. Battle rules never read this.
enum Delivery {
	INSTANT,
	PROJECTILE,
	THROWN,
}


@export var id: StringName
@export var delivery: Delivery = Delivery.PROJECTILE
@export var projectile_color := Color(0.784, 0.725, 0.604, 1.0)
@export var trail_color := Color(0.604, 0.471, 0.271, 0.86)
## Burst at the center of an area ability.
@export var impact_color := Color(0.878, 0.267, 0.216, 0.92)
