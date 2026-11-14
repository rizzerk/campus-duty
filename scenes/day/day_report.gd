extends Control
## F7: end of shift. Stars, the day's numbers and what went wrong, then on to tomorrow.
## A failed shift (patience ran out) shows the S18 version of the title.


func _ready() -> void:
	# Opened on its own (say, with F6 in the editor) there's no shift to report, so start a day.
	if GameState.last_summary.is_empty():
		GameState.go_to("memo")
		return
	Sfx.play_bgm("menu")
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
	var season := UiKit.label("Season so far: %d stars" % GameState.season_stars(), 22, Color("#cfe0d6"))
	season.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(season)
	if failed:
		layout.add_child(UiKit.label("The line ran out of patience. Ma'am Lorna took over the window.", 22, Color("#f3efe2")))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	left.add_child(_today_card(summary))
	if not summary.get("spot_check", []).is_empty():
		left.add_child(_spot_check_card(summary))
	columns.add_child(_because_card())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	layout.add_child(foot)
	var tomorrow := UiKit.wrapped(_tomorrow_text(), 20, Color("#f3efe2"))
	tomorrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(tomorrow)
	var fresh: int = Achievements.fresh.size()
	var trophies := UiKit.button("Achievements (%d new)" % fresh if fresh > 0 else "Achievements", UiKit.PAPER, UiKit.INK, 22)
	trophies.custom_minimum_size = Vector2(0, 64)
	trophies.pressed.connect(func() -> void:
		var screen := AchievementsScreen.open(self)
		screen.closed.connect(func() -> void: trophies.text = "Achievements"))
	foot.add_child(trophies)
	var next := UiKit.button("Play again from day %d" % int(GameData.json("days")["first_day"]) if GameState.is_last_day() else "Next day", UiKit.GOLD, UiKit.INK, 26)
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
	card.custom_minimum_size.x = 440
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var compact: bool = not summary.get("spot_check", []).is_empty()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2 if compact else 8)
	card.add_child(list)
	list.add_child(UiKit.label("Today", 24 if compact else 28))
	for row: Array in [
		["Students served", "%d / %d" % [summary["served"], summary["total"]]],
		["Calls", "%d right · %d wrong" % [summary["correct"], summary["mistakes"]]],
	] + ([["Hard calls right", "%d / %d" % [summary["hard_right"], summary["hard_calls"]]]] if summary.get("hard_calls", 0) > 0 else []) + [
		["Weighted accuracy", _weighted_text(summary)],
		["Integrity", "%d / %d" % [summary.get("integrity", Evaluation.integrity(summary)), Evaluation.integrity_max()]],
		["Walked out angry", summary["walked_out"]],
		["Flags", "%d caught · %d false alarm%s" % [summary["caught"], summary["false_alarms"], "" if summary["false_alarms"] == 1 else "s"]],
	] + ([["Favors done", summary["bends"]]] if summary.get("bends", 0) > 0 else []):
		var line := HBoxContainer.new()
		var caption := UiKit.label(row[0], 19 if compact else 22, Color("#3a463e"))
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(caption)
		line.add_child(UiKit.label(str(row[1]), 21 if compact else 26))
		list.add_child(line)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(spacer)
	list.add_child(UiKit.wrapped("3 stars: 90% weighted accuracy, 90% served, no walkouts. Hard calls (several problems, today's new problem, turn-aways) count extra.", 15 if compact else 17, UiKit.MUTED))
	return card


## "88%", or "88% (incl. +2% streak)" when a run of right calls added a bonus.
static func _weighted_text(summary: Dictionary) -> String:
	var text := "%d%%" % roundi(float(summary.get("weighted_accuracy", summary["accuracy"])) * 100.0)
	var bonus := roundi(float(summary.get("streak_bonus", 0.0)) * 100.0)
	return text + (" (incl. +%d%% streak)" % bonus if bonus > 0 else "")


## Ma'am Lorna's spot check: three of today's transactions, looked at again. Each favor she
## catches costs a star.
func _spot_check_card(summary: Dictionary) -> Control:
	var card := UiKit.card(UiKit.CREAM, 14, 5)
	card.custom_minimum_size.x = 440
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)
	var lorna := UiKit.portrait_frame(PortraitGen.data()["staff"]["lorna"], 64, UiKit.INK, Color("#9fd0e8"), 3)
	lorna.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(lorna)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list)
	list.add_child(UiKit.label("Ma'am Lorna's spot check", 22))
	var worst := "fine"
	for row: Dictionary in summary["spot_check"]:
		var verdict: String = row["verdict"]
		if verdict == "bent" or (verdict == "wrong" and worst == "fine"):
			worst = verdict
		var text: String = { "fine": "Fine", "wrong": "Wrong call", "bent": "Favor caught · −1 star" }[verdict]
		list.add_child(_spot_row("#%s %s" % [row["number"], row["name"]], text, verdict))
	var options: Array = GameData.json("dialogue")["spot_check"][worst]
	var line: Dictionary = options[(GameState.base_seed + GameState.day) % options.size()]
	list.add_child(UiKit.wrapped("“%s” %s" % [line["ceb"], line["en"]], 15, UiKit.MUTED))
	return card


func _spot_row(who: String, verdict_text: String, verdict: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.color = { "fine": UiKit.OK, "wrong": UiKit.RED, "bent": UiKit.GOLD_DARK }[verdict]
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := UiKit.label(who, 17, Color("#3a463e"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(UiKit.label(verdict_text, 17, UiKit.GOLD_DARK if verdict == "bent" else UiKit.INK))
	return row


## F7's "Because of you": what the player's calls led to, wrong calls first.
func _because_card() -> Control:
	var card := UiKit.card(UiKit.CREAM, 18, 5)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	card.add_child(list)
	list.add_child(UiKit.label("Because of you", 28))
	var summary: Dictionary = GameState.last_summary
	var elsewhere: int = summary.get("elsewhere", 0)
	var unserved: int = summary["total"] - summary["served"] - elsewhere
	if summary["served"] == 0 and elsewhere == 0:
		list.add_child(_story("You didn't serve anyone. %d students went home without help." % summary["total"], false))
	elif unserved > 0:
		list.add_child(_story("%d student%s still waiting when the window closed." % [unserved, " was" if unserved == 1 else "s were"], false))
	if elsewhere > 0:
		list.add_child(_story("%d student%s you sent to another office %s still there at closing. That counts as handled." % [elsewhere, "" if elsewhere == 1 else "s", "was" if elsewhere == 1 else "were"], true))
	var integrity_line := Evaluation.integrity_story(summary)
	if integrity_line != "":
		var kept_bar := int(GameData.json("endings")["endings"]["kept"].get("min_integrity", 0))
		list.add_child(_story(integrity_line, Evaluation.integrity(summary) >= kept_bar))
	var stories := Consequences.build(GameState.last_history, 6)
	for story: Dictionary in stories:
		list.add_child(_story(story["text"], story["good"]))
	if stories.is_empty() and summary["served"] > 0:
		list.add_child(_story("A quiet, clean shift. Ma'am Lorna noticed.", true))
	elif stories.all(func(story: Dictionary) -> bool: return story["good"]) and summary["mistakes"] == 0 and summary["served"] > 0:
		list.add_child(_story("Not a single wrong call today. Ma'am Lorna noticed.", true))
	return card


func _story(text: String, good: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := ColorRect.new()
	dot.color = UiKit.OK if good else UiKit.RED
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dot)
	var label := UiKit.wrapped(text, 18, Color("#3a463e"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


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
