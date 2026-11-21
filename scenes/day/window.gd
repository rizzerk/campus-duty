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
	"favor": ["FAVOR", UiKit.GOLD_DARK],
}
const HAND_BACK_SECONDS := 0.3
const REACT_SECONDS := 1.6
const CALL_DELAY := 0.5
const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const KEYPAD_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5]
## How often (real seconds) the waiting faces update what they're doing.
const MOOD_SECONDS := 1.0
## How long after a wrong call's buzz a broken run's record scratch plays.
const SCRATCH_DELAY := 0.13

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
## Only shown when the student at the window asks for a favor (rule bending).
var _favor_button: Button
var _spot_note: String = ""
## The living line: who's on their phone, who's sighing, and the barks over their heads.
var _chatter: LineChatter
var _bubble: LineBubble
## Real seconds since the shift began, for spacing out barks.
var _shift_seconds: float = 0.0
var _mood_left: float = MOOD_SECONDS
## Under this patience the line looks annoyed (balance.json line_life.sigh_patience).
var _sigh_patience: float = 40.0
## The in-the-zone tier shown now (badge and music stems), from ShiftState.streak_changed.
var _zone_tier: int = 0
## Set by the decision being judged: it lost a run that had reached a tier, or reached a new tier.
var _zone_lost: bool = false
var _zone_rose: bool = false


func _ready() -> void:
	Sfx.play_bgm("shift")
	# A retried day keeps the shift music playing: start it plain again.
	Sfx.set_bgm_layers(0, true)
	# Loaded now so the first one doesn't hitch at the moment it plays.
	Sfx.stream("pop")
	Sfx.stream("record_scratch")
	_rng.seed = GameState.base_seed + GameState.day
	_unlocked = GameState.unlocked_actions()
	# The day report only flags what this shift unlocked.
	Achievements.fresh.clear()
	shift = ShiftState.new(GameState.day, GameState.base_seed)
	_chatter = LineChatter.new(GameState.base_seed, GameState.day)
	_sigh_patience = LineChatter.setting("sigh_patience")
	_build()
	shift.student_joined_line.connect(_on_joined_line)
	shift.bench_changed.connect(_refresh_offices)
	shift.office_changed.connect(func(_o: String, _status: String) -> void: _refresh_offices())
	shift.shift_ended.connect(_on_shift_ended)
	shift.rush_arrived.connect(func(count: int) -> void:
		Sfx.play("alert")
		_line_strip.flash("RUSH! %d more students just joined the line" % count)
		# A banner drops onto the top bar (over the clock, never over the line's new faces) and
		# the line hops as they pile in. Not over an open menu or the rulebook: the line strip's
		# red hint says it then.
		if _menu == null:
			Juice.banner(self, "RUSH!  +%d in line" % count, UiKit.GOLD, 4.0)
		Juice.shake(_line_strip, 4.0, 0.3, Vector2(0.0, 1.0))
		_bark("rush", _speakers()))
	shift.event_triggered.connect(_on_event_triggered)
	shift.spot_inspected.connect(_on_spot_inspected)
	shift.streak_changed.connect(_on_streak_changed)
	_refresh_line()
	_refresh_offices()
	_call_left = CALL_DELAY


func _process(delta: float) -> void:
	if shift.ended:
		return
	shift.tick(delta)
	if shift.ended:
		return
	_shift_seconds += delta
	_mood_left -= delta
	if _mood_left <= 0.0:
		_mood_left = MOOD_SECONDS
		_line_strip.update_moods(shift.patience, shift.minute)
	if not shift.current.is_empty() and _react_left <= 0.0 and _chatter.slow_due(shift.minute):
		_bark("slow_service", _speakers(true))
	_top_bar.update_values(shift.clock_text(), shift.served, shift.line.size(), shift.patience)
	var band := 0 if shift.patience < _sigh_patience else 1 if shift.patience < 70.0 else 2
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
	if event.keycode == KEY_ESCAPE:
		_open_pause()
		return
	if event.keycode == KEY_TAB:
		_open_rulebook()
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
	elif event.keycode in [KEY_6, KEY_KP_6]:
		_on_action("favor")


