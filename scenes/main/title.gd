extends Control
## The title screen, after the splash: the game's sign on the office wall, a few students waiting
## behind the counter, and the main menu. Continue picks up the season saved last (Enter does the
## same); New season (N) opens the save slots (SaveSlotsScreen), where a season is started, loaded
## or deleted. The slots also open straight away when the evaluation's New season leads here.
## Settings stays disabled until the settings screen exists. The text and credits live in
## data/title.json.

const SIGN := Rect2(240, 36, 800, 172)
const MENU := Rect2(490, 236, 300, 0)
const DESK_TOP := 560
## Students waiting in two short lines either side of the menu, as x positions.
const STUDENT_X := [36, 160, 284, 846, 970, 1094]
const STUDENT_WIDTH := 150.0
const STUDENT_TOP := 404.0
const BOB_PIXELS := 4.0
const BOB_SECONDS := 1.1
const FACE_SECONDS := 1.8
const IDLE_FACES := ["neutral", "happy", "annoyed", "nervous", "surprised", "delighted"]

var _data: Dictionary
var _rng := RandomNumberGenerator.new()
var _students: Array[Portrait] = []
var _credits: Control
var _achievements: AchievementsScreen
var _slots: SaveSlotsScreen
var _menu: VBoxContainer
## The slot Continue loads, 0 when there's no usable save.
var _continue_slot: int = 0
var _starting: bool = false


func _ready() -> void:
	Sfx.play_bgm("menu")
	_data = GameData.json("title")
	_rng.randomize()
	var wall := ColorRect.new()
	wall.color = UiKit.MINT
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	_add_sign()
	_add_students()
	_place(UiKit.desk(), Rect2(0, DESK_TOP, 1280, 720 - DESK_TOP))
	_add_menu()
	var footer := UiKit.label(_data["footer"], 17, UiKit.INK)
	footer.modulate.a = 0.75
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(footer, Rect2(0, 684, 1280, 24))
	var faces := Timer.new()
	faces.wait_time = FACE_SECONDS
	faces.autostart = true
	faces.timeout.connect(_change_a_face)
	add_child(faces)
	if GameState.open_slots_on_title:
		GameState.open_slots_on_title = false
		_open_slots()


func _unhandled_key_input(event: InputEvent) -> void:
	# Ignore key repeats, so holding Enter from the splash can't skip ahead.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _achievements != null or _slots != null:
		return
	if _credits != null:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_close_credits()
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		Sfx.play("click")
		if _continue_slot > 0:
			_continue()
		else:
			_open_slots()
	elif event.keycode == KEY_N:
		Sfx.play("click")
		_open_slots()


## Only once, so a double click can't load or start two seasons.
func _continue() -> void:
	_load_slot(_continue_slot)


func _load_slot(slot: int) -> void:
	if _starting:
		return
	_starting = true
	if not GameState.continue_game(slot):
		# The file changed since the menu read it (deleted or damaged outside the game). Closing the
		# slots refreshes the menu; from the menu itself, refresh it here.
		_starting = false
		if _slots != null:
			_slots.close_screen()
		else:
			_fill_menu()
		Sfx.play("wrong")
		Juice.pop_text(self, _data["continue_failed"], UiKit.RED_BRIGHT, Vector2(MENU.get_center().x, MENU.position.y - 4), 26)


func _start_in(slot: int) -> void:
	if not _starting:
		_starting = true
		GameState.start_new_game(0, slot)


