extends Control
## F9 / S21: the end of the season. Ma'am Lorna's evaluation sheet on the left (the season's
## numbers against the bars, the reasons, her verdict and the stamp), what happened to the
## regulars on the right, then back to the title or a new season. Which ending it is comes from
## Evaluation.ending; every line of text from data/endings.json.

## Colors per ending "look". kept and probation sit on the USC green room of F9; not_renewed uses
## the dim maroon room of S21.
const LOOKS := {
	"kept": {
		"room": UiKit.GREEN, "stripe": Color("#1d5236"), "shadow": UiKit.GREEN_DARK, "stamp": UiKit.OK,
		"card": Color.WHITE, "card_text": UiKit.INK, "note": UiKit.GREEN_DARK, "note_text": Color("#cfe0d6"),
	},
	"probation": {
		"room": UiKit.GREEN, "stripe": Color("#1d5236"), "shadow": UiKit.GREEN_DARK, "stamp": UiKit.GOLD_DARK,
		"card": Color.WHITE, "card_text": UiKit.INK, "note": UiKit.GREEN_DARK, "note_text": Color("#cfe0d6"),
	},
	"not_renewed": {
		"room": UiKit.MAROON, "stripe": Color.TRANSPARENT, "shadow": Color("#1d1414"), "stamp": UiKit.RED,
		"card": UiKit.MAROON_LIGHT, "card_text": UiKit.PAPER, "note": Color("#2a1e1e"), "note_text": Color("#cfc0c0"),
	},
}
const SHEET := Rect2(60, 36, 640, 648)
const SIDE := Rect2(740, 36, 490, 648)
const ROW_TEXT := Color("#3a463e")
const RULE_LINE := Color("#b3a888")

var _text: Dictionary = {}
var _look: Dictionary = {}
var _totals: Dictionary = {}
var _leaving: bool = false


func _ready() -> void:
	# Opened on its own (say, with F6 in the editor) there's no season to judge.
	if GameState.results.is_empty():
		GameState.go_to("title")
		return
	Sfx.play_bgm("menu")
	var data: Dictionary = GameData.json("endings")
	_text = data["screen"]
	var result := Evaluation.ending(GameState.results)
	_totals = Evaluation.season_totals(GameState.results)
	var ending_data: Dictionary = data["endings"][result["id"]]
	_look = LOOKS.get(String(ending_data.get("look", result["id"])), LOOKS["probation"])
	var room := ColorRect.new()
	room.color = _look["room"]
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(room)
	if _look["stripe"].a > 0.0:
		var stripes := Stripes.new()
		stripes.color = _look["stripe"]
		stripes.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(stripes)
	_place(_sheet(result, ending_data, data["endings"][result["target"]]), SHEET)
	_place(_side(result, ending_data), SIDE)
	Sfx.play("stamp")


func _unhandled_key_input(event: InputEvent) -> void:
	# Ignore key repeats, so a held Enter from the day report can't skip the evaluation.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Keys click like the buttons do (UiKit.button plays the click on press).
	if event.keycode == KEY_ESCAPE:
		Sfx.play("click")
		_main_menu()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		Sfx.play("click")
		_new_season()


## Only one way out, once, so a double click can't start two seasons.
func _main_menu() -> void:
	if not _leaving:
		_leaving = true
		GameState.go_to("title")


## To the save slots, so the next season never replaces this finished one without the player
## choosing its slot.
func _new_season() -> void:
	if not _leaving:
		_leaving = true
		GameState.choose_new_season()


