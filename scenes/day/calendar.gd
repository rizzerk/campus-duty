extends Control
## Step 1 of each day: the season calendar on the office wall. Past days are crossed off with the
## stars they earned, today is circled, and days that aren't built yet are greyed out. The text
## lives in data/season.json and the rules for each square in Season. From here the player goes
## on to the morning memo.

const COLUMNS := 5
const CALENDAR := Rect2(48, 48, 800, 536)
const RING_COUNT := 6
## Fixed so the wrapped phase names know their width up front. Two weeks fill the calendar.
const CELL_SIZE := Vector2(146, 186)
const CROSS_COLOR := Color(0.722, 0.22, 0.165, 0.85)

var _started: bool = false


func _ready() -> void:
	var wall := ColorRect.new()
	wall.color = UiKit.MINT
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	_place(UiKit.desk(), Rect2(0, 612, 1280, 108))
	_place(_calendar(), CALENDAR)
	_add_rings()
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	_place(side, Rect2(880, 48, 352, 636))
	side.add_child(_today_card())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var start := UiKit.button("Read today's memo", UiKit.GREEN, UiKit.PAPER, 26)
	start.custom_minimum_size.y = 64
	start.pressed.connect(_start)
	side.add_child(start)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_start()


## Only once, so a double click or a held key can't skip the memo.
func _start() -> void:
	if not _started:
		_started = true
		GameState.go_to("memo")


func _calendar() -> Control:
	var season: Dictionary = GameData.json("season")
	var card := UiKit.card(UiKit.CREAM, 0, 6, 4)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	card.add_child(layout)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiKit.box(UiKit.GREEN, 0, UiKit.INK, 0, 0))
	band.custom_minimum_size.y = 76
	layout.add_child(band)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_child(head)
	head.add_child(UiKit.label(season["month"].to_upper(), 44, UiKit.GOLD))
	head.add_child(UiKit.label(season["title"], 24, UiKit.PAPER))
	var trim := ColorRect.new()
	trim.color = UiKit.GOLD
	trim.custom_minimum_size.y = 6
	layout.add_child(trim)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	layout.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)
	for weekday: String in season["weekdays"]:
		var name_label := UiKit.label(weekday, 17, UiKit.MUTED)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
	for item: Dictionary in season["days"]:
		grid.add_child(_cell(item, Season.state(int(item["day"]), GameState.day, GameState.results)))
	return card


func _cell(item: Dictionary, look: String) -> Control:
	var number := int(item["day"])
	var locked := look == "locked"
	var cell := PanelContainer.new()
	cell.custom_minimum_size = CELL_SIZE
	match look:
		"today":
			cell.add_theme_stylebox_override("panel", UiKit.box(UiKit.GOLD_PALE, 4, UiKit.GOLD, 0, 8))
		"locked":
			cell.add_theme_stylebox_override("panel", UiKit.box(Color("#e9ece8"), 2, UiKit.SOFT, 0, 8))
		"past", "failed":
			cell.add_theme_stylebox_override("panel", UiKit.box(UiKit.PAPER, 2, UiKit.INK, 0, 8))
		_:
			cell.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 2, UiKit.INK, 0, 8))
	if not locked:
		cell.tooltip_text = item["teaser"]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(body)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(top)
	var date := UiKit.label(str(int(item["date"])), 38, UiKit.SOFT if locked else UiKit.INK)
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(date)
	var day_tag := UiKit.label("Day %d" % number, 15, UiKit.MUTED)
	day_tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(day_tag)
	var phase := UiKit.wrapped(item["phase"], 17, UiKit.MUTED if locked else UiKit.INK)
	# The cell's width minus its padding.
	phase.custom_minimum_size.x = CELL_SIZE.x - 16
	body.add_child(phase)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)
	match look:
		"today":
			body.add_child(_tag("TODAY", UiKit.RED, Color.WHITE))
			_circle(date)
		"past":
			var stars := StarRow.new()
			stars.star_size = 22.0
			stars.gap = 4.0
			stars.filled = int(GameState.results.get(number, {}).get("stars", 0))
			stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_child(stars)
			_cross_off(date)
		"failed":
			body.add_child(_tag("LORNA TOOK OVER", UiKit.RED_PALE, UiKit.RED))
			_cross_off(date)
		"locked":
			body.add_child(UiKit.label("Coming soon", 15, UiKit.MUTED))
	return cell


## Today's date gets a red marker circle, drawn over the number.
func _circle(date: Label) -> void:
	date.draw.connect(func() -> void:
		var text_width := date.get_theme_font("font").get_string_size(date.text, HORIZONTAL_ALIGNMENT_LEFT, -1, date.get_theme_font_size("font_size")).x
		var center := Vector2(text_width / 2.0, date.size.y / 2.0)
		date.draw_arc(center, maxf(text_width, date.size.y) * 0.62, 0.0, TAU, 40, UiKit.RED, 3.0))


## Days already worked get a marker slash through the date.
func _cross_off(date: Label) -> void:
	date.draw.connect(func() -> void:
		var text_width := date.get_theme_font("font").get_string_size(date.text, HORIZONTAL_ALIGNMENT_LEFT, -1, date.get_theme_font_size("font_size")).x
		date.draw_line(Vector2(-4, date.size.y * 0.78), Vector2(text_width + 4, date.size.y * 0.22), CROSS_COLOR, 4.0))


func _tag(text: String, bg: Color, fg: Color) -> Control:
	var tag := UiKit.label(text, 15, fg)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_stylebox_override("normal", UiKit.box(bg, 2, UiKit.INK, 0, 3))
	return tag


## Binder rings along the top edge, so the calendar hangs on the wall.
func _add_rings() -> void:
	var spacing := CALENDAR.size.x / (RING_COUNT + 1)
	for i in RING_COUNT:
		var ring := Panel.new()
		ring.add_theme_stylebox_override("panel", UiKit.box(Color("#b8b6ae"), 3, UiKit.INK))
		_place(ring, Rect2(CALENDAR.position.x + spacing * (i + 1) - 7, CALENDAR.position.y - 16, 14, 32))


func _today_card() -> Control:
	var today := Season.entry(GameState.day)
	var card := UiKit.card(UiKit.CREAM, 18, 5)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	card.add_child(list)
	list.add_child(UiKit.label("TODAY", 17, UiKit.MUTED))
	list.add_child(UiKit.wrapped("Day %d · %s" % [GameState.day, today.get("phase", GameData.day(GameState.day)["phase"])], 30))
	if today.has("teaser"):
		list.add_child(UiKit.wrapped(today["teaser"], 20, Color("#3a463e")))
	var line := ColorRect.new()
	line.color = UiKit.SOFT
	line.custom_minimum_size.y = 3
	list.add_child(line)
	list.add_child(UiKit.label("SEASON SO FAR", 17, UiKit.MUTED))
	var played := GameState.results.size()
	if played == 0:
		list.add_child(UiKit.wrapped("First day at Window 3. Ma'am Lorna's memo is waiting on the desk.", 20, Color("#3a463e")))
	else:
		list.add_child(UiKit.label("%d of %d stars" % [GameState.season_stars(), played * GameData.json("balance")["star_thresholds"].size()], 26))
		list.add_child(UiKit.label("%d day%s worked" % [played, "" if played == 1 else "s"], 18, Color("#3a463e")))
	return card


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
