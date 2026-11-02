class_name SectionPicker
extends Control
## F5: the section picker. The week on the left, the subject's sections on the right. Fix means
## moving the student out of a full section: click a section (or press its number) to see it on
## the week, then move them. Their own section can't be picked, since that changes nothing.
## Spotting a clash is up to the player; on open market day the seat counts keep dropping.

signal chosen(code: String)
signal cancelled

var _student: Dictionary = {}
var _sections: Array = []
var _selected: int = -1
var _grid: TimetableGrid
var _cards: Array = []
var _seat_labels: Array = []
var _enroll: Button
var _card: PanelContainer


static func open(parent: Control, student: Dictionary, live: bool) -> SectionPicker:
	var picker := SectionPicker.new()
	parent.add_child(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker._build(student, live)
	return picker


func _build(student: Dictionary, live: bool) -> void:
	_student = student
	var request: Dictionary = student["request"]
	_sections = student["record"]["sections"][request["course"]]
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_card = UiKit.card(UiKit.CREAM, 18, 5)
	_card.position = Vector2(40, 84)
	_card.size = Vector2(1200, 610)
	add_child(_card)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	_card.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	left.add_child(UiKit.label("Section picker · %s %s" % [request["course"], request["title"]], 28))
	left.add_child(UiKit.label("%s picked %s. Is it full? Move them to an open section that fits their week." % [student["name"], request["section"]], 17, UiKit.MUTED))
	_grid = TimetableGrid.new()
	_grid.schedule = student["record"]["schedule"]
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size = Vector2(760, 420)
	left.add_child(_grid)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 18)
	left.add_child(legend)
	for item: Array in [[TimetableGrid.ENROLLED, "Already enrolled"], [UiKit.GOLD_PALE, "Section you're looking at"], [UiKit.RED_PALE, "Clash"]]:
		var swatch := ColorRect.new()
		swatch.color = item[0]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		legend.add_child(UiKit.label(item[1], 15, Color("#3a463e")))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	var title := HBoxContainer.new()
	right.add_child(title)
	var heading := UiKit.label("Sections", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(heading)
	if live:
		var tag := UiKit.label("LIVE", 14, Color.WHITE)
		tag.add_theme_stylebox_override("normal", UiKit.box(UiKit.RED, 2, UiKit.INK, 0, 3))
		title.add_child(tag)
	for i in _sections.size():
		right.add_child(_make_section_card(i))
	if live:
		right.add_child(UiKit.wrapped("Other windows are enrolling students too. Seats keep dropping.", 15, UiKit.MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	right.add_child(buttons)
	var back := UiKit.button("Esc  Back", UiKit.PAPER, UiKit.INK, 18)
	back.pressed.connect(_cancel)
	buttons.add_child(back)
	_enroll = UiKit.button("Pick a section", UiKit.OK, Color.WHITE, 18)
	_enroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enroll.disabled = true
	_enroll.pressed.connect(_confirm)
	buttons.add_child(_enroll)
	_refresh_seats()


func _make_section_card(index: int) -> Control:
	var section: Dictionary = _sections[index]
	var card := PanelContainer.new()
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select(index))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rows)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(top)
	var own: bool = section["code"] == _student["request"]["section"]
	var code := UiKit.label("%d  %s%s" % [index + 1, section["code"], "  · their section" if own else ""], 19)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(code)
	var seats := UiKit.label("", 16)
	top.add_child(seats)
	rows.add_child(UiKit.label(Timetable.label(section["slots"]), 15, Color("#3a463e")))
	_cards.append(card)
	_seat_labels.append(seats)
	_style_card(index)
	return card


func _process(_delta: float) -> void:
	_refresh_seats()


## Seat counts are read live from the student's record, so open market drains show as they happen.
func _refresh_seats() -> void:
	for i in _sections.size():
		var left: int = _sections[i]["seats"]
		var label: Label = _seat_labels[i]
		var text := "FULL" if left <= 0 else "%d seat%s" % [left, "" if left == 1 else "s"]
		if label.text != text:
			label.text = text
			label.add_theme_color_override("font_color", UiKit.MUTED if left <= 0 else UiKit.INK)
	if _selected >= 0:
		var picked: Dictionary = _sections[_selected]
		var full := " (FULL)" if picked["seats"] <= 0 else ""
		_enroll.text = _button_text(picked, full)


func _select(index: int) -> void:
	var previous := _selected
	_selected = index
	if previous >= 0:
		_style_card(previous)
	_style_card(index)
	var section: Dictionary = _sections[index]
	_grid.show_preview(section["code"], section["slots"])
	_enroll.text = _button_text(section, "")
	_enroll.disabled = _is_theirs(index)


func _is_theirs(index: int) -> bool:
	return _sections[index]["code"] == _student["request"]["section"]


func _button_text(section: Dictionary, full: String) -> String:
	if section["code"] == _student["request"]["section"]:
		return "They're already in %s" % section["code"]
	return "Enter  Move to %s%s" % [section["code"], full]


func _style_card(index: int) -> void:
	var selected := index == _selected
	var style := UiKit.box(UiKit.GOLD_PALE if selected else Color.WHITE, 4 if selected else 3, UiKit.GOLD if selected else UiKit.INK, 0, 8)
	_cards[index].add_theme_stylebox_override("panel", style)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		_:
			var index: int = event.keycode - KEY_1
			if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
				index = event.keycode - KEY_KP_1
			if index >= 0 and index < _sections.size():
				_select(index)


func _confirm() -> void:
	if _selected < 0 or _is_theirs(_selected):
		return
	chosen.emit(_sections[_selected]["code"])
	queue_free()


func _cancel() -> void:
	cancelled.emit()
	queue_free()
