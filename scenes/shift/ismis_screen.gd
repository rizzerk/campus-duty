class_name IsmisScreen
extends PanelContainer
## The ISMIS terminal: the student's official record in tabs. Record fields and adviser
## specimens are clickable for flagging against the papers.

signal record_field_clicked(key: String, context: String)
signal scanned
signal ask_pressed

const TABS := ["Record", "Grades", "Schedule", "Advisers"]
const SCREEN := Color("#eef4f0")
const LOAD_SECONDS := 0.4
const HINT := "Flag a mismatch: click a field on the papers, then the same field here."
const SCAN_HINT := "Scan the student's ID to pull up their record."
## Banner colors per kind: [background, text].
const BANNERS := {
	"": [Color("#26352c"), Color("#cfe0d6")],
	"mismatch": [Color("#5a1f17"), Color("#ffb3a5")],
	"match": [Color("#1f4a2c"), Color("#b5ecbd")],
	"right": [Color("#2f7d46"), Color.WHITE],
	"wrong": [Color("#b8382a"), Color.WHITE],
	"flag": [Color("#4a3a10"), Color("#f6d98a")],
}

var _student: Dictionary = {}
var _tab: String = "Record"
var _tab_buttons: Dictionary = {}
var _content: VBoxContainer
var _banner: Label
var _banner_box: PanelContainer
var _rows: Dictionary = {}
var _states: Dictionary = {}
var _scanned: bool = false
var _loading: bool = false
var _ask_button: Button
var _search: LineEdit


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.INK, 4, UiKit.INK, 5, 6))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	layout.add_child(tabs)
	for tab: String in TABS:
		var button := Button.new()
		button.text = tab
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", UiKit.MONO_FONT)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void: _show_tab(tab))
		tabs.add_child(button)
		_tab_buttons[tab] = button
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UiKit.box(SCREEN, 0, UiKit.INK, 0, 10))
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(screen)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_banner_box = PanelContainer.new()
	_banner_box.custom_minimum_size.y = 58
	layout.add_child(_banner_box)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 8)
	_banner_box.add_child(banner_row)
	_banner = UiKit.wrapped("", 15, Color("#cfe0d6"))
	_banner.add_theme_font_override("font", UiKit.MONO_FONT)
	_banner.custom_minimum_size.x = 320
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_row.add_child(_banner)
	_ask_button = UiKit.button("A  Ask", UiKit.GOLD, UiKit.INK, 18)
	_ask_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ask_button.pressed.connect(func() -> void: ask_pressed.emit())
	banner_row.add_child(_ask_button)
	show_banner(SCAN_HINT, "")
	_show_tab("Record")


func show_student(student: Dictionary) -> void:
	_student = student
	_states.clear()
	_scanned = false
	_loading = false
	show_banner(SCAN_HINT, "")
	_show_tab("Record")


func is_scanned() -> bool:
	return _scanned


## Searching by number, for students without their card. Only their own number finds a record.
func search(number: String) -> void:
	if _student.is_empty() or _scanned or _loading:
		return
	if number.strip_edges() == _student["record"]["id_number"]:
		_load_record()
	else:
		show_banner("No record found for %s. Check the number and try again." % (number if number != "" else "an empty search"), "")
		if _search != null and is_instance_valid(_search):
			_search.select_all()


func is_typing() -> bool:
	return _search != null and is_instance_valid(_search) and _search.has_focus()


## Inserting the ID card (drag, click on the reader, or S). A student without a card has to be
## searched by number instead.
func scan() -> void:
	if _student.is_empty() or _scanned or _loading:
		return
	if _student.get("no_id", false):
		show_banner("This student has no ID card. Search by their ID number below.", "")
		if _search != null and is_instance_valid(_search):
			_search.grab_focus()
		return
	_load_record()


## Clicking anywhere outside the search box gives the keyboard back to the window's hotkeys.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and is_typing() and not _search.get_global_rect().has_point(event.position):
		_search.release_focus()


## A short loading beat, then the record appears.
func _load_record() -> void:
	if _student.is_empty() or _scanned or _loading:
		return
	_loading = true
	_show_tab(_tab)
	var student := _student
	await get_tree().create_timer(LOAD_SECONDS).timeout
	if student != _student:
		return
	_loading = false
	_scanned = true
	show_banner(HINT, "")
	_show_tab("Record")
	scanned.emit()


func clear_student() -> void:
	_student = {}
	_states.clear()
	_show_tab(_tab)


func set_field_state(key: String, context: String, state: String) -> void:
	_states["%s:%s" % [key, context]] = state
	var row: FieldRow = _rows.get("%s:%s" % [key, context])
	if row != null:
		row.set_state(state)


func show_banner(text: String, kind: String, with_ask: bool = false) -> void:
	var colors: Array = BANNERS[kind]
	_ask_button.visible = with_ask
	_banner.text = text
	_banner.add_theme_color_override("font_color", colors[1])
	_banner_box.add_theme_stylebox_override("panel", UiKit.box(colors[0], 0, UiKit.INK, 0, 8))


## ISMIS lists clearance items as required; the paper shows whether each one is attached.
static func shown_value(key: String, value: String) -> String:
	return "Required" if key.begins_with("req_") and value == "Attached" else value


