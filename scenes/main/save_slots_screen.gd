class_name SaveSlotsScreen
extends Control
## S2: the save slots, opened from the title's New season. A card shows a season in progress (day,
## phase, stars, season accuracy, when it was saved) with Load, an empty slot with New season, or a
## save that can't be read, which can only be deleted. Keys: the slot's number or the arrows choose
## a slot, Enter plays it, Delete twice deletes it (the card turns red while it waits), Esc goes
## back. The screen only reads and deletes saves; the title starts or loads the season when it
## hears a request. Text lives in data/saves.json.

signal load_requested(slot: int)
signal new_requested(slot: int)
signal closed

const CONFIRM_SECONDS := 3.0
const CARD_HEIGHT := 128.0
const BADGE_SIZE := 88.0
const PLAY_WIDTH := 170.0
## Wide enough for "Del again to delete slot N", so the key line doesn't jump when it asks.
const DELETE_WIDTH := 220.0
## Space around the layout: left and right, top and bottom.
const MARGIN := Vector2(120, 36)
const HINT_WIDTH := 600.0
const BORDER := 4
const SELECTED_BORDER := 6
## A card under the mouse, between its normal look and selected.
const HOVER_CREAM := Color("#fdf8e6")
const HOVER_EMPTY := Color(1, 1, 1, 0.35)

var _text: Dictionary
var _entries: Array = []
var _selected: int = 1
var _confirming: bool = false
## Set once a slot is played, so a double click can't start or load twice.
var _chosen: bool = false
var _layout: VBoxContainer
var _cards: VBoxContainer
## The slot under the mouse, 0 for none.
var _hovered: int = 0
var _hint: Label
## slot -> its card, number label, badge (none for an empty slot) and play button (none for a
## damaged save).
var _card_nodes: Dictionary = {}
var _numbers: Dictionary = {}
var _badges: Dictionary = {}
var _play_buttons: Dictionary = {}
var _back_button: Button
var _delete_button: Button
var _confirm_timer: Timer


## Opens the slots over `parent`, covering the whole 1280x720 screen.
static func open(parent: Node) -> SaveSlotsScreen:
	var screen := SaveSlotsScreen.new()
	# Sized before it joins the tree, so _ready lays the slots out on the full screen.
	screen.position = Vector2.ZERO
	screen.size = Vector2(1280, 720)
	parent.add_child(screen)
	return screen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_text = GameData.json("saves")
	var wall := ColorRect.new()
	wall.color = UiKit.MINT
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	# Anchored rather than sized by hand: a container sized by hand grows with a wrapped label
	# measured before it had a width, and never shrinks back.
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 18)
	add_child(_layout)
	_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout.offset_left = MARGIN.x
	_layout.offset_right = -MARGIN.x
	_layout.offset_top = MARGIN.y
	_layout.offset_bottom = -MARGIN.y
	var head := HBoxContainer.new()
	_layout.add_child(head)
	var title := UiKit.label(_text["heading"], 44, UiKit.GREEN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_hint = UiKit.label(_text["hint"], 20, UiKit.MUTED)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_hint)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 18)
	_layout.add_child(_cards)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(gap)
	_layout.add_child(_footer())
	_confirm_timer = Timer.new()
	_confirm_timer.one_shot = true
	_confirm_timer.timeout.connect(_cancel_confirm)
	add_child(_confirm_timer)
	_entries = SaveSlots.all()
	_selected = _default_slot()
	_build_cards()
	Juice.slide_in(_layout, Vector2(0, 24), 0.3)


func _unhandled_key_input(event: InputEvent) -> void:
	# Ignore key repeats, so a held Enter from the title can't play a slot straight away.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key: Key = event.keycode
	if key >= KEY_1 and key < KEY_1 + SaveSlots.SLOTS:
		_select(key - KEY_1 + 1)
	elif key >= KEY_KP_1 and key < KEY_KP_1 + SaveSlots.SLOTS:
		_select(key - KEY_KP_1 + 1)
	elif key in [KEY_UP, KEY_W]:
		_select(wrapi(_selected - 1, 1, SaveSlots.SLOTS + 1))
	elif key in [KEY_DOWN, KEY_S]:
		_select(wrapi(_selected + 1, 1, SaveSlots.SLOTS + 1))
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_press_selected()
	elif key in [KEY_DELETE, KEY_BACKSPACE]:
		# Through the button, so a key press looks and sounds the same as a click.
		if not _delete_button.disabled:
			_delete_button.pressed.emit()
	elif key == KEY_ESCAPE:
		if _confirming:
			Sfx.play("click")
			_cancel_confirm()
		else:
			_back_button.pressed.emit()


