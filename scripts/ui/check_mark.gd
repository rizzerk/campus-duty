class_name CheckMark
extends Control
## A hand-ticked box for paper checklists. Empty means the item isn't there; nothing else hints at it.

var checked: bool = false


func _init(is_checked: bool = false, box_size: float = 20.0) -> void:
	checked = is_checked
	custom_minimum_size = Vector2(box_size, box_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var box := Rect2(Vector2(1, (size.y - side) / 2.0 + 1), Vector2(side - 2, side - 2))
	draw_rect(box, UiKit.INK, false, 2.0)
	if checked:
		var a := box.position + Vector2(box.size.x * 0.2, box.size.y * 0.55)
		var b := box.position + Vector2(box.size.x * 0.42, box.size.y * 0.78)
		var c := box.position + Vector2(box.size.x * 0.85, box.size.y * 0.18)
		draw_polyline(PackedVector2Array([a, b, c]), Color("#2b4a8a"), 3.0)
