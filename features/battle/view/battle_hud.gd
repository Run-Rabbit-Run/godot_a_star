class_name BattleHUD
extends CanvasLayer


## HUD сообщает о намерении и не изменяет состояние боя напрямую.
signal end_turn_requested
signal ability_requested(ability_id: StringName)


const GRENADE_ABILITY_ID := &"core:grenade"


@onready var _round_label: Label = %RoundLabel
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _active_unit_label: Label = %ActiveUnitLabel
@onready var _health_label: Label = %HealthLabel
@onready var _movement_label: Label = %MovementLabel
@onready var _main_action_label: Label = %MainActionLabel
@onready var _target_label: Label = %TargetLabel
@onready var _action_label: Label = %ActionLabel
@onready var _end_turn_button: Button = (
	$MovementPanel/VBoxContainer/EndTurnButton
)
@onready var _grenade_button: Button = (
	$MovementPanel/VBoxContainer/GrenadeButton
)

var _objective_description := ""
var _interaction_enabled := true
var _grenade_action_available := false


func _ready() -> void:
	_end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	_grenade_button.pressed.connect(_on_grenade_button_pressed)


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_end_turn_button.disabled = not enabled
	_refresh_grenade_button_state()


func show_grenade_button(visible: bool, available: bool) -> void:
	_grenade_button.visible = visible
	_grenade_action_available = available
	_refresh_grenade_button_state()


func show_ability_targeting(display_name: String, area_size: int) -> void:
	_action_label.text = "Выберите центр: %s (зона %d гексов)" % [
		display_name,
		area_size,
	]


func show_area_target(area_size: int) -> void:
	_target_label.text = "Наведение: зона поражения — %d гексов" % area_size


func show_round(round_number: int) -> void:
	_round_label.text = "Раунд: %d" % round_number


func show_objective(description: String) -> void:
	_objective_description = description
	_objective_label.text = "Цель: %s" % description


func show_active_unit(display_name: String) -> void:
	_active_unit_label.text = "Ход: %s" % display_name


func show_health(current: int, maximum: int) -> void:
	_health_label.text = "Здоровье: %d / %d" % [
		current,
		maximum,
	]


func show_movement(remaining: int, maximum: int) -> void:
	_movement_label.text = "Перемещение: %d / %d" % [
		remaining,
		maximum,
	]


func show_main_action(available: bool) -> void:
	if available:
		_main_action_label.text = "Действие: доступно"
	else:
		_main_action_label.text = "Действие: использовано"


func show_target(display_name: String, current: int, maximum: int) -> void:
	_target_label.text = "Наведение: %s — %d / %d ОЗ" % [
		display_name,
		current,
		maximum,
	]


func clear_target() -> void:
	_target_label.text = "Наведение: —"


func clear_action() -> void:
	_action_label.text = "Последнее действие: —"


func show_attack(
	attacker_display_name: String,
	target_display_name: String,
	damage: int,
	target_health_remaining: int
) -> void:
	_action_label.text = "%s наносит %d урона. %s: %d ОЗ" % [
		attacker_display_name,
		damage,
		target_display_name,
		target_health_remaining,
	]


func show_outcome(outcome: BattleOutcome.Value) -> void:
	match outcome:
		BattleOutcome.Value.VICTORY:
			_objective_label.text = "Цель выполнена: %s" % _objective_description
			_active_unit_label.text = "Победа"
			_action_label.text = "Все враги выведены из боя"
		BattleOutcome.Value.DEFEAT:
			_objective_label.text = "Цель провалена: %s" % _objective_description
			_active_unit_label.text = "Поражение"
			_action_label.text = "Отряд выведен из боя"
		_:
			push_warning("HUD cannot present an unfinished battle outcome.")
			return

	_health_label.text = "Бой завершён"
	_movement_label.text = ""
	_main_action_label.text = ""


func _on_end_turn_button_pressed() -> void:
	end_turn_requested.emit()


func _on_grenade_button_pressed() -> void:
	ability_requested.emit(GRENADE_ABILITY_ID)


func _refresh_grenade_button_state() -> void:
	_grenade_button.disabled = (
		not _interaction_enabled
		or not _grenade_action_available
	)