func _build() -> void:
	var wall := ColorRect.new()
	wall.color = UiKit.MINT
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wall)
	# Everything under the line sits on the counter.
	_place(UiKit.desk(), Rect2(0, 168, 1280, 552))
	_top_bar = ShiftTopBar.new()
	_place(_top_bar, Rect2(0, 0, 1280, 64))
	_line_strip = LineStrip.new()
	_place(_line_strip, Rect2(24, 72, 1232, 96))
	_line_strip.face_clicked.connect(_on_face_clicked)
	# Over the top bar and the line, under everything placed after it (menus, the rulebook).
	_bubble = LineBubble.new()
	add_child(_bubble)
	_student_panel = StudentPanel.new()
	_place(_student_panel, Rect2(24, 176, 494, 440))
	_student_panel.paper_field_clicked.connect(_on_paper_field)
	_ismis = IsmisScreen.new()
	_place(_ismis, Rect2(532, 176, 478, 440))
	_ismis.record_field_clicked.connect(_on_record_field)
	_ismis.ask_pressed.connect(_ask)
	_ismis.scanned.connect(_on_id_scanned)
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
	_favor_button = UiKit.button("6  Do the favor", UiKit.GOLD_DARK, Color.WHITE, 22)
	_favor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_favor_button.tooltip_text = "Wave them through without the checks. Ma'am Lorna spot-checks at the end of the day."
	_favor_button.pressed.connect(_on_action.bind("favor"))
	bar.add_child(_favor_button)
	_hand_back_button = UiKit.button("Space  Hand back", UiKit.GOLD, UiKit.INK, 22)
	_hand_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_back_button.size_flags_stretch_ratio = 1.3
	_hand_back_button.pressed.connect(_hand_back)
	bar.add_child(_hand_back_button)
	var hints := UiKit.label(_hint_text(), 15, UiKit.INK)
	hints.modulate.a = 0.75
	_place(hints, Rect2(24, 698, 1232, 20))
	_update_buttons()
	_fix_sizes.call_deferred()


## The strip under the stamps: the order to handle problems in (once students can have two),
## and the keys for the rulebook and pause.
func _hint_text() -> String:
	var parts: Array = []
	for number in range(int(GameData.json("days")["first_day"]), GameState.day + 1):
		if int(GameData.day(number)["max_problems"]) > 1:
			parts.append("Two problems? Turn away  ›  Send out  ›  Fix at the window")
			break
	parts.append("Tab  Rulebook")
	parts.append("Esc  Pause")
	return "     ·     ".join(parts)


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
	_favor_button.visible = not shift.current.is_empty() and shift.current.get("favor", "") != "" and not shift.ended
	_favor_button.disabled = busy
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
	Sfx.play("bell")
	Sfx.play("paper_slide")
	_selection = {}
	_marks.clear()
	_flags.clear()
	_clear_stamp()
	_student_panel.show_student(student)
	_ismis.show_student(student)
	_chatter.note_called(shift.minute)
	var onboarding := ShiftEvents.onboarding_banner(student, "called")
	if onboarding != "":
		_ismis.show_banner(onboarding, "")
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
	# The next student steps up. The slide has to start after _fix_sizes puts the panel in place,
	# or _fix_sizes snaps it straight back, so both go in one deferred call, in that order.
	(func() -> void:
		_fix_sizes()
		Juice.slide_in(_student_panel, Vector2(-28.0, 0.0), 0.35)).call_deferred()


func _on_face_clicked(index: int) -> void:
	if shift.call_out_of_turn(index):
		Achievements.record_event("priority_call")
		Sfx.play("bell")
		_refresh_line()
		_ismis.show_banner("Called a priority student to the front of the line.", "")
		# Someone they just skipped (now right behind them) has something to say about it.
		var skipped: Array = []
		for i in range(1, mini(index + 1, _visible_faces())):
			if shift.line[i]["priority"] == "":
				skipped.append(i)
		_bark("priority_cut", skipped)


