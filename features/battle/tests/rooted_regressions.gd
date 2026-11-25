extends RefCounted

const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const ROOTED := UnitStatusCatalog.ROOTED
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_check_duration(suite, fixture)
	_check_late_application(suite, fixture)
	_check_maneuvers(suite, fixture)
	_check_interruption(suite, fixture)
	var actor := UnitActor.new()
	actor.show_statuses({ROOTED: 2})
	var icon := actor.get_node_or_null("StatusIcons/core_rooted") as UnitStatusIcon
	suite.expect(icon != null and icon.texture != null and icon.tooltip_text.contains("Скованность · уровней: 2"), "A rooted unit has a status icon with its name and levels")
	actor.free()


func _check_duration(suite: Node, fixture: Fixtures) -> void:
	var caster := fixture.unit(&"caster", PLAYER, Vector2i(1, 0))
	var ally := fixture.unit(&"ally", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))
	var destination := Vector2i(3, 0)
	var ability := _rooting_ability(fixture, AbilityDefinition.TargetMode.ENEMY)
	caster.abilities[ability.id] = ability
	ally.abilities[ability.id] = ability
	var engine := BattleEngine.new(fixture.state([ally.hex, caster.hex, enemy.hex, destination], [caster, ally, enemy]))
	var reach := engine.get_reach(enemy.unit_id)
	suite.expect(reach.move.has(destination), "Ordinary movement can reach the destination before the status")
	var applied := engine.execute(UseAbilityCommand.new(caster.unit_id, enemy.unit_id, ability.id))
	suite.expect(applied.accepted and enemy.statuses.get(ROOTED, 0) == 1, "An ability can apply one level of rooted")
	var stacked := engine.execute(UseAbilityCommand.new(ally.unit_id, enemy.unit_id, ability.id))
	suite.expect(stacked.accepted and enemy.statuses.get(ROOTED, 0) == 2 and engine.get_active_faction() == ENEMY, "A second application adds a level that survives the other side's phase end")
	var move := MoveCommand.new(enemy.unit_id, destination)
	var snapshot := UnitSnapshot.new(enemy)
	suite.expect(snapshot.turn.movement_remaining == 0 and snapshot.turn.movement_spent == 0 and snapshot.turn.main_action_available, "Rooted is shown as zero available movement and preserves the action")
	suite.expect(engine.get_movement_search(enemy.unit_id).get_reachable_cells() == [enemy.hex] and not engine.execute(move).accepted, "Rooted hides all movement destinations and rejects direct move commands")
	reach = engine.get_reach(enemy.unit_id)
	suite.expect(reach.move == [enemy.hex] and reach.attack.has(caster.hex), "Projected reach keeps attacks from the current hex")
	var attack := engine.execute(AttackCommand.new(enemy.unit_id, caster.unit_id))
	suite.expect(attack.accepted and caster.health.current < caster.health.maximum and enemy.statuses.get(ROOTED, 0) == 1, "An ordinary attack still works and only one level expires at the faction handoff")
	engine.execute(EndPhaseCommand.new(PLAYER))
	suite.expect(not engine.execute(move).accepted and enemy.statuses.get(ROOTED, 0) == 1, "The remaining level blocks movement in the second enemy phase")
	engine.execute(EndPhaseCommand.new(ENEMY))
	engine.execute(EndPhaseCommand.new(PLAYER))
	suite.expect(not enemy.statuses.has(ROOTED) and engine.execute(move).accepted and enemy.hex == destination, "Ordinary movement resumes after the final level expires")


func _check_late_application(suite: Node, fixture: Fixtures) -> void:
	var target := fixture.unit(&"target", PLAYER, Vector2i.ZERO)
	var caster := fixture.unit(&"caster", PLAYER, Vector2i(1, 0))
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))
	var ability := _rooting_ability(fixture, AbilityDefinition.TargetMode.ALLY)
	caster.abilities[ability.id] = ability
	var engine := BattleEngine.new(fixture.state([target.hex, caster.hex, enemy.hex], [target, caster, enemy]))
	engine.execute(EndTurnCommand.new(target.unit_id))
	var result := engine.execute(UseAbilityCommand.new(caster.unit_id, target.unit_id, ability.id))
	suite.expect(result.accepted and engine.get_active_faction() == ENEMY and not target.statuses.has(ROOTED), "Rooted applied after the unit acted expires at the end of that same own phase")


func _check_maneuvers(suite: Node, fixture: Fixtures) -> void:
	var mover := fixture.unit(&"mover", PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", ENEMY, Vector2i(3, 0))
	var destination := Vector2i(2, 0)
	var dash: AbilityDefinition = preload("res://content/packages/core/watch_closely.tres")
	var shove: AbilityDefinition = preload("res://content/packages/core/shove.tres")
	mover.abilities[dash.id] = dash
	enemy.abilities[shove.id] = shove
	mover.statuses[ROOTED] = 2
	var engine := BattleEngine.new(fixture.state([mover.hex, Vector2i(1, 0), destination, enemy.hex], [mover, enemy]))
	var dashed := engine.execute(UseAbilityCommand.at_hex(mover.unit_id, destination, dash.id))
	suite.expect(dashed.accepted and mover.hex == destination, "Rooted does not block an ability that moves its user")
	var shoved := engine.execute(UseAbilityCommand.new(enemy.unit_id, mover.unit_id, shove.id))
	suite.expect(shoved.accepted and mover.hex == Vector2i.ZERO and mover.statuses.get(ROOTED, 0) == 1, "A shove still moves a rooted target")


func _check_interruption(suite: Node, fixture: Fixtures) -> void:
	var mover := fixture.unit(&"mover", PLAYER, Vector2i.ZERO)
	var guard := fixture.unit(&"guard", ENEMY, Vector2i(1, -1))
	var first_step := Vector2i(1, 0)
	var destination := Vector2i(2, 0)
	guard.statuses[UnitStatusCatalog.INTERCEPT_READY] = 1
	guard.basic_attack_statuses[ROOTED] = 1
	var engine := BattleEngine.new(fixture.state([mover.hex, first_step, destination, guard.hex], [mover, guard]))
	var command := MoveCommand.new(mover.unit_id, destination)
	var result := engine.execute(command)
	suite.expect(result.accepted and mover.hex == first_step and mover.turn.movement_spent == 1 and mover.statuses.get(ROOTED, 0) == 1, "Rooted applied during interception halts walking after the current step")
	suite.expect(not engine.execute(command).accepted and engine.can_command(mover.unit_id) and mover.turn.main_action_available, "The rooted mover can still act after the interruption")


func _rooting_ability(fixture: Fixtures, mode: AbilityDefinition.TargetMode) -> AbilityDefinition:
	var ability := fixture.ability(&"test:root", mode)
	ability.effects[0].effect_type_id = &"core:unit_status"
	ability.effects[0].parameters = {"status_id": String(ROOTED), "levels": 1}
	return ability
