extends Control
## F4, the window: runs one shift. Students come up, the player scans their ID, flags mismatches
## between the papers and ISMIS, stamps a decision (keys 1-5) and hands the papers back (Space).

const ACTIONS := [
	{ "id": "approve", "text": "1  Approve", "color": UiKit.OK, "fg": Color.WHITE },
	{ "id": "fix", "text": "2  Fix", "color": UiKit.PAPER, "fg": UiKit.INK },
	{ "id": "route", "text": "3  Route", "color": UiKit.PAPER, "fg": UiKit.INK },
	{ "id": "hold", "text": "4  Hold", "color": UiKit.PAPER, "fg": UiKit.INK },
	{ "id": "reject", "text": "5  Turn away", "color": UiKit.RED, "fg": Color.WHITE },
]
## What each stamp says on the paper. Turn-away stamps come from data/reject_reasons.json.
const STAMPS := {
	"approve": ["APPROVED", UiKit.OK],
	"fix": ["FIXED", UiKit.BLUE],
	"hold": ["HOLD", UiKit.GOLD_DARK],
	"route": ["ROUTED", UiKit.BLUE],
}
const HAND_BACK_SECONDS := 0.3
const REACT_SECONDS := 1.6
const CALL_DELAY := 0.5
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const KEYPAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5]

var shift: ShiftState

var _top_bar: ShiftTopBar
var _line_strip: LineStrip
var _student_panel: StudentPanel
var _ismis: IsmisScreen
var _offices: OfficePanel
var _buttons: Dictionary = {}
var _rects: Dictionary = {}
var _selection: Dictionary = {}
## Flag results that stay highlighted while the player keeps clicking around.
var _marks: Dictionary = {}
var _flags: Array = []
var _react_left: float = 0.0
var _call_left: float = 0.0
var _patience_band: int = 2
var _unlocked: Array = []
var _rng := RandomNumberGenerator.new()
## The stamped decision waiting to be handed back: { action, reason, items }.
var _pending: Dictionary = {}
var _stamp: StampMark
## The open popup (a ChoiceMenu or the SectionPicker), which takes the keyboard while it's up.
var _menu: Control
var _handing: bool = false
var _hand_back_button: Button


func _ready() -> void:
	_rng.seed = GameState.base_seed + GameState.day
	_unlocked = GameState.unlocked_actions()
	shift = ShiftState.new(GameState.day, GameState.base_seed)
	_build()
	shift.student_joined_line.connect(func(_s: Dictionary) -> void: _refresh_line())
	shift.bench_changed.connect(_refresh_offices)
	shift.office_changed.connect(func(_o: String, _status: String) -> void: _refresh_offices())
	shift.shift_ended.connect(_on_shift_ended)
	shift.rush_arrived.connect(func(count: int) -> void: _line_strip.flash("RUSH! %d more students just joined the line" % count))
	_refresh_line()
	_refresh_offices()
	_call_left = CALL_DELAY


func _process(delta: float) -> void:
	if shift.ended:
		return
	shift.tick(delta)
	if shift.ended:
		return
	_top_bar.update_values(shift.clock_text(), shift.served, shift.line.size(), shift.patience)
	var band := 0 if shift.patience < 40.0 else 1 if shift.patience < 70.0 else 2
	if band != _patience_band:
		_patience_band = band
		_refresh_line()
	if _react_left > 0.0:
		_react_left -= delta
		if _react_left <= 0.0:
			_student_panel.clear_student()
			_call_left = CALL_DELAY
			_update_buttons()
		return
	if shift.current.is_empty():
		_call_left -= delta
		if _call_left <= 0.0:
			_call_next()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _menu != null or _ismis.is_typing():
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_hand_back()
		return
	if event.keycode == KEY_BACKSPACE:
		_lift_stamp()
		return
	if event.keycode == KEY_S:
		_ismis.scan()
		return
	if event.keycode == KEY_A:
		_ask()
		return
	var index := NUMBER_KEYS.find(event.keycode)
	if index == -1:
		index = KEYPAD_KEYS.find(event.keycode)
	if index != -1:
		_on_action(ACTIONS[index]["id"])