func _on_id_scanned() -> void:
	if shift.current.is_empty():
		return
	var onboarding := ShiftEvents.onboarding_banner(shift.current, "scanned")
	if onboarding != "":
		_ismis.show_banner(onboarding, "")


func _on_event_triggered(event: Dictionary) -> void:
	Sfx.play("alert")
	if event.has("flash"):
		_line_strip.flash(event["flash"])
	if event.has("banner") and _react_left <= 0.0:
		_ismis.show_banner(event["banner"], "flag" if event.get("kind", "") in ["outage", "malfunction"] else "")


func _on_spot_inspected(inspection: Dictionary) -> void:
	if inspection.is_empty():
		return
	Sfx.play("correct" if inspection.get("kind", "") == "praise" else "alert")
	_line_strip.flash("SPOT CHECK · %s" % inspection.get("ceb", ""))
	_spot_note = " · %s" % inspection.get("banner", "")


## Picking a stamp. Nothing is judged until the papers are handed back.
func _on_action(action: String) -> void:
	if shift.ended or shift.current.is_empty() or _react_left > 0.0 or _handing or _menu != null:
		return
	if action == "favor" and shift.current.get("favor", "") == "":
		return
	if action != "favor" and not _unlocked.has(action):
		return
	if action == "hold" and shift.bench_full():
		return
	if action == "reject":
		_open_reject_menu()
		return
	if action == "fix" and shift.current["request"].has("course"):
		_open_section_picker()
		return
	if action == "fix" and shift.current["visit"] == "first_year":
		_open_reset_tool()
		return
	if action == "fix" and shift.current["visit"] == "tuition_payment":
		_open_change_tool()
		return
	if action == "approve" and shift.current["visit"] == "tuition_payment":
		_set_pending({ "action": "approve", "reason": "", "items": [] }, "PAID", UiKit.OK)
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
		_set_pending({ "action": "fix", "reason": "", "items": [], "section": code }, "MOVED · %s" % code.get_slice("-", 1), UiKit.BLUE))
	picker.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


## S5: Esc pauses. The tree pauses, so the clock and patience stop.
func _open_pause() -> void:
	if shift.ended or _handing:
		return
	var menu := PauseMenu.open(self, shift)
	_menu = menu
	menu.resumed.connect(_on_menu_cancelled)


## S15: Tab opens the handbook. The clock keeps running.
func _open_rulebook() -> void:
	if shift.ended:
		return
	Sfx.play("paper_slide")
	var book := Rulebook.open(self, shift.day)
	_menu = book
	book.closed.connect(_on_menu_cancelled)
	_update_buttons()


## S11: the password reset tool for freshmen who can't log in.
func _open_reset_tool() -> void:
	var tool := ResetTool.open(self, shift.current)
	_menu = tool
	tool.printed.connect(func() -> void:
		_menu = null
		_set_pending({ "action": "fix", "reason": "", "items": [] }, "RESET", UiKit.BLUE))
	tool.cancelled.connect(_on_menu_cancelled)
	_update_buttons()


## S17: the change drawer at the payment window, for a student who paid more than they owe.
func _open_change_tool() -> void:
	var tool := ChangeTool.open(self, shift.current)
	_menu = tool
	tool.given.connect(func(change: int) -> void:
		_menu = null
		_set_pending({ "action": "fix", "reason": "", "items": [], "change": change }, "CHANGE · %s" % Money.format(change), UiKit.BLUE))
	tool.cancelled.connect(_on_menu_cancelled)
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
	# In the zone the stamp lands heavier: a deeper thump and a bigger slam per tier.
	var zone := ShiftState.streak_tier(shift.streak)
	Sfx.play("stamp", 0.03, 1.0 - 0.05 * zone)
	_pending = decision
	_stamp = StampMark.make(text, color)
	add_child(_stamp)
	_stamp.lifted.connect(_lift_stamp)
	_stamp.handed_back.connect(_hand_back)
	await get_tree().process_frame
	if _stamp == null or not is_instance_valid(_stamp):
		return
	# Measure where the papers will be, not where a student still sliding in happens to be.
	Juice.settle(_student_panel)
	var area := _student_panel.stamp_rect()
	_stamp.pivot_offset = _stamp.size / 2.0
	_stamp.position = area.get_center() - _stamp.size / 2.0
	# The stamp lands: it slams in a little big, jolts and the game holds for a blink. Only the
	# stamp moves, never the paper. Skipped if the papers are already on their way back.
	if not _handing:
		Juice.punch(_stamp, 1.15 + 0.05 * zone, 0.12)
		Juice.shake(_stamp, 4.0 + 1.5 * zone, 0.12)
		Juice.hit_stop(self, 0.05 + 0.003 * zone)
	_ismis.show_banner("Stamped %s. Hand the papers back (Space), or click the stamp to lift it off." % text, "")
	_update_buttons()


