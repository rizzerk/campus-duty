extends Control
## The Freedom Wall: after each day's report, 3 to 6 student posts about Window 3, picked by
## FreedomWall from what happened today. Bisaya first, English under it, and a reaction count.
## Regulars post under their own name and face. Enter, Space or the button goes on to the next
## day, or to the end-of-season evaluation after the last one. Text lives in
## data/freedom_wall.json.

## The green band with the title and the way on, then the cork board the posts are pinned to.
const BAND := Rect2(0, 0, 1280, 104)
const BOARD := Rect2(36, 112, 1208, 596)
const NOTE_WIDTH := 548
const NOTE_GAP := Vector2(28, 12)
const FRAME := 8
const CORK := Color("#b98a5a")
const WOOD := Color("#6b4a2b")
const PIN_COLORS := [Color("#b8382a"), Color("#3b6ea5"), Color("#e0b23a"), Color("#2f7d46")]
## Seconds between one note fading in and the next. A fade, not motion, so reduced motion keeps it.
const STAGGER := 0.12
## Keys are ignored this long after the wall opens, so a double tap on the report can't skip it.
const KEY_GRACE_MS := 400

var _text: Dictionary = {}
var _leaving: bool = false
var _next: Button
var _opened_ms: int = 0


func _ready() -> void:
	# Opened on its own (say, with F6 in the editor) there's no day to post about.
	if GameState.last_summary.is_empty():
		GameState.go_to("calendar")
		return
	Sfx.play_bgm("menu")
	_text = GameData.json("freedom_wall")["screen"]
	var day: int = GameState.day
	_opened_ms = Time.get_ticks_msec()
	var room := ColorRect.new()
	room.color = UiKit.GREEN
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(room)
	_place(_band(day), BAND)
	var cork := Cork.new()
	cork.cork = CORK
	cork.wood = WOOD
	cork.frame = FRAME
	_place(cork, BOARD)
	# The notes, centred across and down the board, so a quiet day looks pinned up on purpose.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var top_gap := Control.new()
	top_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(top_gap)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", int(NOTE_GAP.x))
	flow.add_theme_constant_override("v_separation", int(NOTE_GAP.y))
	column.add_child(flow)
	var bottom_gap := Control.new()
	bottom_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom_gap)
	var inside := BOARD.grow(-FRAME - 10)
	_place(column, inside)
	# The notes measure tall until their text knows its width, which stretches the column far
	# below the board. Each time they settle on a new height, fit the column back to the board.
	flow.minimum_size_changed.connect(func() -> void: column.size = inside.size)
	var regulars := _regulars_by_id()
	var posts := FreedomWall.posts(GameState.last_summary, GameState.last_history, day, FreedomWall.seed_for(GameState.base_seed, day))
	for i in posts.size():
		var note := _pinned(_card(posts[i], regulars), i)
		flow.add_child(note)
		note.modulate.a = 0.0
		note.create_tween().tween_property(note, "modulate:a", 1.0, 0.2).set_delay(0.15 + i * STAGGER)
	Sfx.play("paper_slide")
	if OS.is_debug_build():
		_report_layout.call_deferred(flow)


func _unhandled_key_input(event: InputEvent) -> void:
	# Ignore key repeats, so the Enter held from the report can't skip the wall.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if Time.get_ticks_msec() - _opened_ms < KEY_GRACE_MS:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _next != null:
		# Through the button, so a key press looks and sounds the same as a click.
		_next.pressed.emit()


## Only once, so a double click can't skip a day.
func _continue() -> void:
	if _leaving:
		return
	_leaving = true
	if GameState.is_last_day():
		GameState.go_to("evaluation")
	else:
		GameState.next_day()


## The green band: the title and today's subtitle on the left, the way on at the right.
func _band(day: int) -> Control:
	var band := PanelContainer.new()
	var style := UiKit.box(UiKit.GREEN, 0, UiKit.INK, 0, 0)
	style.content_margin_left = 60
	style.content_margin_right = 36
	band.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	band.add_child(row)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	var title := UiKit.label(_text["title"], 44, UiKit.GOLD)
	title.add_theme_color_override("font_shadow_color", UiKit.INK)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	head.add_child(title)
	head.add_child(UiKit.label(String(_text["subtitle"]).format({ "day": day }), 20, Color("#cfe0d6")))
	_next = UiKit.button(_text["evaluation"] if GameState.is_last_day() else _text["next_day"], UiKit.GOLD, UiKit.INK, 24)
	_next.custom_minimum_size = Vector2(320, 60)
	_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next.pressed.connect(_continue)
	row.add_child(_next)
	return band


