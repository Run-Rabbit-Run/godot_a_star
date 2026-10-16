extends Control
## Soft vignette behind the framed HUD; never intercepts battlefield input.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	for pixel in range(112):
		var fade := 1.0 - float(pixel) / 112.0
		draw_rect(Rect2(0, pixel, size.x, 1), Color(0.08, 0.045, 0.028, fade * 0.48))
		draw_rect(Rect2(0, size.y - pixel - 1, size.x, 1), Color(0.08, 0.045, 0.028, fade * 0.55))
