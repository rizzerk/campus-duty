class_name ResetTool
extends Control
## S11: the ISMIS password reset. Type the student number, confirm two facts against the papers,
## then print a temporary password. The facts are the player's word: ticking one that isn't true
## prints a password for the wrong person, and the call is judged that way.

signal printed
signal cancelled

var _student: Dictionary = {}
var _number: LineEdit
var _status: Label
var _checks: Array = []
var _print: Button
var _found: bool = false


static func open(parent: Control, student: Dictionary) -> ResetTool:
	var tool := ResetTool.new()
	parent.add_child(tool)
	tool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tool._build(student)
	return tool


func _build(student: Dictionary) -> void:
	_student = student
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := UiKit.card(Color("#eef4f0"), 20, 6)
	card.position = Vector2(340, 150)
	card.custom_minimum_size = Vector2(600, 0)
	add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	card.add_child(list)
	list.add_child(UiKit.label("ISMIS · Password reset", 26, UiKit.GREEN, true))
	list.add_child(UiKit.wrapped("Type the number, check two facts, print the slip. Getting a fact wrong prints a password for the wrong student.", 16, UiKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	list.add_child(row)
	row.add_child(UiKit.label("Student number", 18, UiKit.INK, true))
	_number = LineEdit.new()
	_number.max_length = 8
	_number.placeholder_text = "8 digits"
	_number.custom_minimum_size.x = 170
	_number.add_theme_font_override("font", UiKit.MONO_FONT)
	_number.add_theme_font_size_override("font_size", 20)
	_number.text_changed.connect(_keep_digits)
	_number.text_submitted.connect(_look_up)
	row.add_child(_number)
	var find := UiKit.button("Find", UiKit.PAPER, UiKit.INK, 16)
	find.pressed.connect(func() -> void: _look_up(_number.text))
	row.add_child(find)
	_status = UiKit.label("Type the number from their ID or admission slip, then Enter.", 16, UiKit.MUTED, true)
	list.add_child(_status)
	for i in 2:
		var text: String = ["ID number matches the record", "Birthday matches the admission slip"][i]
		var check := HBoxContainer.new()
		check.add_theme_constant_override("separation", 10)
		check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var box := CheckMark.new(false, 26)
		check.add_child(box)
		check.add_child(UiKit.label("%d  %s" % [i + 1, text], 19))
		check.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_toggle(i))
		_checks.append(box)
		list.add_child(check)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	list.add_child(buttons)
	var back := UiKit.button("Esc  Back", UiKit.PAPER, UiKit.INK, 18)
	back.pressed.connect(_cancel)
	buttons.add_child(back)
	_print = UiKit.button("Enter  Print temp password", UiKit.GREEN, Color("#f3efe2"), 18)
	_print.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_print.pressed.connect(_print_slip)
	buttons.add_child(_print)
	_update_print()
	_number.grab_focus.call_deferred()


## Any edit means looking the number up again, so a match can't be swapped for another number.
func _keep_digits(text: String) -> void:
	if _found:
		_found = false
		_status.text = "Number changed. Press Enter to look it up again."
		_status.add_theme_color_override("font_color", UiKit.MUTED)
		_update_print()
	var digits := ""
	for character in text:
		if character >= "0" and character <= "9":
			digits += character
	if digits != text:
		_number.text = digits
		_number.caret_column = digits.length()


## Only the student's own number finds an account, like the ISMIS search.
func _look_up(number: String) -> void:
	_found = number == _student["record"]["id_number"]
	if _found:
		_status.text = "Account found · %s · %s" % [_student["record"]["name"], _student["record"]["account"].to_upper()]
		_status.add_theme_color_override("font_color", UiKit.INK)
		_number.release_focus()
	else:
		_status.text = "No account found for %s." % (number if number != "" else "an empty number")
		_status.add_theme_color_override("font_color", UiKit.RED)
		_number.select_all()
	_update_print()


func _toggle(index: int) -> void:
	var box: CheckMark = _checks[index]
	box.checked = not box.checked
	box.queue_redraw()
	_update_print()


func _update_print() -> void:
	_print.disabled = not (_found and _checks.all(func(box: CheckMark) -> bool: return box.checked))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			_print_slip()
		KEY_1, KEY_KP_1:
			_toggle(0)
		KEY_2, KEY_KP_2:
			_toggle(1)


## Esc inside the number box leaves the tool too.
func _input(event: InputEvent) -> void:
	if _number.has_focus() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


func _print_slip() -> void:
	if _print.disabled:
		return
	printed.emit()
	queue_free()


func _cancel() -> void:
	cancelled.emit()
	queue_free()
