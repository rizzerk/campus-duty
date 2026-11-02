class_name IdReader
extends PanelContainer
## The ISMIS card reader. Drop the student ID here (or click it) to pull up their record.

signal id_inserted


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(Color("#dfe8e3"), 3, UiKit.GREEN, 0, 18))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	var slot := ColorRect.new()
	slot.color = UiKit.INK
	slot.custom_minimum_size = Vector2(160, 10)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(slot)
	for line: Array in [["INSERT STUDENT ID", 20, UiKit.GREEN], ["Drag the ID card here, or press S", 15, UiKit.MUTED]]:
		var text := UiKit.label(line[0], line[1], line[2], true)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(text)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", "") == "id_card"


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	id_inserted.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		id_inserted.emit()
