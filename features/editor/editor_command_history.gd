class_name EditorCommandHistory
extends RefCounted


signal changed

var _undo_stack: Array[EditCommand] = []
var _redo_stack: Array[EditCommand] = []


func execute(command: EditCommand, document: EditorDocument) -> bool:
	if command == null or not command.apply(document):
		return false

	_undo_stack.append(command)
	_redo_stack.clear()
	changed.emit()
	return true


func undo(document: EditorDocument) -> bool:
	if _undo_stack.is_empty():
		return false

	var command: EditCommand = _undo_stack.pop_back()

	if not command.revert(document):
		_undo_stack.append(command)
		return false

	_redo_stack.append(command)
	changed.emit()
	return true


func redo(document: EditorDocument) -> bool:
	if _redo_stack.is_empty():
		return false

	var command: EditCommand = _redo_stack.pop_back()

	if not command.apply(document):
		_redo_stack.append(command)
		return false

	_undo_stack.append(command)
	changed.emit()
	return true