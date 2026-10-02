class_name UnitPresentationDefinition
extends Resource


@export var id: StringName
@export var actor_scene: PackedScene
@export var actor_texture: Texture2D
@export var portrait_texture: Texture2D
@export var actor_height := 82.0
@export var actor_foot_anchor := Vector2(0.5, 1.0)
@export var actor_color := Color.WHITE
@export var movement_profile: UnitMovementProfile
@export var corpse_texture: Texture2D
@export_range(24.0, 120.0, 1.0) var corpse_width := 76.0
