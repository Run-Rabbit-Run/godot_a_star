extends Node2D

## F6: visual authoring scene using the same animation as the battle queue.
const ACTOR := preload("res://features/battle/units/unit_actor.tscn")
const PAIRS := [["sorokin", "reaper"], ["ranger", "carapace"], ["bastion", "sentry"], ["spore", "guide"]]
var _pairs: Array = []
var _tweens: Array[Tween] = []
var _speed := 1.0


func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)
	var background := Sprite2D.new()
	background.texture = preload("res://features/battle/art/plateau.png")
	background.centered = false
	background.scale = Vector2(1280.0 / 1672.0, 720.0 / 941.0)
	background.modulate = Color(0.7, 0.7, 0.7)
	background.z_index = -1
	add_child(background)
	var bar := HBoxContainer.new()
	bar.position = Vector2(32, 20)
	add_child(bar)
	var title := Label.new()
	title.text = "Удары и выстрелы · предпросмотр   "
	bar.add_child(title)
	for speed: float in [0.25, 0.5, 1.0, 2.0, 4.0]:
		var button := Button.new()
		button.text = "%sx" % speed
		button.pressed.connect(_set_speed.bind(speed))
		bar.add_child(button)
	for index in range(PAIRS.size()):
		var pair: Array[UnitActor] = []
		var center := Vector2(340 + (index % 2) * 600, 300 + (index / 2) * 290)
		for side in range(2):
			var id: String = PAIRS[index][side]
			var definition := load("res://content/packages/plateau/%s.tres" % id) as UnitDefinition
			var presentation := load("res://content/packages/plateau/%s_presentation.tres" % id) as UnitPresentationDefinition
			var actor := ACTOR.instantiate() as UnitActor
			add_child(actor)
			actor.setup(StringName(id), definition, presentation, BattleFaction.Value.PLAYER if side == 0 else BattleFaction.Value.ENEMY, 100, 100)
			var spacing := 47.0 if index % 2 == 0 else 175.0
			actor.position = center + Vector2((-spacing if side == 0 else spacing), 0)
			pair.append(actor)
		_pairs.append(pair)
		var label := Label.new()
		label.text = "Ближний удар · замах / контакт / возврат" if index % 2 == 0 else "Выстрел · отдача / трассер / попадание"
		label.position = center + Vector2(-180, 42)
		add_child(label)
	_cycle()


func _fit() -> void:
	scale = Vector2.ONE * minf(get_viewport_rect().size.x / 1280.0, get_viewport_rect().size.y / 720.0)


func _set_speed(value: float) -> void:
	_speed = value
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.set_speed_scale(value)


func _cycle() -> void:
	var reverse := false
	while is_inside_tree():
		for index in range(_pairs.size()):
			var pair: Array = _pairs[index]
			var attacker: UnitActor = pair[1 if reverse else 0]
			var target: UnitActor = pair[0 if reverse else 1]
			target.show_health(100, 100)
			var tween := UnitCombatAnimator.attack(attacker, target, index % 2 == 1, target.show_health.bind(83, 100))
			tween.set_speed_scale(_speed)
			_tweens.append(tween)
			await tween.finished
			_tweens.erase(tween)
			await get_tree().create_timer(0.3).timeout
		reverse = not reverse
