class_name BattleSessionCreationResult
extends RefCounted


var session: BattleSession
var error_message: String

var is_successful: bool:
	get:
		return session != null


func _init(
	p_session: BattleSession,
	p_error_message: String
) -> void:
	session = p_session
	error_message = p_error_message


static func success(p_session: BattleSession) -> BattleSessionCreationResult:
	return BattleSessionCreationResult.new(p_session, "")


static func failure(message: String) -> BattleSessionCreationResult:
	return BattleSessionCreationResult.new(null, message)
