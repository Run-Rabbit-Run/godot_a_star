class_name ActionPreviewPanel
extends CanvasLayer
## Short summary of a previewed command next to the cursor. It sits above and left of the
## cursor, so the hex popup below and right of it stays readable. Presentation only.

const WARNING_COLOR := Color(1.0, 0.45, 0.38)

var _panel: PanelContainer
var _body: Label


func _ready() -> void:
	layer = 41
	_panel = PanelContainer.new()
	_panel.name = "ActionPreviewPopup"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", BattleVisualTheme.panel(Color.WHITE, 10.0))
	_body = Label.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("font_size", 15)
	_panel.add_child(_body)
	add_child(_panel)
	_panel.hide()
	set_process(false)


func show_lines(lines: PackedStringArray, warning: bool) -> void:
	if _panel == null:
		return
	if lines.is_empty():
		hide_panel()
		return
	_body.text = "\n".join(lines)
	_body.add_theme_color_override("font_color", WARNING_COLOR if warning else BattleVisualTheme.IVORY)
	_panel.reset_size()
	_panel.show()
	_follow_cursor()
	set_process(true)


func hide_panel() -> void:
	if _panel == null:
		return
	_panel.hide()
	set_process(false)


func get_text() -> String:
	return _body.text if _panel != null and _panel.visible else ""


func _process(_delta: float) -> void:
	_follow_cursor()


func _follow_cursor() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cursor := get_viewport().get_mouse_position()
	_panel.position = (cursor - _panel.size - Vector2(18, 18)).clamp(Vector2(8, 8), viewport_size - _panel.size - Vector2(8, 8))
