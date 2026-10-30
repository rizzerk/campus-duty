extends Control
## S1: the team pops in, the bar fills, everyone smiles, then hands off to whatever comes next.

signal finished

const DATA_PATH := "res://data/splash.json"
const PORTRAIT_SCENE := preload("res://scenes/portrait/portrait.tscn")
const FRAME_INNER := 160.0
const FRAME_BORDER := 3
const FRAME_BORDER_COLOR := Color("#e0b23a")
const FRAME_FILL := Color("#1f5a3d")
const FRAME_SHADOW := Color("#143d29")
const FRAME_SHADOW_OFFSET := 5.0
const PORTRAIT_ZOOM := 1.08
const PORTRAIT_TOP_CROP := 20.0
const NAME_COLOR := Color("#e0b23a")
const TIP_BORDER_COLOR := Color("#55604f")
const BAR_NOTCH_COLOR := Color("#1d2a22")
const BAR_NOTCH_SPACING := 18.0
const POP_SECONDS := 0.35
const POP_STAGGER := 0.15
const LOAD_SECONDS := 2.8
const SMILE_SECONDS := 0.8
const PATTERN_TILE_SIZE := 48.0
const PATTERN_DRIFT_SECONDS := 6.0

var _done: bool = false
var _members: Array[Control] = []
var _portraits: Array[Portrait] = []

@onready var _team: HBoxContainer = $Column/Team
@onready var _logo: Control = $Column/Logo
@onready var _bar: ProgressBar = $Column/Loading/Bar
@onready var _tip_box: Control = $TipBox
@onready var _pattern: Control = $Pattern


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	$Column/Studio.text = data["studio_word"]
	$Column/Presents.text = data["presents"]
	$Column/Loading/Status.text = data["loading_text"]
	var tips: Array = data["tips"]
	$TipBox/Tip.text = tips[randi() % tips.size()]
	_tip_box.draw.connect(_draw_tip_border)
	_bar.draw.connect(_draw_bar_notches)
	for member: Dictionary in PortraitGen.data()["team"]:
		_team.add_child(_make_member(member))
	_set_hidden()
	# Containers reset scale while sorting, so wait for the first layout before animating.
	await get_tree().process_frame
	_play_intro()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_finish()


func _set_hidden() -> void:
	for node: Control in _members + [_logo, $Column/Studio, $Column/Presents, $Column/Loading]:
		node.modulate.a = 0.0


func _play_intro() -> void:
	var drift := create_tween().set_loops()
	drift.tween_property(_pattern, "position", Vector2.ZERO, PATTERN_DRIFT_SECONDS).from(Vector2.ONE * -PATTERN_TILE_SIZE)
	var delay := 0.0
	for member: Control in _members:
		_pop_in(member, delay)
		delay += POP_STAGGER
	_pop_in(_logo, delay)
	delay += POP_STAGGER
	for node: Control in [$Column/Studio, $Column/Presents, $Column/Loading]:
		create_tween().tween_property(node, "modulate:a", 1.0, POP_SECONDS).set_delay(delay)
	var bar_tween := create_tween()
	bar_tween.tween_interval(delay + POP_SECONDS)
	bar_tween.tween_property(_bar, "value", 100.0, LOAD_SECONDS)
	bar_tween.tween_callback(_smile)
	bar_tween.tween_interval(SMILE_SECONDS)
	bar_tween.tween_callback(_finish)


func _pop_in(node: Control, delay: float) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * 0.6
	var tween := create_tween().set_parallel()
	tween.tween_property(node, "modulate:a", 1.0, POP_SECONDS * 0.6).set_delay(delay)
	tween.tween_property(node, "scale", Vector2.ONE, POP_SECONDS).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _smile() -> void:
	for portrait: Portrait in _portraits:
		portrait.set_expression("delighted")


## A framed portrait with a name tag under it.
func _make_member(member: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(_make_frame(member))
	var label := Label.new()
	label.text = member["name"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", NAME_COLOR)
	label.add_theme_font_size_override("font_size", 26)
	box.add_child(label)
	_members.append(box)
	return box


## A gold-framed square that crops the portrait to head and shoulders.
func _make_frame(member: Dictionary) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_FILL
	style.border_color = FRAME_BORDER_COLOR
	style.set_border_width_all(FRAME_BORDER)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2.ONE * (FRAME_INNER + FRAME_BORDER * 2)
	var shadow := ColorRect.new()
	shadow.color = FRAME_SHADOW
	shadow.show_behind_parent = true
	shadow.position = Vector2.ONE * FRAME_SHADOW_OFFSET
	shadow.size = frame.custom_minimum_size
	frame.add_child(shadow)
	var crop := Control.new()
	crop.clip_contents = true
	crop.position = Vector2.ONE * FRAME_BORDER
	crop.size = Vector2.ONE * FRAME_INNER
	frame.add_child(crop)
	var portrait: Portrait = PORTRAIT_SCENE.instantiate()
	crop.add_child(portrait)
	portrait.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var width := FRAME_INNER * PORTRAIT_ZOOM
	portrait.position = Vector2((FRAME_INNER - width) / 2.0, -PORTRAIT_TOP_CROP)
	portrait.size = Vector2(width, width * 1228.0 / 1024.0)
	portrait.apply(member.duplicate(true))
	_portraits.append(portrait)
	return frame


func _draw_tip_border() -> void:
	var r := Rect2(Vector2.ONE, _tip_box.size - Vector2.ONE * 2)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in corners.size():
		_tip_box.draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], TIP_BORDER_COLOR, 2.0, 6.0)


func _draw_bar_notches() -> void:
	var x := BAR_NOTCH_SPACING
	while x < _bar.size.x:
		_bar.draw_line(Vector2(x, 2), Vector2(x, _bar.size.y - 2), BAR_NOTCH_COLOR, 2.0)
		x += BAR_NOTCH_SPACING


func _finish() -> void:
	if not _done:
		_done = true
		finished.emit()
