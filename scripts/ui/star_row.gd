class_name StarRow
extends Control
## Draws filled and empty stars, since the game fonts don't have a star glyph.

@export var total: int = 3
@export var filled: int = 0
@export var star_size: float = 56.0
@export var gap: float = 14.0


func _ready() -> void:
	custom_minimum_size = Vector2(total * star_size + (total - 1) * gap, star_size)


func set_filled(count: int) -> void:
	filled = count
	queue_redraw()


func _draw() -> void:
	for i in total:
		var center := Vector2(star_size / 2.0 + i * (star_size + gap), star_size / 2.0)
		var points := PackedVector2Array()
		for p in 10:
			var radius := star_size / 2.0 if p % 2 == 0 else star_size / 4.6
			var angle := -PI / 2.0 + p * PI / 5.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		var shadow := points.duplicate()
		for p in shadow.size():
			shadow[p] += Vector2(4, 4)
		draw_colored_polygon(shadow, UiKit.INK)
		draw_colored_polygon(points, UiKit.GOLD if i < filled else UiKit.DISABLED)
		points.append(points[0])
		draw_polyline(points, UiKit.INK, 3.0)