## The evaluation form: heading, the numbers against the bars, the reasons, Lorna's verdict, the
## stamp and her signature. target holds the bars the MET / NOT MET tags are measured against.
func _sheet(result: Dictionary, ending_data: Dictionary, target: Dictionary) -> Control:
	var sheet := PanelContainer.new()
	var style := UiKit.box(UiKit.CREAM, 4, UiKit.INK, 8, 0)
	style.shadow_color = _look["shadow"]
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 22
	sheet.add_theme_stylebox_override("panel", style)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	sheet.add_child(list)
	var head := HBoxContainer.new()
	list.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UiKit.label(_text["office"], 18, UiKit.MUTED))
	titles.add_child(UiKit.label(_text["heading"], 32))
	var lorna: Dictionary = PortraitGen.data()["staff"]["lorna"].duplicate(true)
	lorna["expression"] = String(ending_data.get("lorna_expression", lorna.get("expression", "neutral")))
	head.add_child(UiKit.portrait_frame(lorna, 66, UiKit.INK, Color("#9fd0e8"), 3))
	var numbers: Dictionary = result["numbers"]
	list.add_child(UiKit.wrapped(String(_text["intro"]).format({ "served": _totals["served"], "days": numbers["days"] }), 20, ROW_TEXT))
	# Say whose bars the MET / NOT MET tags use: on probation they're the bars for keeping the post.
	list.add_child(UiKit.label(String(_text["bars_for"]).format({ "title": target.get("title", result["target"]) }), 18, UiKit.MUTED))
	var checks := Evaluation.checks(numbers, target)
	list.add_child(_stat_row(_text["accuracy"], "%d%%" % Evaluation.percent(numbers["accuracy"]), _tag(checks, target, "accuracy", "min_accuracy")))
	list.add_child(_stat_row(_text["integrity"], "%d / %d" % [numbers["integrity"], Evaluation.integrity_max()], _tag(checks, target, "integrity", "min_integrity")))
	list.add_child(_stat_row(_text["failed_days"], str(numbers["failed_days"]), _tag(checks, target, "failed_days", "max_failed_days")))
	list.add_child(_stat_row(_text["stars"], "%d / %d" % [_totals["stars"], _totals["max_stars"]], -1))
	for reason: String in result["reasons"]:
		list.add_child(UiKit.wrapped("· " + reason, 20, ROW_TEXT))
	var verdict: Dictionary = ending_data.get("verdict", {})
	if not verdict.is_empty():
		# Bisaya first, the English under it as a subtitle.
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 2)
		words.add_child(UiKit.wrapped("“%s”" % verdict.get("ceb", ""), 20, UiKit.INK))
		words.add_child(UiKit.wrapped(String(verdict.get("en", "")), 20, UiKit.MUTED))
		list.add_child(words)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(spacer)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_BEGIN
	list.add_child(foot)
	foot.add_child(_tilted(_stamp(String(ending_data.get("stamp", result["title"])).to_upper(), String(ending_data.get("stamp_note", ""))), -5.0))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var signature := _tilted(UiKit.label(_text["signature"], 30, UiKit.GREEN), -4.0)
	signature.size_flags_vertical = Control.SIZE_SHRINK_END
	foot.add_child(signature)
	return sheet


## 1 met, 0 short, -1 when the bar doesn't apply (the target ending doesn't set it).
static func _tag(checks: Dictionary, target: Dictionary, key: String, bar_key: String) -> int:
	if not target.has(bar_key):
		return -1
	return 1 if checks[key] else 0


