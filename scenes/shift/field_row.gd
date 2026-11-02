class_name FieldRow
extends PanelContainer
## One clickable field on a paper or the ISMIS screen. Clicking one field on each side flags them.
## Values come as plain text, a checkbox or a signature line, so nothing is colored as a hint.

signal clicked

const STATES := {
	"": [Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2],
	"selected": [UiKit.GOLD_PALE, UiKit.GOLD, 2],
	"claimed": [Color("#f6d98a"), UiKit.GOLD_DARK, 3],
}
const SIGNATURE_INK := Color("#2b4a8a")

var key: String
var context: String
## The paper card this row sits on; dragging the row drags the card (used for the ID card).
var drag_card: Control


static func make(field_key: String, caption: String, value: String, mono: bool, field_context: String = "", kind: String = "text") -> FieldRow:
	var row := FieldRow.new()
	row.key = field_key
	row.context = field_context
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var stack: BoxContainer
	if mono or kind == "check":
		stack = HBoxContainer.new()
		stack.add_theme_constant_override("separation", 8)
	else:
		stack = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)
	if kind == "check":
		stack.add_child(CheckMark.new(value == "Attached"))
	var caption_label := UiKit.label(caption, 14 if mono else (16 if kind == "check" else 14), UiKit.MUTED if kind != "check" else UiKit.INK, mono)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption_label)
	if mono:
		caption_label.custom_minimum_size.x = 170
	if kind != "check":
		var value_label := UiKit.label(value, 15 if mono else 18, SIGNATURE_INK if field_key == "signature" else UiKit.INK, mono)
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if kind == "signature":
			# A signature sits on a line, signed or not.
			var line := StyleBoxFlat.new()
			line.bg_color = Color(0, 0, 0, 0)
			line.border_color = UiKit.INK
			line.border_width_bottom = 2
			value_label.add_theme_stylebox_override("normal", line)
			value_label.custom_minimum_size.y = 26
		stack.add_child(value_label)
	row.set_state("")
	return row


func _gui_input(event: InputEvent) -> void:
	# On release, so pressing to start a drag doesn't also select the field.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()


func _get_drag_data(at_position: Vector2) -> Variant:
	if drag_card != null and drag_card.has_method("_get_drag_data"):
		return drag_card._get_drag_data(at_position)
	return null


func set_state(state: String) -> void:
	var look: Array = STATES[state]
	var style := UiKit.box(look[0], look[2], look[1], 0, 1)
	style.content_margin_left = 6
	add_theme_stylebox_override("panel", style)
