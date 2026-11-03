class_name DamageType
extends RefCounted

const ALL := [&"physical", &"electric", &"water", &"fire", &"acid", &"plasma"]
const HEX_STATES := {
	&"electric": &"core:electricity", &"water": &"core:water",
	&"fire": &"core:fire", &"acid": &"core:acid", &"plasma": &"core:plasma",
}

## A hit applies its element by the layer rules, only to a hex that already has a layer;
## explicit terrain effects alone create layers on a clean hex.
## Appends the reaction's events; returns "" or why the map could not react.
static func react(state: BattleState, hex: Vector2i, type: StringName, events: Array[BattleEvent]) -> String:
	if not HEX_STATES.has(type) or not state.hex_grid.has_layers(hex):
		return ""
	var mutations: Array[MapMutation] = [MapMutation.apply_hex_state(hex, HEX_STATES[type])]
	var result := MapMutationService.apply(state, mutations)
	events.append_array(result.events)
	return result.rejection_reason
