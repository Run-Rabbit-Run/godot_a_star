extends RefCounted
## A broken animation must not freeze the battle: the queue cuts it, the controller snaps
## the view to the session and play goes on.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

## Stall detection needs STALL_FRAMES; anything far beyond that means a hang.
const FRAME_LIMIT := 240


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request(true)
	suite.expect(request != null, "Recovery fixture battle loads")
	if request == null:
		return
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(request), "Recovery battle setup accepted")
	suite.add_child(screen)
	var controller: BattleController = screen.get("_battle_controller")
	for _frame in range(FRAME_LIMIT):
		await suite.get_tree().process_frame
		if controller.get("_is_initialized") and not controller.get("_is_presenting"):
			break
	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	var session: BattleSession = controller.get("_battle_session")
	var views: BattleUnitViewRegistry = controller.get("_unit_views")
	var map: BattleMapView = controller.get("_map_view")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var mover_id := session.get_active_unit_id()
	var mover := session.get_unit(mover_id)
	var actor: UnitActor = views.actors[mover_id]
	var sprite := actor.get_combat_sprite()
	var rest_position := sprite.position
	var rest_material := sprite.material
	var destination := Vector2i(999999, 999999)
	for cell: Vector2i in session.get_movement_search(mover_id).get_reachable_cells():
		if HexGrid.get_distance(cell, mover.hex) == 1:
			destination = cell
			break
	var path: Array[Vector2i] = [mover.hex, destination]
	var move := BattleResolution.success([UnitMovedEvent.new(mover_id, path, 1)], session.get_state_revision(), mover_id)

	var outcome := await _present(suite, controller, queue, move, views, map, hud, func(_tween: Tween) -> void: pass)
	suite.expect(outcome.get("presented", false) and queue.interrupted_steps == 0 and actor.global_position.is_equal_approx(map.hex_to_global_position(destination)), "An intact animation plays to its end without interruptions")
	# The event was only shown; put the figure back on its session hex before the next case.
	views.synchronize(session)

	outcome = await _present(suite, controller, queue, move, views, map, hud, func(tween: Tween) -> void: tween.pause())
	suite.expect(outcome.has("presented") and outcome.frames < FRAME_LIMIT, "A stalled animation does not freeze presentation (%d frames)" % outcome.get("frames", -1))
	suite.expect(outcome.get("presented", false) and queue.interrupted_steps == 1 and not controller.get("_runtime_failed"), "A stalled animation is completed without stopping the battle")
	suite.expect(sprite.position == rest_position and sprite.material == rest_material, "Completing a stalled walk runs its final pose restore")
	suite.expect(actor.global_position.is_equal_approx(map.hex_to_global_position(mover.hex)), "After an interruption the actor snaps to its session hex")

	var target_id := StringName()
	for id: StringName in session.get_turn_order():
		var unit := session.get_unit(id)
		if unit.faction != mover.faction and not unit.health.is_defeated():
			target_id = id
			break
	var target := session.get_unit(target_id)
	var hit := UnitDamagedEvent.new(mover_id, target_id, 1, maxi(target.health.current - 1, 1), false)
	var strike := BattleResolution.success([hit], session.get_state_revision(), mover_id)
	var target_actor: UnitActor = views.actors[target_id]
	var target_sprite := target_actor.get_combat_sprite()
	var target_rest := target_sprite.transform
	var attacker_rest := sprite.transform
	var free_effect := func(_tween: Tween) -> void:
		for node: Node in actor.get_parent().get_children():
			if node is UnitCombatAnimator:
				node.free()
	outcome = await _present(suite, controller, queue, strike, views, map, hud, free_effect)
	suite.expect(outcome.has("presented") and outcome.frames < FRAME_LIMIT, "An animation whose node disappears does not freeze presentation (%d frames)" % outcome.get("frames", -1))
	suite.expect(outcome.get("presented", false) and queue.interrupted_steps >= 1 and not controller.get("_runtime_failed"), "A dead animation is cut without stopping the battle")
	suite.expect(sprite.transform == attacker_rest and target_sprite.transform == target_rest, "Removing an attack effect restores both figures")
	var health_label: Label = target_actor.get("_health_label")
	suite.expect(health_label.text == "%d/%d" % [target.health.current, target.health.maximum], "The synchronized view shows session health, not the cut event")
	suite.expect((queue.get("_steps") as Dictionary).is_empty() and not queue.is_processing(), "No step stays watched after recovery")
	screen.queue_free()
	await suite.get_tree().process_frame


## Presents a resolution and lets `interfere` break the first awaited tween.
func _present(suite: Node, controller: BattleController, queue: BattlePresentationQueue, resolution: BattleResolution, views: BattleUnitViewRegistry, map: BattleMapView, hud: BattleHUD, interfere: Callable) -> Dictionary:
	var outcome := {}
	var play := func() -> void:
		outcome["presented"] = await controller.call("_present_resolution", resolution, views.actors, views.definitions, map, hud)
	play.call()
	var steps: Dictionary = queue.get("_steps")
	if not steps.is_empty():
		interfere.call(steps.values()[0].tween)
	for frame in range(FRAME_LIMIT):
		if outcome.has("presented"):
			outcome["frames"] = frame
			break
		await suite.get_tree().process_frame
	return outcome
