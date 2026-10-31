extends SceneTree
## A handler that crashes with a script error must not leave a partial effect. GDScript
## cannot catch the error, so this run raises exactly CRASHES of them on purpose;
## tools/tests/run_tests.py accepts those and still fails on any other error.

const CRASH := "Cannot call method 'call' on a null value."
const CRASHES := 2

var checks := 0
var failures: Array[String] = []


## Strikes through the context, then crashes before returning.
class CrashAfterDamage extends AbilityEffectHandler:
	func validate(_effect: AbilityEffectDefinition) -> String:
		return ""

	func execute(_effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, target: StringName) -> Array[BattleEvent]:
		var events := context.apply_damage_events(source, target, 5)
		var missing: Object = null
		missing.call("explode")
		return events


## Strikes normally on the throw; on the way back it strikes, then crashes.
class CrashOnReturn extends DamageEffectHandler:
	func execute(effect: AbilityEffectDefinition, context: BattleEffectContext, source: StringName, target: StringName) -> Array[BattleEvent]:
		var events := super.execute(effect, context, source, target)
		if context.get_unit_hex(source) == context.target_hex:
			var missing: Object = null
			missing.call("explode")
		return events


func _initialize() -> void:
	# Load resource class dependencies in the same order as the normal game.
	load("res://content/packages/core/core_package.tres")
	var fixture: RefCounted = load("res://features/battle/tests/regression_fixtures.gd").new()
	_check_ability_crash(fixture)
	_check_return_crash(fixture)
	for failure: String in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("Handler crash check passed (%d checks)" % checks)
	quit(0 if failures.is_empty() else 1)


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _check_ability_crash(fixture: RefCounted) -> void:
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(1, 0), 20)
	var ability: AbilityDefinition = fixture.ability(&"core:crash", AbilityDefinition.TargetMode.HEX)
	ability.effects[0].effect_type_id = &"test:crash"
	user.abilities[ability.id] = ability
	user.ability_cooldowns[ability.id] = 0
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0)]
	var units: Array[UnitState] = [user, enemy]
	var state: BattleState = fixture.state(cells, units)
	var api := ModAPI.create_default()
	api.register_effect_handler(&"test:crash", CrashAfterDamage.new())
	state.mod_api = api
	state.turn_service.start()
	var engine := BattleEngine.new(state, false)
	var revision := engine.get_state_revision()
	var resolution := engine.execute(UseAbilityCommand.at_hex(user.unit_id, enemy.hex, ability.id))
	_expect(not resolution.accepted and "script error" in resolution.rejection_reason, "A crashing handler rejects the ability: %s" % resolution.rejection_reason)
	_expect(enemy.health.current == 20 and user.turn.main_action_available and user.ability_cooldowns[ability.id] == 0 and engine.get_state_revision() == revision, "A crashing handler leaves no partial damage, action or cooldown")


func _check_return_crash(fixture: RefCounted) -> void:
	var user: UnitState = fixture.unit(&"user", BattleFaction.Value.PLAYER, Vector2i.ZERO, 20, 3)
	var enemy: UnitState = fixture.unit(&"enemy", BattleFaction.Value.ENEMY, Vector2i(2, 0), 20)
	var throw := load("res://features/abilities/definitions/spear_throw.tres") as AbilityDefinition
	user.abilities[throw.id] = throw
	user.ability_cooldowns[throw.id] = 0
	var cells: Array[Vector2i] = []
	for q in range(0, 7):
		cells.append(Vector2i(q, 0))
	var units: Array[UnitState] = [user, enemy]
	var state: BattleState = fixture.state(cells, units)
	var api := ModAPI.new()
	api.register_effect_handler(&"core:damage", CrashOnReturn.new())
	state.mod_api = api
	state.turn_service.start()
	var engine := BattleEngine.new(state, false)
	engine.execute(UseAbilityCommand.at_hex(user.unit_id, Vector2i(4, 0), throw.id))
	var struck := enemy.health.current
	var boundary := engine.execute(EndTurnCommand.new(enemy.unit_id))
	_expect(struck == 17 and boundary.accepted and "script error" in boundary.terminal_error, "A crash during the spear return stops the battle: %s" % boundary.terminal_error)
	_expect(enemy.health.current == struck, "A crash during the spear return leaves no partial strike")
