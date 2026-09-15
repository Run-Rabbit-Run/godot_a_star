class_name BattleHUD
extends CanvasLayer


## HUD сообщает о намерении и не изменяет состояние боя напрямую.
signal end_turn_requested
signal movement_requested
signal basic_attack_requested
signal ability_requested(ability_id: StringName)
signal playback_speed_requested(speed: float)


const GRENADE_ABILITY_ID := &"core:grenade"
const HUD_LAYOUT := preload("res://features/battle/ui/battle_hud_layout.tscn")
const DISPLAY_CONFIG_PATH := "user://display_settings.cfg"
const DISPLAY_CONFIG_SECTION := "display"
const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
]
const COLOR_PANEL := Color(0.070, 0.078, 0.073, 0.92)
const COLOR_PANEL_INNER := Color(0.105, 0.110, 0.102, 0.96)
const COLOR_IVORY := Color(0.790, 0.735, 0.590, 1.0)
const COLOR_BRONZE := Color(0.435, 0.405, 0.325, 1.0)
const COLOR_ENEMY := Color(0.610, 0.235, 0.195, 1.0)
const COLOR_SIGNAL := Color(0.780, 0.215, 0.165, 1.0)
const COLOR_MUTED := Color(0.480, 0.465, 0.410, 1.0)
const COLOR_HEALTHY := Color(0.400, 0.447, 0.357, 1.0)
const COLOR_WOUNDED := Color(0.604, 0.451, 0.278, 1.0)
const COLOR_CRITICAL := Color(0.431, 0.161, 0.161, 1.0)


@onready var _strategist_panel: PanelContainer = $HUDRoot/StrategistPanel
@onready var _active_unit_panel: PanelContainer = $HUDRoot/ActiveUnitPanel
@onready var _turn_queue_panel: PanelContainer = $HUDRoot/TurnQueuePanel
@onready var _target_panel: PanelContainer = $HUDRoot/TargetPanel
@onready var _action_panel: PanelContainer = $HUDRoot/ActionPanel
@onready var _system_panel: PanelContainer = $HUDRoot/SystemPanel
@onready var _round_label: Label = $HUDRoot/StrategistPanel/Margin/Content/Info/RoundLabel
@onready var _objective_label: Label = $HUDRoot/StrategistPanel/Margin/Content/Info/ObjectiveLabel
@onready var _active_unit_label: Label = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/Stats/ActiveUnitLabel
@onready var _active_portrait: TextureRect = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/ActivePortrait
@onready var _health_label: Label = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/Stats/HealthLabel
@onready var _movement_label: Label = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/Stats/MovementLabel
@onready var _main_action_label: Label = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/Stats/MainActionLabel
@onready var _combat_stats_label: Label = $HUDRoot/ActiveUnitPanel/Content/UnitHeader/Stats/CombatStatsLabel
@onready var _target_placeholder: Label = $HUDRoot/TargetPanel/Content/TargetPlaceholder
@onready var _target_content: HBoxContainer = $HUDRoot/TargetPanel/Content/TargetContent
@onready var _target_portrait: TextureRect = $HUDRoot/TargetPanel/Content/TargetContent/TargetPortrait
@onready var _target_name_label: Label = $HUDRoot/TargetPanel/Content/TargetContent/TargetInfo/TargetNameLabel
@onready var _target_faction_label: Label = $HUDRoot/TargetPanel/Content/TargetContent/TargetInfo/TargetFactionLabel
@onready var _target_health_label: Label = $HUDRoot/TargetPanel/Content/TargetContent/TargetInfo/TargetHealthLabel
@onready var _target_stats_label: Label = $HUDRoot/TargetPanel/Content/TargetContent/TargetInfo/TargetStatsLabel
@onready var _target_effects_label: Label = $HUDRoot/TargetPanel/Content/TargetContent/TargetInfo/TargetEffectsLabel
@onready var _action_label: Label = $HUDRoot/ActionPanel/Content/ActionLabel
@onready var _turn_order_container: HBoxContainer = $HUDRoot/TurnQueuePanel/Content/TurnOrderContainer
@onready var _speed_panel: PanelContainer = $HUDRoot/SpeedPanel
@onready var _speed_label: Label = $HUDRoot/SpeedPanel/Content/SpeedLabel
@onready var _movement_button: Button = $HUDRoot/ActionPanel/Content/SkillButtons/MovementButton
@onready var _basic_attack_button: Button = $HUDRoot/ActionPanel/Content/SkillButtons/BasicAttackButton
@onready var _grenade_button: Button = $HUDRoot/ActionPanel/Content/SkillButtons/GrenadeButton
@onready var _settings_button: Button = $HUDRoot/SystemPanel/Content/SettingsButton
@onready var _end_turn_button: Button = $HUDRoot/ActionPanel/Content/SkillButtons/EndTurnButton
@onready var _speed_1_button: Button = $HUDRoot/SpeedPanel/Content/Buttons/Speed1Button
@onready var _speed_2_button: Button = $HUDRoot/SpeedPanel/Content/Buttons/Speed2Button
@onready var _speed_4_button: Button = $HUDRoot/SpeedPanel/Content/Buttons/Speed4Button
@onready var _resolution_option: OptionButton = $HUDRoot/SpeedPanel/Content/ResolutionRow/ResolutionOption
@onready var _fullscreen_check: CheckButton = $HUDRoot/SpeedPanel/Content/FullscreenCheck
@onready var _display_status_label: Label = $HUDRoot/SpeedPanel/Content/DisplayStatusLabel

