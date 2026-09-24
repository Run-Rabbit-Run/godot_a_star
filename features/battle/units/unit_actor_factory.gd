class_name UnitActorFactory
extends RefCounted


const FALLBACK_ACTOR_SCENE := preload(
	"res://features/battle/units/unit_actor.tscn"
)


static func create(
	state: UnitSnapshot,
	definition: UnitDefinition,
	presentation: UnitPresentationDefinition,
	parent: Node
) -> UnitActor:
	if state == null:
		push_error("UnitActorFactory requires a UnitSnapshot.")
		return null

	if definition == null:
		push_error("UnitActorFactory requires a UnitDefinition.")
		return null

	var actor_scene := FALLBACK_ACTOR_SCENE

	if presentation == null:
		push_warning(
			"UnitDefinition %s has no presentation; using the fallback actor."
			% definition.id
		)
	elif presentation.actor_scene == null:
		push_warning(
			"UnitPresentationDefinition %s has no actor_scene; using the fallback actor."
			% presentation.id
		)
	else:
		actor_scene = presentation.actor_scene

	if parent == null:
		push_error("UnitActorFactory requires a parent node.")
		return null

	var actor_node := actor_scene.instantiate()
	var actor := actor_node as UnitActor

	if actor == null:
		actor_node.free()
		push_warning(
			"Unit presentation actor_scene root is not a UnitActor; using the fallback actor."
		)
		actor = FALLBACK_ACTOR_SCENE.instantiate() as UnitActor

		if actor == null:
			push_error("Fallback unit actor scene root must be a UnitActor.")
			return null

	parent.add_child(actor)
	actor.setup(
	state.unit_id,
	definition,
	presentation,
	state.faction,
	state.health.current,
	state.health.maximum
)

	return actor
