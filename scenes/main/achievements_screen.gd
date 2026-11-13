class_name AchievementsScreen
extends Control
## The achievements list, opened over the title screen or the day report. Unlocked ones are gold,
## locked ones grey with a progress bar when they count something, hidden ones stay "???" until
## earned. Esc or the button closes it.

signal closed

const COLUMNS := 2
const NEW_TAG := "NEW"


## Opens the list over `parent`, covering the whole 1280x720 screen.
static func open(parent: Node) -> AchievementsScreen:
	var screen := AchievementsScreen.new()
	parent.add_child(screen)
	screen.position = Vector2.ZERO
	screen.size = Vector2(1280, 720)
	return screen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := UiKit.card(UiKit.CREAM, 22, 6)
	card.position = Vector2(110, 40)
	card.size = Vector2(1060, 640)
	add_child(card)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	card.add_child(layout)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	layout.add_child(head)
	var title := UiKit.label("ACHIEVEMENTS", 44, UiKit.GREEN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var total := AchievementRules.all().size()
	var count := UiKit.label("%d / %d unlocked" % [Achievements.unlocked_count(), total], 24, UiKit.MUTED)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	layout.add_child(_bar(float(Achievements.unlocked_count()) / maxf(1.0, total), 12))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	# Unlocked first, newest unlocks on top of those, then the rest in data order.
	for item: Dictionary in _sorted():
		grid.add_child(_row(item))
	var close := UiKit.button("Esc  Close", UiKit.GOLD, UiKit.INK, 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_screen)
	layout.add_child(close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		close_screen()


func close_screen() -> void:
	if is_queued_for_deletion():
		return
	# Seen now, so they're not "new" on the next report.
	Achievements.fresh.clear()
	closed.emit()
	queue_free()


func _sorted() -> Array:
	var open_items: Array = []
	var locked: Array = []
	for item: Dictionary in AchievementRules.all():
		(open_items if Achievements.is_unlocked(item["id"]) else locked).append(item)
	open_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(Achievements.earned[a["id"]]) > int(Achievements.earned[b["id"]]))
	return open_items + locked


func _row(item: Dictionary) -> Control:
	var is_open := Achievements.is_unlocked(item["id"])
	var secret: bool = item.get("hidden", false) and not is_open
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.GOLD_PALE if is_open else UiKit.PAPER, 3, UiKit.INK if is_open else UiKit.SOFT, 0, 10))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 92)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(AchievementBadge.make(item, is_open, 60))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	text.add_child(name_row)
	name_row.add_child(UiKit.label("???" if secret else item["name"], 24, UiKit.INK if is_open else UiKit.MUTED))
	if Achievements.fresh.has(item["id"]):
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UiKit.box(UiKit.RED, 0, UiKit.RED, 0, 3))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(UiKit.label(NEW_TAG, 14, UiKit.CREAM))
		name_row.add_child(tag)
	var desc := UiKit.wrapped("A secret. Keep working the window to find it." if secret else item["desc"], 16, UiKit.MUTED)
	text.add_child(desc)
	if is_open:
		var when := Time.get_date_string_from_unix_time(int(Achievements.earned[item["id"]]))
		text.add_child(UiKit.label("Unlocked %s" % when, 14, UiKit.GOLD_DARK))
	elif item.has("stat"):
		var value := mini(AchievementRules.stat_value(Achievements.stats, item["stat"]), int(item["goal"]))
		var progress_row := HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", 8)
		text.add_child(progress_row)
		var bar := _bar(Achievements.progress(item), 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_row.add_child(bar)
		progress_row.add_child(UiKit.label("%d / %d" % [value, int(item["goal"])], 14, UiKit.MUTED))
	return panel


## A flat progress bar in the UI kit's colors.
func _bar(ratio: float, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", UiKit.box(UiKit.MINT, 2, UiKit.INK))
	bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.GOLD, 2, UiKit.INK))
	return bar