var _objective_description := ""
var _interaction_enabled := true
var _movement_available := false
var _main_action_available := false
var _grenade_action_available := false
var _selected_resolution := Vector2i(1920, 1080)
var _fullscreen_enabled := false
var _external_restart_requested := false


func _enter_tree() -> void:
	# battle_map.tscn may still be open in the editor with the legacy HUD.
	# Keep the runtime stable by mounting the reusable layout when it is absent.
	var legacy_panel := get_node_or_null("MovementPanel") as CanvasItem
	if legacy_panel != null:
		legacy_panel.visible = false

	if get_node_or_null("HUDRoot") == null:
		var hud_root := HUD_LAYOUT.instantiate()
		hud_root.name = "HUDRoot"
		add_child(hud_root)

	_fit_hud_to_viewport()

	if not get_viewport().size_changed.is_connected(_fit_hud_to_viewport):
		get_viewport().size_changed.connect(_fit_hud_to_viewport)


func _fit_hud_to_viewport() -> void:
	var hud_root := get_node_or_null("HUDRoot") as Control

	if hud_root == null:
		return

	hud_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud_root.position = Vector2.ZERO
	hud_root.size = get_viewport().get_visible_rect().size


func _ready() -> void:
	_apply_styles()
	_setup_display_settings()
	_end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	_movement_button.pressed.connect(_on_movement_button_pressed)
	_basic_attack_button.pressed.connect(_on_basic_attack_button_pressed)
	_grenade_button.pressed.connect(_on_grenade_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	_speed_1_button.pressed.connect(_on_speed_requested.bind(1.0))
	_speed_2_button.pressed.connect(_on_speed_requested.bind(2.0))
	_speed_4_button.pressed.connect(_on_speed_requested.bind(4.0))
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	call_deferred("_apply_display_settings", false)
	clear_target()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_end_turn_button.disabled = not enabled
	_settings_button.disabled = not enabled
	_speed_1_button.disabled = not enabled
	_speed_2_button.disabled = not enabled
	_speed_4_button.disabled = not enabled
	_refresh_action_button_states()


func show_basic_attack_button(attack_range: int, available: bool) -> void:
	_main_action_available = available
	_basic_attack_button.text = (
		"ДАЛЬНИЙ ВЫСТРЕЛ" if attack_range > 1 else "БЛИЖНЯЯ АТАКА"
	)
	_refresh_action_button_states()


func show_grenade_button(visible: bool, available: bool) -> void:
	_grenade_button.visible = visible
	_grenade_action_available = available
	_refresh_action_button_states()


func show_active_portrait(texture: Texture2D) -> void:
	_active_portrait.texture = texture


func show_combat_stats(damage: int, attack_range: int) -> void:
	_combat_stats_label.text = "УРОН  %d     ДАЛЬНОСТЬ  %d" % [
		damage,
		attack_range,
	]


func show_ability_targeting(display_name: String, area_size: int) -> void:
	_action_label.text = "ВЫБЕРИТЕ ЦЕНТР: %s · ЗОНА %d ГЕКСОВ" % [
		display_name.to_upper(),
		area_size,
	]


func show_area_target(area_size: int) -> void:
	_target_placeholder.visible = true
	_target_content.visible = false
	_target_placeholder.text = "ЗОНА ПОРАЖЕНИЯ\n%d ГЕКСОВ\n\nУрон получат все юниты в области" % area_size


func show_round(round_number: int) -> void:
	_round_label.text = "РАУНД %02d" % round_number


func show_objective(description: String) -> void:
	_objective_description = description
	_objective_label.text = "ЦЕЛЬ: %s" % description.to_upper()


func show_active_unit(display_name: String) -> void:
	_active_unit_label.text = display_name.to_upper()


func show_health(current: int, maximum: int) -> void:
	_health_label.text = "ОЗ   %d / %d" % [current, maximum]
	_apply_health_badge(_health_label, current, maximum)


func show_movement(remaining: int, maximum: int) -> void:
	_movement_label.text = "ОД   %d / %d" % [remaining, maximum]
	_movement_available = remaining > 0
	_refresh_action_button_states()


func show_main_action(available: bool) -> void:
	_main_action_available = available
	_main_action_label.text = (
		"ДЕЙСТВИЕ   ГОТОВО" if available else "ДЕЙСТВИЕ   ИСПОЛЬЗОВАНО"
	)
	_main_action_label.modulate = COLOR_IVORY if available else COLOR_MUTED
	_refresh_action_button_states()


func show_target(
	display_name: String,
	texture: Texture2D,
	faction_name: String,
	current_health: int,
	maximum_health: int,
	damage: int,
	attack_range: int,
	movement_remaining: int,
	movement_maximum: int,
	main_action_available: bool
) -> void:
	_target_placeholder.visible = false
	_target_content.visible = true
	_target_portrait.texture = texture
	_target_name_label.text = display_name.to_upper()
	_target_faction_label.text = faction_name.to_upper()
	_target_faction_label.modulate = (
		COLOR_ENEMY if faction_name == "Противник" else COLOR_IVORY
	)
	_target_health_label.text = "ОЗ   %d / %d" % [
		current_health,
		maximum_health,
	]
	_apply_health_badge(_target_health_label, current_health, maximum_health)
	_target_stats_label.text = (
		"УРОН   %d · ДАЛЬНОСТЬ   %d\nОД   %d / %d · ДЕЙСТВИЕ   %s"
		% [
			damage,
			attack_range,
			movement_remaining,
			movement_maximum,
			"ГОТОВО" if main_action_available else "НЕТ",
		]
	)
	_target_effects_label.text = "ПАССИВНЫЕ ЭФФЕКТЫ\nНет активных эффектов"


func clear_target() -> void:
	_target_content.visible = false
	_target_placeholder.visible = true
	_target_placeholder.text = "Наведите курсор на юнита,\nчтобы увидеть характеристики"


func show_turn_order(entries: Array[Dictionary], active_unit_id: StringName) -> void:
	for child in _turn_order_container.get_children():
		_turn_order_container.remove_child(child)
		child.queue_free()

	var active_index := 0

	for index in range(entries.size()):
		if entries[index].get("unit_id", StringName()) == active_unit_id:
			active_index = index
			break

	for offset in range(entries.size()):
		var entry: Dictionary = entries[(active_index + offset) % entries.size()]
		_turn_order_container.add_child(
			_create_turn_card(entry, offset == 0)
		)


func clear_action() -> void:
	_action_label.text = "СИСТЕМА ГОТОВА"


func show_attack(
	attacker_display_name: String,
	target_display_name: String,
	damage: int,
	target_health_remaining: int
) -> void:
	_action_label.text = "%s  →  %s   ·   −%d ОЗ   ·   ОСТАЛОСЬ %d" % [
		attacker_display_name.to_upper(),
		target_display_name.to_upper(),
		damage,
		target_health_remaining,
	]


func show_outcome(outcome: BattleOutcome.Value) -> void:
	match outcome:
		BattleOutcome.Value.VICTORY:
			_objective_label.text = "ЦЕЛЬ ВЫПОЛНЕНА: %s" % _objective_description.to_upper()
			_active_unit_label.text = "ПОБЕДА"
			_action_label.text = "ВСЕ ПРОТИВНИКИ ВЫВЕДЕНЫ ИЗ БОЯ"
		BattleOutcome.Value.DEFEAT:
			_objective_label.text = "ЦЕЛЬ ПРОВАЛЕНА: %s" % _objective_description.to_upper()
			_active_unit_label.text = "ПОРАЖЕНИЕ"
			_action_label.text = "ОТРЯД ВЫВЕДЕН ИЗ БОЯ"
		_:
			push_warning("HUD cannot present an unfinished battle outcome.")
			return

	_health_label.text = "БОЙ ЗАВЕРШЁН"
	_movement_label.text = ""
	_main_action_label.text = ""


func _on_end_turn_button_pressed() -> void:
	end_turn_requested.emit()


func _on_movement_button_pressed() -> void:
	movement_requested.emit()


func _on_basic_attack_button_pressed() -> void:
	basic_attack_requested.emit()


func _on_grenade_button_pressed() -> void:
	ability_requested.emit(GRENADE_ABILITY_ID)


func _on_settings_button_pressed() -> void:
	_speed_panel.visible = not _speed_panel.visible


func _on_speed_requested(speed: float) -> void:
	_speed_label.text = "СКОРОСТЬ АНИМАЦИИ: %sx" % String.num(speed, 0)
	playback_speed_requested.emit(speed)


func _setup_display_settings() -> void:
	_resolution_option.clear()

	for resolution: Vector2i in SUPPORTED_RESOLUTIONS:
		var index := _resolution_option.item_count
		_resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		_resolution_option.set_item_metadata(index, resolution)

	var config := ConfigFile.new()
	var load_error := config.load(DISPLAY_CONFIG_PATH)

	if load_error == OK:
		_selected_resolution = Vector2i(
			int(config.get_value(
				DISPLAY_CONFIG_SECTION,
				"width",
				_selected_resolution.x
			)),
			int(config.get_value(
				DISPLAY_CONFIG_SECTION,
				"height",
				_selected_resolution.y
			))
		)
		_fullscreen_enabled = bool(config.get_value(
			DISPLAY_CONFIG_SECTION,
			"fullscreen",
			false
		))

	var selected_index := SUPPORTED_RESOLUTIONS.find(_selected_resolution)

	if selected_index == -1:
		_selected_resolution = SUPPORTED_RESOLUTIONS[0]
		selected_index = 0

	_resolution_option.select(selected_index)
	_fullscreen_check.set_pressed_no_signal(_fullscreen_enabled)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_option.item_count:
		return

	_selected_resolution = _resolution_option.get_item_metadata(index)
	_save_display_settings()
	_apply_display_settings()


func _on_fullscreen_toggled(enabled: bool) -> void:
	_fullscreen_enabled = enabled
	_save_display_settings()
	_apply_display_settings()


func _apply_display_settings(restart_if_embedded := true) -> void:
	if DisplayServer.get_name() == "headless":
		return

	if _is_editor_managed_run():
		if restart_if_embedded:
			_restart_outside_editor()
		else:
			_display_status_label.text = (
				"ЗАПУСК ИЗ РЕДАКТОРА · ИЗМЕНЕНИЕ ПЕРЕОТКРОЕТ ИГРУ"
			)
		return

	if _fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_selected_resolution)
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if OS.has_feature("windows")
			else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		call_deferred("_update_display_status")
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_apply_windowed_resolution")