func close_screen() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## The slot that starts selected: the player came for a new season, so the first empty slot, else
## the save played last, else slot 1.
func _default_slot() -> int:
	var empty := _first_empty()
	if empty > 0:
		return empty
	var latest := SaveSlots.latest(_entries)
	return latest if latest > 0 else 1


func _first_empty() -> int:
	for entry: Dictionary in _entries:
		if entry["state"] == SaveSlots.STATE_EMPTY:
			return int(entry["slot"])
	return 0


func _entry(slot: int) -> Dictionary:
	return _entries[slot - 1]


func _build_cards() -> void:
	UiKit.clear(_cards)
	_card_nodes.clear()
	_numbers.clear()
	_badges.clear()
	_play_buttons.clear()
	_hovered = 0
	for entry: Dictionary in _entries:
		_cards.add_child(_card(entry))
	# With every slot taken, say how to make room for a new season, in ink so it stands out.
	var full := _first_empty() == 0
	_hint.text = _text["hint_full"] if full else _text["hint"]
	_hint.add_theme_color_override("font_color", UiKit.INK if full else UiKit.MUTED)
	_restyle()


func _card(entry: Dictionary) -> PanelContainer:
	var slot: int = entry["slot"]
	var state: String = entry["state"]
	var card := PanelContainer.new()
	card.custom_minimum_size.y = CARD_HEIGHT
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select(slot))
	card.mouse_entered.connect(_hover.bind(slot, true))
	card.mouse_exited.connect(_hover.bind(slot, false))
	_card_nodes[slot] = card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var number := UiKit.label(str(slot), 30, UiKit.MUTED)
	number.custom_minimum_size.x = 30
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number)
	_numbers[slot] = number
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match state:
		SaveSlots.STATE_OK:
			var save: Dictionary = entry["save"]
			var facts := SaveSlots.overview(save)
			_badges[slot] = _badge(_text["badge_done"] if facts["complete"] else _text["badge_day"], str(facts["day"]), UiKit.GOLD if facts["complete"] else UiKit.GREEN, UiKit.INK if facts["complete"] else UiKit.PAPER)
			row.add_child(_badges[slot])
			row.add_child(info)
			var heading: String = _text["complete_line"].format(facts) if facts["complete"] else _text["day_line"].format(facts)
			info.add_child(UiKit.label(heading, 24))
			info.add_child(UiKit.label(_text["progress"].format(facts) if facts["played"] > 0 else _text["progress_none"], 20))
			var saved := _saved_text(int(save["saved_at"]))
			if saved != "":
				info.add_child(UiKit.label(saved, 20, UiKit.MUTED))
			row.add_child(_play_button(slot, _text["load"], UiKit.GREEN, UiKit.PAPER))
		SaveSlots.STATE_DAMAGED:
			_badges[slot] = _badge("", "!", UiKit.RED_PALE, UiKit.RED)
			row.add_child(_badges[slot])
			row.add_child(info)
			info.add_child(UiKit.label(_text["damaged_title"], 24, UiKit.RED))
			var hint := UiKit.wrapped(_text["damaged_hint"], 20, UiKit.MUTED)
			hint.custom_minimum_size.x = HINT_WIDTH
			info.add_child(hint)
		_:
			row.add_child(info)
			info.add_child(UiKit.label(_text["empty_title"], 24, UiKit.INK))
			info.add_child(UiKit.label(_text["empty_hint"], 20, UiKit.MUTED))
			row.add_child(_play_button(slot, _text["new_season"], UiKit.GOLD, UiKit.INK))
	return card


## The square on a card: a small word over a big one ("DAY" over 7), like a desk calendar page.
func _badge(top: String, big: String, bg: Color, fg: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.box(bg, 3, UiKit.INK))
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", -6)
	badge.add_child(lines)
	if top != "":
		var small := UiKit.label(top, 20, fg)
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lines.add_child(small)
	var large := UiKit.label(big, 48, fg)
	large.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(large)
	return badge


func _play_button(slot: int, text: String, bg: Color, fg: Color) -> Button:
	var button := UiKit.button(text, bg, fg, 22)
	button.custom_minimum_size = Vector2(PLAY_WIDTH, 52)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_play.bind(slot))
	_play_buttons[slot] = button
	return button


