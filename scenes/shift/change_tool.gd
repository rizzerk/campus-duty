class_name ChangeTool
extends Control
## S17: the payment window's change drawer. The student paid more than the amount due; the player
## counts the change (the cash in the tray minus the Amount due) and types it in. The amount is the
## player's word: the wrong change is judged as a wrong call when the papers go back.

signal given(change: int)
signal cancelled

var _student: Dictionary = {}
var _amount: LineEdit
var _give: Button
## Set on the first hand-over or cancel, so a second key in the same frame can't fire again.
var _done: bool = false


static func open(parent: Control, student: Dictionary) -> ChangeTool:
	var tool := ChangeTool.new()
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
	card.position = Vector2(340, 190)
	card.custom_minimum_size = Vector2(600, 0)
	add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	card.add_child(list)
	list.add_child(UiKit.label("Payment window · Give change", 28, UiKit.GREEN))
	list.add_child(UiKit.wrapped("Take the payment and count the change: the cash minus the amount due.", 20, UiKit.MUTED))
	# Both numbers, as on the S17 board: the card covers the ISMIS screen while it's open.
	list.add_child(_amount_row("Cash in tray", _cash_text()))
	list.add_child(_amount_row("Amount due (ISMIS)", str(_student["record"].get("amount_due", "—"))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	list.add_child(row)
	row.add_child(UiKit.label("Change  PHP", 22))
	_amount = LineEdit.new()
	_amount.focus_mode = Control.FOCUS_CLICK
	_amount.max_length = 6
	_amount.placeholder_text = "whole pesos"
	_amount.keep_editing_on_text_submit = true
	_amount.custom_minimum_size.x = 170
	_amount.add_theme_font_override("font", UiKit.MONO_FONT)
	_amount.add_theme_font_size_override("font_size", 22)
	_amount.text_changed.connect(_keep_digits)
	_amount.text_submitted.connect(func(_text: String) -> void: _hand_over())
	row.add_child(_amount)
	row.add_child(UiKit.label(".00", 22, UiKit.MUTED, true))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	list.add_child(buttons)
	var back := UiKit.button("Esc  Back", UiKit.PAPER, UiKit.INK, 20)
	back.pressed.connect(_cancel)
	buttons.add_child(back)
	_give = UiKit.button("Enter  Hand over the change", UiKit.GREEN, Color("#f3efe2"), 20)
	_give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_give.pressed.connect(_hand_over)
	buttons.add_child(_give)
	_give.disabled = true
	_amount.grab_focus.call_deferred()


## A caption in the game font with the peso amount in mono, like the papers.
func _amount_row(caption: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := UiKit.label(caption, 22)
	name_label.custom_minimum_size.x = 210
	row.add_child(name_label)
	row.add_child(UiKit.label(value, 22, UiKit.INK, true))
	return row


func _cash_text() -> String:
	for paper: Dictionary in _student["papers"]:
		if paper["form"] == "cash":
			return str(paper["fields"]["amount_due"])
	return "—"


func _keep_digits(text: String) -> void:
	var digits := ""
	for character in text:
		if character >= "0" and character <= "9":
			digits += character
	if digits != text:
		_amount.text = digits
		_amount.caret_column = digits.length()
	_give.disabled = digits == ""


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			_hand_over()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	# Holding 2 to open the drawer would otherwise key-repeat "222" into the box. Other keys
	# (Backspace, arrows) still repeat.
	if event.echo and event.unicode >= 48 and event.unicode <= 57:
		get_viewport().set_input_as_handled()
		return
	# Esc inside the amount box leaves the tool too.
	if _amount.has_focus() and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


func _hand_over() -> void:
	if _done or _give.disabled:
		return
	_done = true
	given.emit(int(_amount.text))
	queue_free()


func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()
	queue_free()