func _lift_stamp() -> void:
	if _pending.is_empty() or _handing:
		return
	Sfx.play("stamp_lift")
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
		Sfx.play("wrong")
		_ismis.show_banner("Stamp the papers first (keys 1 to 5).", "")
		return
	Sfx.play("paper_slide")
	_handing = true
	_update_buttons()
	_student_panel.slide_out(HAND_BACK_SECONDS)
	if _stamp != null:
		Juice.settle(_stamp)
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
	var student := shift.current
	_spot_note = ""
	_zone_lost = false
	_zone_rose = false
	var result := shift.act(action, {
		"flags": _flags_for_decision(),
		"reason": decision["reason"],
		"items": decision["items"],
		"section": decision.get("section", ""),
		"change": decision.get("change", -1),
	})
	if result.is_empty() or result.has("error"):
		# Nothing happened, so put the papers back on the desk.
		_student_panel.show_student(shift.current)
		_fix_sizes.call_deferred()
		_update_buttons()
		return
	Achievements.record_decision(shift, student)
	var outcome: String = result["outcome"]
	var flag_note := _flag_note(_flags_for_decision().size(), shift.history[-1]) + _spot_note
	if _zone_lost:
		flag_note += " Your run is over."
	if result["bent"]:
		Sfx.play("alert")
		_ismis.show_banner("FAVOR DONE · %s The line saw it.%s" % [shift.history[-1]["reason"], flag_note], "flag")
		_verdict_juice("Favor done", UiKit.GOLD, false)
	elif result["correct"]:
		Sfx.play("correct")
		_ismis.show_banner("CORRECT · %s%s" % [_outcome_text(outcome), flag_note], "right")
		_verdict_juice("Right call", UiKit.OK_BRIGHT, false)
	else:
		Sfx.play("wrong")
		_ismis.show_banner("WRONG CALL · %s%s" % [result["reason"], flag_note], "wrong")
		_verdict_juice("Wrong call", UiKit.RED, true)
	if outcome == "stays":
		_selection = {}
		_marks.clear()
		_flags.clear()
		_student_panel.show_student(shift.current)
		_fix_sizes.call_deferred()
	else:
		_react_left = REACT_SECONDS
	_react(action, result)
	if action.begins_with("route:") and student.get("trait", "") == "with_parent" and outcome != "walked_out":
		_parent_argues()
	_refresh_line()
	_refresh_offices()
	_update_buttons()
	# Quick right calls in a row get the line cheering. A student who stays for another problem
	# is still the same visit, so only their last decision counts. A favor never earns a cheer.
	if outcome != "stays" and _chatter.note_decision(result["correct"] and action != "favor", shift.minute) and not shift.ended:
		_line_strip.cheer(LineChatter.setting("cheer_seconds"))
		# A new zone tier already popped on this call: one pop, not two.
		if not _zone_rose:
			Sfx.play("pop")
		_bark("fast_streak", _speakers())


