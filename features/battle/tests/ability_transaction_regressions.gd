extends RefCounted
## An ability is one transaction: either every effect lands, or the live battle stays exactly
## as it was. A failure at a turn boundary has no alternative path and stops the battle.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const FAILURE := "Injected failure"


## Changes units through the context, then reports that it cannot finish.
class DamageThenFail extends AbilityEffectHandler:
	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute(_effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, target: StringName) -> Array[BattleEvent]:
		var events := context.apply_damage_events(source, target, 4, &"electric")
		context.fail(FAILURE)
		return events


## Changes the map, then reports that it cannot finish.
class TerrainThenFail extends AbilityEffectHandler:
	func affects_hexes() -> bool:
		return true

	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute_hexes(_effect: AbilityEffectDefinition, context: BattleEffectContext, _source: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
		var events := context.apply_hex_states(hexes, &"core:fire")
		context.fail(FAILURE)
		return events


## Adds a participant, then reports that it cannot finish.
class SummonThenFail extends AbilityEffectHandler:
	var definition: UnitDefinition

	func affects_hexes() -> bool:
		return true

	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute_hexes(_effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, hexes: Array[Vector2i]) -> Array[BattleEvent]:
		var events := context.summon(source, hexes[0], definition)
		context.fail(FAILURE)
		return events


## Returns something that is not an event.
class InvalidEvent extends AbilityEffectHandler:
	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute(_effect: AbilityEffectDefinition, _context: BattleEffectContext, _source: StringName, _target: StringName) -> Array[BattleEvent]:
		var events: Array[BattleEvent] = [null]
		return events


## Strikes normally on the throw; on the way back it strikes, then reports a failure.
class ReturnFailingDamage extends DamageEffectHandler:
	func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, target: StringName) -> Array[BattleEvent]:
		var events := super.execute(effect, context, source, target)
		if context.get_unit_hex(source) == context.target_hex:
			context.fail("Injected return failure")
		return events


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_failed_effects_change_nothing(suite, fixture)
	_check_adopted_ability_equals_direct(suite, fixture)
	_check_detached_failure(suite, fixture)
	_check_return_failure(suite, fixture)
	_check_context_failures(suite, fixture)
	_check_script_error_watch(suite)
	_check_unit_copy_covers_every_field(suite, fixture)


func _check_failed_effects_change_nothing(suite: Node, fixture: Fixtures) -> void:
	var summoned := UnitDefinition.new()
	summoned.id = &"core:test_summon"
	summoned.base_stats = UnitStatsDefinition.new()
	var summon_handler := SummonThenFail.new()
	summon_handler.definition = summoned
	var handlers := {&"test:damage_then_fail": DamageThenFail.new(), &"test:terrain_then_fail": TerrainThenFail.new(), &"test:summon_then_fail": summon_handler, &"test:invalid_event": InvalidEvent.new()}
	var cases := [
		[&"test:damage_then_fail", Vector2i(2, 0), FAILURE, "Damage then failure"],
		[&"test:terrain_then_fail", Vector2i(2, 0), FAILURE, "Terrain change then failure"],
		[&"test:summon_then_fail", Vector2i(3, 1), FAILURE, "Summon then failure"],
		[&"test:invalid_event", Vector2i(2, 0), "invalid event", "Invalid handler result"],
	]
	for entry: Array in cases:
		var api := ModAPI.create_default()
		for id: StringName in handlers:
			api.register_effect_handler(id, handlers[id])
		var state := _line_state(fixture, api)
		var user: UnitState = state.unit_states[&"user"]
		var enemy: UnitState = state.unit_states[&"enemy"]
		var ability: AbilityDefinition = fixture.ability(&"core:transaction", AbilityDefinition.TargetMode.HEX, 1)
		ability.range = 4
		var failing := AbilityEffectDefinition.new()
		failing.effect_type_id = entry[0]
		failing.parameters = {"center_only": true}
		ability.effects.append(failing)
		user.abilities[ability.id] = ability
		user.ability_cooldowns[ability.id] = 0
		var session := _session(state)
		var before := _encode(session.get_diagnostic_state())
		var resolution := session.step(UseAbilityCommand.at_hex(user.unit_id, entry[1], ability.id))
		suite.expect(not resolution.accepted and String(entry[2]) in resolution.rejection_reason and resolution.events.is_empty() and resolution.terminal_error.is_empty(), "%s rejects the ability with the handler's reason: %s" % [entry[3], resolution.rejection_reason])
		suite.expect(before == _encode(session.get_diagnostic_state()), "%s leaves units, map, obstacles, turn order, revisions and RNG untouched" % entry[3])
		suite.expect(user.turn.main_action_available and user.ability_cooldowns[ability.id] == 0 and enemy.health.current == 20 and state.unit_states.size() == 2, "%s spends neither the action nor the cooldown" % entry[3])
		suite.expect(session.step(EndTurnCommand.new(user.unit_id)).accepted, "%s keeps the battle playable" % entry[3])


