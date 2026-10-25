class_name EditorUi
extends RefCounted
## Shared look and small widget factories of development tools. No content rules or file IO.

enum Severity { INFO, OK, WARN, ERROR }

const BACKGROUND := Color("0e1216")
const PANEL := Color("151b21")
const CARD := Color("1a2229")
const FIELD := Color("0f1519")
const BORDER := Color("2a3640")
const BUTTON := Color("232e37")
const BUTTON_HOVER := Color("2c3a45")
const TEXT := Color("e3e7ea")
const MUTED := Color("8e9ba6")
const ACCENT := Color("e2b04a")
const INFO := Color("5fc4d8")
const OK := Color("72c48f")
const WARN := Color("e6b450")
const ERROR := Color("ee6d61")

const UNSAVED_TITLE := "Несохранённые изменения"
const DISCARD := "Отбросить"
const KEEP_EDITING := "Продолжить редактирование"

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func severity_color(severity: Severity) -> Color:
	return [INFO, OK, WARN, ERROR][severity]


## Applies the editor skin to a tool root. Child windows (popups, dialogs) inherit it.
static func apply(root: Control) -> void:
	root.theme = theme()


static func background(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"EditorBackground"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	return root


## Header strip of a tool window: returns the horizontal content row.
static func bar(parent: Node, variation: StringName = &"EditorHeader") -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	return row


## A titled card; returns the content column. Its panel is `body.get_parent()`.
static func card(parent: Node, title := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"EditorCard"
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	if not title.is_empty():
		body.add_child(label(title, &"SectionLabel"))
	return body


static func set_card_visible(body: Control, visible: bool) -> void:
	(body.get_parent() as Control).visible = visible


static func form(parent: Node, columns := 2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


## Adds a caption and its control to a form; both share the tooltip.
static func row(grid: GridContainer, title: String, control: Control, tooltip := "") -> Label:
	var caption := label(title, &"FieldLabel")
	caption.tooltip_text = tooltip
	caption.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not tooltip.is_empty() and control.tooltip_text.is_empty():
		control.tooltip_text = tooltip
	grid.add_child(control)
	return caption


static func label(text: String, variation: StringName = &"", wrap := false) -> Label:
	var result := Label.new()
	result.text = text
	result.theme_type_variation = variation
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


static func hint(text: String) -> Label:
	return label(text, &"MutedLabel", true)


## The action may be left empty when the owner of the panel connects the button later.
static func button(text: String, action := Callable(), tooltip := "", variation: StringName = &"") -> Button:
	var result := Button.new()
	result.text = text
	result.tooltip_text = tooltip
	result.theme_type_variation = variation
	if action.is_valid():
		result.pressed.connect(action)
	return result


static func spin(minimum: float, maximum: float, step := 1.0, suffix := "") -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.suffix = suffix
	result.select_all_on_focus = true
	result.custom_minimum_size.x = 110
	return result


static func spacer() -> Control:
	var result := Control.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func separator() -> VSeparator:
	return VSeparator.new()


## Ctrl maps to Cmd on macOS.
static func shortcut(keycode: Key, ctrl := false, shift := false) -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.command_or_control_autoremap = ctrl
	event.shift_pressed = shift
	var result := Shortcut.new()
	result.events = [event]
	return result


static func add_shortcut(target: BaseButton, keycode: Key, ctrl := false, shift := false) -> void:
	if target.shortcut == null:
		target.shortcut = Shortcut.new()
	var events := target.shortcut.events.duplicate()
	events.append_array(shortcut(keycode, ctrl, shift).events)
	target.shortcut.events = events
	target.shortcut_in_tooltip = true


static func set_status(target: Label, text: String, severity := Severity.INFO) -> void:
	target.text = text
	target.add_theme_color_override("font_color", severity_color(severity) if severity != Severity.INFO else TEXT)


## Header marker of the document state: unsaved edits, a new file or a clean copy.
static func set_dirty(target: Label, dirty: bool, stored := true) -> void:
	if dirty:
		set_status(target, "● Не сохранено", Severity.WARN)
	elif not stored:
		set_status(target, "○ Новый, ещё не в библиотеке", Severity.WARN)
	else:
		target.text = "Сохранено"
		target.add_theme_color_override("font_color", MUTED)


static func confirm_discard(parent: Node, text: String, action: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = UNSAVED_TITLE
	dialog.dialog_text = text
	dialog.ok_button_text = DISCARD
	dialog.cancel_button_text = KEEP_EDITING
	dialog.confirmed.connect(action)
	parent.add_child(dialog)
	return dialog


static func _box(color: Color, border := Color.TRANSPARENT, radius := 4, margin := Vector4(10, 6, 10, 6), border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin.x
	style.content_margin_top = margin.y
	style.content_margin_right = margin.z
	style.content_margin_bottom = margin.w
	style.anti_aliasing = radius > 0
	return style


static func _empty(margin := 4.0) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(margin)
	return style


static func _button_styles(theme: Theme, type: StringName, normal: Color, hover: Color, pressed: Color, pressed_border: Color, text: Color, pressed_text: Color) -> void:
	theme.set_stylebox("normal", type, _box(normal, BORDER))
	theme.set_stylebox("hover", type, _box(hover, BORDER.lightened(0.15)))
	theme.set_stylebox("pressed", type, _box(pressed, pressed_border))
	theme.set_stylebox("hover_pressed", type, _box(pressed.lightened(0.08), pressed_border))
	theme.set_stylebox("disabled", type, _box(normal.darkened(0.25), BORDER.darkened(0.3)))
	theme.set_stylebox("focus", type, _box(Color.TRANSPARENT, ACCENT.darkened(0.2)))
	theme.set_color("font_color", type, text)
	theme.set_color("font_hover_color", type, text.lightened(0.15))
	theme.set_color("font_focus_color", type, text)
	theme.set_color("font_pressed_color", type, pressed_text)
	theme.set_color("font_hover_pressed_color", type, pressed_text)
	theme.set_color("font_disabled_color", type, MUTED.darkened(0.3))
	theme.set_color("icon_normal_color", type, Color.WHITE)


## The default check icons are dark squares that vanish on the editor background.
static func _check_icon(checked: bool, enabled: bool) -> ImageTexture:
	var size := 18
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var alpha := 1.0 if enabled else 0.45
	var border := Color(ACCENT if checked else MUTED, alpha)
	for y in range(size):
		for x in range(size):
			var corner := (x == 0 or x == size - 1) and (y == 0 or y == size - 1)
			if corner:
				continue
			if x < 2 or y < 2 or x >= size - 2 or y >= size - 2:
				image.set_pixel(x, y, border)
			elif checked:
				image.set_pixel(x, y, Color(ACCENT, alpha))
	if checked:
		var mark := Color(Color("1c1507"), alpha)
		var points: Array[Vector2] = [Vector2(4.5, 9.0), Vector2(7.5, 12.0), Vector2(13.5, 5.5)]
		for segment in range(points.size() - 1):
			for step in range(24):
				var point := points[segment].lerp(points[segment + 1], step / 23.0)
				for offset: Vector2i in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 0)]:
					var pixel := Vector2i(point.round()) + offset
					image.set_pixel(clampi(pixel.x, 0, size - 1), clampi(pixel.y, 0, size - 1), mark)
	return ImageTexture.create_from_image(image)


static func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", TEXT)
	var selection := Color(ACCENT, 0.32)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, Color.TRANSPARENT, 0, Vector4.ZERO))
	theme.set_type_variation(&"EditorBackground", &"PanelContainer")
	theme.set_stylebox("panel", "EditorBackground", _box(BACKGROUND, Color.TRANSPARENT, 0, Vector4.ZERO))
	theme.set_type_variation(&"EditorHeader", &"PanelContainer")
	var header := _box(PANEL, Color.TRANSPARENT, 0, Vector4(16, 8, 16, 8))
	header.border_color = BORDER
	header.border_width_bottom = 1
	theme.set_stylebox("panel", "EditorHeader", header)
	theme.set_type_variation(&"EditorStatusBar", &"PanelContainer")
	var footer := _box(PANEL, Color.TRANSPARENT, 0, Vector4(16, 5, 16, 5))
	footer.border_color = BORDER
	footer.border_width_top = 1
	theme.set_stylebox("panel", "EditorStatusBar", footer)
	theme.set_type_variation(&"EditorCard", &"PanelContainer")
	theme.set_stylebox("panel", "EditorCard", _box(CARD, BORDER, 6, Vector4(14, 12, 14, 14)))
	theme.set_type_variation(&"EditorOverlay", &"PanelContainer")
	theme.set_stylebox("panel", "EditorOverlay", _box(Color(PANEL, 0.86), BORDER, 6, Vector4(6, 6, 6, 6)))

	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font_size("font_size", "TitleLabel", 20)
	theme.set_color("font_color", "TitleLabel", TEXT)
	theme.set_type_variation(&"SectionLabel", &"Label")
	theme.set_font_size("font_size", "SectionLabel", 13)
	theme.set_color("font_color", "SectionLabel", ACCENT)
	theme.set_type_variation(&"FieldLabel", &"Label")
	theme.set_color("font_color", "FieldLabel", Color(TEXT, 0.82))
	theme.set_type_variation(&"MutedLabel", &"Label")
	theme.set_font_size("font_size", "MutedLabel", 13)
	theme.set_color("font_color", "MutedLabel", MUTED)

	_button_styles(theme, &"Button", BUTTON, BUTTON_HOVER, Color("3a3322"), ACCENT, TEXT, ACCENT)
	theme.set_constant("icon_max_width", "Button", 40)
	theme.set_constant("h_separation", "Button", 6)
	theme.set_type_variation(&"PrimaryButton", &"Button")
	_button_styles(theme, &"PrimaryButton", ACCENT.darkened(0.12), ACCENT, ACCENT.darkened(0.3), ACCENT.lightened(0.2), Color("1c1507"), Color("1c1507"))
	theme.set_color("font_disabled_color", "PrimaryButton", Color("1c1507", 0.6))
	theme.set_type_variation(&"ToolButton", &"Button")
	_button_styles(theme, &"ToolButton", Color(BUTTON, 0.0), BUTTON_HOVER, Color(ACCENT, 0.2), ACCENT, TEXT, ACCENT)
	theme.set_stylebox("normal", "ToolButton", _box(Color(BUTTON, 0.55), Color(BORDER, 0.6)))

	for type: StringName in [&"CheckBox", &"CheckButton"]:
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
			theme.set_stylebox(state, type, _empty())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, TEXT.lightened(0.15))
		theme.set_color("font_pressed_color", type, TEXT)
		theme.set_color("font_hover_pressed_color", type, TEXT)
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_disabled_color", type, MUTED.darkened(0.3))
	theme.set_icon("checked", "CheckBox", _check_icon(true, true))
	theme.set_icon("unchecked", "CheckBox", _check_icon(false, true))
	theme.set_icon("checked_disabled", "CheckBox", _check_icon(true, false))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, false))

	for type: StringName in [&"LineEdit", &"TextEdit"]:
		theme.set_stylebox("normal", type, _box(FIELD, BORDER, 4, Vector4(8, 5, 8, 5)))
		theme.set_stylebox("focus", type, _box(Color.TRANSPARENT, ACCENT, 4))
		theme.set_stylebox("read_only", type, _box(FIELD.darkened(0.2), BORDER.darkened(0.3), 4, Vector4(8, 5, 8, 5)))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_placeholder_color", type, Color(MUTED, 0.75))
		theme.set_color("font_readonly_color", type, MUTED)
		theme.set_color("caret_color", type, ACCENT)
		theme.set_color("selection_color", type, selection)

	theme.set_stylebox("panel", "ItemList", _box(FIELD, BORDER, 4, Vector4(4, 4, 4, 4)))
	theme.set_stylebox("focus", "ItemList", _box(Color.TRANSPARENT, Color(ACCENT, 0.5), 4))
	theme.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 3))
	theme.set_stylebox("selected", "ItemList", _box(Color(ACCENT, 0.2), Color.TRANSPARENT, 3))
	theme.set_stylebox("selected_focus", "ItemList", _box(Color(ACCENT, 0.26), Color(ACCENT, 0.6), 3))
	theme.set_stylebox("hovered_selected", "ItemList", _box(Color(ACCENT, 0.28), Color.TRANSPARENT, 3))
	theme.set_stylebox("hovered_selected_focus", "ItemList", _box(Color(ACCENT, 0.3), Color(ACCENT, 0.6), 3))
	theme.set_stylebox("cursor", "ItemList", _empty(0))
	theme.set_stylebox("cursor_unfocused", "ItemList", _empty(0))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_hovered_selected_color", "ItemList", Color.WHITE)
	theme.set_color("guide_color", "ItemList", Color(BORDER, 0.5))
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_constant("h_separation", "ItemList", 8)

	var popup := _box(PANEL, BORDER, 4, Vector4(4, 4, 4, 4))
	popup.shadow_color = Color(0, 0, 0, 0.45)
	popup.shadow_size = 8
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.22), Color.TRANSPARENT, 3))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED.darkened(0.25))
	theme.set_color("font_accelerator_color", "PopupMenu", MUTED)
	theme.set_color("font_separator_color", "PopupMenu", MUTED)
	theme.set_constant("icon_max_width", "PopupMenu", 48)
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_stylebox("panel", "TooltipPanel", _box(PANEL, BORDER, 4, Vector4(10, 6, 10, 6)))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 14)
	theme.set_stylebox("panel", "AcceptDialog", _box(PANEL, Color.TRANSPARENT, 0, Vector4(12, 12, 12, 12)))

	theme.set_stylebox("panel", "TabContainer", _box(PANEL, Color.TRANSPARENT, 0, Vector4(0, 0, 0, 0)))
	theme.set_stylebox("tabbar_background", "TabContainer", _empty(0))
	for type: StringName in [&"TabContainer", &"TabBar"]:
		var selected := _box(CARD, Color.TRANSPARENT, 0, Vector4(14, 7, 14, 7))
		selected.border_color = ACCENT
		selected.border_width_top = 2
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_unselected", type, _box(Color(PANEL, 0.0), Color.TRANSPARENT, 0, Vector4(14, 7, 14, 7)))
		theme.set_stylebox("tab_hovered", type, _box(BUTTON_HOVER, Color.TRANSPARENT, 0, Vector4(14, 7, 14, 7)))
		theme.set_stylebox("tab_focus", type, _empty(0))
		theme.set_color("font_selected_color", type, ACCENT)
		theme.set_color("font_unselected_color", type, MUTED)
		theme.set_color("font_hovered_color", type, TEXT)

	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vertical := line.duplicate() as StyleBoxLine
	vertical.vertical = true
	theme.set_stylebox("separator", "VSeparator", vertical)
	theme.set_constant("separation", "VSeparator", 12)
	theme.set_stylebox("panel", "ScrollContainer", _empty(0))
	theme.set_stylebox("title_panel", "FoldableContainer", _box(BUTTON, BORDER, 4, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("title_hover_panel", "FoldableContainer", _box(BUTTON_HOVER, BORDER, 4, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("title_collapsed_panel", "FoldableContainer", _box(BUTTON, BORDER, 4, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("title_collapsed_hover_panel", "FoldableContainer", _box(BUTTON_HOVER, BORDER, 4, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("panel", "FoldableContainer", _box(FIELD, BORDER, 4, Vector4(10, 8, 10, 8)))
	theme.set_color("font_color", "FoldableContainer", TEXT)
	return theme