func _build() -> void:
	var wall := ColorRect.new()
	wall.color = UiKit.MINT
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	_top_bar = ShiftTopBar.new()
	_place(_top_bar, Rect2(0, 0, 1280, 64))
	_line_strip = LineStrip.new()
	_place(_line_strip, Rect2(24, 72, 1232, 96))
	_line_strip.face_clicked.connect(_on_face_clicked)
	_student_panel = StudentPanel.new()
	_place(_student_panel, Rect2(24, 176, 494, 440))
	_student_panel.paper_field_clicked.connect(_on_paper_field)
	_ismis = IsmisScreen.new()
	_place(_ismis, Rect2(532, 176, 478, 440))
	_ismis.record_field_clicked.connect(_on_record_field)
	_ismis.ask_pressed.connect(_ask)
	_offices = OfficePanel.new()
	_place(_offices, Rect2(1024, 176, 232, 440))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	_place(bar, Rect2(24, 632, 1232, 64))
	for action: Dictionary in ACTIONS:
		var button := UiKit.button(action["text"], action["color"], action["fg"], 22)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action.bind(action["id"]))
		bar.add_child(button)
		_buttons[action["id"]] = button
	_hand_back_button = UiKit.button("Space  Hand back", UiKit.GOLD, UiKit.INK, 22)
	_hand_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_back_button.size_flags_stretch_ratio = 1.3
	_hand_back_button.pressed.connect(_hand_back)
	bar.add_child(_hand_back_button)
	_update_buttons()
	_fix_sizes.call_deferred()


func _place(node: Control, rect: Rect2) -> void:
	add_child(node)
	_rects[node] = rect
	node.position = rect.position
	node.size = rect.size


## Wrapped labels can briefly ask for a huge height before they know their width, and a Control
## never shrinks back on its own. Re-applying the layout rectangles undoes that.
func _fix_sizes() -> void:
	for node: Control in _rects:
		node.size = _rects[node].size
		node.position = _rects[node].position


func _update_buttons() -> void:
	var busy := shift.ended or shift.current.is_empty() or _react_left > 0.0 or _menu != null or _handing
	_hand_back_button.disabled = busy or _pending.is_empty()
	for id: String in _buttons:
		var button: Button = _buttons[id]
		var unlocked: bool = _unlocked.has(id)
		button.disabled = busy or not unlocked
		button.tooltip_text = "" if unlocked else "You'll learn this on a later day."
		if unlocked and id == "hold" and shift.bench_full():
			button.disabled = true
			button.tooltip_text = "The bench is full."


func _call_next() -> void:
	var student := shift.call_next()
	if student.is_empty():
		return
	_selection = {}
	_marks.clear()
	_flags.clear()
	_clear_stamp()
	_student_panel.show_student(student)
	_ismis.show_student(student)
	var mood: String = student.get("mood", "calm")
	var trip: Dictionary = student.get("trip", {})
	if trip.get("wrong", false):
		_student_panel.set_expression("angry")
		_student_panel.say(_pick_line(GameData.json("dialogue")["wrong_office"]["closed" if trip["closed"] else trip["office"]]))
	elif mood == "angry":
		_student_panel.set_expression("angry")
		_student_panel.say(_reaction("returned_angry"))
	elif trip.get("office", "") != "":
		_student_panel.set_expression("happy")
		_student_panel.say(_pick_line(GameData.json("dialogue")["returned_from"][trip["office"]]))
	elif student.get("returning", false):
		_student_panel.say(_reaction("returned"))
	_refresh_line()
	_update_buttons()
	_fix_sizes.call_deferred()


func _on_face_clicked(index: int) -> void:
	if shift.call_out_of_turn(index):
		_refresh_line()
		_ismis.show_banner("Called a priority student to the front of the line.", "")


## Picking a stamp. Nothing is judged until the papers are handed back.
func _on_action(action: String) -> void:
	if shift.ended or shift.current.is_empty() or _react_left > 0.0 or _handing or _menu != null:
		return
	if not _unlocked.has(action):
		return
	if action == "hold" and shift.bench_full():
		return
	if action == "reject":
		_open_reject_menu()
		return
	if action == "fix" and shift.current["request"].has("course"):
		_open_section_picker()
		return
	if action == "route":
		_open_route_menu()
		return
	_set_pending({ "action": action, "reason": "", "items": [] }, STAMPS[action][0], STAMPS[action][1])


