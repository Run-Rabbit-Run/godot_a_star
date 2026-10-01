extends Node2D

## Visual authoring scene, independent of battle state. Run with F6.
const ACTOR := preload("res://features/battle/units/unit_actor.tscn")
const NAMES := ["sorokin", "ranger", "bastion", "guide", "carapace", "reaper", "spore", "sentry"]
var _actors: Array[UnitActor] = []
var _tweens: Array[Tween] = []
var _speed := 1.0


func _ready() -> void:
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	var background := Sprite2D.new()
	background.z_index = -1
	background.texture = preload("res://features/battle/art/plateau.png")
	background.centered = false
	background.scale = Vector2(1280.0 / 1672.0, 720.0 / 941.0)
	background.modulate = Color(0.65, 0.65, 0.65)
	add_child(background)
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 16)
	add_child(bar)
	var title := Label.new()
	title.text = "Походка · 8 юнитов   "
	bar.add_child(title)
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var button := Button.new()
		button.text = "%sx" % speed
		button.pressed.connect(_set_speed.bind(speed))
		bar.add_child(button)
	for index in range(NAMES.size()):
		var definition := load("res://content/packages/plateau/%s.tres" % NAMES[index]) as UnitDefinition
		var presentation := load("res://content/packages/plateau/%s_presentation.tres" % NAMES[index]) as UnitPresentationDefinition
		var actor := ACTOR.instantiate() as UnitActor
		add_child(actor)
		actor.setup(StringName(NAMES[index]), definition, presentation, BattleFaction.Value.PLAYER, 100, 100)
		actor.position = _origin(index)
		_actors.append(actor)
		var label := Label.new()
		label.text = definition.display_name
		label.position = _origin(index) + Vector2(-45, 26)
		add_child(label)
	queue_redraw()
	_run_routes()


func _draw() -> void:
	for index in range(NAMES.size()):
		for step in range(5):
			var center := _origin(index) + Vector2(step * 58, -29 * (step % 2))
			var polygon := PackedVector2Array()
			for corner in range(7):
				polygon.append(center + Vector2.from_angle(corner * TAU / 6.0) * 33)
			draw_polyline(polygon, Color(0.8, 0.8, 0.65, 0.45), 1.0, true)


func _origin(index: int) -> Vector2:
	return Vector2(115 + (index % 2) * 620, 190 + (index / 2) * 155)


func _fit_viewport() -> void:
	scale = Vector2.ONE * minf(get_viewport_rect().size.x / 1280.0, get_viewport_rect().size.y / 720.0)


func _set_speed(speed: float) -> void:
	_speed = speed
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.set_speed_scale(speed)


func _run_routes() -> void:
	var forward := true
	while is_inside_tree():
		_tweens.clear()
		for index in range(_actors.size()):
			var path: Array[Vector2] = []
			for step in (range(1, 5) if forward else range(3, -1, -1)):
				path.append(to_global(_origin(index) + Vector2(step * 58, -29 * (step % 2))))
			var tween := _actors[index].create_movement_tween(path)
			tween.set_speed_scale(_speed)
			_tweens.append(tween)
		# All figures share the route; the heavy gait is the last to arrive.
		await _tweens[2].finished
		await get_tree().create_timer(0.65).timeout
		forward = not forward
