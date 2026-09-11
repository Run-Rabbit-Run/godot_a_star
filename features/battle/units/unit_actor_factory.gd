class_name UnitActorFactory
extends RefCounted


static func create(
	state: UnitState,
	definition: UnitDefinition,
	parent: Node
) -> UnitActor:
	if state == null:
		push_error("UnitActorFactory requires a UnitState.")
		return null

	if definition == null:
		push_error("UnitActorFactory requires a UnitDefinition.")
		return null

	if definition.actor_scene == null:
		push_error("UnitDefinition actor_scene is not assigned.")
		return null

	if parent == null:
		push_error("UnitActorFactory requires a parent node.")
		return null

	var actor_node := definition.actor_scene.instantiate()
	var actor := actor_node as UnitActor

	if actor == null:
		actor_node.free()
		push_error("UnitDefinition actor_scene root must be a UnitActor.")
		return null

	parent.add_child(actor)
	actor.setup(state.unit_id, definition)

	return actor