func _show_tab(tab: String) -> void:
	_tab = tab
	for tab_name: String in _tab_buttons:
		var button: Button = _tab_buttons[tab_name]
		var active := tab_name == tab
		button.add_theme_stylebox_override("normal", UiKit.box(SCREEN if active else UiKit.GREEN, 0, UiKit.INK, 0, 6))
		button.add_theme_stylebox_override("hover", UiKit.box(SCREEN if active else UiKit.GREEN.lightened(0.15), 0, UiKit.INK, 0, 6))
		button.add_theme_stylebox_override("pressed", UiKit.box(SCREEN, 0, UiKit.INK, 0, 6))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, UiKit.INK if active else Color("#f3efe2"))
	UiKit.clear(_content)
	_rows.clear()
	if _student.is_empty():
		_content.add_child(UiKit.label("ISMIS · no student", 16, UiKit.MUTED, true))
		return
	if _loading:
		_content.add_child(UiKit.label("Reading ID… loading record…", 17, UiKit.GREEN, true))
		return
	if not _scanned:
		var reader := IdReader.new()
		reader.custom_minimum_size = Vector2(0, 200)
		reader.id_inserted.connect(scan)
		_content.add_child(reader)
		_content.add_child(_make_search())
		return
	match tab:
		"Record":
			_fill_record()
		"Grades":
			_fill_grades()
		"Schedule":
			_fill_schedule()
		"Advisers":
			_fill_advisers()


func _make_search() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.label("No ID? Search by ID number", 15, UiKit.MUTED, true))
	_search = LineEdit.new()
	_search.max_length = 8
	_search.placeholder_text = "8 digits"
	_search.custom_minimum_size.x = 130
	_search.add_theme_font_override("font", UiKit.MONO_FONT)
	_search.add_theme_font_size_override("font_size", 16)
	_search.text_changed.connect(func(text: String) -> void:
		var digits := ""
		for character in text:
			if character >= "0" and character <= "9":
				digits += character
		if digits != text:
			_search.text = digits
			_search.caret_column = digits.length())
	_search.text_submitted.connect(search)
	_search.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_search.release_focus())
	row.add_child(_search)
	var go := Button.new()
	go.text = "Search"
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_override("font", UiKit.MONO_FONT)
	go.pressed.connect(func() -> void: search(_search.text))
	row.add_child(go)
	return row


func _title(text: String) -> void:
	_content.add_child(UiKit.label(text, 17, UiKit.GREEN, true))


func _row(key: String, caption: String, value: String, clickable: bool, context: String = "") -> void:
	var row := FieldRow.make(key, caption, value, true, context)
	if clickable:
		row.clicked.connect(func() -> void: record_field_clicked.emit(key, context))
		_rows["%s:%s" % [key, context]] = row
		row.set_state(_states.get("%s:%s" % [key, context], ""))
	else:
		row.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_content.add_child(row)


func _fill_record() -> void:
	var record: Dictionary = _student["record"]
	_title("ISMIS · Student record")
	# Rows only show for the visits they matter to (units when adding a subject, birthday for a
	# freshman's reset), so the screen fits. That depends on the visit, never on a problem.
	var has_course: bool = _student["request"].has("course")
	for key: String in GameData.json("fields")["record_order"]:
		if key in ["units_enrolled", "max_units"] and not has_course:
			continue
		if key == "birthday" and _student["visit"] != "first_year":
			continue
		_row(key, StudentPanel._caption(key), str(record[key]), true)
	var requirements: Array = GameData.json("students")["grad_requirements"]
	if record.has(requirements[0]["key"]):
		_title("Graduation requirements")
		for requirement: Dictionary in requirements:
			_row(requirement["key"], requirement["label"], shown_value(requirement["key"], record[requirement["key"]]), true)


func _fill_grades() -> void:
	var request: Dictionary = _student["request"]
	_title("ISMIS · Grades")
	if request.has("course"):
		var needs: String = "needs %s" % request["prereq"] if request["prereq"] != "" else "no prerequisite"
		_content.add_child(UiKit.label("Requested: %s (%s)" % [request["course"], needs], 15, UiKit.MUTED, true))
	var grades: Dictionary = _student["record"]["grades"]
	if grades.is_empty():
		_content.add_child(UiKit.label("No grades yet (first year).", 15, UiKit.MUTED, true))
	for course: String in grades:
		_row("grade", course, grades[course], false)


func _fill_schedule() -> void:
	var record: Dictionary = _student["record"]
	_title("ISMIS · Enrolled schedule")
	if record["schedule"].is_empty():
		_content.add_child(UiKit.label("Nothing enrolled yet.", 15, UiKit.MUTED, true))
	for entry: Dictionary in record["schedule"]:
		_row("schedule", entry["section"], Timetable.label(entry["slots"]), false)
	var request: Dictionary = _student["request"]
	if request.has("course"):
		_title("Sections of %s" % request["course"])
		for section: Dictionary in record["sections"][request["course"]]:
			var seats := "FULL" if section["seats"] <= 0 else "%d seats" % section["seats"]
			_row("section", section["code"], "%-16s %s" % [Timetable.label(section["slots"]), seats], false)


func _fill_advisers() -> void:
	_title("ISMIS · Adviser specimens")
	_content.add_child(UiKit.label(_student["record"]["department"], 14, UiKit.MUTED, true))
	for adviser: Dictionary in _student["record"]["advisers"]:
		_row("signature", adviser["name"], adviser["specimen"], true, adviser["name"])
