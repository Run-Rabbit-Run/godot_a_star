extends RefCounted
## «Огненный росчерк»: a neighboring hex chooses a side; every unit on it and on the two hexes
## beside it next to the user — allies too — takes 1 fire damage and one level of burning.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const STROKE := &"core:fire_stroke"
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var loaded := ContentLoader.load_packages([core])
	var ability := loaded.snapshot.get_ability_definition(STROKE) if loaded.is_successful else null
	suite.expect(ability != null, "The core package ships «Огненный росчерк»: %s" % "\n".join(loaded.errors))
	if ability == null:
		return
	_run_definition(suite, loaded.snapshot, ability, core)
	_run_geometry(suite, fixture, ability)
	_run_strike(suite, fixture, ability)
	_run_ai(suite, fixture, ability)


func _run_definition(suite: Node, snapshot: ContentSnapshot, ability: AbilityDefinition, core: ContentPackage) -> void:
	suite.expect(ability.target_mode == AbilityDefinition.TargetMode.ARC and ability.range == 1 and ability.area_radius == 0 and ability.targets_hex() and not ability.melee_attack, "«Огненный росчерк» chooses a side of three neighboring hexes")
	suite.expect(ability.cooldown_turns == 1 and ability.initial_cooldown_turns == 0 and ability.validate().is_empty(), "«Огненный росчерк» has a cooldown of 1 and none at the start")
	var damage := ability.effects[0] if ability.effects.size() == 2 else null
	var burning := ability.effects[1] if ability.effects.size() == 2 else null
	suite.expect(damage != null and damage.effect_type_id == &"core:damage" and damage.parameters.get("amount") == 1 and damage.parameters.get("secondary_amount") == 1 and damage.parameters.get("damage_type") == "fire" and damage.parameters.get("affects_obstacles") == false, "The stroke deals 1 fire damage to units only")
	suite.expect(burning != null and burning.effect_type_id == &"core:unit_status" and StringName(burning.parameters.get("status_id")) == UnitStatusCatalog.BURNING and burning.parameters.get("levels") == 1, "Then it sets one level of burning")
	suite.expect(snapshot.get_ability_presentation_definition(ability.presentation_id) != null, "«Огненный росчерк» has a presentation")
	var text := AbilityDescription.render(ability)
	suite.expect(text.contains("1 урона (огненный)") and text.contains("горение ×1") and not "{" in text, "The stroke describes itself: %s" % text)
	var wide := ability.duplicate(true) as AbilityDefinition
	wide.range = 2
	var spread := ability.duplicate(true) as AbilityDefinition
	spread.area_radius = 1
	suite.expect(not wide.validate().is_empty() and not spread.validate().is_empty(), "A side of neighbors needs range 1 and no area radius")
	var skills := SkillLibrary.new([core])
	var document: Dictionary = skills.builtin_documents().get(String(STROKE), {})
	var reread: Dictionary = SkillLibrary.normalized(JSON.parse_string(JSON.stringify(document)))
	suite.expect(not document.is_empty() and skills.validate(reread).is_empty() and skills.is_builtin_default(reread), "The skill editor reads the built-in stroke as valid")


func _run_geometry(suite: Node, fixture: Fixtures, ability: AbilityDefinition) -> void:
	var user := fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	_give(user, ability)
	var state := fixture.state(_disk(2), [user, fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))])
	BattleEngine.new(state)
	var targets := AbilityExecutor.get_target_hexes(state, user.unit_id, STROKE)
	var neighbors: Array[Vector2i] = []
	for direction: Vector2i in HexGrid.DIRECTIONS:
		neighbors.append(direction)
	neighbors.sort()
	suite.expect(targets == neighbors, "Any of the six neighbors chooses a side, the user's own hex does not: %s" % [targets])
	var east: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0)]
	suite.expect(AbilityExecutor.get_affected_hexes(state.hex_grid, user.hex, ability, Vector2i(1, 0)) == east, "The east side is the east hex and the two hexes beside it")
	var north_west: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
	suite.expect(AbilityExecutor.get_affected_hexes(state.hex_grid, user.hex, ability, Vector2i(0, -1)) == north_west, "Each side turns with the chosen neighbor")
	suite.expect(AbilityExecutor.get_affected_hexes(state.hex_grid, user.hex, ability, Vector2i(2, 0)).is_empty(), "A hex that is no neighbor gives no side")
	var holed_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]
	var holed := HexGrid.new(holed_cells)
	var cut: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0)]
	suite.expect(AbilityExecutor.get_affected_hexes(holed, Vector2i.ZERO, ability, Vector2i(1, 0)) == cut, "Missing hexes are left out of the side")