## In the zone: each tier a run of right calls reaches pops the badge and brings in a music stem.
## Breaking a run that had reached a tier scratches the record, drops the badge and the stems.
func _on_streak_changed(streak: int, tier: int, broken: bool) -> void:
	if broken:
		if _zone_tier > 0:
			_zone_lost = true
			# Just after the wrong buzz, so the scratch is heard on its own.
			get_tree().create_timer(SCRATCH_DELAY).timeout.connect(func() -> void: Sfx.play("record_scratch", 0.0))
			_top_bar.drop_streak()
			Sfx.set_bgm_layers(0)
		_zone_tier = 0
		return
	_top_bar.set_streak(streak, tier)
	var badge := _top_bar.zone_badge()
	if tier > _zone_tier:
		_zone_rose = true
		Sfx.play("pop", 0.0, 1.0 + 0.12 * tier)
		Sfx.set_bgm_layers(tier)
		if Juice.punch(badge, 1.3, 0.3) == null:
			Juice.flash(badge, Color(1.6, 1.6, 1.6), 0.3)
	elif tier > 0:
		# One more on the count: a small nudge, the right-call sound already says it.
		Juice.punch(badge, 1.08, 0.12)
	_zone_tier = tier


## How a call lands: a wash of its color over the window and its word popping up where the stamp
## was, which is where the player is looking (and clear of the student's name).
## A wrong call also shakes the patience bar, which shows what it cost (the papers stay put).
func _verdict_juice(word: String, color: Color, wrong: bool) -> void:
	Juice.screen_flash(self, Color(color, 0.22 if wrong else 0.16), 0.3 if wrong else 0.25)
	var spot := _student_panel.stamp_rect().get_center()
	Juice.pop_text(self, word, UiKit.RED_BRIGHT if wrong else color, spot, 38)
	if wrong:
		# Only the patience bar, which is what the mistake cost; the rest of the top bar holds still.
		Juice.shake(_top_bar.patience_bar(), 6.0, 0.3, Vector2(1.0, 0.5))


## With parent: any routing gets an argument from the parent, which costs the window a few minutes.
func _parent_argues() -> void:
	var line: Dictionary = _pick_line(GameData.json("traits")["with_parent"]["argue"]).duplicate()
	line["en"] = "(Parent) %s" % line["en"]
	_student_panel.set_expression("annoyed")
	_student_panel.say(line)
	shift.argue()


func _react(action: String, result: Dictionary) -> void:
	var outcome: String = result["outcome"]
	if result["bent"] or (action == "favor" and result["correct"]):
		_student_panel.set_expression("delighted")
		_student_panel.say(_reaction("approved"))
		return
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
		Sfx.play("click")
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
		Sfx.play("wrong")
		_ismis.show_banner("Those aren't the same field. Pick matching fields to flag.", "")
		return
	var caption := _paper_caption(paper)
	for flag: Dictionary in _flags:
		if _mark_key(flag["paper"]) == _mark_key(paper) and _mark_key(flag["record"]) == _mark_key(record):
			Sfx.play("stamp_lift")
			_flags.erase(flag)
			_set_mark(paper, "")
			_set_mark(record, "")
			_ismis.show_banner("Flag removed · %s." % caption, "")
			return
	Sfx.play("flag")
	var flag := { "paper": paper, "record": record, "asked": false }
	_flags.append(flag)
	_set_mark(paper, "claimed")
	_set_mark(record, "claimed")
	# Both flagged fields give a small pulse, like a pin going in (2%, so the paper barely moves).
	_student_panel.pulse_field(paper["form"], paper["key"])
	_ismis.pulse_field(record["key"], record.get("context", ""))
	var onboarding_flag := ShiftEvents.onboarding_banner(shift.current, "flagged")
	_ismis.show_banner(onboarding_flag if onboarding_flag != "" else "Flagged · %s. It gets checked when you decide." % caption, "flag", true)


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
	var onboarding_ask := ShiftEvents.onboarding_banner(shift.current, "asked")
	_ismis.show_banner(onboarding_ask if onboarding_ask != "" else "You asked about %s. That took a few minutes." % _paper_caption(flag["paper"]), "")


