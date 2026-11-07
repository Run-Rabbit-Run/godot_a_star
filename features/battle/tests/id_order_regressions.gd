extends RefCounted
## Rules that go through units or abilities by ID take them in the text order of the IDs
## (`IdOrder`), not in the pointer order `Array.sort()` gives StringName nor in the order
## units entered the battle. The IDs are made at run time, alphabetically, so the pointer
## order follows their creation and not their text; units enter in a third, mixed order.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")
const WORDS: Array[String] = ["alpha", "beta", "mid", "zeta"]
## Indexes into WORDS: the order units are added to the battle.
const ENTRY_ORDER: Array[int] = [2, 0, 3, 1]
const PLAYER := BattleFaction.Value.PLAYER
const ENEMY := BattleFaction.Value.ENEMY


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	_run_helper(suite)
	_run_ability_targets(suite, fixture)
	_run_health_aura(suite, fixture)
	_run_held_hexes(suite, fixture)
	_run_snapshot_abilities(suite, fixture)


func _run_helper(suite: Node) -> void:
	var ids := _fresh_ids("helper")
	var shuffled: Array[StringName] = []
	for index: int in ENTRY_ORDER:
		shuffled.append(ids[index])
	shuffled.reverse()
	suite.expect(IdOrder.sorted(shuffled) == ids, "IdOrder sorts IDs by their text: %s" % [IdOrder.sorted(shuffled)])
	suite.expect(IdOrder.is_before(ids[0], ids[3]) and not IdOrder.is_before(ids[3], ids[0]) and not IdOrder.is_before(ids[1], ids[1]), "IdOrder.is_before compares the text of IDs")
	var untyped: Array = [ids[3], ids[0]]
	var expected: Array[StringName] = [ids[0], ids[3]]
	suite.expect(IdOrder.sorted(untyped) == expected and untyped == [ids[3], ids[0]], "IdOrder.sorted takes untyped keys and leaves its argument as it was")


## A damaging sweep around the user hits its neighbours in the text order of their IDs.
func _run_ability_targets(suite: Node, fixture: Fixtures) -> void:
	var ids := _fresh_ids("targets")
	var user: UnitState = fixture.unit(&"id_order:user", PLAYER, Vector2i.ZERO)
	var sweep: AbilityDefinition = fixture.ability(&"id_order:sweep", AbilityDefinition.TargetMode.SELF, 1)
	sweep.range = 1
	user.abilities[sweep.id] = sweep
	var units: Array[UnitState] = [user]
	for index: int in ENTRY_ORDER:
		units.append(fixture.unit(ids[index], ENEMY, HexGrid.DIRECTIONS[index]))
	var state: BattleState = fixture.state(_cells(2), units)
	Fixtures.start_turns(state)
	var resolution := BattleEngine.new(state, false).execute(UseAbilityCommand.at_hex(user.unit_id, user.hex, sweep.id))
	var hit: Array[StringName] = []
	for event: BattleEvent in resolution.events:
		if event is UnitDamagedEvent:
			hit.append(event.target_id)
	suite.expect(resolution.accepted and hit == ids, "Ability effects reach their targets in ID order: %s" % [hit])


## A health aura changes its allies in the text order of their IDs.
func _run_health_aura(suite: Node, fixture: Fixtures) -> void:
	var ids := _fresh_ids("aura")
	var units: Array[UnitState] = []
	for index: int in ENTRY_ORDER:
		units.append(fixture.unit(ids[index], PLAYER, HexGrid.DIRECTIONS[index], 10))
	var source: UnitState = fixture.unit(&"id_order:aura_source", PLAYER, Vector2i.ZERO, 10)
	source.ally_max_health_bonus = 2
	units.append(source)
	var state: BattleState = fixture.state(_cells(2), units)
	var events: Array[BattleEvent] = []
	HealthAuraService.refresh(state, events)
	var changed: Array[StringName] = []
	for event: BattleEvent in events:
		if event is UnitHealthChangedEvent:
			changed.append(event.unit_id)
	suite.expect(changed == ids, "The health aura reaches its allies in ID order: %s" % [changed])


## Defeated holders lose their hexes, and the bodies on them, in the text order of their IDs.
func _run_held_hexes(suite: Node, fixture: Fixtures) -> void:
	var ids := _fresh_ids("held")
	var units: Array[UnitState] = [fixture.unit(&"id_order:survivor", ENEMY, Vector2i.ZERO)]
	for index: int in ENTRY_ORDER:
		var holder: UnitState = fixture.unit(ids[index], PLAYER, HexGrid.DIRECTIONS[index] * 2)
		holder.holds_hex = true
		holder.health.current = 0
		units.append(holder)
	var state: BattleState = fixture.state(_cells(3), units)
	var events: Array[BattleEvent] = []
	var error := HeldHexService.collapse_defeated(state, events)
	var removed: Array[StringName] = []
	for event: BattleEvent in events:
		if event is CorpseRemovedEvent:
			removed.append(event.unit_id)
	suite.expect(error.is_empty() and removed == ids, "Defeated holders collapse in ID order: %s" % [removed])


## A unit's abilities are listed in the text order of their IDs, which the basic AI follows.
func _run_snapshot_abilities(suite: Node, fixture: Fixtures) -> void:
	var ids := _fresh_ids("ability")
	var unit: UnitState = fixture.unit(&"id_order:caster", PLAYER, Vector2i.ZERO)
	for index: int in ENTRY_ORDER:
		unit.abilities[ids[index]] = fixture.ability(ids[index], AbilityDefinition.TargetMode.ENEMY)
	suite.expect(UnitSnapshot.new(unit).ability_ids == ids, "A unit snapshot lists abilities in ID order: %s" % [UnitSnapshot.new(unit).ability_ids])


## New StringNames, made in the alphabetical order of WORDS.
func _fresh_ids(topic: String) -> Array[StringName]:
	var ids: Array[StringName] = []
	for word: String in WORDS:
		ids.append(StringName("id_order_%s:%s" % [topic, word]))
	return ids


func _cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			cells.append(Vector2i(q, r))
	return cells
