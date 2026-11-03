extends RefCounted
## A summon names its unit by ID: content loading checks the reference, the battle setup
## resolves it from the same snapshot, and no rule definition shares a resource with the
## loader cache or with another snapshot copy.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")

const TURRET := &"core:electric_turret"
const TURRET_UNIT := &"core:electric_turret_unit"


func run(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request()
	suite.expect(request != null, "The regression battle loads")
	if request == null:
		return
	_check_snapshot_isolation(suite, request.content_snapshot)
	_check_override_reaches_summon(suite, request)
	_check_unresolved_summon_stops_setup(suite, request)
	_check_content_references(suite)


func _check_snapshot_isolation(suite: Node, snapshot: ContentSnapshot) -> void:
	var first := snapshot.get_ability_definition(TURRET)
	var second := snapshot.get_ability_definition(TURRET)
	suite.expect(SummonEffectHandler.unit_id(first.effects[0]) == TURRET_UNIT and ContentLoader._find_external_resource(first, {}).is_empty(), "The turret summon names its unit by ID and embeds no external resource")
	first.effects[0].parameters["unit_id"] = "core:changed"
	suite.expect(SummonEffectHandler.unit_id(second.effects[0]) == TURRET_UNIT and SummonEffectHandler.unit_id(snapshot.get_ability_definition(TURRET).effects[0]) == TURRET_UNIT, "Changing one copy of the summon leaves the snapshot and other copies intact")


## The unit a summon brings comes from the battle's snapshot, overrides included.
func _check_override_reaches_summon(suite: Node, request: BattleStartRequest) -> void:
	var snapshot := request.content_snapshot
	var turret_unit := snapshot.get_unit_definition(TURRET_UNIT)
	turret_unit.base_stats.max_health = 9
	var session := BattleSessionFactory.create(_with_turret(request, [turret_unit], [])).session
	suite.expect(session != null and session.setup.unit_definitions.has(TURRET_UNIT), "The battle setup resolves the summoned unit by ID")
	if session == null:
		return
	var active := session.get_active_unit_id()
	var targets := session.get_ability_target_hexes(active, TURRET)
	var summoned := StringName()
	if not targets.is_empty():
		for event: BattleEvent in session.step(UseAbilityCommand.at_hex(active, targets[0], TURRET)).events:
			if event is UnitSummonedEvent:
				summoned = event.unit.unit_id
	var unit := session.get_unit(summoned) if not summoned.is_empty() else null
	suite.expect(unit != null and unit.health.maximum == 9, "A unit override of the battle reaches the summoned unit")
	suite.expect(snapshot.get_unit_definition(TURRET_UNIT).base_stats.max_health != 9, "The override stays in its own snapshot")


func _check_unresolved_summon_stops_setup(suite: Node, request: BattleStartRequest) -> void:
	var broken := request.content_snapshot.get_ability_definition(TURRET)
	broken.effects[0].parameters["unit_id"] = "core:missing_turret"
	var creation := BattleSessionFactory.create(_with_turret(request, [], [broken]))
	suite.expect(not creation.is_successful and "core:missing_turret" in creation.error_message, "A summon of an unknown unit stops the battle setup: %s" % creation.error_message)


func _check_content_references(suite: Node) -> void:
	var core: ContentPackage = load("res://content/packages/core/core_package.tres")
	var missing := _probe_package(&"probe:summon_missing", &"core:summon", {"unit_id": "probe:missing", "center_only": true})
	var errors := "\n".join(ContentLoader.load_packages([core, missing]).errors)
	suite.expect("references missing UnitDefinition probe:missing" in errors, "Content loading rejects a summon of a missing unit: %s" % errors)
	var embedded := _probe_package(&"probe:embedded", &"core:damage", {"amount": 2, "extra": load("res://content/packages/core/electric_turret.tres")})
	errors = "\n".join(ContentLoader.load_packages([core, embedded]).errors)
	suite.expect("embeds external resource res://content/packages/core/electric_turret.tres" in errors, "Content loading rejects a rule definition that embeds an external resource: %s" % errors)
	var undeclared := _probe_package(&"probe:summon_foreign", &"core:summon", {"unit_id": "elsewhere:unit", "center_only": true})
	errors = "\n".join(ContentLoader.load_packages([core, undeclared]).errors)
	suite.expect("undeclared reference elsewhere:unit (unit_id)" in errors, "A summoned unit from an undeclared package is rejected: %s" % errors)


## The request's battle where every placed unit also has the turret summon.
func _with_turret(request: BattleStartRequest, unit_overrides: Array[UnitDefinition], ability_overrides: Array[AbilityDefinition]) -> BattleStartRequest:
	var snapshot := request.content_snapshot
	var battle := snapshot.get_battle_definition(request.battle_id)
	var units: Array[UnitDefinition] = unit_overrides.duplicate()
	var seen: Dictionary[StringName, bool] = {}
	for placement: UnitPlacementDefinition in battle.unit_placements:
		if seen.has(placement.definition_id):
			continue
		seen[placement.definition_id] = true
		var unit := snapshot.get_unit_definition(placement.definition_id)
		if not unit.ability_ids.has(TURRET):
			unit.ability_ids.append(TURRET)
		units.append(unit)
	var overridden := snapshot.with_battle_document(snapshot.get_map_definition(battle.map_id), battle, units, ability_overrides)
	return BattleStartRequest.new(battle.id, overridden, request.deterministic_seed)


## A package depending on core with one hex ability of a single effect.
func _probe_package(ability_id: StringName, effect_type: StringName, parameters: Dictionary) -> ContentPackage:
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"probe"
	package.manifest.package_version = "1"
	var dependency := ContentPackageDependency.new()
	dependency.package_id = &"core"
	package.manifest.dependencies.append(dependency)
	var ability := AbilityDefinition.new()
	ability.id = ability_id
	ability.display_name = "Probe"
	ability.target_mode = AbilityDefinition.TargetMode.EMPTY_HEX
	var effect := AbilityEffectDefinition.new()
	effect.effect_type_id = effect_type
	effect.parameters = parameters
	ability.effects.append(effect)
	package.abilities.append(ability)
	return package
