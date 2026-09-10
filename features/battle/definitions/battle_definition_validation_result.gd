class_name BattleDefinitionValidationResult
extends RefCounted


var is_valid: bool
var error_message: String


func _init(
	p_is_valid: bool,
	p_error_message: String
) -> void:
	is_valid = p_is_valid
	error_message = p_error_message


static func success() -> BattleDefinitionValidationResult:
	return BattleDefinitionValidationResult.new(true, "")


static func failure(
	message: String
) -> BattleDefinitionValidationResult:
	return BattleDefinitionValidationResult.new(false, message)