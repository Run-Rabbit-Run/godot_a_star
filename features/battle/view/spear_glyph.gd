extends Node2D
## Shared spear silhouette for flight and the weapon left on its landing hex.

func _draw() -> void:
	var shaft_start := Vector2(-34, 0)
	var shaft_end := Vector2(22, 0)
	draw_line(shaft_start + Vector2(1, 3), Vector2(37, 3), Color(0.05, 0.04, 0.03, 0.65), 6, true)
	draw_line(shaft_start, shaft_end, Color("221f1c"), 6, true)
	draw_line(shaft_start, shaft_end, Color("9a7845"), 3, true)
	draw_line(Vector2(-26, -1), Vector2(20, -1), Color("c8b99a"), 1, true)
	var outline := PackedVector2Array([Vector2(18, -5), Vector2(27, -6), Vector2(39, 0), Vector2(27, 6), Vector2(18, 5)])
	draw_colored_polygon(outline, Color("221f1c"))
	draw_colored_polygon(PackedVector2Array([Vector2(21, -3), Vector2(27, -4), Vector2(36, 0), Vector2(27, 4), Vector2(21, 3)]), Color("b4b7ad"))
	draw_line(Vector2(22, 0), Vector2(35, 0), Color("e4dfca"), 1.5, true)
	for x in range(10, 19, 3):
		draw_line(Vector2(x, -2), Vector2(x + 1, 2), Color("6b665c"), 2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(13, 2), Vector2(15, 9), Vector2(21, 7), Vector2(18, 2)]), Color("8e3f39"))