## F5: the section picker. Seats can drain while it's open on open market day.
func _open_section_picker() -> void:
	var picker := SectionPicker.open(self, shift.current, not GameData.day(shift.day).get("live_slots", {}).is_empty())
	_menu = picker
	shift.choosing_section = true
	picker.chosen.connect(func(code: String) -> void:
		_menu = null
		shift.choosing_section = false
		_set_pending({ "action": "fix", "reason": "", "items": [], "section": code }, "ENROLLED · %s" % code.get_slice("-", 1), UiKit.BLUE))
	picker.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


## Where to send them. Each office shows its live status, since a closed office is a wasted trip.
func _open_route_menu() -> void:
	var options: Array = []
	var live := shift.offices()
	for office: String in GameData.json("offices"):
		var badge: Array = OfficePanel.BADGES[live[office]["status"]]
		options.append({
			"id": office,
			"label": "%s · %s · %s" % [GameData.json("offices")[office]["name"], badge[0], OfficeSchedule.detail(shift.day, office, shift.minute)],
		})
	_menu = ChoiceMenu.open(self, "Send them to which office?", options)
	_menu.chosen.connect(func(ids: Array) -> void:
		_menu = null
		var office_name: String = GameData.json("offices")[ids[0]]["name"]
		_set_pending({ "action": "route:" + ids[0], "reason": "", "items": [] }, "TO %s" % office_name.to_upper(), STAMPS["route"][1]))
	_menu.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


func _open_reject_menu() -> void:
	var options: Array = []
	for reason: String in GameState.unlocked_reject_reasons():
		options.append({ "id": reason, "label": GameData.json("reject_reasons")[reason]["label"] })
	_menu = ChoiceMenu.open(self, "Why are you turning them away?", options)
	_menu.chosen.connect(func(ids: Array) -> void:
		_menu = null
		if ids[0] == "missing_requirement":
			_open_items_menu()
		else:
			_set_reject(ids[0], []))
	_menu.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


## Return with list: tick exactly what they still need to bring.
func _open_items_menu() -> void:
	var options: Array = []
	for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
		options.append({ "id": requirement["key"], "label": requirement["label"] })
	_menu = ChoiceMenu.open(self, "Tick what they need to bring back", options, true)
	_menu.chosen.connect(func(ids: Array) -> void:
		_menu = null
		_set_reject("missing_requirement", ids))
	_menu.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


func _on_menu_cancelled() -> void:
	_menu = null
	shift.choosing_section = false
	_update_buttons()


func _set_reject(reason: String, items: Array) -> void:
	_set_pending({ "action": "reject", "reason": reason, "items": items }, GameData.json("reject_reasons")[reason]["stamp"], UiKit.RED)


## Presses the stamp onto the papers. A new stamp replaces the old one.
func _set_pending(decision: Dictionary, text: String, color: Color) -> void:
	_clear_stamp()
	_pending = decision
	_stamp = StampMark.make(text, color)
	add_child(_stamp)
	_stamp.lifted.connect(_lift_stamp)
	_stamp.handed_back.connect(_hand_back)
	await get_tree().process_frame
	if _stamp == null or not is_instance_valid(_stamp):
		return
	var area := _student_panel.stamp_rect()
	_stamp.pivot_offset = _stamp.size / 2.0
	_stamp.position = area.get_center() - _stamp.size / 2.0
	_ismis.show_banner("Stamped %s. Hand the papers back (Space), or click the stamp to lift it off." % text, "")
	_update_buttons()


func _lift_stamp() -> void:
	if _pending.is_empty() or _handing:
		return
	_clear_stamp()
	_ismis.show_banner("Stamp lifted. Pick another.", "")
	_update_buttons()


func _clear_stamp() -> void:
	_pending = {}
	if _stamp != null and is_instance_valid(_stamp):
		_stamp.queue_free()
	_stamp = null


## The papers slide back across the counter, then the decision is judged.
func _hand_back() -> void:
	if _handing or shift.ended or shift.current.is_empty() or _react_left > 0.0 or _menu != null:
		return
	if _pending.is_empty():
		_ismis.show_banner("Stamp the papers first (keys 1 to 5).", "")
		return
	_handing = true
	_update_buttons()
	_student_panel.slide_out(HAND_BACK_SECONDS)
	if _stamp != null:
		var tween := create_tween().set_parallel()
		tween.tween_property(_stamp, "position:y", _stamp.position.y - 60.0, HAND_BACK_SECONDS)
		tween.tween_property(_stamp, "modulate:a", 0.0, HAND_BACK_SECONDS)
	await get_tree().create_timer(HAND_BACK_SECONDS).timeout
	_handing = false
	var decision := _pending
	_clear_stamp()
	_commit(decision)


