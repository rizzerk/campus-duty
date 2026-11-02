class_name LineStrip
extends PanelContainer
## The queue as a row of faces. Priority students (GRAD, PWD) can be clicked to call them early.

signal face_clicked(index: int)

const FACE := 54.0
const MAX_FACES := 12
const HINT := "Click a GRAD or PWD face to call them out of turn"
const FLASH_SECONDS := 4.0

var _faces: HBoxContainer
var _more: Label
var _hint: Label
var _flash_left: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(Color("#cfdcd6"), 3, UiKit.INK, 0, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var title := UiKit.label("THE\nLINE", 20, UiKit.GREEN)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	_faces = HBoxContainer.new()
	_faces.add_theme_constant_override("separation", 8)
	row.add_child(_faces)
	_more = UiKit.label("", 20, UiKit.MUTED)
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_more)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_hint = UiKit.wrapped(HINT, 16, UiKit.MUTED)
	_hint.custom_minimum_size.x = 200
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)


## A short alert where the hint usually is, like a rush wave arriving.
func flash(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", UiKit.RED)
	_flash_left = FLASH_SECONDS


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_hint.text = HINT
			_hint.add_theme_color_override("font_color", UiKit.MUTED)


func refresh(line: Array, patience: float) -> void:
	UiKit.clear(_faces)
	for i in mini(line.size(), MAX_FACES):
		_faces.add_child(_make_face(line[i], i, patience))
	_more.text = "+%d more" % (line.size() - MAX_FACES) if line.size() > MAX_FACES else ""


func _make_face(student: Dictionary, index: int, patience: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var tag_text := ""
	var tag_color := UiKit.GOLD
	if student["priority"] == "grad":
		tag_text = "GRAD"
	elif student["priority"] == "pwd":
		tag_text = "PWD"
		tag_color = Color("#7fb3e0")
	elif student.get("mood", "") == "angry":
		tag_text = "BACK"
		tag_color = Color("#f08a7a")
	var tag := UiKit.label(tag_text, 14, UiKit.INK)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tag_text != "":
		tag.add_theme_stylebox_override("normal", UiKit.box(tag_color, 2))
	box.add_child(tag)
	var parts: Dictionary = student["portrait"].duplicate(true)
	parts["expression"] = "angry" if student.get("mood", "") == "angry" else "annoyed" if patience < 40.0 else student["portrait"].get("expression", "neutral")
	var frame := UiKit.portrait_frame(parts, FACE, UiKit.INK, Color("#9fd0e8"), 2)
	if student["priority"] != "":
		frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		frame.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				face_clicked.emit(index))
	box.add_child(frame)
	return box
