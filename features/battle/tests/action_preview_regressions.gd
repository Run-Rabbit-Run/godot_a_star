extends RefCounted
## Action preview: what a command would do, computed on a forecast copy, up to the end of the
## acting unit's turn; and the reach of a unit in its next turn.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_attack(suite, fixture)
	_run_boundary(suite, fixture)
	_run_terrain(suite, fixture)
	_run_move(suite, fixture)
	_run_reach(suite, fixture)


func _line(length: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(length):
		cells.append(Vector2i(q, 0))
	return cells


func _run_attack(suite: Node, fixture: Fixtures) -> void:
	var shooter := fixture.unit(&"shooter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	shooter.basic_attack_range = 3
	shooter.basic_attack_damage = 5
	var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(2, 0))
	var weak := fixture.unit(&"weak", BattleFaction.Value.ENEMY, Vector2i(3, 0), 3)
	var session := fixture.ai_session(fixture.state(_line(5), [shooter, target, weak]))
	var revision := session.get_state_revision()
	var preview := session.preview(AttackCommand.new(&"shooter", &"target"))
	var change := preview.units.get(&"target") as ActionPreview.UnitChange
	suite.expect(preview.accepted and change != null and change.health_before == 100 and change.health_after == 95 and not change.defeated, "A shot previews the target's health after the hit")
	suite.expect(target.health.current == 100 and shooter.turn.main_action_available and session.get_state_revision() == revision, "A preview leaves the live battle untouched")
	preview = session.preview(AttackCommand.new(&"shooter", &"weak"))
	suite.expect((preview.units[&"weak"] as ActionPreview.UnitChange).defeated, "A lethal hit is previewed as a kill")
	suite.expect(not session.preview(AttackCommand.new(&"target", &"shooter")).accepted, "An illegal command previews as rejected")

	var fighter := fixture.unit(&"fighter", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var guard := fixture.unit(&"guard", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	guard.passive_ability_ids = [&"core:melee_retaliation"]
	session = fixture.ai_session(fixture.state(_line(3), [fighter, guard]))
	preview = session.preview(AttackCommand.new(&"fighter", &"guard"))
	suite.expect((preview.units[&"fighter"] as ActionPreview.UnitChange).health_after == 98, "Retaliation against the attacker is part of the preview")


func _run_boundary(suite: Node, fixture: Fixtures) -> void:
	# The attack ends the only player unit's turn, so the enemy phase starts in the same step.
	var attacker := fixture.unit(&"attacker", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	attacker.statuses[&"core:burning"] = 2
	var target := fixture.unit(&"target", BattleFaction.Value.ENEMY, Vector2i(1, 0))
	var state := fixture.state(_line(3), [attacker, target])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:fire")
	var session := fixture.ai_session(state)
	var preview := session.preview(AttackCommand.new(&"attacker", &"target"))
	suite.expect(preview.accepted and not preview.units.has(&"attacker"), "The actor's burning acts at its next phase start, outside the preview")
	suite.expect((preview.units[&"target"] as ActionPreview.UnitChange).health_after == 98, "Effects of the next phase are not part of the preview")


func _run_terrain(suite: Node, fixture: Fixtures) -> void:
	var user := fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var ability := fixture.ability(&"test:fire_field", AbilityDefinition.TargetMode.HEX)
	ability.effects[0].effect_type_id = &"core:hex_state"
	ability.effects[0].parameters = {"state_id": "core:fire"}
	user.abilities[ability.id] = ability
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(4, 0))
	var state := fixture.state(_line(5), [user, enemy])
	state.hex_grid.set_hex_state(Vector2i(2, 0), &"core:water")
	var session := fixture.ai_session(state)
	var preview := session.preview(UseAbilityCommand.at_hex(&"user", Vector2i(2, 0), ability.id))
	suite.expect(preview.accepted and preview.hexes.get(Vector2i(2, 0), []) == [&"core:water", &"", &"core:steam", &""], "Hex reactions are previewed as layers before and after")
	suite.expect(state.hex_grid.get_liquid(Vector2i(2, 0)) == &"core:water", "The live map keeps its layers")


func _run_move(suite: Node, fixture: Fixtures) -> void:
	var walker := fixture.unit(&"walker", BattleFaction.Value.PLAYER, Vector2i.ZERO, 100, 3)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(4, 0))
	var state := fixture.state(_line(5), [walker, enemy])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:fire")
	var session := fixture.ai_session(state)
	var preview := session.preview(MoveCommand.new(&"walker", Vector2i(2, 0)))
	var change := preview.units[&"walker"] as ActionPreview.UnitChange
	suite.expect(preview.reached and preview.destination == Vector2i(2, 0) and change.health_after == 99 and change.statuses_after.get(&"core:burning", 0) == 2, "A route previews the damage and statuses picked up on the way")

	walker = fixture.unit(&"walker", BattleFaction.Value.PLAYER, Vector2i.ZERO, 100, 3)
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(4, 0))
	state = fixture.state(_line(5), [walker, enemy])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:oil")
	session = fixture.ai_session(state)
	preview = session.preview(MoveCommand.new(&"walker", Vector2i(2, 0)))
	suite.expect(not preview.reached and preview.destination == Vector2i(1, 0), "A route that oil cuts short previews where the unit stops")

	walker = fixture.unit(&"walker", BattleFaction.Value.PLAYER, Vector2i.ZERO, 1, 3)
	enemy = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(4, 0))
	state = fixture.state(_line(5), [walker, enemy])
	state.hex_grid.set_hex_state(Vector2i(1, 0), &"core:acid")
	session = fixture.ai_session(state)
	preview = session.preview(MoveCommand.new(&"walker", Vector2i(2, 0)))
	suite.expect(not preview.reached and (preview.units[&"walker"] as ActionPreview.UnitChange).defeated, "A lethal route previews the death")


func _run_reach(suite: Node, fixture: Fixtures) -> void:
	var player := fixture.unit(&"player", BattleFaction.Value.PLAYER, Vector2i.ZERO)
	var enemy := fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(6, 0), 100, 2)
	var session := fixture.ai_session(fixture.state(_line(8), [player, enemy]))
	var reach := session.get_reach(&"enemy")
	suite.expect(reach.move == [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0)], "An enemy's reach covers the cells its movement allows")
	suite.expect(reach.attack.has(Vector2i(3, 0)) and not reach.attack.has(Vector2i(2, 0)), "Its attack area adds the attack range around them")
	enemy.statuses[&"core:paralysis"] = 1
	suite.expect(session.get_reach(&"enemy").move.is_empty(), "A paralyzed unit reaches nothing")
