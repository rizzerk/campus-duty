class_name Rulebook
extends Control
## S15: the SA handbook. Every rule learned so far, by topic, with today's new rules on top. The
## clock keeps running while it's open (unless the game is paused). Tab or Esc closes it.

signal closed

var _day: int
var _topics: Array = []
var _tab_buttons: Array = []
var _content: VBoxContainer


static func open(parent: Control, day: int) -> Rulebook:
	var book := Rulebook.new()
	book.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	book._build(day)
	return book


## Topics with at least one rule unlocked by this day, each with only its unlocked entries.
static func unlocked_topics(day: int) -> Array:
	var topics: Array = []
	for topic: Dictionary in GameData.json("rulebook")["topics"]:
		var entries: Array = topic["entries"].filter(func(entry: Dictionary) -> bool: return int(entry["day"]) <= day)
		if not entries.is_empty():
			topics.append({ "name": topic["name"], "entries": entries })
	return topics


func _build(day: int) -> void:
	_day = day
	_topics = unlocked_topics(day)
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())
	add_child(dim)
	var card := UiKit.card(UiKit.CREAM, 20, 6)
	card.position = Vector2(170, 70)
	card.size = Vector2(940, 580)
	add_child(card)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	card.add_child(layout)
	layout.add_child(UiKit.label("SA HANDBOOK", 28, UiKit.GREEN))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	layout.add_child(tabs)
	for i in _topics.size():
		var button := UiKit.button("%d %s" % [i + 1, _topics[i]["name"]], UiKit.PAPER, UiKit.INK, 16)
		button.pressed.connect(_show.bind(i))
		tabs.add_child(button)
		_tab_buttons.append(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var today := UiKit.card(UiKit.GOLD_PALE, 10, 0, 3)
	layout.add_child(today)
	var today_rules: Array = GameData.day(day)["rules"].map(func(rule: Dictionary) -> String: return rule["text"])
	today.add_child(UiKit.wrapped("Today's new rule%s: %s" % ["" if today_rules.size() == 1 else "s", " ".join(today_rules)], 17))
	var foot := HBoxContainer.new()
	layout.add_child(foot)
	var note := UiKit.label("The clock keeps running while this is open.", 15, UiKit.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(note)
	var close := UiKit.button("Close · Tab", UiKit.PAPER, UiKit.INK, 16)
	close.pressed.connect(_close)
	foot.add_child(close)
	_show(_topic_with_todays_rule())


## Open on the topic that has today's newest rule, so it's the first thing the player sees.
func _topic_with_todays_rule() -> int:
	for i in _topics.size():
		for entry: Dictionary in _topics[i]["entries"]:
			if int(entry["day"]) == _day:
				return i
	return _topics.size() - 1


func _show(index: int) -> void:
	for i in _tab_buttons.size():
		var active := i == index
		var button: Button = _tab_buttons[i]
		button.add_theme_stylebox_override("normal", UiKit.box(UiKit.GREEN if active else UiKit.PAPER, 3, UiKit.INK, 0, 6))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, Color("#f3efe2") if active else UiKit.INK)
	UiKit.clear(_content)
	for entry: Dictionary in _topics[index]["entries"]:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 2)
		var new_today: bool = int(entry["day"]) == _day
		block.add_child(UiKit.label(entry["title"] + ("   NEW" if new_today else ""), 21, UiKit.RED if new_today else UiKit.INK))
		block.add_child(UiKit.wrapped(entry["text"], 18, Color("#3a463e")))
		_content.add_child(block)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode in [KEY_TAB, KEY_ESCAPE]:
		_close()
		return
	var index: int = event.keycode - KEY_1
	if index >= 0 and index < _topics.size():
		_show(index)


func _close() -> void:
	closed.emit()
	queue_free()
