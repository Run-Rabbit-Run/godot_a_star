class_name BattleSetupCreationResult
extends RefCounted


var setup: BattleSetup
var error_message: String


var is_successful: bool:
    get:
        return setup != null


func _init(
    p_setup: BattleSetup,
    p_error_message: String
) -> void:
    setup = p_setup
    error_message = p_error_message


static func success(p_setup: BattleSetup) -> BattleSetupCreationResult:
    return BattleSetupCreationResult.new(p_setup, "")


static func failure(message: String) -> BattleSetupCreationResult:
    return BattleSetupCreationResult.new(null, message)
