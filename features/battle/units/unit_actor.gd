class_name UnitActor
extends Node2D


const CUSTOM_TEXTURE_SIZE := 82.0
const SKULL_ICON := preload("res://features/battle/ui/icons/skull.svg")
## Brightness of the figure of a unit that can no longer act in the current phase.
const SPENT_TURN_TINT := Color(0.68, 0.68, 0.68)


@export_range(0.01, 1.0, 0.01)
var movement_step_duration := 0.28

var unit_id: StringName
var _faction_color := Color(0.51, 0.66, 0.75)
var _show_base := true
var _movement_profile: UnitMovementProfile
var _movement_animator: UnitMovementAnimator
var _presentation: UnitPresentationDefinition
var _corpse: Sprite2D
var _defeat_tween: Tween
var _defeated := false
## The figure is still falling onto its hex: health and base appear once it lands.
var _arriving := false
var _health_display_expanded := true
var _status_row: GridContainer
var _shown_statuses: Dictionary = {}
## Health a previewed command would leave, or -1 without a preview.
var _preview_health := -1
var _preview_defeated := false
var _preview_nodes: Array[CanvasItem] = []
## The figure's own tint; dimming for a spent turn multiplies it.
var _sprite_tint := Color.WHITE
var _turn_spent := false

@onready var _sprite: Sprite2D = %Sprite
@onready var _unit_id_label: Label = %UnitIdLabel
@onready var _combat_role_label: Label = %CombatRoleLabel
@onready var _health_label: Label = %HealthLabel
@onready var _health_bar: ProgressBar = %HealthBar


func _draw() -> void:
	if not _show_base:
		return

	var base_points := PackedVector2Array()
	for i in range(49):
		var angle := TAU * float(i) / 48.0
		base_points.append(Vector2(cos(angle) * 29.0, sin(angle) * 11.0))
	draw_colored_polygon(base_points, Color(0.07, 0.035, 0.018, 0.42))
	draw_polyline(base_points, _faction_color, 1.5, true)

func setup(
	p_unit_id: StringName,
	definition: UnitDefinition,
	presentation: UnitPresentationDefinition,
	faction: BattleFaction.Value,
	current_health: int,
	maximum_health: int
) -> void:
	unit_id = p_unit_id
	_presentation = presentation
	_movement_profile = presentation.movement_profile if presentation != null else null
	if _movement_profile == null:
		_movement_profile = UnitMovementProfile.new()
		_movement_profile.seconds_per_hex = movement_step_duration
	_faction_color = (
		Color(0.52, 0.69, 0.82)
		if faction == BattleFaction.Value.PLAYER
		else Color(0.77, 0.29, 0.22)
	)
	_show_base = true
	queue_redraw()
	_unit_id_label.text = definition.display_name
	_unit_id_label.visible = false

	_sprite_tint = _sprite.self_modulate
	if presentation != null and presentation.actor_texture != null:
		_sprite.texture = presentation.actor_texture
		_sprite.material = null
		_sprite_tint = BattleVisualPalette.MINIATURE_TINT
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var texture_size := presentation.actor_texture.get_size()
		var longest_side := maxf(texture_size.x, texture_size.y)

		if longest_side > 0.0:
			_sprite.scale = Vector2.ONE * (
				presentation.texture_scale()
			)
			# The actor origin is the hex center; align the painted feet to it.
			_sprite.offset = (
				Vector2.ONE * 0.5 - presentation.actor_foot_anchor
			) * texture_size

	_combat_role_label.visible = false
	_combat_role_label.text = "◎"
	show_health(current_health, maximum_health)
	set_turn_spent(_turn_spent)
	modulate = (
		presentation.actor_color if presentation != null else Color.WHITE
	)


## Dims only the figure: health, statuses and the base stay readable. Hit and death animations
## tint the sprite's modulate, the dimming its self_modulate, so neither undoes the other.
func set_turn_spent(spent: bool) -> void:
	_turn_spent = spent
	_sprite.self_modulate = _sprite_tint * (SPENT_TURN_TINT if spent else Color.WHITE)


func is_turn_spent() -> bool:
	return _turn_spent


func show_health(current: int, maximum: int) -> void:
	_health_label.text = "%d/%d" % [maxi(current, 0), maximum]
	_health_bar.max_value = maxi(maximum, 1)
	_health_bar.value = clampi(current, 0, maxi(maximum, 1))
	_apply_health_display()
	var ratio := 0.0 if maximum <= 0 else float(current) / float(maximum)
	var bar_color := Color(0.37, 0.57, 0.25)

	if ratio <= 0.33:
		bar_color = Color(0.65, 0.22, 0.17)
	elif ratio <= 0.66:
		bar_color = Color(0.58, 0.43, 0.18)

	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", style)


