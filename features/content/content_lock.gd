class_name ContentLock
extends RefCounted


var rules_api_version: int
var packages: Array[ContentLockEntry] = []


func _init(
	p_rules_api_version: int,
	p_packages: Array[ContentLockEntry]
) -> void:
	rules_api_version = p_rules_api_version
	packages.assign(p_packages)


func to_dictionary() -> Dictionary:
	var package_data: Array[Dictionary] = []

	for entry: ContentLockEntry in packages:
		package_data.append({
			"package_id": String(entry.package_id),
			"package_version": entry.package_version,
			"content_hash": entry.content_hash,
		})

	return {
		"rules_api_version": rules_api_version,
		"packages": package_data,
	}