func _commit(decision: Dictionary) -> void:
	if shift.ended or shift.current.is_empty():
		return
	var action: String = decision["action"]
	var result := shift.act(action, {
		"flags": _flags_for_decision(),
		"reason": decision["reason"],
		"items": decision["items"],
		"section": decision.get("section", ""),
	})
	if result.is_empty() or result.has("error"):
		# Nothing happened, so put the papers back on the desk.
		_student_panel.show_student(shift.current)
		_fix_sizes.call_deferred()
		_update_buttons()
		return
	var outcome: String = result["outcome"]
	var flag_note := _flag_note(_flags_for_decision().size(), shift.history[-1])
	if result["correct"]:
		_ismis.show_banner("CORRECT · %s%s" % [_outcome_text(outcome), flag_note], "right")
	else:
		_ismis.show_banner("WRONG CALL · %s%s" % [result["reason"], flag_note], "wrong")
	if outcome == "stays":
		_selection = {}
		_marks.clear()
		_flags.clear()
		_student_panel.show_student(shift.current)
		_fix_sizes.call_deferred()
	else:
		_react_left = REACT_SECONDS
	_react(action, result)
	_refresh_line()
	_refresh_offices()
	_update_buttons()


func _react(action: String, result: Dictionary) -> void:
	var outcome: String = result["outcome"]
	if not result["correct"]:
		_student_panel.set_expression("angry" if action != "approve" else "delighted")
		_student_panel.say(_reaction("wrong" if action != "approve" else "approved"))
		return
	match outcome:
		"routed":
			_student_panel.set_expression("neutral")
			_student_panel.say(_reaction("routed"))
		"held":
			_student_panel.set_expression("neutral")
			_student_panel.say(_reaction("held"))
		_:
			if action == "reject":
				_student_panel.set_expression("nervous")
				_student_panel.say(_reaction("rejected_right"))
			elif action == "fix":
				_student_panel.set_expression("happy")
				_student_panel.say(_reaction("fixed"))
			else:
				_student_panel.set_expression("delighted")
				_student_panel.say(_reaction("approved"))


func _flag_note(flag_count: int, entry: Dictionary) -> String:
	if flag_count == 0:
		return ""
	var parts: Array = []
	if entry["caught"] > 0:
		parts.append("%d caught" % entry["caught"])
	if entry["false_alarms"] > 0:
		parts.append("%d false alarm%s" % [entry["false_alarms"], "" if entry["false_alarms"] == 1 else "s"])
	return " Flags: %s." % ", ".join(parts)


func _outcome_text(outcome: String) -> String:
	match outcome:
		"routed":
			return "They're on their way."
		"held":
			return "They'll wait on the bench."
		"stays":
			return "One problem down. Check again."
	return "Next!"


func _reaction(kind: String) -> Dictionary:
	return _pick_line(GameData.json("dialogue")["reactions"][kind])


func _pick_line(options: Array) -> Dictionary:
	return options[_rng.randi_range(0, options.size() - 1)]


## Flagging: one field on the papers and one on ISMIS, in either order. A flag is the player's
## claim that they differ; nothing says whether it's right until the decision.
func _on_paper_field(form_index: int, key: String) -> void:
	_select({ "side": "paper", "form": form_index, "key": key })


func _on_record_field(key: String, context: String) -> void:
	_select({ "side": "record", "key": key, "context": context })