## One line of the sheet: what, the number, and MET or NOT MET (a word, not only a color).
func _stat_row(caption: String, value: String, met: int) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	block.add_child(row)
	var name_label := UiKit.label(caption, 21, ROW_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if met >= 0:
		var tag := UiKit.label(_text["met"] if met == 1 else _text["not_met"], 18, UiKit.OK if met == 1 else UiKit.RED)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	var number := UiKit.label(value, 26, UiKit.INK)
	number.custom_minimum_size.x = 96
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	var rule := ColorRect.new()
	rule.color = RULE_LINE
	rule.custom_minimum_size.y = 2
	block.add_child(rule)
	return block


## The rubber stamp: the ending in capitals with a note under it, tilted as if stamped by hand.
func _stamp(title: String, note: String) -> Control:
	var color: Color = _look["stamp"]
	var stamp := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_border_width_all(5)
	style.border_color = color
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	stamp.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	stamp.add_child(lines)
	var big := UiKit.label(title, 32, color)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(big)
	if note != "":
		var small := UiKit.label(note, 18, color)
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lines.add_child(small)
	return stamp


## Containers reset their children's rotation, so a tilted node sits in a plain holder that
## takes its size and lets the container place the holder instead.
static func _tilted(node: Control, degrees: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(node)
	node.rotation_degrees = degrees
	node.resized.connect(func() -> void:
		node.pivot_offset = node.size / 2.0
		holder.custom_minimum_size = node.size)
	return holder


## The right side: the regulars, the season totals, where this ending ranks, and the buttons.
func _side(result: Dictionary, ending_data: Dictionary) -> Control:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	var title := UiKit.label(_text["regulars_title"], 28, UiKit.GOLD)
	title.add_theme_color_override("font_shadow_color", UiKit.INK)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	side.add_child(title)
	var faces: Dictionary = GameData.json("endings").get("regular_expressions", {})
	for regular: Dictionary in Evaluation.regulars(GameState.results):
		side.add_child(_regular_card(regular, String(faces.get(regular["outcome"], "neutral"))))
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	side.add_child(strip)
	strip.add_child(_total(str(_totals["served"]), _text["served"]))
	strip.add_child(_total("%d%%" % Evaluation.percent(result["numbers"]["accuracy"]), _text["correct"]))
	strip.add_child(_total(str(_totals["stars"]), _text["star_total"]))
	strip.add_child(_total("%d / %d" % [_totals["bends"], _totals["caught_bends"]], _text["favors"]))
	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UiKit.box(_look["note"], 3, UiKit.INK, 0, 10))
	note.add_child(UiKit.wrapped("%s %s" % [ending_data.get("rank", ""), _text["endings_note"]], 20, _look["note_text"]))
	side.add_child(note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	side.add_child(buttons)
	var menu := UiKit.button(_text["main_menu"], UiKit.PAPER, UiKit.INK, 22)
	menu.custom_minimum_size.y = 64
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.size_flags_stretch_ratio = 1.0
	menu.pressed.connect(_main_menu)
	buttons.add_child(menu)
	var again := UiKit.button(_text["new_season"], UiKit.GOLD, UiKit.INK, 24)
	again.custom_minimum_size.y = 64
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.size_flags_stretch_ratio = 1.4
	again.pressed.connect(_new_season)
	buttons.add_child(again)
	return side


func _regular_card(regular: Dictionary, expression: String) -> Control:
	var info: Dictionary = regular["regular"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(_look["card"], 3, UiKit.INK, 0, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var parts := PortraitGen.roll(int(info["portrait_seed"]), false, int(info["year"]), String(info["gender"]))
	parts["expression"] = expression
	var face := UiKit.portrait_frame(parts, 60, UiKit.INK, Color("#9fd0e8"), 2)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(UiKit.label("#%d %s" % [regular["number"], regular["name"]], 20, _look["card_text"]))
	words.add_child(UiKit.wrapped(regular["text"], 20, _look["card_text"]))
	return card


func _total(value: String, caption: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, 3, UiKit.INK, 0, 8))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	box.add_child(lines)
	var big := UiKit.label(value, 26)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(big)
	var small := UiKit.label(caption, 16, UiKit.MUTED)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(small)
	return box


## Wrapped labels measure tall before they know their width, which stretches the panel past its
## rect. Setting the size again after the first layout pass shrinks it back.
func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
	(func() -> void: node.size = rect.size).call_deferred()


## F9's faint diagonal stripes on the green room. Drawn once; nothing here moves.
class Stripes extends Control:
	var color: Color = Color.TRANSPARENT

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var step := 20.0
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0.0), color, 2.0)
			x += step
