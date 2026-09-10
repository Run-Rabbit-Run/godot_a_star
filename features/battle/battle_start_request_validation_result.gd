class_name BattleStartRequestValidationResult
extends RefCounted


var is_valid: bool
var error_message: String


func _init(
	p_is_valid: bool,
	p_error_message: String
) -> void:
	is_valid = p_is_valid
	error_message = p_error_message


static func success() -> BattleStartRequestValidationResult:
	return BattleStartRequestValidationResult.new(true, "")


static func failure(
	message: String
) -> BattleStartRequestValidationResult:
	return BattleStartRequestValidationResult.new(false, message)