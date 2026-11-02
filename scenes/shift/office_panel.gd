class_name OfficePanel
extends PanelContainer
## Live status of the other offices and the three-seat hold bench.

const BADGES := {
	"open": ["OPEN", UiKit.OK],
	"long_line": ["LONG LINE", Color("#c9761e")],
	"break": ["BREAK", UiKit.GOLD_DARK],
	"closed": ["CLOSED", UiKit.MUTED],
}

var _list: VBoxContainer
var _bench: HBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, 4, UiKit.INK, 5, 12))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)
	layout.add_child(UiKit.label("Other offices · live", 22))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	layout.add_child(_list)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	layout.add_child(UiKit.label("Hold bench", 22))
	_bench = HBoxContainer.new()
	_bench.add_theme_constant_override("separation", 8)
	layout.add_child(_bench)


## notes: office -> a short live note, like "Back at 11:00".
func refresh(offices: Dictionary, bench: Array, notes: Dictionary = {}) -> void:
	UiKit.clear(_list)
	for office: String in offices:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		entry.add_child(row)
		row.add_child(UiKit.label(GameData.json("offices")[office]["name"], 19))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var badge: Array = BADGES[offices[office]["status"]]
		var tag := UiKit.label(badge[0], 15, Color.WHITE)
		tag.add_theme_stylebox_override("normal", UiKit.box(badge[1], 2, UiKit.INK, 0, 3))
		row.add_child(tag)
		if notes.has(office):
			entry.add_child(UiKit.label(notes[office], 15, UiKit.MUTED))
		_list.add_child(entry)
	UiKit.clear(_bench)
	for seat in ShiftState.BENCH_SEATS:
		if seat < bench.size():
			_bench.add_child(UiKit.portrait_frame(bench[seat]["portrait"], 56, UiKit.INK, Color("#9fd0e8"), 2))
		else:
			var empty := UiKit.label("free", 16, UiKit.MUTED)
			empty.custom_minimum_size = Vector2(60, 60)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.add_theme_stylebox_override("normal", UiKit.box(UiKit.MINT, 2, UiKit.SOFT))
			_bench.add_child(empty)
