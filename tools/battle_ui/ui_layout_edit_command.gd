class_name UILayoutEditCommand
extends RefCounted
## One reversible property edit or complete mouse gesture.

var element_id: String
var before: Dictionary
var after: Dictionary


func apply(document: UILayoutDocument) -> void:
	_set_properties(document, after)


func revert(document: UILayoutDocument) -> void:
	_set_properties(document, before)


func _set_properties(document: UILayoutDocument, value: Dictionary) -> void:
	if value.is_empty():
		document.elements.erase(element_id)
	else:
		document.elements[element_id] = value.duplicate(true)