func _add_sign() -> void:
	var sign_board := PanelContainer.new()
	sign_board.add_theme_stylebox_override("panel", UiKit.box(UiKit.GREEN, 6, UiKit.GOLD, 8, 18))
	_place(sign_board, SIGN)
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 2)
	sign_board.add_child(lines)
	var title := UiKit.label(_data["title"], 96, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", UiKit.INK)
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	lines.add_child(title)
	var tagline := UiKit.label(_data["tagline"], 24, UiKit.PAPER)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(tagline)
	# Two hooks holding the sign up.
	for x: float in [SIGN.position.x + 90, SIGN.end.x - 104]:
		var hook := Panel.new()
		hook.add_theme_stylebox_override("panel", UiKit.box(Color("#b8b6ae"), 3, UiKit.INK))
		_place(hook, Rect2(x, SIGN.position.y - 22, 14, 30))


## A random line of students each time, gently shifting on their feet behind the counter.
func _add_students() -> void:
	for i in STUDENT_X.size():
		var portrait: Portrait = UiKit.PORTRAIT_SCENE.instantiate()
		# The portrait scene fills its parent by default; size it by hand instead.
		portrait.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_place(portrait, Rect2(STUDENT_X[i], STUDENT_TOP, STUDENT_WIDTH, STUDENT_WIDTH * 1228.0 / 1024.0))
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.apply(PortraitGen.roll(_rng.randi()))
		_students.append(portrait)
		var bob := create_tween().set_loops()
		bob.tween_interval(_rng.randf_range(0.0, BOB_SECONDS))
		bob.tween_property(portrait, "position:y", STUDENT_TOP - BOB_PIXELS, BOB_SECONDS).set_trans(Tween.TRANS_SINE)
		bob.tween_property(portrait, "position:y", STUDENT_TOP, BOB_SECONDS).set_trans(Tween.TRANS_SINE)


func _change_a_face() -> void:
	if _students.is_empty():
		return
	var student: Portrait = _students[_rng.randi_range(0, _students.size() - 1)]
	student.set_expression(IDLE_FACES[_rng.randi_range(0, IDLE_FACES.size() - 1)])


func _add_menu() -> void:
	var card := UiKit.card(UiKit.CREAM, 18, 6)
	_place(card, MENU)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	card.add_child(_menu)
	_fill_menu()


## The menu's buttons. Rebuilt when the save slots close, since a save may have been deleted. The
## green button is what Enter does: Continue when there's a save, else New season (gold beside a
## green Continue, as on the slots and the evaluation).
func _fill_menu() -> void:
	UiKit.clear(_menu)
	var entries := SaveSlots.all()
	_continue_slot = SaveSlots.latest(entries)
	var can_continue := _continue_slot > 0
	var continue_text: String = _data["continue_empty"]
	if can_continue:
		var save: Dictionary = entries[_continue_slot - 1]["save"]
		continue_text = _data["continue_done"] if save["complete"] else String(_data["continue"]).format({ "day": save["day"] })
	var items := [
		[continue_text, UiKit.GREEN if can_continue else UiKit.PAPER, UiKit.PAPER if can_continue else UiKit.INK,
				_continue if can_continue else Callable(), _data["continue_none"]],
		[_data["new_season"], UiKit.GOLD if can_continue else UiKit.GREEN, UiKit.INK if can_continue else UiKit.PAPER, _open_slots, ""],
		[_data["settings_label"], UiKit.PAPER, UiKit.INK, Callable(), _data["settings_soon"]],
		[_data["achievements_label"], UiKit.PAPER, UiKit.INK, _open_achievements, ""],
		[_data["credits_label"], UiKit.PAPER, UiKit.INK, _open_credits, ""],
		[_data["quit_label"], UiKit.PAPER, UiKit.INK, func() -> void: get_tree().quit(), ""],
	]
	for item: Array in items:
		var button := UiKit.button(item[0], item[1], item[2], 24)
		button.custom_minimum_size.y = 48
		if item[3].is_valid():
			button.pressed.connect(item[3])
		else:
			button.disabled = true
			button.tooltip_text = item[4]
		_menu.add_child(button)


func _open_slots() -> void:
	if _slots != null or _achievements != null or _credits != null or _starting:
		return
	_slots = SaveSlotsScreen.open(self)
	_slots.load_requested.connect(_load_slot)
	_slots.new_requested.connect(_start_in)
	_slots.closed.connect(func() -> void:
		_slots = null
		_fill_menu())


func _open_credits() -> void:
	if _credits != null:
		return
	var credits: Dictionary = _data["credits"]
	_credits = Control.new()
	_place(_credits, Rect2(0, 0, 1280, 720))
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(dim)
	var card := UiKit.card(UiKit.CREAM, 26, 6)
	card.position = Vector2(190, 70)
	card.custom_minimum_size = Vector2(900, 0)
	_credits.add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	card.add_child(list)
	list.add_child(UiKit.label("CREDITS", 44, UiKit.GREEN))
	var team := HBoxContainer.new()
	team.add_theme_constant_override("separation", 24)
	list.add_child(team)
	var faces: Dictionary = {}
	for member: Dictionary in PortraitGen.data()["team"]:
		faces[member["name"]] = member
	for person: Dictionary in credits["team"]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		team.add_child(column)
		if faces.has(person["name"]):
			var frame := UiKit.portrait_frame(faces[person["name"]], 110.0, UiKit.GOLD, UiKit.GREEN, 3)
			frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			column.add_child(frame)
		column.add_child(UiKit.label(person["name"], 28))
		column.add_child(UiKit.label(person["role"], 19, UiKit.GREEN))
		var detail := UiKit.wrapped(person["detail"], 16, UiKit.MUTED)
		detail.custom_minimum_size.x = 260
		column.add_child(detail)
	var line := ColorRect.new()
	line.color = UiKit.SOFT
	line.custom_minimum_size.y = 3
	list.add_child(line)
	for text: String in credits["thanks"]:
		list.add_child(UiKit.label(text, 17, Color("#3a463e")))
	var close := UiKit.button("Esc  Close", UiKit.GOLD, UiKit.INK, 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_close_credits)
	list.add_child(close)


func _open_achievements() -> void:
	if _achievements != null or _credits != null or _slots != null:
		return
	_achievements = AchievementsScreen.open(self)
	_achievements.closed.connect(func() -> void: _achievements = null)


func _close_credits() -> void:
	if _credits != null:
		_credits.queue_free()
		_credits = null


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