## A note pinned to the board: tilted a little one way or the other, with a coloured pin on top.
## Containers reset rotation, so the note sits in a plain holder that takes its size.
func _pinned(card: Control, index: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = NOTE_WIDTH
	holder.add_child(card)
	card.rotation_degrees = [-1.2, 0.9, 0.6, -0.8, 1.1, -0.5][index % 6]
	var pin := Pin.new()
	pin.color = PIN_COLORS[index % PIN_COLORS.size()]
	holder.add_child(pin)
	card.resized.connect(func() -> void:
		card.pivot_offset = card.size / 2.0
		holder.custom_minimum_size = card.size
		pin.position = Vector2(card.size.x / 2.0 - pin.size.x / 2.0, -6.0))
	return holder


## One post: who posted it (a regular's face and name, or an anonymous tag), the Bisaya, the
## English under it, and how many reactions it got.
func _card(post: Dictionary, regulars: Dictionary) -> Control:
	var card := UiKit.card(UiKit.CREAM, 12, 4, 3)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	card.add_child(lines)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	lines.add_child(head)
	var regular: Dictionary = regulars.get(post["author"], {})
	var name_text: String = _text["anonymous"]
	if regular.is_empty():
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UiKit.box(UiKit.SOFT, 2, UiKit.INK, 0, 0))
		badge.custom_minimum_size = Vector2(36, 36)
		var mark := UiKit.label("?", 24, UiKit.INK)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(mark)
		head.add_child(badge)
	else:
		var parts := PortraitGen.roll(int(regular["portrait_seed"]), false, int(regular["year"]), String(regular["gender"]))
		parts["expression"] = "nervous" if String(post["when"]).ends_with("_bad") else "happy"
		head.add_child(UiKit.portrait_frame(parts, 32, UiKit.INK, Color("#9fd0e8"), 2))
		name_text = "#%d %s" % [int(regular["number"]), regular["name"]]
	var who := UiKit.label(name_text, 20, UiKit.INK)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(who)
	var likes := UiKit.label(String(_text["reactions"]).format({ "likes": post["likes"] }), 18, UiKit.MUTED)
	likes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(likes)
	lines.add_child(UiKit.wrapped(post["ceb"], 20, UiKit.INK))
	lines.add_child(UiKit.wrapped(post["en"], 20, UiKit.MUTED))
	return card


## Debug builds only: once the notes have settled, says how many sit inside the board, so
## tests/smoke.sh fails if a layout change pushes them off it.
func _report_layout(flow: Control) -> void:
	for i in 3:
		await get_tree().process_frame
	var notes := flow.get_children()
	var inside := notes.filter(func(note: Control) -> bool: return BOARD.encloses(note.get_global_rect()))
	print("freedom_wall: %d/%d notes on the board" % [inside.size(), notes.size()])


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	node.position = rect.position
	node.size = rect.size
	# Wrapped labels measure tall before they know their width; set the size again once laid out.
	(func() -> void: node.size = rect.size).call_deferred()


## events.json regulars by id, for the posts they write themselves.
static func _regulars_by_id() -> Dictionary:
	var by_id := {}
	for regular: Dictionary in GameData.json("events")["regulars"]:
		by_id[String(regular["id"])] = regular
	return by_id


## The cork board: a wooden frame round a cork face with darker and lighter flecks. Drawn once.
class Cork extends Control:
	var cork: Color
	var wood: Color
	var frame: int = 8

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2(6, 6), size), UiKit.INK)
		draw_rect(Rect2(Vector2.ZERO, size), wood)
		var face := Rect2(Vector2.ONE * frame, size - Vector2.ONE * frame * 2)
		draw_rect(face, cork)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2026
		for i in 900:
			var at := face.position + Vector2(rng.randf() * (face.size.x - 3), rng.randf() * (face.size.y - 3))
			draw_rect(Rect2(at, Vector2(2, 2) * rng.randi_range(1, 2)), cork.darkened(0.22) if i % 3 else cork.lightened(0.18))


## A round pushpin with a highlight.
class Pin extends Control:
	var color: Color

	func _ready() -> void:
		custom_minimum_size = Vector2(16, 16)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(9, 9), 7.0, UiKit.INK)
		draw_circle(Vector2(8, 8), 7.0, color)
		draw_circle(Vector2(6, 6), 2.0, color.lightened(0.5))
