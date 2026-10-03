class_name UILayoutCanvas
extends Control
## Fixed-resolution HUD preview and mouse manipulation, independent of saved state.

signal selected(id: String)
signal edited(id: String, properties: Dictionary)
signal rebuilt
signal gesture_cancelled

var selected_id := ""
var presenter: UILayoutPresenter
var show_target := false
var show_settings := false
var _viewport: SubViewport
var _hud: BattleHUD
var _document: UILayoutDocument
var _frame := Rect2()
var _dragging := false
var _edge := Vector2i.ZERO
var _start_mouse := Vector2.ZERO
var _start_rect := Rect2()
var _revision := 0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _background := BattleBackdrops.texture(&"plateau")


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(320, 240)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	resized.connect(queue_redraw)
	get_window().focus_exited.connect(_cancel_gesture)


func display(document: UILayoutDocument) -> void:
	_revision += 1
	var revision := _revision
	_document = document.copy()
	if _hud != null:
		_viewport.remove_child(_hud)
		_hud.queue_free()
	_hud = BattleHUD.new()
	_hud.ui_document_override = _document
	_viewport.add_child(_hud)
	presenter = _hud.layout_presenter
	_hud.show_round(3)
	_hud.show_objective("Победить противников")
	_hud.show_active_unit("Стрелок")
	_hud.show_health(74, 100)
	_hud.show_movement(4, 6)
	_hud.show_main_action(true)
	_hud.show_basic_attack_button(6, true)
	var ability := AbilityDefinition.new()
	ability.id = &"preview:grenade"
	ability.display_name = "Граната"
	_hud.show_abilities([ability], true)
	_hud.show_active_portrait(load("res://features/battle/art/plateau_units/0.png"))
	_hud.show_turn_order([
		{"unit_id": &"a", "texture": load("res://features/battle/art/plateau_units/0.png"), "short_name": "Стрелок"},
		{"unit_id": &"b", "texture": load("res://features/battle/art/plateau_units/1.png"), "short_name": "Страж"},
	], &"a")
	if show_target:
		_hud.show_target("Страж", load("res://features/battle/art/plateau_units/1.png"), "Противник", 60, 100, 12, 1, 3, 5, true)
	(_hud.get_node("HUDRoot/SpeedPanel") as Control).visible = show_settings
	await get_tree().process_frame
	if not is_inside_tree() or revision != _revision:
		return
	presenter.refresh()
	rebuilt.emit()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("171b22"))
	var ratio := minf(size.x / 1920.0, size.y / 1080.0) * _zoom
	_frame = Rect2((size - Vector2(1920, 1080) * ratio) / 2.0 + _pan, Vector2(1920, 1080) * ratio)
	draw_texture_rect(_background, _frame, false)
	if _viewport == null:
		return
	draw_texture_rect(_viewport.get_texture(), _frame, false)
	if presenter == null or not presenter.controls.has(selected_id):
		return
	var rect := _screen_rect(presenter.canvas_rect(selected_id))
	draw_rect(rect, Color("79dbff"), false, 2.0)
	for point: Vector2 in _handles(rect):
		draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), Color("79dbff"))


func _screen_rect(rect: Rect2) -> Rect2:
	var ratio := _frame.size.x / 1920.0
	return Rect2(_frame.position + rect.position * ratio, rect.size * ratio)


func _handles(rect: Rect2) -> Array[Vector2]:
	return [rect.position, Vector2(rect.get_center().x, rect.position.y), Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y),
		Vector2(rect.position.x, rect.end.y), Vector2(rect.get_center().x, rect.end.y), rect.end]


func _gui_input(event: InputEvent) -> void:
	if presenter == null or _frame.size.x <= 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		accept_event()
		return
	if event is InputEventMouseMotion and _panning:
		_pan += event.relative
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		elif _dragging:
			_dragging = false
			var properties: Dictionary = _document.elements.get(selected_id, {}).duplicate(true)
			edited.emit(selected_id, properties)
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag(event.position)
		else:
			_update_cursor(event.position)


func _begin_drag(point: Vector2) -> void:
	_edge = _edge_at(point)
	if _edge == Vector2i.ZERO:
		# Smallest visible block wins; groups remain directly selectable in the tree.
		var best_area := INF
		var hit := ""
		for id: String in presenter.controls:
			var node: Control = presenter.controls[id]
			var rect := _screen_rect(presenter.canvas_rect(id))
			if node.is_visible_in_tree() and rect.has_point(point) and rect.get_area() <= best_area:
				best_area = rect.get_area()
				hit = id
		# Drag the already selected group from anywhere inside it.
		if presenter.controls.has(selected_id) and _screen_rect(presenter.canvas_rect(selected_id)).has_point(point):
			hit = selected_id
		selected_id = hit
		selected.emit(hit)
	if selected_id.is_empty():
		return
	_start_mouse = point
	_start_rect = presenter.local_rect(selected_id)
	_dragging = true


func _drag(point: Vector2) -> void:
	var delta := (point - _start_mouse) / (_frame.size.x / 1920.0)
	var rect := _start_rect
	if _edge == Vector2i.ZERO:
		rect.position += delta
	else:
		if _edge.x < 0:
			rect.position.x += minf(delta.x, rect.size.x - 8)
			rect.size.x -= minf(delta.x, rect.size.x - 8)
		elif _edge.x > 0:
			rect.size.x = maxf(8, rect.size.x + delta.x)
		if _edge.y < 0:
			rect.position.y += minf(delta.y, rect.size.y - 8)
			rect.size.y -= minf(delta.y, rect.size.y - 8)
		elif _edge.y > 0:
			rect.size.y = maxf(8, rect.size.y + delta.y)
	var properties: Dictionary = _document.elements.get(selected_id, {}).duplicate(true)
	properties.rect = [roundf(rect.position.x), roundf(rect.position.y), roundf(rect.size.x), roundf(rect.size.y)]
	var first_rect: bool = not _document.elements.get(selected_id, {}).has("rect")
	_document.elements[selected_id] = properties
	if first_rect:
		presenter.apply_element(selected_id)
	presenter.refresh()


func _edge_at(point: Vector2) -> Vector2i:
	if not presenter.controls.has(selected_id):
		return Vector2i.ZERO
	var rect := _screen_rect(presenter.canvas_rect(selected_id))
	if not rect.grow(7).has_point(point):
		return Vector2i.ZERO
	var edge := Vector2i.ZERO
	if absf(point.x - rect.position.x) < 7:
		edge.x = -1
	elif absf(point.x - rect.end.x) < 7:
		edge.x = 1
	if absf(point.y - rect.position.y) < 7:
		edge.y = -1
	elif absf(point.y - rect.end.y) < 7:
		edge.y = 1
	return edge


func _update_cursor(point: Vector2) -> void:
	var edge := _edge_at(point)
	if edge.x != 0 and edge.y != 0:
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if edge.x == edge.y else Control.CURSOR_BDIAGSIZE
	elif edge.x != 0:
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif edge.y != 0:
		mouse_default_cursor_shape = Control.CURSOR_VSIZE
	else:
		mouse_default_cursor_shape = Control.CURSOR_MOVE


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _dragging:
		_cancel_gesture()
		get_viewport().set_input_as_handled()


func _cancel_gesture() -> void:
	_panning = false
	if _dragging:
		_dragging = false
		# Shell supplies the unchanged authoritative document.
		gesture_cancelled.emit()


func fit() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO


func actual_size() -> void:
	_zoom = 1.0 / minf(size.x / 1920.0, size.y / 1080.0)
	_pan = Vector2.ZERO
