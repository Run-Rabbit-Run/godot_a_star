extends RefCounted
## A push moves a unit straight away from the pusher. Whatever stops it — a living unit, an
## obstacle, an impassable hex or the field edge — ends the push, and the pushed unit and what
## it hit each take 1 physical damage.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const SHOVE_PATH := "res://content/packages/core/shove.tres"
const Collision := UnitPushedEvent.Collision


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_free_flight(suite, fixture)
	_run_collisions(suite, fixture)
	_run_path_rules(suite, fixture)
	_run_shove(suite, fixture)
	_run_content(suite, fixture)


func _run_free_flight(suite: Node, fixture: Fixtures) -> void:
	var pusher := fixture.unit(&"pusher", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state(_cells(4), [pusher, target])
	var movement := target.turn.movement_remaining
	var events := _push(state, pusher, target, 2)
	suite.expect(target.hex == Vector2i(3, 0) and target.health.current == 100, "A push moves the target straight away by its distance without damage")
	suite.expect(target.turn.movement_remaining == movement, "Being pushed spends none of the target's movement")
	var pushes := _pushes(events)
	suite.expect(pushes.size() == 1 and pushes[0].path == [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] and pushes[0].collision == Collision.NONE and pushes[0].source_unit_id == pusher.unit_id, "A free push publishes its whole line once")
	suite.expect(_damage(events).is_empty(), "A push with nothing in the way deals no damage")
	# A target two hexes away on an axis flies along the same line.
	target.hex = Vector2i(0, 2)
	_push(state, pusher, target, 1)
	suite.expect(target.hex == Vector2i(0, 3), "A distant target on an axis is pushed away from the pusher")


func _run_collisions(suite: Node, fixture: Fixtures) -> void:
	# A living unit: both take the collision damage, the blocker stays where it stands.
	var pusher := fixture.unit(&"pusher", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var blocker := fixture.unit(&"blocker", BattleFaction.Value.ENEMY, Vector2i(3, 0))
	var state := fixture.state(_cells(4), [pusher, target, blocker])
	var events := _push(state, pusher, target, 2)
	var pushes := _pushes(events)
	var hits := _damage(events)
	suite.expect(target.hex == Vector2i(2, 0) and blocker.hex == Vector2i(3, 0), "A unit in the way stops the push on the hex before it and is not moved")
	suite.expect(target.health.current == 99 and blocker.health.current == 99, "Both the pushed unit and the unit it hit take 1 damage")
	suite.expect(pushes.size() == 1 and pushes[0].collision == Collision.UNIT and pushes[0].blocker_hex == Vector2i(3, 0) and pushes[0].blocker_unit_id == blocker.unit_id, "The push event names the unit it hit")
	suite.expect(hits.size() == 2 and hits[0].target_id == target.unit_id and hits[1].target_id == blocker.unit_id, "The pushed unit is hit first, then the blocker")
	suite.expect(hits.all(func(hit: UnitDamagedEvent) -> bool: return hit.collision and hit.damage_type == &"physical" and hit.base_damage == 1 and hit.attacker_id == pusher.unit_id), "Collision damage is 1 physical, marked as a collision of the pusher's push")
	suite.expect(events.find(pushes[0]) < events.find(hits[0]), "The push is published before its collision damage")

	# A unit right behind the target: no movement, still a collision.
	target.hex = Vector2i(1, 0)
	blocker.hex = Vector2i(2, 0)
	events = _push(state, pusher, target, 2)
	pushes = _pushes(events)
	suite.expect(target.hex == Vector2i(1, 0) and target.health.current == 98 and blocker.health.current == 98, "A unit right behind the target stops it at once and both are hit")
	suite.expect(pushes.size() == 1 and pushes[0].path == [Vector2i(1, 0)] and pushes[0].collision == Collision.UNIT, "A push stopped at once still publishes the collision")

	# An obstacle: it takes the damage too when it can be destroyed.
	pusher = fixture.unit(&"pusher", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	target = fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	state = fixture.state(_cells(4), [pusher, target])
	state.hex_grid.add_obstacle(_obstacle(&"test:rock", Vector2i(3, 0), true))
	var map_revision := state.map_revision
	events = _push(state, pusher, target, 2)
	suite.expect(target.hex == Vector2i(2, 0) and target.health.current == 99, "An obstacle stops the push and hits the pushed unit")
	suite.expect(state.hex_grid.get_obstacle(Vector2i(3, 0)).current_hp == 4 and state.map_revision > map_revision, "A destructible obstacle takes 1 collision damage")
	suite.expect(_pushes(events)[0].collision == Collision.OBSTACLE and events.any(func(event: BattleEvent) -> bool: return event is MapMutationEvent and event.obstacle_changed and event.obstacle_damage == 1), "The obstacle's collision damage is published")
	target.hex = Vector2i(1, -1)
	state.hex_grid.add_obstacle(_obstacle(&"test:hill", Vector2i(3, -3), false))
	_push(state, pusher, target, 4)
	suite.expect(target.hex == Vector2i(2, -2) and target.health.current == 98 and state.hex_grid.get_obstacle(Vector2i(3, -3)).current_hp == 5, "An indestructible obstacle stops the push and takes nothing")

	# An impassable hex and the field edge act as walls: only the pushed unit is hit.
	pusher = fixture.unit(&"pusher", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	target = fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	state = fixture.state(_cells(2), [pusher, target])
	state.hex_grid.set_traversal(Vector2i(0, 2), false, 1)
	events = _push(state, pusher, target, 3)
	suite.expect(target.hex == Vector2i(2, 0) and target.health.current == 99 and _pushes(events)[0].collision == Collision.EDGE and _damage(events).size() == 1, "The field edge stops the push and hits only the pushed unit")
	target.hex = Vector2i(0, 1)
	events = _push(state, pusher, target, 3)
	suite.expect(target.hex == Vector2i(0, 1) and target.health.current == 98 and _pushes(events)[0].collision == Collision.IMPASSABLE and _damage(events).size() == 1, "An impassable hex stops the push and hits only the pushed unit")

	# Ordinary damage rules apply: armor absorbs the hit, a lethal collision defeats.
	target.hex = Vector2i(1, 0)
	target.statuses[UnitStatusCatalog.ARMOR] = 1
	_push(state, pusher, target, 3)
	suite.expect(target.health.current == 98, "Armor absorbs physical collision damage")
	target.statuses.clear()
	target.hex = Vector2i(1, 0)
	target.health.current = 1
	events = _push(state, pusher, target, 3)
	suite.expect(target.health.is_defeated() and target.hex == Vector2i(2, 0) and _damage(events)[0].target_defeated, "A lethal collision defeats the pushed unit where it stopped")


func _run_path_rules(suite: Node, fixture: Fixtures) -> void:
	var pusher := fixture.unit(&"pusher", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(2, -1))
	var body := fixture.unit(&"body", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	body.health.current = 0
	var state := fixture.state(_cells(4), [pusher, target, body])
	var events := _push(state, pusher, target, 2)
	suite.expect(target.hex == Vector2i(2, -1) and events.is_empty(), "A target off the pusher's axes stays in place")

	target.hex = Vector2i(1, 0)
	_push(state, pusher, target, 2)
	suite.expect(target.hex == Vector2i(3, 0) and target.health.current == 100, "A body does not stop the push")

	# Hex layers act on every hex the unit slides onto, as on an ordinary move.
	target.hex = Vector2i(0, 1)
	state.hex_grid.set_energy(Vector2i(0, 2), &"core:fire")
	events = _push(state, pusher, target, 2)
	var pushes := _pushes(events)
	suite.expect(target.hex == Vector2i(0, 3) and target.statuses.get(UnitStatusCatalog.BURNING, 0) > 0 and target.health.current < 100, "A hex layer on the line acts on the pushed unit")
	suite.expect(pushes.size() == 2 and pushes[0].path == [Vector2i(0, 1), Vector2i(0, 2)] and pushes[1].path == [Vector2i(0, 2), Vector2i(0, 3)], "The push is split at the layered hex, like a move")
	target.statuses.clear()
	target.hex = Vector2i(0, 1)
	target.health.current = 1
	_push(state, pusher, target, 2)
	suite.expect(target.health.is_defeated() and target.hex == Vector2i(0, 2), "A unit killed on the way stops where it fell")

	# A hex holder is anchored, a defeated unit is not moved, a missing unit fails the effect.
	var holder := fixture.unit(&"holder", BattleFaction.Value.ENEMY, Vector2i(-1, 0))
	holder.holds_hex = true
	state = fixture.state(_cells(4), [pusher, holder, target])
	events = _push(state, pusher, holder, 2)
	suite.expect(holder.hex == Vector2i(-1, 0) and events.is_empty(), "A unit holding its hex is not pushed")
	events = _push(state, pusher, target, 2)
	suite.expect(target.hex == Vector2i(0, 2) and events.is_empty(), "A defeated unit is not pushed")
	var context := BattleEffectContext.new(state, &"test:push")
	context.push(pusher.unit_id, &"missing", 2)
	suite.expect(context.has_failed(), "Pushing a missing unit fails the effect")


func _run_shove(suite: Node, fixture: Fixtures) -> void:
	var shove := load(SHOVE_PATH) as AbilityDefinition
	suite.expect(shove != null and shove.validate().is_empty(), "The shove ability validates")
	var user := fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var other := fixture.unit(&"other", BattleFaction.Value.ENEMY, Vector2i(-3, 0))
	user.abilities[shove.id] = shove
	var state := fixture.state(_cells(4), [user, enemy, other])
	var engine := BattleEngine.new(state)
	var command := UseAbilityCommand.new(user.unit_id, enemy.unit_id, shove.id)
	var forecast := engine.fork_for_prediction().execute(command)
	suite.expect(forecast.accepted and enemy.hex == Vector2i(1, 0) and enemy.health.current == 100, "A forecast shove leaves the live battle unchanged")
	var result := engine.execute(command)
	suite.expect(result.accepted and enemy.health.current == 99 and enemy.hex == Vector2i(3, 0), "Shove hits the neighbor for 1 and pushes it two hexes")
	suite.expect(not user.turn.main_action_available and user.ability_cooldowns.get(shove.id, 0) > 0, "Shove spends the action and starts its cooldown")
	var damage_index := result.events.find(_damage(result.events)[0])
	var push_index := result.events.find(_pushes(result.events)[0])
	suite.expect(damage_index >= 0 and damage_index < push_index, "The shove's hit comes before the push")

	# Into another unit: the target takes the hit and the collision, the blocker the collision.
	user = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	other = fixture.unit(&"other", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	user.abilities[shove.id] = shove
	state = fixture.state(_cells(4), [user, enemy, other])
	engine = BattleEngine.new(state)
	command = UseAbilityCommand.new(user.unit_id, enemy.unit_id, shove.id)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	suite.expect(preview.accepted and preview.units[enemy.unit_id].health_after == 98 and preview.units[other.unit_id].health_after == 99, "The action preview counts collision damage")
	result = engine.execute(command)
	suite.expect(result.accepted and enemy.hex == Vector2i(1, 0) and enemy.health.current == 98 and other.health.current == 99, "A shove into a unit hits both with the collision")
	suite.expect(engine.supports_ability_prediction(shove) and AILastActionPlanner._supports_prediction(shove) and AILastActionPlanner.depends_on_origin(shove), "The AI forecasts shoves and scores each from the hex it would stand on")

	# Shove reaches neighbors only.
	user = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	user.abilities[shove.id] = shove
	state = fixture.state(_cells(4), [user, enemy])
	engine = BattleEngine.new(state)
	result = engine.execute(UseAbilityCommand.new(user.unit_id, enemy.unit_id, shove.id))
	suite.expect(not result.accepted and enemy.hex == Vector2i(2, 0) and user.turn.main_action_available, "Shove rejects a target beyond its neighbors without changes")


func _run_content(suite: Node, fixture: Fixtures) -> void:
	var loaded := fixture.content()
	var shove := loaded.snapshot.get_ability_definition(&"core:shove") if loaded.snapshot != null else null
	suite.expect(shove != null and loaded.snapshot.get_ability_presentation_definition(shove.presentation_id) != null, "The core package ships shove with its presentation")
	var text := AbilityDescription.render(load(SHOVE_PATH) as AbilityDefinition)
	suite.expect(text.contains("дальность толчка — 2") and text.contains("по 1 физического урона") and not text.contains("{"), "Shove's description fills the push variables: %s" % text)

	var skills := fixture.skills()
	var document: Dictionary = skills.builtin_documents()["core:shove"]
	suite.expect(skills.validate(document).is_empty(), "The built-in shove document validates")
	document.effects[1].parameters.distance = 3
	suite.expect(skills.validate(document).is_empty() and skills.to_ability(document).effects[1].parameters.distance == 3, "The skill editor may change the push distance")
	for wrong: Variant in [0, PushEffectHandler.MAX_DISTANCE + 1, 1.5, "2"]:
		document.effects[1].parameters.distance = wrong
		suite.expect(not skills.validate(document).is_empty(), "A push distance of %s is rejected" % str(wrong))

	var units: Dictionary[StringName, UnitDefinition] = {}
	var push := UnitPushedEvent.new(&"target", &"pusher", [Vector2i(1, 0), Vector2i(2, 0)])
	push.collision = Collision.UNIT
	push.blocker_unit_id = &"blocker"
	suite.expect(BattleLogFormatter.describe(push, units, null) == "target отброшен в (2, 0) и врезается в blocker.", "The battle log describes a push and what it hit")
	var hit := UnitDamagedEvent.new(&"pusher", &"target", 1, 99, false, &"", &"core:shove")
	hit.collision = true
	var line := BattleLogFormatter.describe(hit, units, null)
	suite.expect(line.begins_with("Столкновение → target: 1 урона") and line.contains("(столкновение)"), "The battle log names collision damage: %s" % line)


## A pushed actor ends on the last hex of its line; one that hit something returns to its hex.
func run_presentation(suite: Node) -> void:
	var screen := preload("res://features/battle/battle_screen.tscn").instantiate() as BattleScreen
	suite.expect(screen.setup(suite.fixture.spear_request()), "Push presentation battle setup accepted")
	suite.add_child(screen)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	var controller: BattleController = screen.get("_battle_controller")
	var queue: BattlePresentationQueue = controller.get("_presentation_queue")
	queue.set_speed(4.0)
	var session: BattleSession = controller.get("_battle_session")
	var map: BattleMapView = controller.get("_map_view")
	var hud := screen.get_node("BattleMap/BattleUI") as BattleHUD
	var views: BattleUnitViewRegistry = controller.get("_unit_views")
	var unit := session.get_unit(session.get_active_unit_id())
	var grid := session.get_hex_grid()
	var free := Vector2i.ZERO
	for direction: Vector2i in HexGrid.DIRECTIONS:
		var hex := unit.hex + direction
		if grid.is_traversable(hex) and session.get_unit_at(hex) == null:
			free = hex
			break
	suite.expect(free != Vector2i.ZERO, "The presentation battle has a free neighbor hex")
	var actor: UnitActor = views.actors[unit.unit_id]
	var events: Array[BattleEvent] = [UnitPushedEvent.new(unit.unit_id, &"", [unit.hex, free])]
	var presented: bool = await queue.present(BattleResolution.success(events, 0, unit.unit_id), views.actors, views.definitions, map, hud)
	suite.expect(presented and queue.interrupted_steps == 0 and actor.global_position.distance_to(map.hex_to_global_position(free)) < 1.0, "A pushed actor slides to the end of its line")
	var bump := UnitPushedEvent.new(unit.unit_id, &"", [free])
	bump.collision = Collision.EDGE
	bump.blocker_hex = free + (free - unit.hex)
	events = [bump]
	presented = await queue.present(BattleResolution.success(events, 0, unit.unit_id), views.actors, views.definitions, map, hud)
	suite.expect(presented and actor.global_position.distance_to(map.hex_to_global_position(free)) < 1.0, "A collision knocks the actor toward the blocker and back")
	screen.queue_free()
	await suite.get_tree().process_frame


func _push(state: BattleState, source: UnitState, target: UnitState, distance: int) -> Array[BattleEvent]:
	var context := BattleEffectContext.new(state, &"test:push")
	return context.push(source.unit_id, target.unit_id, distance)


func _pushes(events: Array[BattleEvent]) -> Array[UnitPushedEvent]:
	var result: Array[UnitPushedEvent] = []
	for event: BattleEvent in events:
		if event is UnitPushedEvent:
			result.append(event)
	return result


func _damage(events: Array[BattleEvent]) -> Array[UnitDamagedEvent]:
	var result: Array[UnitDamagedEvent] = []
	for event: BattleEvent in events:
		if event is UnitDamagedEvent:
			result.append(event)
	return result


## A hexagon of the given radius around the origin.
static func _cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells


static func _obstacle(id: StringName, hex: Vector2i, destructible: bool) -> BattleObstacleDefinition:
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = id
	obstacle.hexes.assign([hex])
	obstacle.destructible = destructible
	obstacle.max_hp = 5
	return obstacle
