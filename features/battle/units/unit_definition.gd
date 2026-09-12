class_name UnitDefinition
extends Resource


@export var id: StringName
@export var display_name: String
@export var actor_scene: PackedScene
@export var actor_texture: Texture2D
@export var actor_color := Color.WHITE
@export var base_stats: UnitStatsDefinition

@export var race_id: StringName
@export var ability_ids: Array[StringName] = []
@export var presentation_id: StringName
