class_name StrategistAbilityDefinition
extends Resource
## An ability of a faction's strategist. The strategist stands on no hex and is no unit: once per
## phase of its side it uses one such ability, and the effects run through the ordinary handlers.

## FIELD_EDGE: a hex missing from the battlefield next to one of its hexes.
enum TargetMode { FIELD_EDGE }

@export var id: StringName
@export var display_name: String
## Player-facing text without variables.
@export_multiline var description := ""
@export var presentation_id: StringName
@export var target_mode: TargetMode = TargetMode.FIELD_EDGE
## The ability cannot be used again while a unit an earlier use brought in is still alive.
@export var one_at_a_time := false
@export var effects: Array[AbilityEffectDefinition] = []


func validate() -> String:
	if display_name.strip_edges().is_empty():
		return "Strategist ability needs a display name."
	if target_mode < TargetMode.FIELD_EDGE or target_mode > TargetMode.FIELD_EDGE:
		return "Unknown strategist target mode."
	if effects.is_empty():
		return "Strategist ability must have effects."
	for effect: AbilityEffectDefinition in effects:
		if effect == null:
			return "Strategist ability contains a null effect."
	# Only a landing creates the missing hex the field edge points at.
	if target_mode == TargetMode.FIELD_EDGE and (effects.size() != 1 or effects[0].effect_type_id != &"core:landing"):
		return "A field-edge strategist ability requires a single core:landing effect."
	return ""
