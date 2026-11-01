extends RefCounted
## Content and battle documents: loading the shipped packages and validating a document.
const Fixtures := preload("res://features/battle/tests/regression_fixtures.gd")


func run_content(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var loaded := fixture.content()
	suite.expect(loaded.is_successful, "All shipped packages and authored logic load: %s" % str(loaded.errors))
	if not loaded.is_successful:
		return
	var snapshot := loaded.snapshot
	var lock := snapshot.content_lock
	lock.packages[0].package_version = "changed"
	suite.expect(snapshot.content_lock.packages[0].package_version != "changed", "Content lock detached from external callers")
	var laser := snapshot.get_ability_definition(&"core:laser")
	var cooldown := laser.initial_cooldown_turns
	laser.initial_cooldown_turns = 77
	suite.expect(snapshot.get_ability_definition(laser.id).initial_cooldown_turns == cooldown, "Snapshot getter does not expose mutable ability")
	var unit := snapshot.get_all_unit_definitions()[0]
	var health := unit.base_stats.max_health
	unit.base_stats.max_health = 999
	suite.expect(snapshot.get_unit_definition(unit.id).base_stats.max_health == health, "Nested stats detached from snapshot getters")
	suite.expect(not snapshot.mod_api.register_effect_handler(&"test:damage", DamageEffectHandler.new()), "Snapshot effect registry frozen")
	var package := ContentPackage.new()
	package.manifest = ContentPackageManifest.new()
	package.manifest.package_id = &"foreign"
	var foreign := UnitDefinition.new()
	foreign.id = &"foreign:unit"
	foreign.display_name = "Foreign"
	foreign.base_stats = UnitStatsDefinition.new()
	foreign.ability_ids.append(&"core:laser")
	package.units.append(foreign)
	var packages := GameContentSettings.read().content_packages.duplicate()
	packages.append(package)
	suite.expect(not ContentLoader.load_packages(packages).is_successful, "Undeclared cross-package reference rejected")
	var hash_before := ContentLoader._create_lock_entry(package).content_hash
	foreign.base_stats.max_health += 1
	suite.expect(ContentLoader._create_lock_entry(package).content_hash != hash_before, "Content fingerprint changes when stats change with same IDs")
	var dependency := ContentPackageDependency.new()
	dependency.package_id = &"core"
	package.manifest.dependencies.append(dependency)
	suite.expect(ContentLoader.load_packages(packages).is_successful, "Declared cross-package reference accepted")
	var data := UnitLibrary.new_document()
	data.attack_range = 1
	data.image = "missing.png"
	suite.expect(UnitLibrary.validate(data, fixture.skills().catalog()).is_empty(), "Melee range one and missing optional image allowed")
	data.image = "../outside.png"
	suite.expect(not UnitLibrary.validate(data, fixture.skills().catalog()).is_empty(), "Unit image cannot leave asset folder")
	data = UnitLibrary.new_document()
	data.passives = ["core:fire_attack", "core:water_attack"]
	suite.expect(not UnitLibrary.validate(data, fixture.skills().catalog()).is_empty(), "Conflicting basic damage types rejected")


func run_documents(suite: Node) -> void:
	var fixture: Fixtures = suite.fixture
	var request := fixture.request()
	suite.expect(request != null, "Regression battle fixture loads")
	if request == null:
		return
	var document := BattleDocument.from_snapshot(request.content_snapshot, request.battle_id)
	suite.expect(document.validate(request.content_snapshot).is_valid, "Valid document accepted")
	var data := BattleDocumentSerializer.to_dictionary(document)
	var roundtrip := BattleDocumentSerializer.from_dictionary(data)
	suite.expect(roundtrip != null and BattleDocumentSerializer.to_dictionary(roundtrip) == data, "Document serialization round-trips")
	var bad := document.duplicate_document()
	bad.battle_definition.map_id = &"core:wrong_map"
	suite.expect(not bad.validate(request.content_snapshot).is_valid and bad.create_start_request(request.content_snapshot, 1) == null, "Map mismatch rejected before startup")
	bad = document.duplicate_document()
	bad.battle_definition.primary_objective = null
	suite.expect(not bad.validate(request.content_snapshot).is_valid, "Missing objective rejected by document validator")
	bad = document.duplicate_document()
	for cell: BattleMapCellDefinition in bad.map_definition.cells:
		if cell.hex == bad.battle_definition.unit_placements[0].start_hex:
			cell.traversable = false
	suite.expect(not bad.validate(request.content_snapshot).is_valid, "Nontraversable placement rejected")
	bad = document.duplicate_document()
	bad.battle_definition.sides[0].faction = 99 as BattleFaction.Value
	suite.expect(not bad.validate(request.content_snapshot).is_valid, "Unknown faction rejected")
	data.map.cells[0].q = 1.5
	suite.expect(BattleDocumentSerializer.from_dictionary(data) == null, "Fractional hex coordinates rejected")
	var save_path := "user://review_regression_document_%d.json" % OS.get_process_id()
	suite.expect(BattleDocumentSerializer.save(document, save_path).is_empty(), "Atomic document save succeeds")
	suite.expect(BattleDocumentSerializer.load_result(save_path).document != null, "Saved document loads")
	DirAccess.remove_absolute(save_path)