## The live battle runs abilities on a copy and adopts it; a forecast changes in place.
## Both must reach the same state, including reactions, summons and the returning spear.
func _check_adopted_ability_equals_direct(suite: Node, fixture: Fixtures) -> void:
	var cells: Array[Vector2i] = []
	for q in range(0, 7):
		for r in range(0, 3):
			cells.append(Vector2i(q, r))
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i(0, 1), 20, 3)
	var shock: AbilityDefinition = fixture.ability(&"core:shock", AbilityDefinition.TargetMode.HEX, 1)
	shock.range = 4
	shock.effects[0].parameters = {"amount": 2, "damage_type": "electric"}
	var fire := AbilityEffectDefinition.new()
	fire.effect_type_id = &"core:hex_state"
	fire.parameters = {"state_id": "core:oil"}
	shock.effects.append(fire)
	var turret := load("res://features/abilities/definitions/electric_turret.tres") as AbilityDefinition
	var throw := load("res://features/abilities/definitions/spear_throw.tres") as AbilityDefinition
	for ability: AbilityDefinition in [shock, turret, throw]:
		user.abilities[ability.id] = ability
		user.ability_cooldowns[ability.id] = 0
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(3, 1), 30)
	var other: UnitState = fixture.unit(&"other", BattleFaction.Value.ENEMY, Vector2i(5, 1), 30)
	var state: BattleState = fixture.state(cells, [user, enemy, other])
	for hex: Vector2i in [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(4, 0)]:
		state.hex_grid.set_hex_state(hex, &"core:water")
	state.turn_service.start()
	var live := BattleEngine.new(state, false)
	var forecast := live.fork_for_prediction()
	var grid := state.hex_grid
	var commands: Array[BattleCommand] = [
		UseAbilityCommand.at_hex(user.unit_id, Vector2i(3, 1), shock.id),
		EndTurnCommand.new(enemy.unit_id), EndTurnCommand.new(other.unit_id),
		UseAbilityCommand.at_hex(user.unit_id, Vector2i(1, 2), turret.id),
		EndTurnCommand.new(enemy.unit_id), EndTurnCommand.new(other.unit_id),
	]
	var equal := true
	var mismatch := ""
	for command: BattleCommand in commands:
		var a := live.execute(command)
		var b := forecast.execute(command)
		if not command is EndTurnCommand and not (a.accepted and b.accepted):
			equal = false
			mismatch = "%s rejected: %s / %s" % [command.get_script().get_global_name(), a.rejection_reason, b.rejection_reason]
			break
		if _engine_fingerprint(live) != _engine_fingerprint(forecast) or _encode(a.events) != _encode(b.events):
			equal = false
			mismatch = "after %s" % command.get_script().get_global_name()
			break
	# The summoned turret takes a turn before the owner's next one.
	var summon_id := StringName()
	for id: StringName in live.get_turn_order():
		if String(id).contains(":summon:"):
			summon_id = id
	if equal and not summon_id.is_empty():
		while live.get_active_unit_id() != user.unit_id:
			var active := live.get_active_unit_id()
			live.execute(EndTurnCommand.new(active))
			forecast.execute(EndTurnCommand.new(active))
		live.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 1), throw.id))
		forecast.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 1), throw.id))
		while live.get_active_unit_id() != user.unit_id and live.get_outcome() == BattleOutcome.Value.IN_PROGRESS:
			var active := live.get_active_unit_id()
			var a := live.execute(EndTurnCommand.new(active))
			var b := forecast.execute(EndTurnCommand.new(active))
			if _encode(a.events) != _encode(b.events):
				equal = false
				mismatch = "spear return events"
		equal = equal and _engine_fingerprint(live) == _engine_fingerprint(forecast)
	suite.expect(equal and not summon_id.is_empty(), "An adopted transaction equals direct application: reactions, summon and spear return (%s)" % mismatch)
	suite.expect(state.unit_states[&"user"] == user and state.hex_grid == grid and enemy.health.current < 30 and state.unit_states.has(summon_id), "Adopting keeps the live state's unit and grid objects and adds the summoned unit")


