class_name TimetableGrid
extends Control
## The student's week, drawn: enrolled classes as blue blocks and the section being considered on
## top of them. Wherever the preview overlaps a class, those cells turn red.

const LABEL_WIDTH := 64.0
const HEADER_HEIGHT := 30.0
const ENROLLED := Color("#5b6b8a")
const EMPTY := Color("#eef2f0")
const EMPTY_EDGE := Color("#d3dcd8")

var schedule: Array = []
var preview_slots: Array = []
var preview_code: String = ""


func show_preview(code: String, slots: Array) -> void:
	preview_code = code
	preview_slots = slots
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var cell := Vector2((size.x - LABEL_WIDTH) / Timetable.DAYS.size(), (size.y - HEADER_HEIGHT) / Timetable.TIMES.size())
	for d in Timetable.DAYS.size():
		var head := Rect2(LABEL_WIDTH + d * cell.x + 2, 0, cell.x - 4, HEADER_HEIGHT - 4)
		draw_rect(head, UiKit.GREEN)
		_text(font, Timetable.DAYS[d], head, Color("#f3efe2"), 16)
	for t in Timetable.TIMES.size():
		_text(font, Timetable.TIMES[t], Rect2(0, HEADER_HEIGHT + t * cell.y, LABEL_WIDTH - 6, cell.y), Color("#3a463e"), 15)
		for d in Timetable.DAYS.size():
			var rect := _cell_rect(d, t, 1, cell)
			draw_rect(rect, EMPTY)
			draw_rect(rect, EMPTY_EDGE, false, 2.0)
	for entry: Dictionary in schedule:
		for slot: Dictionary in entry["slots"]:
			var rect := _slot_rect(slot, cell)
			draw_rect(rect, ENROLLED)
			draw_rect(rect, UiKit.INK, false, 3.0)
			_text(font, entry["course"], rect, Color.WHITE, 15)
	for slot: Dictionary in preview_slots:
		var rect := _slot_rect(slot, cell)
		var clashing := _clashing_course(slot)
		if clashing == "":
			draw_rect(rect, UiKit.GOLD_PALE)
			_dashed_box(rect, UiKit.GOLD_DARK)
			_text(font, preview_code, rect, UiKit.INK, 15)
		else:
			# Covers the class it runs into, so the second line names it.
			draw_rect(rect, UiKit.RED_PALE)
			_dashed_box(rect, UiKit.RED)
			var half := Rect2(rect.position, Vector2(rect.size.x, rect.size.y / 2.0))
			_text(font, preview_code, half, UiKit.RED, 15)
			_text(font, "× %s" % clashing, Rect2(half.position + Vector2(0, half.size.y), half.size), UiKit.RED, 15)


func _clashing_course(slot: Dictionary) -> String:
	for entry: Dictionary in schedule:
		if Timetable.clashes([slot], entry["slots"]):
			return entry["course"]
	return ""


func _cell_rect(day_index: int, start: int, length: int, cell: Vector2) -> Rect2:
	return Rect2(LABEL_WIDTH + day_index * cell.x + 2, HEADER_HEIGHT + start * cell.y + 2, cell.x - 4, cell.y * length - 4)


func _slot_rect(slot: Dictionary, cell: Vector2) -> Rect2:
	return _cell_rect(Timetable.DAYS.find(slot["day"]), slot["start"], slot["length"], cell)


func _dashed_box(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 3.0, 8.0)


func _text(font: Font, text: String, rect: Rect2, color: Color, font_size: int) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(rect.position.x + (rect.size.x - width) / 2.0, rect.position.y + rect.size.y / 2.0 + font_size * 0.35)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
