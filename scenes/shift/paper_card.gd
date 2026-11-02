class_name PaperCard
extends PanelContainer
## One paper on the desk. The student ID can be dragged onto the ISMIS card reader.

var form_kind: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if form_kind != "id_card":
		return null
	var preview := UiKit.card(UiKit.CREAM, 8, 4, 3)
	preview.add_child(UiKit.label("Student ID", 19))
	set_drag_preview(preview)
	return { "kind": "id_card" }