func set_health_display_expanded(expanded: bool) -> void:
	_health_display_expanded = expanded
	_apply_health_display()


## Marks the part of the health bar a previewed command would remove, with "−N" beside it
## and a skull when the unit would die. Presentation only.
func show_health_preview(health_after: int, defeated: bool) -> void:
	_preview_health = maxi(health_after, 0)
	_preview_defeated = defeated
	_draw_health_preview()


func clear_health_preview() -> void:
	_preview_health = -1
	_draw_health_preview()


func _draw_health_preview() -> void:
	for node: CanvasItem in _preview_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_preview_nodes.clear()
	var current := int(_health_bar.value)
	if _preview_health < 0 or _defeated or _preview_health >= current or not _health_bar.visible:
		return
	var maximum := maxf(_health_bar.max_value, 1.0)
	var width := _health_bar.size.x
	var loss := ColorRect.new()
	loss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loss.color = Color(1.0, 0.9, 0.5, 0.9)
	loss.position = Vector2(width * _preview_health / maximum, 0)
	loss.size = Vector2(width * (current - _preview_health) / maximum, _health_bar.size.y)
	_health_bar.add_child(loss)
	_preview_nodes.append(loss)
	var label := Label.new()
	label.text = "−%d" % (current - _preview_health)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34))
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.05))
	label.add_theme_constant_override("outline_size", 5)
	label.z_as_relative = false
	label.z_index = 101
	label.position = _health_bar.position + Vector2(width + 4, -9)
	add_child(label)
	_preview_nodes.append(label)
	if _preview_defeated:
		var skull := Sprite2D.new()
		skull.texture = SKULL_ICON
		skull.scale = Vector2.ONE * 0.9
		skull.z_as_relative = false
		skull.z_index = 101
		skull.position = _health_bar.position + Vector2(-14, _health_bar.size.y * 0.5)
		add_child(skull)
		_preview_nodes.append(skull)


func _apply_health_display() -> void:
	_health_bar.visible = not _defeated and not _arriving and _health_bar.value > 0
	_health_label.visible = _health_display_expanded and not _defeated and not _arriving
	# Only the expanded badge needs enough width for its numbers.
	var badge_width := maxf(52.0, _health_label.get_minimum_size().x + 10.0) if _health_display_expanded else 40.0
	_health_bar.position = Vector2(-badge_width * 0.5, 13.0)
	_health_bar.size = Vector2(badge_width, 17.0 if _health_display_expanded else 4.0)
	if _status_row != null:
		_status_row.position.y = 32.0 if _health_display_expanded else 19.0
	# The badge size follows Alt; a shown preview follows the badge.
	if _preview_health >= 0:
		_draw_health_preview()


func show_statuses(statuses: Dictionary) -> void:
	if _status_row != null and _shown_statuses == statuses:
		return
	_shown_statuses = statuses.duplicate()
	if _status_row == null:
		_status_row = GridContainer.new()
		_status_row.name = "StatusIcons"
		_status_row.columns = 4
		_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_row.z_index = 101
		_status_row.z_as_relative = false
		_status_row.add_theme_constant_override("h_separation", 2)
		_status_row.add_theme_constant_override("v_separation", 2)
		add_child(_status_row)
	for child: Node in _status_row.get_children():
		_status_row.remove_child(child)
		child.queue_free()
	var ids := statuses.keys()
	ids.sort()
	for id: StringName in ids:
		var icon := UnitStatusIcon.new()
		icon.name = String(id).replace(":", "_")
		icon.texture = load("res://features/battle/ui/icons/status/%s.svg" % String(id).trim_prefix("core:"))
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.tooltip_text = "%s · уровней: %d\nКатегория: %s\n\n%s" % [UnitStatusCatalog.display_name(id), int(statuses[id]), UnitStatusCatalog.category_name(id), UnitStatusCatalog.description(id)]
		_status_row.add_child(icon)
		var count := Label.new()
		count.text = str(statuses[id])
		count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_theme_font_size_override("font_size", 10)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 3)
		icon.add_child(count)
	_status_row.position = Vector2(-float(mini(ids.size(), 4) * 20 - 2) * 0.5, 32.0 if _health_display_expanded else 19.0)
	_status_row.size = Vector2.ZERO
	_status_row.visible = not _defeated and not statuses.is_empty()

func create_defeat_tween(direction: float = 1.0) -> Tween:
	if _defeated:
		return _defeat_tween if _defeat_tween != null and _defeat_tween.is_running() else null
	_defeated = true
	if _status_row != null:
		_status_row.hide()
	_show_base = false
	queue_redraw()
	_combat_role_label.visible = false
	_health_bar.visible = false
	_health_label.visible = false
	_unit_id_label.visible = false
	_create_corpse()
	_defeat_tween = UnitDeathAnimator.create(self, _sprite, _corpse, direction)
	return _defeat_tween


