class_name UILayoutDocument
extends RefCounted
## Presentation-only document; nodes are a projection, never the saved state.

var title := "Новый UI"
var elements: Dictionary = {}


func copy() -> UILayoutDocument:
	var result := UILayoutDocument.new()
	result.title = title
	result.elements = elements.duplicate(true)
	return result


func to_data() -> Dictionary:
	return {"schema": 1, "title": title, "elements": elements.duplicate(true)}

