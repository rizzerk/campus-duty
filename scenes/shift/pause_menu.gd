class_name PauseMenu
extends Control
## S5: Esc pauses the shift. The clock stops; the player can resume, check the rulebook, restart
## the day or quit.

signal resumed

var _shift: ShiftState
var _book: Rulebook


static func open(parent: Control, shift: ShiftState) -> PauseMenu:
	var menu := PauseMenu.new()
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu._build(shift)
	menu.get_tree().paused = true
	return menu


func _build(shift: ShiftState) -> void:
	_shift = shift
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(250, 130)
	add_child(row)
	var menu := UiKit.card(UiKit.CREAM, 22, 6)
	menu.custom_minimum_size = Vector2(380, 0)
	row.add_child(menu)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	menu.add_child(list)
	list.add_child(UiKit.label("PAUSED", 44, UiKit.GREEN))
	list.add_child(UiKit.wrapped("The clock is stopped. The line is frozen mid-sigh.", 17, UiKit.MUTED))
	for item: Array in [["Esc  Resume", _resume, UiKit.GREEN, Color("#f3efe2")], ["Tab  Rulebook", _open_rulebook, UiKit.PAPER, UiKit.INK], ["Restart day", _restart, UiKit.PAPER, UiKit.INK], ["Quit game", _quit, UiKit.PAPER, UiKit.INK]]:
		var button := UiKit.button(item[0], item[2], item[3], 22)
		button.pressed.connect(item[1])
		list.add_child(button)
	var stats := UiKit.card(UiKit.CREAM, 22, 6)
	stats.custom_minimum_size = Vector2(380, 0)
	row.add_child(stats)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	stats.add_child(info)
	info.add_child(UiKit.label("Day %d so far" % shift.day, 26))
	var summary := shift.summary()
	for line: Array in [["Served", "%d / %d" % [summary["served"], summary["total"]]], ["Correct calls", str(summary["correct"])], ["Wrong calls", str(summary["mistakes"])]]:
		var entry := HBoxContainer.new()
		var caption := UiKit.label(line[0], 20, Color("#3a463e"))
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(caption)
		entry.add_child(UiKit.label(line[1], 22))
		info.add_child(entry)
	info.add_child(UiKit.label("On track for", 18, UiKit.MUTED))
	var stars := StarRow.new()
	stars.star_size = 36.0
	stars.filled = Scoring.projected(summary)
	info.add_child(stars)
	var rules: Array = GameData.day(shift.day)["rules"]
	info.add_child(UiKit.wrapped("Today's new rule: %s" % rules[0]["text"], 16, UiKit.GOLD_DARK))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or _book != null:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		_resume()
	elif event.keycode == KEY_TAB:
		_open_rulebook()


func _open_rulebook() -> void:
	if _book != null:
		return
	_book = Rulebook.open(self, _shift.day)
	_book.closed.connect(func() -> void: _book = null)


func _resume() -> void:
	get_tree().paused = false
	resumed.emit()
	queue_free()


func _restart() -> void:
	get_tree().paused = false
	GameState.go_to("memo")


func _quit() -> void:
	get_tree().quit()
