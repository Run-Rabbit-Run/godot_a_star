class_name AbilityDefinition
extends Resource


@export var id: StringName
@export var display_name: String
@export var range := 1
@export var ends_main_action := true
@export var effects: Array[AbilityEffectDefinition] = []