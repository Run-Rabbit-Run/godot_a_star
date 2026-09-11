class_name BattleAuthoringValidationResult
extends RefCounted


var errors: Array[String] = []
var warnings: Array[String] = []


var is_valid: bool:
    get:
        return errors.is_empty()


func add_error(message: String) -> void:
    errors.append(message)


func add_warning(message: String) -> void:
    warnings.append(message)


func get_first_error() -> String:
    if errors.is_empty():
        return ""

    return errors[0]
