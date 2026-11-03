extends RefCounted
## Preview scenes build valid battles from the ordinary content with their overrides.
const HexStatusPreview := preload("res://tools/previews/hex_status_preview.gd")
const DamageAbilityPreview := preload("res://tools/previews/damage_ability_preview.gd")


func run(suite: Node) -> void:
	var hex_preview := HexStatusPreview.create_request()
	suite.expect(hex_preview != null, "Hex status preview request builds")
	if hex_preview != null:
		var snapshot := hex_preview.content_snapshot
		var battle := snapshot.get_battle_definition(hex_preview.battle_id)
		var map := snapshot.get_map_definition(battle.map_id)
		var states_on_starts := 0
		for placement: UnitPlacementDefinition in battle.unit_placements:
			for cell: BattleMapCellDefinition in map.cells:
				if cell.hex == placement.start_hex and cell.has_layers():
					states_on_starts += 1
		var first_unit := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		suite.expect(states_on_starts == battle.unit_placements.size(), "Hex status preview puts a state under every unit")
		suite.expect(first_unit.base_stats.armor_levels == 3 and first_unit.ability_ids.has(&"core:create_fire"), "Hex status preview applies armor and creation abilities")
		suite.expect(BattleSessionFactory.create(hex_preview).is_successful, "Hex status preview battle starts")

	var damage_preview := DamageAbilityPreview.create_request()
	suite.expect(damage_preview != null, "Damage preview request builds")
	if damage_preview != null:
		var snapshot := damage_preview.content_snapshot
		var battle := snapshot.get_battle_definition(damage_preview.battle_id)
		var unit := snapshot.get_unit_definition(battle.unit_placements[0].definition_id)
		suite.expect(snapshot.get_ability_definition(&"core:laser").initial_cooldown_turns == 1 and unit.ability_ids.has(&"core:laser") and battle.unit_placements.back().placement_id == &"preview:turret", "Damage preview applies its overrides")
		suite.expect(BattleSessionFactory.create(damage_preview).is_successful, "Damage preview battle starts")
