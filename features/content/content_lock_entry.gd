class_name ContentLockEntry
extends RefCounted


var package_id: StringName
var package_version: String
var content_hash: String


func _init(
	p_package_id: StringName,
	p_package_version: String,
	p_content_hash: String
) -> void:
	package_id = p_package_id
	package_version = p_package_version
	content_hash = p_content_hash