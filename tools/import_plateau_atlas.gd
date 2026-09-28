extends SceneTree
## Reproduce makeMatte and the atlas regions from the supplied battle.js.
## Usage: godot --headless --path . --script tools/import_plateau_atlas.gd -- SOURCE.png
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Expected the reference units-source.png path.")
		quit(1)
		return
	var atlas := Image.load_from_file(args[0])
	if atlas == null:
		quit(1)
		return
	atlas.convert(Image.FORMAT_RGBA8)
	var width := atlas.get_width()
	var height := atlas.get_height()
	var pixels := atlas.get_data()
	var candidate := PackedByteArray()
	candidate.resize(width * height)
	var queue := PackedInt32Array()
	for i in range(width * height):
		var red := int(pixels[i * 4])
		var green := int(pixels[i * 4 + 1])
		var blue := int(pixels[i * 4 + 2])
		candidate[i] = int(mini(red, mini(green, blue)) > 157 and maxi(red, maxi(green, blue)) - mini(red, mini(green, blue)) < 30 and blue >= red - 6)
		if candidate[i] == 1 and (i < width or i >= width * (height - 1) or i % width == 0 or i % width == width - 1):
			candidate[i] = 2
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		pixels[i * 4 + 3] = 0
		var neighbors: Array[int] = [i - width, i + width]
		if i % width > 0:
			neighbors.append(i - 1)
		if i % width < width - 1:
			neighbors.append(i + 1)
		for neighbor in neighbors:
			if neighbor >= 0 and neighbor < candidate.size() and candidate[neighbor] == 1:
				candidate[neighbor] = 2
				queue.append(neighbor)
	atlas.set_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	var regions := [Rect2i(40,35,360,443), Rect2i(416,43,381,435), Rect2i(806,45,380,433), Rect2i(1190,15,311,463), Rect2i(15,603,425,365), Rect2i(448,491,323,477), Rect2i(850,491,296,477), Rect2i(1167,486,353,482)]
	var heads := [Rect2i(145,52,92,115), Rect2i(524,65,95,110), Rect2i(915,65,98,115), Rect2i(1290,66,96,110), Rect2i(40,743,130,105), Rect2i(519,551,112,113), Rect2i(876,501,133,126), Rect2i(1280,568,137,133)]
	DirAccess.make_dir_recursive_absolute("res://features/battle/art/plateau_units")
	for i in range(regions.size()):
		atlas.get_region(regions[i]).save_png("res://features/battle/art/plateau_units/%d.png" % i)
		atlas.get_region(heads[i]).save_png("res://features/battle/art/plateau_units/%d-portrait.png" % i)
	print("Imported 8 figures and 8 portraits using the reference atlas coordinates.")
	quit()
