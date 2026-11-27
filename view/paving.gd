class_name Paving
extends RefCounted
## Brick paving patterns, shared by the renderer (textures) and the icons.

## The bricks of one 4x4-unit cell of a paving pattern (a unit is half a brick
## long), wrapping at the cell's edges. Bricks are 2x1 units.
static func bricks(kind: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	match kind:
		"herringbone":
			# staircases of a flat and a standing brick, every (2,-2) along
			for m in range(-4, 5):
				for k in range(-6, 7):
					var o := Vector2(k + 2 * m, k - 2 * m)
					out.append(Rect2(o, Vector2(2, 1)))
					out.append(Rect2(o + Vector2(0, 1), Vector2(1, 2)))
		"basket":
			for by in 2:
				for bx in 2:
					var o := Vector2(bx * 2, by * 2)
					if (bx + by) % 2 == 0:
						out.append(Rect2(o, Vector2(2, 1)))
						out.append(Rect2(o + Vector2(0, 1), Vector2(2, 1)))
					else:
						out.append(Rect2(o, Vector2(1, 2)))
						out.append(Rect2(o + Vector2(1, 0), Vector2(1, 2)))
		_:
			# stretcher bond: courses of long pavers, every other one offset by half
			for row in 4:
				for b in range(-1, 3):
					out.append(Rect2(Vector2(b * 2 + (1 if row % 2 == 1 else 0), row), Vector2(2, 1)))
	return out
