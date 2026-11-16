class_name StarRow
extends Control
## Draws filled and empty stars, since the game fonts don't have a star glyph. reveal() fills
## them one by one with a rising pop, for the end of a shift.

## Emitted when reveal() has shown its last star.
signal revealed

@export var total: int = 3
@export var filled: int = 0
@export var star_size: float = 56.0
@export var gap: float = 14.0

## Star index -> how big it's drawn right now (1 is normal), while it pops in.
var _star_scale: Dictionary = {}
var _reveal: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(total * star_size + (total - 1) * gap, star_size)


func set_filled(count: int) -> void:
	filled = count
	queue_redraw()


## Starts empty and fills count stars gap_seconds apart, each with a pop a little higher than the
## last. The stars swell in unless reduced motion is on; the order and sounds stay either way.
## Nothing waits on it: the player can leave the screen at any time.
func reveal(count: int, gap_seconds: float = 0.25) -> void:
	# A new reveal replaces one still running, so two can't fill the row at once.
	if _reveal != null and _reveal.is_valid():
		_reveal.kill()
	filled = 0
	_star_scale.clear()
	queue_redraw()
	_reveal = create_tween()
	_reveal.tween_interval(0.3)
	var shown := clampi(count, 0, total)
	for i in shown:
		if i > 0:
			_reveal.tween_interval(gap_seconds)
		_reveal.tween_callback(_show_star.bind(i))
	# Right on the last star, so anything waiting on it (confetti) lands with that star.
	_reveal.tween_callback(revealed.emit)


func _show_star(index: int) -> void:
	filled = index + 1
	Sfx.play("pop", 0.0, 1.0 + 0.15 * index)
	if Settings.motion_allowed():
		var grow := create_tween()
		grow.tween_method(func(value: float) -> void:
			_star_scale[index] = value
			queue_redraw(), 1.6, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _draw() -> void:
	for i in total:
		var center := Vector2(star_size / 2.0 + i * (star_size + gap), star_size / 2.0)
		var points := PackedVector2Array()
		for p in 10:
			var radius := (star_size / 2.0 if p % 2 == 0 else star_size / 4.6) * float(_star_scale.get(i, 1.0))
			var angle := -PI / 2.0 + p * PI / 5.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		var shadow := points.duplicate()
		for p in shadow.size():
			shadow[p] += Vector2.ONE * maxf(2.0, roundf(star_size / 14.0))
		draw_colored_polygon(shadow, UiKit.INK)
		draw_colored_polygon(points, UiKit.GOLD if i < filled else UiKit.DISABLED)
		points.append(points[0])
		draw_polyline(points, UiKit.INK, maxf(2.0, star_size / 18.0))
