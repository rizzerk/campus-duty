class_name ShiftTopBar
extends PanelContainer
## The green bar across the top of the window: day, clock, served, line and patience.

var _clock: Label
var _served: Label
var _line: Label
var _patience: ProgressBar
var _fill: StyleBoxFlat


func _ready() -> void:
	var style := UiKit.box(UiKit.GREEN, 0, UiKit.INK, 0, 0)
	style.border_width_bottom = 4
	style.content_margin_left = 24
	style.content_margin_right = 24
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var info := GameData.day(GameState.day)
	row.add_child(UiKit.label("REGISTRAR · WINDOW 3", 28, UiKit.GOLD))
	row.add_child(UiKit.label("Day %d · %s" % [GameState.day, info["phase"]], 20, Color("#cfe0d6")))
	row.add_child(_spacer())
	_clock = UiKit.label("8:00 AM", 34, Color("#f3efe2"))
	row.add_child(_clock)
	row.add_child(_spacer())
	_served = UiKit.label("", 20, Color("#f3efe2"))
	row.add_child(_served)
	_line = UiKit.label("", 20, Color("#f3efe2"))
	row.add_child(_line)
	row.add_child(UiKit.label("Patience", 20, Color("#f3efe2")))
	_patience = ProgressBar.new()
	_patience.custom_minimum_size = Vector2(130, 18)
	_patience.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_patience.show_percentage = false
	_patience.add_theme_stylebox_override("background", UiKit.box(UiKit.GREEN_DARK, 2, Color("#f3efe2")))
	_fill = UiKit.box(UiKit.GOLD, 0)
	_patience.add_theme_stylebox_override("fill", _fill)
	row.add_child(_patience)


func update_values(clock: String, served: int, waiting: int, patience: float) -> void:
	_clock.text = clock
	_served.text = "Served %d" % served
	_line.text = "Line %d" % waiting
	_patience.value = patience
	_fill.bg_color = UiKit.RED if patience < 30.0 else UiKit.GOLD if patience < 60.0 else Color("#6fbf73")


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer
