class_name ContentPackageManifest
extends Resource


@export var package_id: StringName
@export var package_version: String = "1.0.0"
@export var content_schema_version := 1
@export var rules_api_version := 1
@export var dependencies: Array[ContentPackageDependency] = []
@export var entry_battle_ids: Array[StringName] = []
@export var entry_campaign_ids: Array[StringName] = []
@export var has_executable_extensions := false