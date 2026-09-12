class_name ContentLoadResult
extends RefCounted


var snapshot: ContentSnapshot
var errors: Array[String] = []
var warnings: Array[String] = []


var is_successful: bool:
	get:
		return snapshot != null and errors.is_empty()


func add_error(message: String) -> void:
	errors.append(message)


func add_warning(message: String) -> void:
	warnings.append(message)