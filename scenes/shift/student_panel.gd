class_name StudentPanel
extends PanelContainer
## The student at the window: portrait, what they say (Bisaya with an English subtitle) and the
## papers they hand over. Paper fields are clickable for flagging.

signal paper_field_clicked(form_index: int, key: String)

const PORTRAIT_SIZE := 96.0

var _body: VBoxContainer
var _frame: Panel
var _ceb: Label
var _en: Label
var _rows: Dictionary = {}
var _papers: Control
var _main_form: Control


func _ready() -> void:
	# No background of its own: the student and their papers sit on the desk.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	clear_student()


func clear_student() -> void:
	UiKit.clear(_body)
	_rows.clear()
	_frame = null
	var waiting := UiKit.label("Waiting for the next student…", 22, UiKit.MUTED)
	waiting.size_flags_vertical = Control.SIZE_EXPAND_FILL
	waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(waiting)


func show_student(student: Dictionary) -> void:
	UiKit.clear(_body)
	_rows.clear()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_body.add_child(header)
	_frame = UiKit.portrait_frame(student["portrait"], PORTRAIT_SIZE, UiKit.INK, Color("#9fd0e8"), 3)
	header.add_child(_frame)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	header.add_child(info)
	info.add_child(UiKit.label("Student #%d" % student["number"], 26))
	info.add_child(UiKit.label(student["name"], 19, UiKit.MUTED))
	info.add_child(UiKit.label("%s · %s" % [student["program"], _year_text(student["year"])], 19, UiKit.MUTED))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	info.add_child(tags)
	if student["priority"] != "":
		tags.add_child(_tag(student["priority"].to_upper(), UiKit.GOLD))
	if student.get("mood", "") == "angry":
		tags.add_child(_tag("ANGRY", Color("#f08a7a")))
	elif student.get("returning", false):
		tags.add_child(_tag("BACK", UiKit.SOFT))
	var bubble := UiKit.card(Color.WHITE, 8, 0, 3)
	_body.add_child(bubble)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	bubble.add_child(lines)
	_ceb = UiKit.wrapped("", 19)
	_en = UiKit.wrapped("", 15, UiKit.MUTED)
	lines.add_child(_ceb)
	lines.add_child(_en)
	say(student["line"])
	_main_form = null
	_papers = _make_papers(student)
	_body.add_child(_papers)


func say(line: Dictionary) -> void:
	if _ceb == null or not is_instance_valid(_ceb):
		return
	_ceb.text = "“%s”" % line["ceb"]
	_en.text = line["en"]


## Where the stamp goes: the main form (not the ID card), or the papers as a whole.
func stamp_rect() -> Rect2:
	if _main_form != null and is_instance_valid(_main_form):
		return _main_form.get_global_rect()
	if _papers != null and is_instance_valid(_papers):
		return _papers.get_global_rect()
	return get_global_rect()


## The papers slide up across the counter when they're handed back.
func slide_out(seconds: float) -> void:
	if _papers == null or not is_instance_valid(_papers):
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(_papers, "position:y", _papers.position.y - 60.0, seconds)
	tween.tween_property(_papers, "modulate:a", 0.0, seconds)


func set_expression(expression: String) -> void:
	if _frame != null and is_instance_valid(_frame):
		UiKit.frame_portrait(_frame).set_expression(expression)


func set_field_state(form_index: int, key: String, state: String) -> void:
	var row: FieldRow = _rows.get("%d:%s" % [form_index, key])
	if row != null:
		row.set_state(state)


## Forms go into three columns, each form into whichever column is shorter, so even four papers
## (say, a returning student with a Dean's approval) fit without scrolling.
const PAPER_COLUMNS := 3


func _make_papers(student: Dictionary) -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stacks: Array = []
	var heights: Array = []
	for c in PAPER_COLUMNS:
		heights.append(0)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 8)
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(stack)
		stacks.append(stack)
	var papers: Array = student["papers"]
	for i in papers.size():
		var column := heights.find(heights.min())
		stacks[column].add_child(_make_form(i, papers[i]))
		heights[column] += papers[i]["fields"].size() + 1
	return columns


func _make_form(index: int, form: Dictionary) -> Control:
	var card := PaperCard.new()
	card.form_kind = form["form"]
	card.add_theme_stylebox_override("panel", UiKit.paper_style(form["form"] == "id_card"))
	if form["form"] != "id_card" and _main_form == null:
		_main_form = card
	if form["form"] == "id_card":
		card.mouse_default_cursor_shape = Control.CURSOR_DRAG
		card.tooltip_text = "Drag onto the ISMIS card reader to pull up the record."
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	# Let presses reach the card so the ID can be dragged from anywhere on it.
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(rows)
	rows.add_child(UiKit.label(form["title"], 19))
	for key: String in form["fields"]:
		var kind := "check" if key.begins_with("req_") else "signature" if key == "signature" else "text"
		var row := FieldRow.make(key, _caption(key), str(form["fields"][key]), false, "", kind)
		row.drag_card = card
		row.clicked.connect(func() -> void: paper_field_clicked.emit(index, key))
		_rows["%d:%s" % [index, key]] = row
		rows.add_child(row)
	return card


static func _caption(key: String) -> String:
	var labels: Dictionary = GameData.json("fields")["labels"]
	if labels.has(key):
		return labels[key]
	for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
		if requirement["key"] == key:
			return requirement["label"]
	return key.capitalize()


static func _year_text(year: int) -> String:
	return ["1st", "2nd", "3rd", "4th"][clampi(year - 1, 0, 3)] + " year"


func _tag(text: String, color: Color) -> Label:
	var tag := UiKit.label(text, 14)
	tag.add_theme_stylebox_override("normal", UiKit.box(color, 2, UiKit.INK, 0, 2))
	return tag
