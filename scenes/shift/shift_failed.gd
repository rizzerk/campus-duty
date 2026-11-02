class_name ShiftFailed
extends Control
## S18: the line gave up. Ma'am Lorna takes over the window; the player can retry the same day
## or carry on to the report.

signal retry
signal carry_on


static func open(parent: Control, shift: ShiftState) -> ShiftFailed:
	var screen := ShiftFailed.new()
	parent.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen._build(shift)
	return screen


func _build(shift: ShiftState) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.11, 0.16, 0.13, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := UiKit.card(UiKit.CREAM, 24, 6)
	card.position = Vector2(290, 110)
	card.custom_minimum_size = Vector2(700, 0)
	add_child(card)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	card.add_child(list)
	list.add_child(UiKit.label("THE LINE GAVE UP", 44, UiKit.RED))
	list.add_child(UiKit.label("Line patience hit zero at %s." % shift.clock_text(), 20, UiKit.MUTED))
	var lorna := HBoxContainer.new()
	lorna.add_theme_constant_override("separation", 14)
	list.add_child(lorna)
	lorna.add_child(UiKit.portrait_frame(PortraitGen.data()["staff"]["lorna"], 96, UiKit.INK, Color("#9fd0e8"), 3))
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lorna.add_child(said)
	said.add_child(UiKit.label("Ma'am Lorna steps in", 22))
	var line: Dictionary = GameData.json("dialogue")["lorna_takes_over"][0]
	said.add_child(UiKit.wrapped("“%s”" % line["ceb"], 19))
	said.add_child(UiKit.wrapped(line["en"], 15, UiKit.MUTED))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 30)
	list.add_child(stats)
	for stat: Array in [["0", "stars today"], [str(shift.served), "served"], [str(shift.mistakes), "wrong calls"]]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.add_child(UiKit.label(stat[0], 36))
		box.add_child(UiKit.label(stat[1], 16, UiKit.MUTED))
		stats.add_child(box)
	var tips: Array = GameData.json("dialogue")["failure_tips"]
	list.add_child(UiKit.wrapped(tips[shift.day % tips.size()], 17, UiKit.GOLD_DARK))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	list.add_child(buttons)
	var again := UiKit.button("R  Retry day %d" % shift.day, UiKit.GOLD, UiKit.INK, 22)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(_once.bind(retry))
	buttons.add_child(again)
	var onward := UiKit.button("Enter  Continue anyway", UiKit.PAPER, UiKit.INK, 22)
	onward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	onward.pressed.connect(_once.bind(carry_on))
	buttons.add_child(onward)


var _chosen: bool = false


## One choice only, so a double click can't both retry and continue.
func _once(which: Signal) -> void:
	if _chosen:
		return
	_chosen = true
	which.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_R:
		_once(retry)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_once(carry_on)