func _apply_windowed_resolution() -> void:
	if DisplayServer.get_name() == "headless" or _fullscreen_enabled:
		return

	DisplayServer.window_set_size(_selected_resolution)
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var centered_position := usable_rect.position + Vector2i(
		(usable_rect.size.x - _selected_resolution.x) / 2,
		(usable_rect.size.y - _selected_resolution.y) / 2
	)
	DisplayServer.window_set_position(centered_position)
	_update_display_status()


func _is_editor_managed_run() -> bool:
	return EngineDebugger.is_active()


func _restart_outside_editor() -> void:
	if _external_restart_requested:
		return

	_external_restart_requested = true
	_display_status_label.text = "ПЕРЕЗАПУСК В ОТДЕЛЬНОМ ОКНЕ…"
	var process_id := OS.create_process(
		OS.get_executable_path(),
		PackedStringArray([
			"--path",
			ProjectSettings.globalize_path("res://"),
		])
	)

	if process_id <= 0:
		_external_restart_requested = false
		_display_status_label.text = (
			"НЕ УДАЛОСЬ ОТКРЫТЬ ОТДЕЛЬНОЕ ОКНО"
		)
		return

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _update_display_status() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var actual_size := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	var mode_name := (
		"ПОЛНЫЙ ЭКРАН"
		if mode in [
			DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
		]
		else "ОКНО"
	)
	_display_status_label.text = "ТЕКУЩИЙ РЕЖИМ: %d × %d · %s" % [
		actual_size.x,
		actual_size.y,
		mode_name,
	]
	print("Display settings applied: %dx%d, %s" % [
		actual_size.x,
		actual_size.y,
		mode_name,
	])