func _check_detached_failure(suite: Node, fixture: Fixtures) -> void:
	var api := ModAPI.create_default()
	api.register_effect_handler(&"test:damage_then_fail", DamageThenFail.new())
	var state := _line_state(fixture, api)
	var user: UnitState = state.unit_states[&"user"]
	var ability: AbilityDefinition = fixture.ability(&"core:transaction", AbilityDefinition.TargetMode.HEX, 1)
	ability.range = 4
	var failing := AbilityEffectDefinition.new()
	failing.effect_type_id = &"test:damage_then_fail"
	ability.effects.append(failing)
	user.abilities[ability.id] = ability
	user.ability_cooldowns[ability.id] = 0
	state.turn_service.start()
	var live := BattleEngine.new(state, false)
	var before := _engine_fingerprint(live)
	var forecast := live.fork_for_prediction()
	var failed := forecast.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(2, 0), ability.id))
	var later := forecast.execute(EndTurnCommand.new(user.unit_id))
	suite.expect(not failed.accepted and not later.accepted and later.rejection_reason == FAILURE, "A forecast changed by a failed effect rejects every later command")
	suite.expect(_engine_fingerprint(live) == before and live.execute(EndTurnCommand.new(user.unit_id)).accepted, "A failed forecast never touches the live battle")


func _check_return_failure(suite: Node, fixture: Fixtures) -> void:
	var api := ModAPI.new()
	api.register_effect_handler(&"core:damage", ReturnFailingDamage.new())
	var cells: Array[Vector2i] = []
	for q in range(0, 7):
		cells.append(Vector2i(q, 0))
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var throw := load("res://features/abilities/definitions/spear_throw.tres") as AbilityDefinition
	user.abilities[throw.id] = throw
	user.ability_cooldowns[throw.id] = 0
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0), 20)
	var state: BattleState = fixture.state(cells, [user, enemy])
	state.mod_api = api
	state.turn_service.start()
	var engine := BattleEngine.new(state, false)
	var thrown := engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 0), throw.id))
	var struck := enemy.health.current
	var boundary := engine.execute(EndTurnCommand.new(enemy.unit_id))
	var returned := false
	for event: BattleEvent in boundary.events:
		returned = returned or (event is AreaAbilityUsedEvent and event.is_return)
	suite.expect(thrown.accepted and struck == 17, "The throw itself strikes through the custom handler")
	suite.expect(boundary.accepted and boundary.terminal_error == "Injected return failure" and not returned and enemy.health.current == struck, "A failed return stops the battle at the turn boundary without a partial strike")
	suite.expect(not engine.execute(EndTurnCommand.new(user.unit_id)).accepted, "A battle stopped by a failed return rejects further commands")


func _check_context_failures(suite: Node, fixture: Fixtures) -> void:
	var state := _line_state(fixture, ModAPI.create_default())
	var definition := UnitDefinition.new()
	definition.id = &"core:test_summon"
	definition.base_stats = UnitStatsDefinition.new()
	var context := BattleEffectContext.new(state)
	suite.expect(context.summon(&"user", Vector2i(2, 0), definition).is_empty() and "occupied" in context.get_failure(), "Summoning onto an occupied hex fails instead of doing nothing")
	context = BattleEffectContext.new(state)
	var none: Array[Vector2i] = []
	suite.expect(context.apply_hex_states(none, &"core:fire").is_empty() and not context.has_failed(), "An empty area changes nothing and is not a failure")
	var outside: Array[Vector2i] = [Vector2i(99, 99)]
	context.apply_hex_states(outside, &"core:fire")
	suite.expect(context.has_failed(), "A rejected terrain batch fails the effect")
	context = BattleEffectContext.new(state)
	suite.expect(context.apply_damage_events(&"user", &"nobody", 3).is_empty() and context.has_failed(), "Damage to a missing unit fails the effect")
	context = BattleEffectContext.new(state)
	suite.expect(context.apply_unit_status(&"enemy", &"core:unknown", 1).is_empty() and context.has_failed(), "An unknown status fails the effect")
	context.fail("Second reason")
	suite.expect(not context.get_failure().contains("Second"), "The first failure reason is kept")


