class_name EditorPackageExporter
extends RefCounted


static func export(
	document: EditorDocument,
	root_path: String
) -> String:
	if document == null:
		return "EditorDocument is missing."

	var absolute_root := ProjectSettings.globalize_path(root_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_root)

	if directory_error != OK:
		return "Could not create export directory: %s." % root_path

	var package_id := _namespace_of(document.battle_definition.id)
	var dependencies: Array[Dictionary] = []

	for dependency_id: StringName in document.package_versions:
		if dependency_id == package_id:
			continue
		dependencies.append({
			"package_id": String(dependency_id),
			"exact_version": document.package_versions[dependency_id],
		})

	var manifest := {
		"package_id": String(package_id),
		"package_version": document.package_versions.get(package_id, "1.0.0"),
		"content_schema_version": EditorDocument.SCHEMA_VERSION,
		"rules_api_version": ModAPI.VERSION,
		"dependencies": dependencies,
		"entry_battle_ids": [String(document.battle_definition.id)],
		"has_executable_extensions": false,
	}
	var manifest_file := FileAccess.open(root_path.path_join("manifest.json"), FileAccess.WRITE)

	if manifest_file == null:
		return "Could not write exported manifest."

	manifest_file.store_string(JSON.stringify(manifest, "  "))
	return EditorDocumentSerializer.save(
		document,
		root_path.path_join("battle_document.json")
	)


static func _namespace_of(definition_id: StringName) -> StringName:
	var parts := String(definition_id).split(":", false, 1)
	return StringName(parts[0]) if not parts.is_empty() else &"author_pack"