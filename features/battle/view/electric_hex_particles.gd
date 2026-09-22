class_name ElectricHexParticles
extends Node2D


## Small, intermittent sparks over one electric hex. This is presentation only.
const MAX_SPARKS := 12
const SPARKS_PER_BURST_MIN := 3
const SPARKS_PER_BURST_MAX := 5

var _random := RandomNumberGenerator.new()
var _sparks: Array[Dictionary] = []
var _burst_delay := 0.0
var _spark_color := Color(0.55, 0.88, 1.0)


func configure(hex: Vector2i, color: Color) -> void:
	_random.seed = hash("electric:%d:%d" % [hex.x, hex.y])
	_spark_color = color
	_burst_delay = _random.randf_range(0.05, 0.40)


func _process(delta: float) -> void:
	var had_sparks := not _sparks.is_empty()
	_burst_delay -= delta

	if _burst_delay <= 0.0:
		_spawn_burst()
		_burst_delay = _random.randf_range(0.35, 0.80)

	for index in range(_sparks.size() - 1, -1, -1):
		var spark: Dictionary = _sparks[index]
		spark["remaining"] = float(spark["remaining"]) - delta

		if float(spark["remaining"]) <= 0.0:
			_sparks.remove_at(index)
			continue

		spark["position"] = (spark["position"] as Vector2) + (spark["velocity"] as Vector2) * delta

	if had_sparks or not _sparks.is_empty():
		queue_redraw()


func _spawn_burst() -> void:
	for _index in range(_random.randi_range(SPARKS_PER_BURST_MIN, SPARKS_PER_BURST_MAX)):
		if _sparks.size() >= MAX_SPARKS:
			return

		var lifetime := _random.randf_range(0.28, 0.50)
		_sparks.append({
			"position": Vector2(
				_random.randf_range(-20.0, 20.0),
				_random.randf_range(-10.0, 10.0)
			),
			"velocity": Vector2(
				_random.randf_range(-12.0, 12.0),
				_random.randf_range(-24.0, -8.0)
			),
			"remaining": lifetime,
			"lifetime": lifetime,
			"length": _random.randf_range(6.0, 11.0),
			"bend": _random.randf_range(-2.0, 2.0),
		})


func _draw() -> void:
	for spark: Dictionary in _sparks:
		var position: Vector2 = spark["position"]
		var length: float = spark["length"]
		var bend: float = spark["bend"]
		var fade: float = float(spark["remaining"]) / float(spark["lifetime"])
		var start := position + Vector2(-length * 0.5, length * 0.25)
		var middle := position + Vector2(bend, -length * 0.2)
		var finish := position + Vector2(length * 0.5, -length * 0.45)
		var glow := Color(_spark_color.r, _spark_color.g, _spark_color.b, 0.28 * fade)
		var bright := Color(_spark_color.r, _spark_color.g, _spark_color.b, 0.95 * fade)
		var core := Color(0.96, 0.98, 1.0, 0.95 * fade)

		draw_line(start, middle, glow, 6.0, true)
		draw_line(middle, finish, glow, 6.0, true)
		draw_line(start, middle, bright, 2.0, true)
		draw_line(middle, finish, core, 1.5, true)
		draw_circle(middle, 2.0, core)