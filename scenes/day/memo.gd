extends Control
## F3: Ma'am Lorna's morning memo. Today's new rules are highlighted; earlier ones stay listed.

const MAX_RULES := 6
## How much fits on the paper, in lines of text, and about how many characters make a line.
const PAPER_LINES := 17
const RULE_CHARS := 56
const INTRO_CHARS := 66

var _started: bool = false


func _ready() -> void:
	Sfx.play_bgm("menu")
	var day: int = GameState.day
	var info := GameData.day(day)
	var wood := ColorRect.new()
	wood.color = Color("#6b4a33")
	wood.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wood)
	for y in range(0, 720, 24):
		var plank := ColorRect.new()
		plank.color = Color("#5c4030")
		plank.position = Vector2(0, y + 22)
		plank.size = Vector2(1280, 2)
		add_child(plank)
	var board := ColorRect.new()
	board.color = Color("#8a5a3b")
	_place(board, Rect2(70, 34, 640, 652))
	var board_edge := Panel.new()
	board_edge.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0), 4, UiKit.INK, 8))
	_place(board_edge, Rect2(70, 34, 640, 652))
	var paper := UiKit.card(UiKit.CREAM, 26, 0, 3)
	_place(paper, Rect2(96, 66, 588, 596))
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UiKit.box(Color("#b8b6ae"), 4, UiKit.INK))
	_place(clip, Rect2(330, 20, 120, 36))
	paper.add_child(_memo_body(day, info))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	_place(side, Rect2(760, 40, 460, 640))
	side.add_child(_offices_card(day))
	side.add_child(_tips_card() if ShiftEvents.is_onboarding(day) else _bulletin_card(day))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var open := UiKit.button("Open Window 3", UiKit.GREEN, Color("#f3efe2"), 26)
	open.custom_minimum_size.y = 64
	open.pressed.connect(_start)
	side.add_child(open)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_start()


## Only once, so a double click or a held key can't start the shift twice.
func _start() -> void:
	if not _started:
		_started = true
		Sfx.play("bell")
		GameState.start_shift()


func _memo_body(day: int, info: Dictionary) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	body.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UiKit.label("MEMO · OFFICE OF THE REGISTRAR", 17, UiKit.MUTED))
	titles.add_child(UiKit.label("Day %d · %s" % [day, info["phase"]], 34))
	var stamp := UiKit.label("READ ME", 18, UiKit.RED)
	stamp.add_theme_stylebox_override("normal", UiKit.box(Color(0, 0, 0, 0), 3, UiKit.RED, 0, 4))
	stamp.rotation_degrees = 6
	head.add_child(stamp)
	body.add_child(UiKit.wrapped(info["intro"], 20, Color("#3a463e")))
	var rules := _rules_for(day)
	for i in rules.size():
		body.add_child(_rule_row(i + 1, rules[i]))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var foot := HBoxContainer.new()
	body.add_child(foot)
	var note := UiKit.wrapped("The line loses patience while it waits.", 16, UiKit.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var signature := VBoxContainer.new()
	signature.add_theme_constant_override("separation", 0)
	foot.add_child(signature)
	var signer := UiKit.label("L. Abellana", 30, UiKit.GREEN)
	signer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	signer.rotation_degrees = -4
	signature.add_child(signer)
	signature.add_child(UiKit.label("Ma'am Lorna, University Registrar", 15, UiKit.MUTED))
	return body


## Today's new rules, plus as many earlier ones as fit, most recent first.
func _rules_for(day: int) -> Array:
	var today: Array = []
	for rule: Dictionary in GameData.day(day)["rules"]:
		today.append({ "text": rule["text"], "new": true })
	var earlier: Array = []
	for number in range(day - 1, int(GameData.json("days")["first_day"]) - 1, -1):
		for rule: Dictionary in GameData.day(number)["rules"]:
			earlier.append({ "text": rule["text"], "new": false })
	var room := PAPER_LINES - _lines(GameData.day(day)["intro"], INTRO_CHARS)
	for rule: Dictionary in today:
		room -= _rule_cost(rule["text"])
	var shown: Array = []
	for rule: Dictionary in earlier:
		if shown.size() + today.size() >= MAX_RULES or _rule_cost(rule["text"]) > room:
			break
		room -= _rule_cost(rule["text"])
		shown.append(rule)
	return shown + today


## Rough wrapped line counts, so long rules don't push the memo off its clipboard.
static func _lines(text: String, per_line: int) -> int:
	return ceili(float(text.length()) / per_line)


## A rule's lines plus the row's padding.
static func _rule_cost(text: String) -> int:
	return _lines(text, RULE_CHARS) + 1


func _rule_row(number: int, rule: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := UiKit.box(UiKit.GOLD_PALE if rule["new"] else Color(0, 0, 0, 0), 3, UiKit.GOLD if rule["new"] else Color(0, 0, 0, 0), 0, 8)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var index := UiKit.label("%d." % number, 22, UiKit.GREEN)
	index.custom_minimum_size.x = 26
	row.add_child(index)
	var text := UiKit.wrapped(rule["text"], 20)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if rule["new"]:
		var tag := UiKit.label("NEW", 15, Color.WHITE)
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		tag.add_theme_stylebox_override("normal", UiKit.box(UiKit.RED, 2, UiKit.INK, 0, 3))
		row.add_child(tag)
	return panel


func _offices_card(day: int) -> Control:
	var card := UiKit.card(UiKit.CREAM, 16, 5)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	card.add_child(list)
	list.add_child(UiKit.label("Other offices today", 24))
	for office: String in GameData.json("offices"):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.add_child(UiKit.label(GameData.json("offices")[office]["name"], 21))
		row.add_child(UiKit.label(OfficeSchedule.describe(day, office), 17, Color("#3a463e")))
		list.add_child(row)
	return card


func _tips_card() -> Control:
	var card := UiKit.card(UiKit.CREAM, 16, 5)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	card.add_child(list)
	list.add_child(UiKit.label("Day 1 · Onboarding with Ma'am Lorna", 24))
	for tip: String in [
		"Drag the student ID onto the ISMIS reader (or press S) to pull up their record.",
		"Think something's off? Click the field on the paper, then the same field on ISMIS to flag it. Flags are checked when you decide, and false alarms cost patience.",
		"Press A to ask the student about a flag. It takes a few minutes.",
		"Stamp a decision (1 to Approve, 5 to Turn away), then hand the papers back with Space. Click a stamp to lift it off.",
	]:
		list.add_child(UiKit.wrapped(tip, 17, Color("#3a463e")))
	return card


## Day 2+: never repeat the tutorial. Show today's schedule, announcements, policy and events.
func _bulletin_card(day: int) -> Control:
	var bulletin := ShiftEvents.bulletin_for_day(day)
	var card := UiKit.card(UiKit.CREAM, 16, 5)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	card.add_child(list)
	list.add_child(UiKit.label(bulletin.get("title", "Today's office bulletin"), 24))
	for field: String in ["schedule", "announcement", "policy", "event_preview"]:
		if bulletin.has(field):
			list.add_child(UiKit.wrapped(bulletin[field], 17, Color("#3a463e")))
	return card


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
