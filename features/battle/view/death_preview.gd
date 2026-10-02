extends Node2D

## F6 visual authoring scene. Bodies stay until Replay, as in a battle.
const ACTOR := preload("res://features/battle/units/unit_actor.tscn")
const NAMES := ["sorokin", "ranger", "bastion", "guide", "carapace", "reaper", "spore", "sentry"]
var _bodies: Array[UnitActor] = []
var _living: Array[UnitActor] = []
var _tweens: Array[Tween] = []
var _speed := 1.0
var _grid := true
var _running := false


func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)
	var background := Sprite2D.new()
	background.texture = preload("res://features/battle/art/plateau.png")
	background.centered = false
	background.scale = Vector2(1920.0 / 1672.0, 1080.0 / 941.0)
	background.z_index = -1
	add_child(background)
	var bar := HBoxContainer.new()
	bar.position = Vector2(42, 26)
	add_child(bar)
	var title := Label.new()
	title.text = "Смерть и трупы · масштаб боя   "
	bar.add_child(title)
	for speed: float in [0.25, 0.5, 1.0, 2.0, 4.0]:
		var button := Button.new()
		button.text = "%sx" % speed
		button.pressed.connect(_set_speed.bind(speed))
		bar.add_child(button)
	var replay := Button.new()
	replay.text = "Повторить"
	replay.pressed.connect(_replay)
	bar.add_child(replay)
	var grid := CheckButton.new()
	grid.text = "Гексы"
	grid.button_pressed = true
	grid.toggled.connect(func(value: bool) -> void: _grid = value; queue_redraw())
	bar.add_child(grid)
	var living := CheckButton.new()
	living.text = "Живые рядом"
	living.button_pressed = true
	living.toggled.connect(_toggle_living)
	bar.add_child(living)
	for index in range(NAMES.size()):
		var actor := _create_actor(index, _origin(index) + Vector2(-94, 0))
		_living.append(actor)
		var label := Label.new()
		label.text = (load("res://content/packages/plateau/%s.tres" % NAMES[index]) as UnitDefinition).display_name
		label.position = _origin(index) + Vector2(-85, 75)
		add_child(label)
	_replay()
	_capture_if_requested()


func _create_actor(index: int, at: Vector2) -> UnitActor:
	var id: String = NAMES[index]
	var definition := load("res://content/packages/plateau/%s.tres" % id) as UnitDefinition
	var presentation := load("res://content/packages/plateau/%s_presentation.tres" % id) as UnitPresentationDefinition
	var actor := ACTOR.instantiate() as UnitActor
	add_child(actor)
	actor.setup(StringName(id), definition, presentation, BattleFaction.Value.PLAYER, 100, 100)
	actor.position = at
	return actor


func _origin(index: int) -> Vector2:
	return Vector2(395 + (index % 4) * 376, 360 + (index / 4) * 390)


func _fit() -> void:
	scale = Vector2.ONE * minf(get_viewport_rect().size.x / 1920.0, get_viewport_rect().size.y / 1080.0)


func _draw() -> void:
	if not _grid:
		return
	for index in range(NAMES.size()):
		for offset: float in [-94.0, 0.0, 94.0]:
			var polygon := PackedVector2Array()
			for corner in range(7):
				var angle := float(corner) * TAU / 6.0 - PI * 0.5
				polygon.append(_origin(index) + Vector2(offset, 0) + Vector2(cos(angle) * 54, sin(angle) * 39))
			draw_polyline(polygon, Color(0.72, 0.67, 0.54, 0.38), 1.0, true)


func _set_speed(value: float) -> void:
	_speed = value
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.set_speed_scale(value)


func _toggle_living(value: bool) -> void:
	for actor: UnitActor in _living:
		actor.visible = value


func _replay() -> void:
	if _running:
		return
	_running = true
	for actor: UnitActor in _bodies:
		actor.queue_free()
	_bodies.clear()
	_tweens.clear()
	for index in range(NAMES.size()):
		_bodies.append(_create_actor(index, _origin(index)))
	await get_tree().create_timer(0.65).timeout
	for index in range(_bodies.size()):
		var tween := _bodies[index].create_defeat_tween(-1.0 if index % 2 else 1.0)
		tween.set_speed_scale(_speed)
		_tweens.append(tween)
	await _tweens.back().finished
	_running = false


## Optional still export from the authoring scene; never runs in battle.
func _capture_if_requested() -> void:
	var capture_time := 2.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--corpse-capture-at="):
			capture_time = maxf(0.1, argument.trim_prefix("--corpse-capture-at=").to_float())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--corpse-capture="):
			await get_tree().create_timer(capture_time).timeout
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--corpse-capture=")
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()
