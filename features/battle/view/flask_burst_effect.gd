class_name FlaskBurstEffect
extends RefCounted
## Presentation of a flask bursting: a flash and a wave over the cells it affects, with glass
## shards flying out in fixed directions. Shows the event only; the effects follow as events.

const DURATION := 0.36
## Share of the duration the flash stays bright before it fades.
const HOLD := 0.35
const SHARDS := 8
const CONTENT_COLORS: Dictionary[StringName, Color] = {
	&"core:acid": Color("9fd34a"), &"core:water": Color("5fb4dc"),
	&"core:oil": Color("b88a3a"), &"core:electricity": Color("8fd8ff"),
}
const PRESSURE_COLOR := Color("e8f2ff")
const EXPLOSION_COLOR := Color("ff9a3c")


## Builds the effect under `parent` at `center`; `step` is the distance between neighboring hex
## centers there. The returned tween frees the nodes when it finishes.
static func play(parent: Node2D, center: Vector2, step: float, flask: BattleObstacleDefinition) -> Tween:
	var color := color_of(flask)
	var reach := 0.45
	if flask.terrain_type in [&"big_flask", &"explosive_flask"]:
		reach = 1.15
	elif flask.terrain_type == &"pressure_flask":
		reach = float(ObstacleBreakService.PRESSURE_PUSH_DISTANCE) + 0.2
	var root := Node2D.new()
	root.name = "FlaskBurst"
	root.position = center
	root.z_index = 54
	parent.add_child(root)
	var core := Polygon2D.new()
	core.polygon = _circle(step * 0.42, 24)
	core.color = Color(color, 0.8)
	core.scale = Vector2(0.2, 0.2)
	root.add_child(core)
	var flash := Polygon2D.new()
	flash.polygon = _circle(step * 0.22, 20)
	flash.color = Color(1.0, 0.98, 0.9, 0.95)
	flash.scale = Vector2(0.3, 0.3)
	root.add_child(flash)
	var wave := Line2D.new()
	wave.width = 7.0 if flask.terrain_type == &"pressure_flask" else 5.0
	wave.default_color = Color(color.lightened(0.25), 0.95)
	wave.antialiased = true
	wave.closed = true
	wave.points = _circle(step * reach, 36)
	wave.scale = Vector2(0.15, 0.15)
	root.add_child(wave)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	var fade := DURATION * (1.0 - HOLD)
	tween.tween_property(core, "scale", Vector2(2.2, 2.2) if flask.terrain_type == &"explosive_flask" else Vector2(1.3, 1.3), DURATION)
	tween.tween_property(core, "modulate:a", 0.0, fade).set_delay(DURATION * HOLD)
	tween.tween_property(flash, "scale", Vector2(1.4, 1.4), DURATION * 0.5)
	tween.tween_property(flash, "modulate:a", 0.0, DURATION * 0.5)
	tween.tween_property(wave, "scale", Vector2.ONE, DURATION)
	tween.tween_property(wave, "modulate:a", 0.0, fade).set_delay(DURATION * HOLD)
	for index in range(SHARDS):
		var direction := Vector2.from_angle(TAU * (float(index) + 0.5) / float(SHARDS))
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([Vector2(-3.5, 0), Vector2(0, -9), Vector2(3.5, 0)])
		shard.color = Color(0.86, 0.95, 1.0, 0.9) if index % 2 == 0 else Color(color, 0.9)
		shard.rotation = direction.angle() + PI * 0.5
		root.add_child(shard)
		tween.tween_property(shard, "position", direction * step * maxf(reach, 0.6) * 0.8, DURATION)
		tween.tween_property(shard, "modulate:a", 0.0, fade).set_delay(DURATION * HOLD)
	tween.chain().tween_callback(root.queue_free)
	return tween


static func color_of(flask: BattleObstacleDefinition) -> Color:
	if flask.terrain_type == &"pressure_flask":
		return PRESSURE_COLOR
	if flask.terrain_type == &"explosive_flask":
		return EXPLOSION_COLOR
	return CONTENT_COLORS.get(flask.contents, PRESSURE_COLOR)


static func _circle(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		points.append(Vector2.from_angle(TAU * float(index) / float(segments)) * radius)
	return points