func _save_display_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"width",
		_selected_resolution.x
	)
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"height",
		_selected_resolution.y
	)
	config.set_value(
		DISPLAY_CONFIG_SECTION,
		"fullscreen",
		_fullscreen_enabled
	)
	var save_error := config.save(DISPLAY_CONFIG_PATH)

	if save_error != OK:
		push_warning("Display settings could not be saved. Error: %d" % save_error)


func _refresh_action_button_states() -> void:
	_movement_button.disabled = (
		not _interaction_enabled
		or not _movement_available
	)
	_basic_attack_button.disabled = (
		not _interaction_enabled
		or not _main_action_available
	)
	_grenade_button.disabled = (
		not _interaction_enabled
		or not _grenade_action_available
	)


func _create_turn_card(entry: Dictionary, is_active: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(68.0, 62.0)
	var faction: int = entry.get("faction", BattleFaction.Value.PLAYER)
	var border_color := COLOR_IVORY if faction == BattleFaction.Value.PLAYER else COLOR_ENEMY
	card.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			COLOR_PANEL_INNER,
			COLOR_BRONZE if is_active else border_color,
			3 if is_active else 1,
			4
		)
	)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	card.add_child(stack)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(56.0, 38.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = entry.get("texture") as Texture2D
	portrait.modulate = Color(0.35, 0.35, 0.35, 1.0) if entry.get("defeated", false) else Color.WHITE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(portrait)
	var caption := Label.new()
	caption.text = "СЕЙЧАС" if is_active else String(entry.get("short_name", "—"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 9)
	caption.modulate = COLOR_BRONZE if is_active else COLOR_MUTED
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	return card


func _apply_styles() -> void:
	_strategist_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_BRONZE, 2, 8)
	)
	_active_unit_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_SIGNAL, 2, 1)
	)
	_turn_queue_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_BRONZE, 1, 1)
	)
	_target_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_ENEMY, 1, 1)
	)
	_action_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_BRONZE, 1, 1)
	)
	_system_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL, COLOR_BRONZE, 1, 1)
	)
	_speed_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(COLOR_PANEL_INNER, COLOR_IVORY, 1, 1)
	)

	for button: Button in [
		_movement_button,
		_basic_attack_button,
		_grenade_button,
		_settings_button,
		_end_turn_button,
		_speed_1_button,
		_speed_2_button,
		_speed_4_button,
		_resolution_option,
		_fullscreen_check,
	]:
		button.add_theme_color_override("font_color", COLOR_IVORY)
		button.add_theme_color_override("font_hover_color", Color(0.90, 0.86, 0.75))
		button.add_theme_stylebox_override(
			"normal",
			_make_panel_style(COLOR_PANEL_INNER, COLOR_BRONZE, 1, 4)
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_panel_style(Color(0.25, 0.22, 0.18, 1.0), COLOR_SIGNAL, 1, 3)
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_panel_style(Color(0.31, 0.20, 0.17, 1.0), COLOR_SIGNAL, 2, 3)
		)


func _apply_health_badge(label: Label, current: int, maximum: int) -> void:
	var ratio := 0.0 if maximum <= 0 else float(current) / float(maximum)
	var color := COLOR_CRITICAL

	if ratio > 0.66:
		color = COLOR_HEALTHY
	elif ratio > 0.33:
		color = COLOR_WOUNDED

	label.add_theme_stylebox_override(
		"normal",
		_make_panel_style(color, color.lightened(0.12), 1, 3)
	)


func _make_panel_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style
