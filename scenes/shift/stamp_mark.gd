class_name StampMark
extends PanelContainer
## The rubber stamp pressed onto the student's papers. Click it to lift it off and change your
## mind; drag it up toward the student to hand the papers back.

signal lifted
signal handed_back

const HAND_BACK_DRAG := 60.0

var _press_at: Vector2 = Vector2.ZERO
var _pressing: bool = false


static func make(text: String, color: Color) -> StampMark:
	var stamp := StampMark.new()
	var style := UiKit.box(Color(1, 1, 1, 0.55), 4, color, 0, 8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	stamp.add_theme_stylebox_override("panel", style)
	# Long stamps (TO CASHIER, ENROLLED · B) use smaller letters so they stay on the form.
	var label := UiKit.label(text, 40 if text.length() <= 9 else 28, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.add_child(label)
	stamp.rotation_degrees = -8.0
	stamp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stamp.tooltip_text = "Click to lift the stamp off. Drag up to hand the papers back."
	return stamp


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_press_at = event.global_position
		elif _pressing:
			_pressing = false
			if _press_at.y - event.global_position.y >= HAND_BACK_DRAG:
				handed_back.emit()
			else:
				lifted.emit()
	elif event is InputEventMouseMotion and _pressing:
		if _press_at.y - event.global_position.y >= HAND_BACK_DRAG:
			_pressing = false
			handed_back.emit()
