class_name DamageType
extends RefCounted

const ALL := [&"physical", &"electric", &"water", &"fire", &"acid", &"plasma"]
const HEX_STATES := {
	&"electric": &"core:electricity", &"water": &"core:water",
	&"fire": &"core:fire", &"acid": &"core:acid", &"plasma": &"core:plasma",
}

## Hits react with existing terrain; only explicit terrain effects create new terrain.
## Appends the reaction's events; returns "" or why the map could not react.
static func react(state: BattleState, hex: Vector2i, type: StringName, events: Array[BattleEvent]) -> String:
	var existing := state.hex_grid.get_hex_state_id(hex)
	# The damage-triggered matrix defines only base states. Repeated electric hits
	# must not erase electrified water/acid or plasma produced by the first hit.
	if not HEX_STATES.has(type) or existing not in [&"core:electricity", &"core:water", &"core:fire", &"core:oil", &"core:acid"]:
		return ""
	var mutations: Array[MapMutation] = [MapMutation.apply_hex_state(hex, HEX_STATES[type])]
	var result := MapMutationService.apply(state, mutations)
	events.append_array(result.events)
	return result.rejection_reason
