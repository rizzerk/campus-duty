class_name ChoiceMenu
extends Control
## A small numbered popup over the window: pick one option (reject reasons, offices), or tick
## several and confirm (items to bring back). Keys 1-9 pick or tick, Enter confirms, Esc cancels.

signal chosen(ids: Array)
signal cancelled

var _multi: bool = false
var _ids: Array = []
var _boxes: Array = []


static func open(parent: Control, title: String, options: Array, multi: bool = false) -> ChoiceMenu:
	var menu := ChoiceMenu.new()
	menu._multi = multi
	parent.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu._build(title, options)
	return menu


## options: [{ "id": ..., "label": ... }]
func _build(title: String, options: Array) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_cancel())
	add_child(dim)
	var card := UiKit.card(UiKit.CREAM, 18, 6)
	card.custom_minimum_size.x = 520
	# Hidden until it's centered, so it doesn't flash in the corner for a frame.
	card.modulate.a = 0.0
	add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	card.add_child(list)
	list.add_child(UiKit.label(title, 26))
	for i in options.size():
		var option: Dictionary = options[i]
		_ids.append(option["id"])
		var button := UiKit.button("%d   %s" % [i + 1, option["label"]], UiKit.PAPER, UiKit.INK, 20)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_pick.bind(i))
		if _multi:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var box := CheckMark.new(false, 26)
			box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_boxes.append(box)
			row.add_child(box)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(button)
			list.add_child(row)
		else:
			list.add_child(button)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	list.add_child(footer)
	var cancel := UiKit.button("Esc  Cancel", UiKit.PAPER, UiKit.INK, 18)
	cancel.pressed.connect(_cancel)
	footer.add_child(cancel)
	if _multi:
		var done := UiKit.button("Enter  Done", UiKit.GREEN, Color("#f3efe2"), 18)
		done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		done.pressed.connect(_confirm)
		footer.add_child(done)
	await get_tree().process_frame
	card.position = (size - card.size) / 2.0
	card.modulate.a = 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			if _multi:
				_confirm()
		_:
			var index: int = event.keycode - KEY_1
			if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
				index = event.keycode - KEY_KP_1
			if index >= 0 and index < _ids.size():
				_pick(index)


func _pick(index: int) -> void:
	if not _multi:
		chosen.emit([_ids[index]])
		queue_free()
		return
	var box: CheckMark = _boxes[index]
	box.checked = not box.checked
	box.queue_redraw()


func _confirm() -> void:
	var picked: Array = []
	for i in _ids.size():
		if _boxes[i].checked:
			picked.append(_ids[i])
	chosen.emit(picked)
	queue_free()


func _cancel() -> void:
	cancelled.emit()
	queue_free()
