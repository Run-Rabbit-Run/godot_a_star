class_name ReferenceCanvas
extends RefCounted
## The 1920×1080 canvas on which battle art, HUD layouts and grid offsets are authored.

const SIZE := Vector2(1920, 1080)


## Uniform scale that fits the whole canvas into `size` without cropping.
static func fit_scale(size: Vector2) -> float:
	return minf(size.x / SIZE.x, size.y / SIZE.y)
