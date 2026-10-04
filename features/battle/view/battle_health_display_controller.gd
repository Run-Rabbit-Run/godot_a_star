extends Node


const CONFIG_PATH := "user://battle_ui_settings.cfg"

var _actors: Dictionary[StringName, UnitActor] = {}
var _alt_only := true
var _details_visible := false


func setup(actors: Dictionary[StringName, UnitActor], alt_check: CheckButton) -> void:
	_actors = actors
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var saved: Variant = config.get_value("unit_health", "alt_only", true)
		if saved is bool:
			_alt_only = saved
	alt_check.set_pressed_no_signal(_alt_only)
	alt_check.toggled.connect(_on_alt_only_toggled)
	_refresh_display_mode(true)


func _process(_delta: float) -> void:
	_refresh_display_mode()


func _refresh_display_mode(force := false) -> void:
	var show_details := not _alt_only or (
		get_window().has_focus() and Input.is_key_pressed(KEY_ALT)
	)
	if not force and show_details == _details_visible:
		return
	_details_visible = show_details
	for actor: UnitActor in _actors.values():
		if is_instance_valid(actor):
			actor.set_health_display_expanded(show_details)


func _on_alt_only_toggled(enabled: bool) -> void:
	_alt_only = enabled
	_refresh_display_mode(true)
	var config := ConfigFile.new()
	config.set_value("unit_health", "alt_only", _alt_only)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Battle UI settings could not be saved. Error: %d" % error)