func _footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	_back_button = UiKit.button(_text["back"], UiKit.PAPER, UiKit.INK, 22)
	_back_button.pressed.connect(close_screen)
	footer.add_child(_back_button)
	var keys := UiKit.label(String(_text["keys"]).format({ "slots": SaveSlots.SLOTS }), 20, UiKit.MUTED)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(keys)
	_delete_button = UiKit.button(_text["delete"], UiKit.RED, UiKit.PAPER, 20)
	_delete_button.custom_minimum_size.x = DELETE_WIDTH
	_delete_button.pressed.connect(_delete)
	footer.add_child(_delete_button)
	return footer


## The selected card is pale gold with a thicker green border and a green number, or pale red
## while a delete waits for its second press. Empty slots have no fill; the card under the mouse
## is tinted.
func _restyle() -> void:
	for entry: Dictionary in _entries:
		var slot: int = entry["slot"]
		var selected := slot == _selected
		var empty: bool = entry["state"] == SaveSlots.STATE_EMPTY
		var bg := Color(0, 0, 0, 0) if empty else UiKit.CREAM
		var border := UiKit.MUTED if empty else UiKit.INK
		if selected and _confirming:
			bg = UiKit.RED_PALE
			border = UiKit.RED
		elif selected:
			bg = UiKit.GOLD_PALE
			border = UiKit.GREEN
		elif slot == _hovered:
			bg = HOVER_EMPTY if empty else HOVER_CREAM
			border = UiKit.GREEN
		var style := UiKit.box(bg, SELECTED_BORDER if selected else BORDER, border, 0 if empty and not selected else 5, 16)
		(_card_nodes[slot] as PanelContainer).add_theme_stylebox_override("panel", style)
		(_numbers[slot] as Label).add_theme_color_override("font_color", border if selected else UiKit.MUTED)
	_delete_button.disabled = _entry(_selected)["state"] == SaveSlots.STATE_EMPTY


func _hover(slot: int, inside: bool) -> void:
	if inside:
		_hovered = slot
	elif _hovered == slot:
		_hovered = 0
	_restyle()


func _select(slot: int) -> void:
	if not SaveSlots.valid_slot(slot) or slot == _selected or _chosen:
		return
	_selected = slot
	_cancel_confirm()
	_restyle()
	Sfx.play("click")
	Juice.punch(_card_nodes[slot], 1.02)


## Enter: the selected slot's button, or a shake and a red flash of its "!" for a save that can't
## be played (the badge, not the text the player is reading; the flash stays with reduced motion).
func _press_selected() -> void:
	if _play_buttons.has(_selected):
		(_play_buttons[_selected] as Button).pressed.emit()
	else:
		Sfx.play("wrong")
		Juice.shake(_badges[_selected], 5.0)
		Juice.flash(_badges[_selected], UiKit.RED)


func _play(slot: int) -> void:
	if _chosen:
		return
	_chosen = true
	_cancel_confirm()
	if _entry(slot)["state"] == SaveSlots.STATE_OK:
		load_requested.emit(slot)
	else:
		new_requested.emit(slot)


## First press asks, a second within CONFIRM_SECONDS deletes.
func _delete() -> void:
	if _chosen or _entry(_selected)["state"] == SaveSlots.STATE_EMPTY:
		return
	if not _confirming:
		_confirming = true
		_delete_button.text = String(_text["confirm_delete"]).format({ "slot": _selected })
		_restyle()
		Sfx.play("alert")
		Juice.punch(_delete_button, 1.08)
		_confirm_timer.start(CONFIRM_SECONDS)
		return
	var card: Control = _card_nodes[_selected]
	var at := card.get_global_rect().get_center() - get_global_rect().position
	var deleted := SaveSlots.delete(_selected)
	_cancel_confirm()
	_entries[_selected - 1] = SaveSlots.read(_selected)
	_build_cards()
	Sfx.play("paper_slide" if deleted else "wrong")
	Juice.pop_text(self, String(_text["deleted" if deleted else "delete_failed"]).format({ "slot": _selected }),
			UiKit.GOLD if deleted else UiKit.RED_BRIGHT, at)


func _cancel_confirm() -> void:
	var was_confirming := _confirming
	_confirming = false
	if _confirm_timer != null:
		_confirm_timer.stop()
	if _delete_button != null:
		_delete_button.text = _text["delete"]
	if was_confirming and not _card_nodes.is_empty():
		_restyle()


## "Saved today", "Saved yesterday" or "Saved 3 days ago", in the player's time zone. Empty when
## the save has no time.
func _saved_text(saved_at: int) -> String:
	if saved_at <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var days := SaveSlots.days_ago(saved_at, int(Time.get_unix_time_from_system()), bias)
	if days == 0:
		return _text["saved_today"]
	if days == 1:
		return _text["saved_yesterday"]
	return String(_text["saved_days_ago"]).format({ "days": days })