## Real crashes are covered by handler_crash_check.gd; here the counter's filter is fed directly.
func _check_script_error_watch(suite: Node) -> void:
	var watch := ScriptErrorWatch.start()
	var no_trace: Array[ScriptBacktrace] = []
	watch._log_error("f", "file", 1, "pushed", "", false, Logger.ERROR_TYPE_ERROR, no_trace)
	watch._log_error("f", "file", 1, "warned", "", false, Logger.ERROR_TYPE_WARNING, no_trace)
	var thread := Thread.new()
	thread.start(func() -> void: watch._log_error("f", "file", 1, "elsewhere", "", false, Logger.ERROR_TYPE_SCRIPT, no_trace))
	thread.wait_to_finish()
	suite.expect(watch.error_count() == 0, "Pushed errors, warnings and other threads' script errors do not fail an effect")
	watch._log_error("f", "file", 1, "crashed", "", false, Logger.ERROR_TYPE_SCRIPT, no_trace)
	suite.expect(watch.stop() == 1, "A script error on the watched thread is counted")


## A field added to UnitState without copy_from would silently survive a rolled-forward
## transaction with a stale value; the fixture sets every field so this check notices.
func _check_unit_copy_covers_every_field(suite: Node, fixture: Fixtures) -> void:
	var full: UnitState = fixture.unit(&"unit", BattleFaction.Value.ENEMY, Vector2i(3, -2), 17, 6)
	full.health.current = 9
	full.turn.movement_remaining = 2
	full.turn.main_action_available = false
	full.basic_attack_damage = 7
	full.basic_attack_range = 3
	full.abilities[&"core:copied"] = fixture.ability(&"core:copied", AbilityDefinition.TargetMode.HEX)
	full.statuses[&"core:wet"] = 2
	full.passive_ability_ids.append(&"core:melee_retaliation")
	full.basic_attack_damage_type = &"fire"
	full.basic_attack_statuses[&"core:burning"] = 1
	full.status_immunities.append(&"core:acid")
	full.ability_cooldowns[&"core:copied"] = 2
	full.turns_started = 4
	full.melee_retaliation = true
	full.retaliation_configured = true
	full.pending_spear_return = {"hex": Vector2i(1, 1), "ability_id": &"core:copied"}
	var fresh: UnitState = fixture.unit(&"unit", BattleFaction.Value.ENEMY, Vector2i.ZERO)
	var untouched: Array[String] = []
	for property: Dictionary in full.get_property_list():
		var name: String = property.name
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or name in ["unit_id", "definition_id", "faction"]:
			continue
		if _encode(full.get(name)) == _encode(fresh.get(name)):
			untouched.append(name)
	suite.expect(untouched.is_empty(), "The copy fixture sets every UnitState field: %s" % ", ".join(untouched))
	var held_turn := fresh.turn
	fresh.copy_from(full)
	suite.expect(_encode(fresh) == _encode(full) and fresh.turn == held_turn, "copy_from takes every runtime field and keeps the unit's own objects")


func _line_state(fixture: Fixtures, api: ModAPI) -> BattleState:
	var cells: Array[Vector2i] = []
	for q in range(0, 6):
		for r in range(0, 2):
			cells.append(Vector2i(q, r))
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0), 20)
	var state: BattleState = fixture.state(cells, [user, enemy])
	state.mod_api = api
	var rock := BattleObstacleDefinition.new()
	rock.id = &"rock"
	rock.hexes = [Vector2i(3, 0)]
	rock.destructible = true
	state.hex_grid.add_obstacle(rock)
	state.hex_grid.set_hex_state(Vector2i(1, 1), &"core:water")
	return state


func _session(state: BattleState) -> BattleSession:
	if state.turn_service.get_active_unit_id().is_empty():
		state.turn_service.start()
	var setup := BattleSetup.new(state.battle_id, state.hex_grid, [], [], BattleObjectiveDefinition.new(), BattleFaction.Value.PLAYER, state.deterministic_seed)
	return BattleSession.new(setup, state, BattleEngine.new(state, false), null)


func _engine_fingerprint(engine: BattleEngine) -> String:
	var state: BattleState = engine.get("_state")
	var ids := state.unit_states.keys()
	ids.sort()
	var units: Array = []
	for id: StringName in ids:
		units.append(state.unit_states[id])
	return _encode({"units": units, "grid": state.hex_grid, "order": state.turn_service.get_turn_order(), "active": engine.get_active_unit_id(), "round": engine.get_round_number(), "revisions": [state.state_revision, state.map_revision], "rng": str(state.random.state)})


func _encode(value: Variant) -> String:
	return JSON.stringify(BattleLogSerializer.encode(value))