func _select(picked: Dictionary) -> void:
	if shift.ended or shift.current.is_empty() or _react_left > 0.0:
		return
	if _selection.is_empty() or _selection["side"] == picked["side"]:
		_clear_selection_highlight()
		_selection = picked
		_highlight(picked, "selected")
		var other := "ISMIS screen" if picked["side"] == "paper" else "papers"
		if picked["side"] == "paper" and not _ismis.is_scanned():
			other = "ISMIS screen (scan the ID first)"
		_ismis.show_banner("Now click the same field on the %s." % other, "")
		return
	var paper: Dictionary = picked if picked["side"] == "paper" else _selection
	var record: Dictionary = picked if picked["side"] == "record" else _selection
	_clear_selection_highlight()
	_selection = {}
	if paper["key"] != record["key"]:
		_ismis.show_banner("Those aren't the same field. Pick matching fields to flag.", "")
		return
	var caption := StudentPanel._caption(paper["key"])
	for flag: Dictionary in _flags:
		if _mark_key(flag["paper"]) == _mark_key(paper) and _mark_key(flag["record"]) == _mark_key(record):
			_flags.erase(flag)
			_set_mark(paper, "")
			_set_mark(record, "")
			_ismis.show_banner("Flag removed · %s." % caption, "")
			return
	var flag := { "paper": paper, "record": record, "asked": false }
	_flags.append(flag)
	_set_mark(paper, "claimed")
	_set_mark(record, "claimed")
	_ismis.show_banner("Flagged · %s. It gets checked when you decide." % caption, "flag", true)


## Asks the student about the latest flag they haven't been asked about. Costs time and patience.
func _ask() -> void:
	if shift.ended or shift.current.is_empty() or _react_left > 0.0:
		return
	var flag: Dictionary = {}
	for candidate: Dictionary in _flags:
		if not candidate["asked"]:
			flag = candidate
	if flag.is_empty():
		return
	flag["asked"] = true
	shift.ask()
	_student_panel.say(_ask_line(shift.current, flag))
	_ismis.show_banner("You asked about %s. That took a few minutes." % StudentPanel._caption(flag["paper"]["key"]), "")


func _ask_line(student: Dictionary, flag: Dictionary) -> Dictionary:
	var key: String = flag["paper"]["key"]
	var kind := "same"
	var item := ""
	if Mismatch.flag_is_real(student, _flag_data(flag)):
		var value := str(student["papers"][flag["paper"]["form"]]["fields"][key])
		if key.begins_with("req_"):
			kind = "requirement"
			item = StudentPanel._caption(key).to_lower()
		elif key == "signature":
			kind = "signature_blank" if value == "" else "signature_fake"
		elif key == "balance":
			kind = "balance"
	elif student["harmless"].has(key):
		kind = "harmless_" + key
	var options: Array = GameData.json("dialogue")["ask"][kind]
	var line: Dictionary = options[_rng.randi_range(0, options.size() - 1)].duplicate()
	for lang: String in ["ceb", "en"]:
		line[lang] = line[lang].format({ "item": item })
	return line


func _flag_data(flag: Dictionary) -> Dictionary:
	return { "form": flag["paper"]["form"], "key": flag["paper"]["key"], "context": flag["record"].get("context", "") }


func _flags_for_decision() -> Array:
	return _flags.map(_flag_data)


## An empty state puts back the field's flag mark, if it has one.
func _highlight(pick: Dictionary, state: String) -> void:
	if state == "":
		state = _marks.get(_mark_key(pick), "")
	if pick["side"] == "paper":
		_student_panel.set_field_state(pick["form"], pick["key"], state)
	else:
		_ismis.set_field_state(pick["key"], pick["context"], state)


func _set_mark(pick: Dictionary, state: String) -> void:
	if state == "":
		_marks.erase(_mark_key(pick))
	else:
		_marks[_mark_key(pick)] = state
	_highlight(pick, state)


func _mark_key(pick: Dictionary) -> String:
	if pick["side"] == "paper":
		return "paper:%d:%s" % [pick["form"], pick["key"]]
	return "record:%s:%s" % [pick["key"], pick.get("context", "")]


func _clear_selection_highlight() -> void:
	if not _selection.is_empty():
		_highlight(_selection, "")


func _refresh_line() -> void:
	_line_strip.refresh(shift.line, shift.patience)


func _refresh_offices() -> void:
	var notes := {}
	for office: String in GameData.json("offices"):
		notes[office] = OfficeSchedule.detail(shift.day, office, shift.minute)
	_offices.refresh(shift.offices(), shift.bench, notes)


## Leaves the last verdict on screen for a moment before the report.
func _on_shift_ended(_reason: String) -> void:
	_update_buttons()
	get_tree().create_timer(REACT_SECONDS + 0.4).timeout.connect(func() -> void:
		GameState.finish_shift(shift.summary(), shift.history))
