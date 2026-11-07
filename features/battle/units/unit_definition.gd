class_name UnitDefinition
extends Resource


@export var id: StringName
@export var display_name: String
@export var base_stats: UnitStatsDefinition

@export var race_id: StringName
## UnitBody: a living body takes ordinary healing, a mechanical one only repairs.
@export var body: StringName = UnitBody.LIVING
@export var ability_ids: Array[StringName] = []
@export var passive_ability_ids: Array[StringName] = []
@export var presentation_id: StringName
@export var passive_definitions: Dictionary = {}
