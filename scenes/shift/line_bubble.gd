class_name LineBubble
extends PanelContainer
## A speech bubble over a face in the line: a short Bisaya bark with its English subtitle under
## it, and a tail pointing down at whoever said it. One at a time (LineChatter rate limits them);
## a new one replaces the old. Never takes input, so the player can click through it.

const TAIL := 8.0
## Room kept clear at the screen's left and right edges.
const MARGIN := 8.0
const FILL := UiKit.CREAM

var _ceb: Label
var _en: Label
var _tail_x: float = 0.0
var _tween: Tween
var _anchor: Callable
## Counts bubbles, so a bubble still waiting for its first frame knows it was replaced.
var _generation: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.box(FILL, 2, UiKit.INK, 0, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_ceb = UiKit.label("", 19, UiKit.INK)
	column.add_child(_ceb)
	_en = UiKit.label("", 15, UiKit.MUTED)
	column.add_child(_en)
	visible = false
	# Only follows the speaker while a bubble is up.
	set_process(false)


## Shows line for hold seconds. anchor returns where the tail points (canvas coordinates), the top
## of the speaker's face, or Vector2.INF once they're gone; the bubble follows it as the line moves.
func say(line: Dictionary, anchor: Callable, hold: float) -> void:
	_generation += 1
	var generation := _generation
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	_ceb.text = line.get("ceb", "")
	_en.text = line.get("en", "")
	_anchor = anchor
	size = Vector2.ZERO
	size = get_combined_minimum_size()
	# The faces may have just been rebuilt; wait until the line is laid out so the tail lands on
	# the speaker from the first frame (a frame or two at most).
	for i in 5:
		await get_tree().process_frame
		if generation != _generation or not is_inside_tree():
			return
		if _anchor.call() != LineStrip.LAYING_OUT:
			break
	if not _follow():
		return
	visible = true
	set_process(true)
	modulate.a = 1.0
	scale = Vector2.ONE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if Settings.motion_allowed():
		# Pops out of the speaker's head.
		pivot_offset = Vector2(_tail_x, size.y + TAIL)
		scale = Vector2.ONE * 0.6
		_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold)
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(func() -> void:
		_anchor = Callable()
		set_process(false)
		visible = false)


func _process(_delta: float) -> void:
	_follow()


## Puts the tail on the speaker. Takes the bubble down if they've left the visible line.
func _follow() -> bool:
	var point: Vector2 = _anchor.call() if _anchor.is_valid() else Vector2.INF
	if point == Vector2.INF:
		dismiss()
		return false
	if point == LineStrip.LAYING_OUT:
		# The faces are mid rebuild: stay put for this frame.
		return true
	var parent := get_parent() as Control
	if parent != null:
		point -= parent.global_position
	var screen_width := get_parent_area_size().x
	var x := clampf(point.x - size.x / 2.0, MARGIN, screen_width - size.x - MARGIN)
	var tail_x := clampf(point.x - x, TAIL * 1.5, size.x - TAIL * 1.5)
	position = Vector2(x, point.y - TAIL - size.y)
	if tail_x != _tail_x:
		_tail_x = tail_x
		pivot_offset = Vector2(_tail_x, size.y + TAIL)
		queue_redraw()
	return true


## Takes the bubble down at once, say when the shift ends.
func dismiss() -> void:
	_generation += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_anchor = Callable()
	set_process(false)
	visible = false


func _draw() -> void:
	var base := size.y - 2.0
	var tail := PackedVector2Array([
		Vector2(_tail_x - TAIL, base), Vector2(_tail_x + TAIL, base), Vector2(_tail_x, size.y + TAIL)])
	draw_colored_polygon(tail, FILL)
	draw_line(tail[0] + Vector2(0, 2), tail[2], UiKit.INK, 2.0)
	draw_line(tail[1] + Vector2(0, 2), tail[2], UiKit.INK, 2.0)