## The user at the origin strikes east: enemies at (1, 0) and (1, -1), an ally at (0, 1);
## an enemy west at (-1, 0) and an obstacle next to the side stay untouched.
func _run_strike(suite: Node, fixture: Fixtures, ability: AbilityDefinition) -> void:
	var user := fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	_give(user, ability)
	var front := fixture.unit(&"front", ENEMY, Vector2i(1, 0))
	front.melee_retaliation = true
	front.retaliation_configured = true
	var flank := fixture.unit(&"flank", ENEMY, Vector2i(1, -1))
	var ally := fixture.unit(&"ally", PLAYER, Vector2i(0, 1))
	var behind := fixture.unit(&"behind", ENEMY, Vector2i(-1, 0))
	var state := fixture.state(_disk(2), [user, front, flank, ally, behind])
	var engine := BattleEngine.new(state)
	var command := UseAbilityCommand.at_hex(user.unit_id, Vector2i(1, 0), STROKE)
	var preview := ActionPreview.build(engine.fork_for_prediction(), engine, command)
	suite.expect(preview.accepted and preview.units.has(front.unit_id) and preview.units.has(flank.unit_id) and preview.units.has(ally.unit_id) and not preview.units.has(behind.unit_id), "The preview shows the three units of the side")
	var result := engine.execute(command)
	suite.expect(result.accepted, "The stroke is used on the east side: %s" % result.rejection_reason)
	for unit: UnitState in [front, flank, ally]:
		suite.expect(unit.health.current == 99 and unit.statuses.get(UnitStatusCatalog.BURNING, 0) == 1, "%s takes 1 fire damage and starts burning" % unit.unit_id)
	suite.expect(behind.health.current == 100 and behind.statuses.is_empty() and user.health.current == 100 and user.statuses.is_empty(), "The other side and the user are untouched")
	var types: Array[StringName] = []
	var retaliated := false
	for event: BattleEvent in result.events:
		if event is UnitDamagedEvent:
			types.append(event.damage_type)
			retaliated = retaliated or event.target_id == user.unit_id
	suite.expect(types == [&"fire", &"fire", &"fire"] and not retaliated, "Every hit is fire, and the stroke is no melee strike to answer")
	var area := result.events[0] as AreaAbilityUsedEvent if not result.events.is_empty() else null
	suite.expect(area != null and area.affected_hexes == AbilityExecutor.get_affected_hexes(state.hex_grid, Vector2i.ZERO, ability, Vector2i(1, 0)), "The area event lists the side")

	# Obstacles in the side keep their health.
	user = fixture.unit(&"user", PLAYER, Vector2i.ZERO)
	_give(user, ability)
	state = fixture.state(_disk(2), [user, fixture.unit(&"enemy", ENEMY, Vector2i(2, 0))])
	var obstacle := BattleObstacleDefinition.new()
	obstacle.id = &"test:crate"
	obstacle.destructible = true
	obstacle.max_hp = 5
	obstacle.hexes.append(Vector2i(1, 0))
	state.hex_grid.add_obstacle(obstacle)
	engine = BattleEngine.new(state)
	result = engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(1, 0), STROKE))
	suite.expect(result.accepted and state.hex_grid.get_obstacle(Vector2i(1, 0)).current_hp == 5, "The stroke leaves an obstacle on the side whole")


## The tactical AI burns two neighbors with one stroke rather than a weak strike at one.
func _run_ai(suite: Node, fixture: Fixtures, ability: AbilityDefinition) -> void:
	var burner := fixture.unit(&"ai_burner", ENEMY, Vector2i.ZERO, 100, 0)
	burner.basic_attack_damage = 1
	_give(burner, ability)
	var left := fixture.unit(&"left", PLAYER, Vector2i(1, 0))
	var right := fixture.unit(&"right", PLAYER, Vector2i(1, -1))
	var session := fixture.ai_session(fixture.state(_disk(2), [burner, left, right]))
	var profile := AIProfileDefinition.new()
	profile.policy_id = AICommandSource.TACTICAL_POLICY
	var command := AICommandSource.new(profile).next_command(session)
	var stroke := command as UseAbilityCommand
	var area: Array[Vector2i] = []
	if stroke != null:
		area = session.get_ability_affected_hexes(burner.unit_id, STROKE, stroke.target_hex)
	suite.expect(stroke != null and stroke.ability_id == STROKE and area.has(left.hex) and area.has(right.hex), "The tactical AI strokes the side with both opponents")
	var result := session.step(command) if command != null else null
	var struck: Array[StringName] = []
	if result != null:
		for event: BattleEvent in result.events:
			if event is UnitDamagedEvent and event.source_ability_id == STROKE:
				struck.append(event.target_id)
	suite.expect(result != null and result.accepted and struck.size() == 2 and struck.has(left.unit_id) and struck.has(right.unit_id), "The AI's stroke is accepted and strikes both: %s" % [struck])


static func _give(unit: UnitState, ability: AbilityDefinition) -> void:
	unit.abilities[ability.id] = ability
	unit.ability_cooldowns[ability.id] = 0


static func _disk(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, radius - q) + 1):
			cells.append(Vector2i(q, r))
	return cells
