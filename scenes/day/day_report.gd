extends Control
## F7: end of shift. Stars, the day's numbers and what went wrong, then on to tomorrow.
## A failed shift (patience ran out) shows the S18 version of the title.


func _ready() -> void:
	# Opened on its own (say, with F6 in the editor) there's no shift to report, so start a day.
	if GameState.last_summary.is_empty():
		GameState.go_to("memo")
		return
	var summary: Dictionary = GameState.last_summary
	var day: int = GameState.day
	var failed: bool = summary["reason"] == "patience"
	var background := ColorRect.new()
	background.color = UiKit.GREEN_DARK if failed else UiKit.GREEN
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_place(layout, Rect2(60, 30, 1160, 660))
	var ended_at: String = "shift over at %s" % summary.get("clock", "12:00")
	layout.add_child(UiKit.label("Day %d · %s · %s" % [day, GameData.day(day)["phase"], ended_at], 20, Color("#cfe0d6")))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 30)
	layout.add_child(head)
	head.add_child(UiKit.label("SHIFT FAILED" if failed else "END OF SHIFT", 60, UiKit.GOLD))
	var stars := StarRow.new()
	stars.filled = summary["stars"]
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stars)
	if failed:
		layout.add_child(UiKit.label("The line ran out of patience. Ma'am Lorna took over the window.", 22, Color("#f3efe2")))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	columns.add_child(_today_card(summary))
	columns.add_child(_because_card())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	layout.add_child(foot)
	var tomorrow := UiKit.wrapped(_tomorrow_text(), 20, Color("#f3efe2"))
	tomorrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(tomorrow)
	var next := UiKit.button("Play again from day 2" if GameState.is_last_day() else "Next day", UiKit.GOLD, UiKit.INK, 26)
	next.custom_minimum_size = Vector2(300, 64)
	# Only once: a double click must not skip a day.
	next.pressed.connect(func() -> void:
		if next.disabled:
			return
		next.disabled = true
		GameState.next_day())
	foot.add_child(next)


func _today_card(summary: Dictionary) -> Control:
	var card := UiKit.card(UiKit.CREAM, 18, 5)
	card.custom_minimum_size.x = 420
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	card.add_child(list)
	list.add_child(UiKit.label("Today", 28))
	for row: Array in [
		["Students served", "%d / %d" % [summary["served"], summary["total"]]],
		["Correct calls", summary["correct"]],
		["Wrong calls", summary["mistakes"]],
		["Walked out angry", summary["walked_out"]],
		["Mismatches caught", summary["caught"]],
		["False alarms", summary["false_alarms"]],
	]:
		var line := HBoxContainer.new()
		var caption := UiKit.label(row[0], 22, Color("#3a463e"))
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(caption)
		line.add_child(UiKit.label(str(row[1]), 26))
		list.add_child(line)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(spacer)
	list.add_child(UiKit.wrapped("3 stars needs 90% correct, 90% of the line served and no walkouts.", 17, UiKit.MUTED))
	return card


## Every wrong call with the reason, so the player learns the rule they missed.
func _because_card() -> Control:
	var card := UiKit.card(UiKit.CREAM, 18, 5)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	card.add_child(list)
	list.add_child(UiKit.label("Because of you", 28))
	var summary: Dictionary = GameState.last_summary
	var mistakes: Array = GameState.last_history.filter(func(entry: Dictionary) -> bool: return not entry["correct"])
	var unserved: int = summary["total"] - summary["served"]
	if summary["served"] == 0:
		list.add_child(UiKit.wrapped("You didn't serve anyone. %d students went home without help." % summary["total"], 21, UiKit.RED))
	elif unserved > 0:
		list.add_child(UiKit.wrapped("%d students were still waiting when the window closed." % unserved, 21, UiKit.RED))
	if mistakes.is_empty() and summary["served"] > 0:
		list.add_child(UiKit.wrapped("Not a single wrong call today. Ma'am Lorna noticed.", 21, Color("#3a463e")))
	for entry: Dictionary in mistakes.slice(0, 6):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.color = UiKit.RED
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var text := UiKit.wrapped("#%d %s at %s: you chose %s. %s" % [entry["number"], entry["name"], entry["clock"], _action_name(entry["action"]), entry["reason"]], 19, Color("#3a463e"))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		list.add_child(row)
	if mistakes.size() > 6:
		list.add_child(UiKit.label("…and %d more." % (mistakes.size() - 6), 19, UiKit.MUTED))
	if summary["false_alarms"] > 0:
		list.add_child(UiKit.wrapped("You flagged %d thing%s that turned out to be fine. Short forms like Ma. for Maria don't count." % [summary["false_alarms"], "" if summary["false_alarms"] == 1 else "s"], 19, UiKit.GOLD_DARK))
	return card


func _tomorrow_text() -> String:
	if GameState.is_last_day():
		return "That's the last day built so far. Days 9 and 10 come later."
	var next := GameData.day(GameState.day + 1)
	return "TOMORROW · Day %d, %s. %s" % [GameState.day + 1, next["phase"], next["rules"][0]["text"]]


static func _action_name(action: String) -> String:
	if action.begins_with("route:"):
		return "to send them to %s" % GameData.json("offices")[action.trim_prefix("route:")]["name"]
	return { "approve": "to approve", "reject": "to reject", "fix": "to fix it at the window", "hold": "to hold them" }.get(action, action)


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