func _ask_line(student: Dictionary, flag: Dictionary) -> Dictionary:
	if student.get("trait", "") == "palusot":
		# A palusot student denies everything, real problem or not.
		return _pick_line(GameData.json("traits")["palusot"]["ask"])
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
		elif key == "birthday":
			kind = "birthday"
		elif key == "amount_due":
			var short := Money.parse(value) < Money.parse(str(student["record"].get("amount_due", "")))
			kind = "payment_short" if short else "payment_over"
	elif student["harmless"].has(key):
		kind = "harmless_" + key
	var options: Array = GameData.json("dialogue")["ask"][kind]
	var line: Dictionary = options[_rng.randi_range(0, options.size() - 1)].duplicate()
	for lang: String in ["ceb", "en"]:
		line[lang] = line[lang].format({ "item": item })
	return line


## The field's caption as the paper shows it (the cash reads "Cash handed over", not "Amount due").
func _paper_caption(pick: Dictionary) -> String:
	return StudentPanel._form_caption(shift.current["papers"][pick["form"]]["form"], pick["key"])


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
	_line_strip.refresh(shift.line, shift.patience, shift.minute)


func _on_joined_line(student: Dictionary) -> void:
	_refresh_line()
	# Back from a wrong call, and they let the whole line know. (Back from an office that helped
	# them, they have nothing to complain about, even if they were angry earlier.)
	if student.get("trip", {}).get("sent_back", false):
		var index := shift.line.size() - 1
		_bark("angry_return", [index] if index < _visible_faces() else [])


## Faces on screen that could speak. Impatient students get the first word when the window is slow.
func _speakers(impatient_first: bool = false) -> Array:
	var all: Array = []
	var impatient: Array = []
	for i in _visible_faces():
		all.append(i)
		if shift.line[i].get("trait", "") == "impatient":
			impatient.append(i)
	return impatient if impatient_first and not impatient.is_empty() else all


## Someone in line says something, if LineChatter allows it right now. The bubble follows them as
## the line moves and goes away if they're called up.
func _bark(situation: String, speakers: Array) -> void:
	if shift.ended:
		return
	var bark := _chatter.bark(situation, _shift_seconds, _clear_of_tags(speakers))
	if bark.is_empty() or int(bark["index"]) >= shift.line.size():
		return
	var student: Dictionary = shift.line[bark["index"]]
	_bubble.say(bark["line"], func() -> Vector2: return _line_strip.anchor_of(student), LineChatter.setting("bark_seconds"))
	_line_strip.speak(bark["index"])
	Sfx.play("murmur", 0.08)


## Faces both on screen and still in line (the same unless the strip hasn't caught up yet).
func _visible_faces() -> int:
	return mini(_line_strip.shown_count(), shift.line.size())


## A bubble covers the tags of the faces around its speaker, so speakers whose neighbors have no
## GRAD, PWD or BACK tag go first; the player is often scanning for those tags right then.
func _clear_of_tags(speakers: Array) -> Array:
	var clear: Array = []
	for i: int in speakers:
		var tagged := false
		for j in range(maxi(0, i - 2), mini(i + 3, _visible_faces())):
			var other: Dictionary = shift.line[j]
			if other["priority"] != "" or other.get("mood", "") == "angry":
				tagged = true
		if not tagged:
			clear.append(i)
	return clear if not clear.is_empty() else speakers


func _refresh_offices() -> void:
	var notes := {}
	for office: String in GameData.json("offices"):
		notes[office] = OfficeSchedule.detail(shift.day, office, shift.minute)
	_offices.refresh(shift.offices(), shift.bench, notes)


## Leaves the last verdict on screen for a moment, then the report, or S18 if the line gave up.
func _on_shift_ended(reason: String) -> void:
	_top_bar.calm()
	_bubble.dismiss()
	_update_buttons()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	if reason == "patience":
		# Earned even if the player retries the day instead of carrying on to the report.
		Achievements.record_event("lorna_takes_over")
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			var failed := ShiftFailed.open(self, shift)
			failed.retry.connect(func() -> void:
				GameState.log_failed_attempt(shift.summary(), shift.history)
				GameState.retry_day())
			failed.carry_on.connect(func() -> void: GameState.finish_shift(shift.summary(), shift.history)))
		return
	get_tree().create_timer(REACT_SECONDS + 0.4).timeout.connect(func() -> void:
		GameState.finish_shift(shift.summary(), shift.history))
