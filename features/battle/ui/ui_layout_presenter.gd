class_name UILayoutPresenter
extends Node
## Applies presentation overrides to existing controls without replacing HUD bindings.

var root: Control
var document: UILayoutDocument
var controls: Dictionary = {}
var diagnostics: PackedStringArray = []
var _last_text: Dictionary = {}
var _source_text: Dictionary = {}
var _backgrounds: Dictionary = {}
var _textures: Dictionary = {}
var _label_styles: Dictionary = {}


func setup(p_root: Control, p_document: UILayoutDocument) -> void:
	root = p_root
	document = p_document
	_collect(root)
	for id: String in document.elements:
		if not controls.has(id):
			diagnostics.append("Элемент отсутствует: %s" % id)
			continue
		apply_element(id)
	refresh()


func _collect(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control and child.name != "EdgeShading":
			controls[String(root.get_path_to(child))] = child
		_collect(child)


func apply_element(id: String) -> void:
	var node := controls.get(id) as Control
	if node == null:
		return
	var entry: Dictionary = document.elements.get(id, {})
	for key: String in [id, id + "#asset"]:
		if _backgrounds.has(key):
			_backgrounds[key].queue_free()
			_backgrounds.erase(key)
	if entry.has("font_size"):
		node.add_theme_font_size_override("font_size", int(entry.font_size))
	if entry.has("font_color"):
		for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			node.add_theme_color_override(key, Color(entry.font_color))
	if entry.has("tint"):
		node.self_modulate = Color(entry.tint)
	if entry.has("background") or entry.has("border_color") or entry.has("border_width"):
		var original := node.get_theme_stylebox("panel" if node is PanelContainer or node is Panel else "normal") as StyleBoxFlat
		var style := original.duplicate() as StyleBoxFlat if original != null else StyleBoxFlat.new()
		if entry.has("background"):
			style.bg_color = Color(entry.background)
		if entry.has("border_color"):
			style.border_color = Color(entry.border_color)
		if entry.has("border_width"):
			style.set_border_width_all(int(entry.border_width))
		if node is Button:
			for key: String in ["normal", "hover", "pressed", "disabled"]:
				node.add_theme_stylebox_override(key, style)
		elif node is PanelContainer or node is Panel:
			node.add_theme_stylebox_override("panel", style)
		elif node is Label:
			node.add_theme_stylebox_override("normal", style)
			_label_styles[id] = style
		else:
			var panel := Panel.new()
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.show_behind_parent = true
			panel.top_level = true
			panel.add_theme_stylebox_override("panel", style)
			node.add_child(panel)
			_backgrounds[id] = panel
	if entry.has("asset"):
		var texture := UILayoutStore.texture(entry.asset)
		if texture == null and not String(entry.asset).is_empty():
			diagnostics.append("Изображение отсутствует: %s" % entry.asset)
		elif node is TextureRect:
			node.texture = texture
			_textures[id] = texture
		elif node is Button:
			node.icon = texture
			node.expand_icon = true
			_textures[id] = texture
		elif node is PanelContainer or node is Panel:
			if texture != null:
				var texture_style := StyleBoxTexture.new()
				texture_style.texture = texture
				node.add_theme_stylebox_override("panel", texture_style)
		else:
			var backdrop := TextureRect.new()
			backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			backdrop.texture = texture
			backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			backdrop.stretch_mode = TextureRect.STRETCH_SCALE
			# Behind text/children, also works for Container-backed panels.
			backdrop.show_behind_parent = true
			backdrop.top_level = true
			node.add_child(backdrop)
			_backgrounds[id + "#asset"] = backdrop
	if entry.has("text") and (node is Label or node is Button) and not _source_text.has(id):
		_source_text[id] = node.text
	if entry.has("rect"):
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.top_level = true
		if node is Label:
			node.clip_text = true


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if root == null or document == null:
		return
	# Parent-first order preserves group movement and scaling for detached children.
	for id: String in controls:
		var node: Control = controls[id]
		var entry: Dictionary = document.elements.get(id, {})
		if entry.has("rect"):
			var rect: Array = entry.rect
			var parent := node.get_parent() as Control
			node.global_position = parent.get_global_transform() * Vector2(rect[0], rect[1])
			node.scale = parent.get_global_transform().get_scale()
			node.custom_minimum_size = Vector2.ZERO
			node.size = Vector2(rect[2], rect[3])
		if entry.has("visibility") and entry.visibility != "inherit":
			node.visible = entry.visibility == "show"
		if entry.has("font_color"):
			node.modulate = Color.WHITE
		if _textures.has(id):
			if node is TextureRect:
				node.texture = _textures[id]
			elif node is Button:
				node.icon = _textures[id]
		if _label_styles.has(id) and node.get_theme_stylebox("normal") != _label_styles[id]:
			node.add_theme_stylebox_override("normal", _label_styles[id])
		if entry.has("text") and (node is Label or node is Button):
			if node.text != _last_text.get(id, node.text):
				_source_text[id] = node.text
			var rendered := String(entry.text).replace("{value}", str(_source_text.get(id, node.text)))
			node.text = rendered
			_last_text[id] = rendered
		for key: String in [id, id + "#asset"]:
			if _backgrounds.has(key):
				var backdrop: Control = _backgrounds[key]
				backdrop.global_position = node.global_position
				backdrop.scale = node.get_global_transform().get_scale()
				backdrop.size = node.size


func local_rect(id: String) -> Rect2:
	var node: Control = controls[id]
	var parent := node.get_parent() as Control
	return Rect2(parent.get_global_transform().affine_inverse() * node.global_position, node.size)


func canvas_rect(id: String) -> Rect2:
	var node: Control = controls[id]
	return Rect2(root.get_global_transform().affine_inverse() * node.global_position, node.size)
