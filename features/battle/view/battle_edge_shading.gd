extends Control
## Local contrast behind the text-only HUD; never intercepts battlefield input.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	for pixel in range(112):
		var fade := 1.0 - float(pixel) / 112.0
		draw_rect(Rect2(0, pixel, size.x, 1), Color(0.07, 0.09, 0.086, fade * 0.90))
		draw_rect(Rect2(0, size.y - pixel - 1, size.x, 1), Color(0.07, 0.09, 0.086, fade * 0.93))
