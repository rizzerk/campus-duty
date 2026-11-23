class_name ShiftTopBar
extends PanelContainer
## The green bar across the top of the window: day, clock, served, line and patience. Under a
## quarter of the starting patience, the bar beats like a heart. A run of right calls shows an
## in-the-zone badge beside the counts.

## Share of the starting patience under which the bar starts to beat.
const LOW_PATIENCE := 0.25
## The badge's color per in-the-zone tier (1, 2, 3), so each tier looks different. A pale border
## keeps even the darkest one clear of the green bar.
const ZONE_COLORS := [UiKit.GOLD_DARK, UiKit.GOLD, UiKit.OK_BRIGHT]
const ZONE_TEXT := [UiKit.PAPER, UiKit.INK, UiKit.INK]

var _clock: Label
var _served: Label
var _line: Label
var _patience: ProgressBar
var _fill: StyleBoxFlat
## True while patience is under LOW_PATIENCE of the start and the bar's heartbeat is on.
var _beating: bool = false
var _low_line: float = 0.0
## The in-the-zone badge, inside a fixed slot so it can pop and drop without moving the row.
var _zone: Label
var _zone_style: StyleBoxFlat


func _ready() -> void:
	_low_line = float(GameData.balance("patience_start")) * LOW_PATIENCE
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
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(104, 30)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slot)
	_zone = UiKit.label("", 20, UiKit.INK)
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zone.size = slot.custom_minimum_size
	_zone_style = UiKit.box(UiKit.GOLD, 2, UiKit.GOLD_PALE)
	_zone.add_theme_stylebox_override("normal", _zone_style)
	_zone.tooltip_text = "In the zone: right calls in a row. The line is a little calmer while it lasts. A wrong call or a favor ends it."
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone.modulate.a = 0.0
	slot.add_child(_zone)
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
	_fill.bg_color = UiKit.RED if patience < 30.0 else UiKit.GOLD if patience < 60.0 else UiKit.OK_BRIGHT
	var low := patience < _low_line
	if low != _beating:
		_beating = low
		if low:
			Juice.heartbeat(_patience, 1.0, func() -> void: Sfx.play("heartbeat", 0.0))
		else:
			Juice.stop_heartbeat(_patience)


## Shows the run on the in-the-zone badge from the first tier; below it the badge stays hidden
## (drop_streak hides it again when a run breaks).
func set_streak(streak: int, tier: int) -> void:
	if tier <= 0:
		return
	Juice.cancel_drop(_zone)
	_zone.text = "ZONE ×%d" % streak
	_zone_style.bg_color = ZONE_COLORS[clampi(tier, 1, ZONE_COLORS.size()) - 1]
	_zone.add_theme_color_override("font_color", ZONE_TEXT[clampi(tier, 1, ZONE_TEXT.size()) - 1])
	_zone.modulate.a = 1.0
	_zone.mouse_filter = Control.MOUSE_FILTER_PASS


## The run broke: the badge falls away (only fades with reduced motion).
func drop_streak() -> void:
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _zone.modulate.a > 0.0:
		Juice.drop_out(_zone)


## The in-the-zone badge, for the window's pop effects.
func zone_badge() -> Control:
	return _zone


## The patience bar, for effects that show what a mistake cost.
func patience_bar() -> Control:
	return _patience


## Stops the heartbeat, say when the shift is over.
func calm() -> void:
	_beating = false
	Juice.stop_heartbeat(_patience)


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer
