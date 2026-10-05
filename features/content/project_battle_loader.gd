class_name ProjectBattleLoader
extends RefCounted
## Loads a saved battle and its project unit library into the ordinary battle pipeline.

class LoadResult extends RefCounted:
	var request: BattleStartRequest
	var error_message := ""


static func load_battle(
	packages: Array[ContentPackage], path: String, seed: int, include_presentation := true
) -> LoadResult:
	var result := LoadResult.new()
	var content := UnitLibrary.load_content(packages, include_presentation)
	if not content.is_successful:
		result.error_message = "\n".join(content.errors)
		return result
	var loaded := BattleDocumentSerializer.load_result(path)
	if loaded.document == null:
		result.error_message = loaded.error_message
		return result
	var validation := loaded.document.validate(content.snapshot)
	if not validation.is_valid:
		result.error_message = "\n".join(validation.errors)
		return result
	result.request = loaded.document.create_start_request(content.snapshot, seed)
	return result