## Final state restore without creating a tween that nobody will await.
func synchronize_defeat() -> void:
	if not _defeated:
		_defeated = true
		_show_base = false
		_create_corpse()
		_combat_role_label.hide()
		_health_bar.hide()
		_health_label.hide()
		_unit_id_label.hide()
		if _status_row != null:
			_status_row.hide()
	if _defeat_tween != null and _defeat_tween.is_running():
		_defeat_tween.kill()
	for child: Node in get_children():
		if child is UnitDeathAnimator:
			child.queue_free()
	finish_defeat()
	queue_redraw()


func _create_corpse() -> void:
	_corpse = Sprite2D.new()
	_corpse.name = "Corpse"
	_corpse.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var width := _presentation.corpse_width if _presentation != null else 76.0
	if _presentation != null and _presentation.corpse_texture != null:
		_corpse.texture = _presentation.corpse_texture
		var bounds := _presentation.corpse_visible_rect()
		_corpse.scale = Vector2.ONE * width / maxf(bounds.size.x, 1.0)
		_corpse.offset = _corpse.texture.get_size() * 0.5 - bounds.get_center()
	else:
		# Optional presentation fallback for custom units without a painted corpse.
		_corpse.texture = _sprite.texture
		if _corpse.texture != null:
			_corpse.rotation = -PI * 0.5
			var bounds := _presentation.visible_rect() if _presentation != null else Rect2(Vector2.ZERO, _corpse.texture.get_size())
			_corpse.scale = Vector2(0.52, 1.0) * width / maxf(bounds.size.y, 1.0)
			_corpse.offset = _corpse.texture.get_size() * 0.5 - bounds.get_center()
	var material := ShaderMaterial.new()
	material.shader = preload("res://features/battle/art/corpse.gdshader")
	_corpse.material = material
	_corpse.position = Vector2(0, -3)
	_corpse.modulate.a = 0.0
	add_child(_corpse)


func finish_defeat() -> void:
	_sprite.hide()
	_corpse.modulate.a = 1.0
	# Below living units (20) and tactical overlays (8+), above terrain effects (5).
	z_index = 6


## The figure falls from the sky onto its hex; health and base appear once it has landed.
func create_arrival_tween() -> Tween:
	_arriving = true
	_show_base = false
	queue_redraw()
	_apply_health_display()
	if _status_row != null:
		_status_row.hide()
	var height := _presentation.height_above_feet() if _presentation != null else CUSTOM_TEXTURE_SIZE
	return UnitArrivalAnimator.create(self, _sprite, height)


## Also the reset after a cut arrival: the figure stands on its hex at rest.
func finish_arrival() -> void:
	_arriving = false
	for child: Node in get_children():
		if child is UnitArrivalAnimator:
			child.restore()
			child.queue_free()
	if _defeated:
		return
	_show_base = true
	queue_redraw()
	_apply_health_display()
	if _status_row != null:
		_status_row.visible = not _shown_statuses.is_empty()


## The body leaves the battlefield with its hex: it fades out and stays hidden.
func create_removal_tween() -> Tween:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(hide)
	return tween


func create_movement_tween(positions: Array[Vector2]) -> Tween:
	_movement_animator = UnitMovementAnimator.new()
	return _movement_animator.create_motion(self, _sprite, positions, _movement_profile)


## A push: a quick slide without gait through the given global positions, then, when
## `blocker` is a global position, a short knock toward it and back. Null without motion.
func create_push_tween(positions: Array[Vector2], blocker: Variant = null) -> Tween:
	const SECONDS_PER_HEX := 0.12
	const KNOCK_SHARE := 0.22
	var parent := get_parent() as Node2D
	if parent == null or (positions.is_empty() and not blocker is Vector2):
		return null
	var tween := create_tween()
	for index in range(positions.size()):
		var step := tween.tween_property(self, "position", parent.to_local(positions[index]), SECONDS_PER_HEX)
		if index == positions.size() - 1 and not blocker is Vector2:
			step.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if blocker is Vector2:
		var rest := parent.to_local(positions.back() if not positions.is_empty() else global_position)
		tween.tween_property(self, "position", rest.lerp(parent.to_local(blocker), KNOCK_SHARE), 0.06)
		tween.tween_property(self, "position", rest, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


func get_combat_sprite() -> Sprite2D:
	return _sprite


func get_combat_anchor(height_ratio: float = 0.52) -> Vector2:
	var height := _presentation.height_above_feet() if _presentation != null else CUSTOM_TEXTURE_SIZE
	return to_global(Vector2(0, -height * height_ratio))
