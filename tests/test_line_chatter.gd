extends SceneTree
## Run: godot --headless --path . --script res://tests/test_line_chatter.gd
## The living line: idle states from wait time, barks that never overlap or spam, the slow and fast
## triggers, the bark lines in data, and the line strip dropping all motion under reduced motion.

var _failures: int = 0


## The root window only joins the tree on the first frame, and the strip test needs it.
func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Never read the developer's own settings file into these checks.
	Settings._loaded = true
	_test_idle_states()
	_test_bark_rate_limits()
	_test_no_line_twice_in_a_row()
	_test_same_seed_same_barks()
	_test_slow_service_once_per_student()
	_test_fast_streak()
	_test_bark_lines_in_data()
	_test_shift_records_when_students_join()
	_test_only_wrong_calls_send_back()
	await _test_strip_motion_follows_settings()
	Settings.reduced_motion = false
	print("line_chatter: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _student(joined_at: float, trait_id: String = "", mood: String = "calm") -> Dictionary:
	return { "joined_at": joined_at, "trait": trait_id, "mood": mood }


func _test_idle_states() -> void:
	var phone := LineChatter.setting("phone_after_minutes")
	var fan := LineChatter.setting("fan_after_minutes")
	var sigh := LineChatter.setting("sigh_after_minutes")
	_check(phone < fan and fan < sigh, "idle thresholds climb: phone, then fan, then sigh")
	_check(LineChatter.idle_state(_student(0.0), 0.0, 100.0) == "", "a student who just arrived does nothing yet")
	_check(LineChatter.idle_state(_student(0.0), phone, 100.0) == "phone", "a short wait gets the phone out")
	_check(LineChatter.idle_state(_student(0.0), fan, 100.0) == "fan", "a longer wait gets the fan out")
	_check(LineChatter.idle_state(_student(0.0), sigh, 100.0) == "sigh", "a long wait gets a sigh")
	_check(LineChatter.idle_state(_student(0.0), 0.0, LineChatter.setting("sigh_patience") - 1.0) == "sigh",
			"a line out of patience sighs even if they just arrived")
	_check(LineChatter.idle_state(_student(10.0), 10.0 + phone - 1.0, 100.0) == "",
			"the wait counts from when they joined, not from the start of the shift")
	_check(LineChatter.idle_state(_student(0.0, "impatient"), phone / 2.0, 100.0) == "phone",
			"an impatient student gets restless twice as fast")
	_check(LineChatter.idle_state(_student(0.0, "with_parent"), phone, 100.0) == "",
			"a student with a parent waits calmer")
	_check(LineChatter.idle_state(_student(0.0, "", "angry"), sigh, 10.0) == "",
			"an angry returner already shows it on their face")
	_check(LineChatter.idle_state({ "trait": "", "mood": "calm" }, 50.0, 100.0) == "",
			"a student with no join time counts as just arrived")


func _test_bark_rate_limits() -> void:
	var chatter := LineChatter.new(7, 4)
	var gap := maxf(LineChatter.setting("bark_gap_seconds"), LineChatter.setting("bark_seconds"))
	var repeat := LineChatter.setting("bark_repeat_seconds")
	_check(LineChatter.setting("bark_gap_seconds") >= LineChatter.setting("bark_seconds"),
			"balance: the gap between barks is at least as long as a bubble stays up")
	_check(chatter.bark("rush", 0.0, []).is_empty(), "nobody on screen, nobody barks")
	_check(chatter.bark("no_such_situation", 0.0, [0]).is_empty(), "a situation with no lines stays quiet")
	var first := chatter.bark("rush", 0.0, [2, 3])
	_check(not first.is_empty(), "the first bark of the shift is allowed")
	_check(first.get("index", -1) in [2, 3], "the speaker is one of the faces offered")
	_check(first.get("situation", "") == "rush", "the bark says what it was about")
	_check(String(first.get("line", {}).get("ceb", "")) != "" and String(first.get("line", {}).get("en", "")) != "",
			"a bark carries Bisaya and its English subtitle")
	_check(chatter.bark("slow_service", gap - 0.1, [0]).is_empty(), "no second bark while the first is still up")
	_check(not chatter.bark("slow_service", gap, [0]).is_empty(), "another situation may speak once the gap is over")
	_check(chatter.bark("rush", gap * 2.0, [0]).is_empty() or gap * 2.0 >= repeat,
			"the same situation waits for its repeat time")
	_check(not chatter.bark("rush", repeat + gap, [0]).is_empty(), "the same situation may come back after its repeat time")


func _test_no_line_twice_in_a_row() -> void:
	var chatter := LineChatter.new(3, 6)
	var step := maxf(LineChatter.setting("bark_repeat_seconds"), LineChatter.setting("bark_gap_seconds"))
	var last: Dictionary = {}
	for i in 40:
		var bark := chatter.bark("slow_service", step * i, [0])
		_check(not bark.is_empty(), "a well-spaced bark is never refused")
		_check(bark.get("line", {}) != last, "the same line never comes twice in a row")
		last = bark.get("line", {})


func _test_same_seed_same_barks() -> void:
	var a := LineChatter.new(42, 6)
	var b := LineChatter.new(42, 6)
	var step := LineChatter.setting("bark_repeat_seconds")
	var same := true
	for i in 10:
		var situation: String = LineChatter.SITUATIONS[i % LineChatter.SITUATIONS.size()]
		if a.bark(situation, step * i, [0, 1, 2, 3]) != b.bark(situation, step * i, [0, 1, 2, 3]):
			same = false
	_check(same, "same seed, same barks from the same faces")


func _test_slow_service_once_per_student() -> void:
	var chatter := LineChatter.new(1, 3)
	var slow := LineChatter.setting("slow_service_minutes")
	_check(not chatter.slow_due(100.0), "nobody at the window, nothing is slow")
	chatter.note_called(20.0)
	_check(not chatter.slow_due(20.0 + slow - 1.0), "not slow before the threshold")
	_check(chatter.slow_due(20.0 + slow), "slow once the student has taken too long")
	_check(not chatter.slow_due(20.0 + slow * 3.0), "the line grumbles only once per student")
	chatter.note_decision(true, 20.0 + slow * 3.0)
	_check(not chatter.slow_due(200.0), "after the decision, nobody is at the window")
	chatter.note_called(200.0)
	_check(chatter.slow_due(200.0 + slow), "the next student can be slow again")


func _test_fast_streak() -> void:
	var chatter := LineChatter.new(1, 5)
	var quick := LineChatter.setting("fast_minutes")
	var needed := int(LineChatter.setting("fast_streak"))
	var minute := 0.0
	var cheers: Array = []
	for i in needed * 2:
		chatter.note_called(minute)
		minute += quick
		cheers.append(chatter.note_decision(true, minute))
	_check(cheers.count(true) == 2, "every %d quick right calls make the line cheer" % needed)
	_check(cheers[needed - 1] and not cheers[needed], "the run starts over after a cheer")
	# needed - 1 good calls, one bad call, needed - 1 good calls: never a cheer, but only if the
	# bad call resets the run rather than just not counting.
	for bad: String in ["slow", "wrong"]:
		chatter = LineChatter.new(1, 5)
		var cheered := false
		for i in needed * 2 - 1:
			var is_bad := i == needed - 1
			chatter.note_called(minute)
			minute += quick + (5.0 if is_bad and bad == "slow" else 0.0)
			cheered = chatter.note_decision(not (is_bad and bad == "wrong"), minute) or cheered
		_check(not cheered, "a %s call starts the run over" % bad)
	_check(not LineChatter.new(1, 5).note_decision(true, 10.0), "a decision with nobody called counts as slow")


func _test_bark_lines_in_data() -> void:
	var barks: Dictionary = GameData.json("dialogue").get("line_barks", {})
	for situation: String in LineChatter.SITUATIONS:
		var pool: Array = barks.get(situation, [])
		_check(pool.size() >= 2, "line_barks.%s has at least two lines" % situation)
		for line: Dictionary in pool:
			var ceb := String(line.get("ceb", ""))
			var en := String(line.get("en", ""))
			_check(ceb != "" and en != "", "line_barks.%s: every line has Bisaya and English" % situation)
			_check(ceb.length() <= 40 and en.length() <= 40, "line_barks.%s: \"%s\" fits in 40 characters" % [situation, ceb])
			_check(not ceb.contains("{") and not en.contains("{"), "line_barks.%s: no placeholders (nothing fills them)" % situation)
	for situation: String in barks:
		_check(situation in LineChatter.SITUATIONS, "line_barks.%s is a situation the game uses" % situation)


func _test_shift_records_when_students_join() -> void:
	var shift := ShiftState.new(4, 42)
	_check(not shift.line.is_empty(), "day 4 starts with a line")
	var all_stamped := true
	for student: Dictionary in shift.line:
		if not student.has("joined_at"):
			all_stamped = false
	_check(all_stamped, "every student in line knows when they joined")
	for i in 200:
		shift.tick(0.5)
	var later := false
	for student: Dictionary in shift.line:
		if float(student.get("joined_at", 0.0)) > 0.0:
			later = true
	_check(later, "students who arrive later carry their own join time")


## The angry-return bark keys off trip.sent_back: true after a wrong call, false after an office
## visit the player got right.
func _test_only_wrong_calls_send_back() -> void:
	for wrong: bool in [true, false]:
		var shift := ShiftState.new(4, 42)
		var student: Dictionary = {}
		for i in 2000:
			if shift.ended:
				break
			shift.tick(0.25)
			if shift.current.is_empty():
				shift.call_next()
			if shift.current.is_empty():
				continue
			var want := RulesCheck.expected(shift.current, shift.offices())
			if String(want["action"]).begins_with("route:") and shift.current["problems"].size() == 1:
				student = shift.current
				# A wrong turn-away sends them off and back angry (a wrong approve would just let them go).
				shift.act("reject" if wrong else want["action"], { "reason": "missing_requirement", "items": [] })
				break
			var section := ""
			if want["problem"] == "closed_section":
				section = Timetable.fitting_sections(shift.current)[0]
			shift.act(want["action"], { "reason": want["reason_id"], "items": want["items"], "section": section, "change": RulesCheck.change_due(shift.current) })
		_check(not student.is_empty(), "found a student who needs routing (wrong=%s)" % wrong)
		for i in 2000:
			if student.has("trip") or shift.ended:
				break
			shift.tick(0.25)
		_check(student.get("trip", {}).get("sent_back", not wrong) == wrong,
				"a student back from %s has sent_back %s" % ["a wrong call" if wrong else "the right office", wrong])


func _test_strip_motion_follows_settings() -> void:
	var line: Array = []
	for i in 4:
		var student := StudentGen.make(9000 + i, 4)
		student["joined_at"] = 0.0
		line.append(student)
	var strip := LineStrip.new()
	root.add_child(strip)
	Settings.reduced_motion = false
	strip.refresh(line, 100.0, LineChatter.setting("fan_after_minutes"))
	await process_frame
	_check(strip.shown_count() == 4, "every waiting student gets a face")
	_check(_bobbing(strip) == 4, "with motion on, every face bobs")
	_check(_tells(strip, "fan") == 4, "after a long wait, the faces fan themselves")
	var settled := strip.anchor_of(line[2])
	_check(settled != Vector2.INF and settled != LineStrip.LAYING_OUT, "a face on screen has a spot for a bubble")
	# Right after a rebuild the containers haven't placed the faces yet: the strip says so instead
	# of handing out a wrong spot, and gives the real one a frame later.
	strip.refresh(line, 100.0, LineChatter.setting("fan_after_minutes"))
	_check(strip.anchor_of(line[2]) == LineStrip.LAYING_OUT, "a just-rebuilt row says it's still laying out")
	var bubble := LineBubble.new()
	root.add_child(bubble)
	bubble.say({ "ceb": "Dugay ra kaayo oy.", "en": "This is taking forever." }, func() -> Vector2: return strip.anchor_of(line[2]), 3.0)
	_check(not bubble.visible, "a bubble waits for the layout before showing")
	await process_frame
	await process_frame
	_check(strip.anchor_of(line[2]) == settled, "a frame later the face is back where it was")
	_check(bubble.visible, "the bubble shows once the row is laid out")
	var tail := bubble.position + Vector2(bubble._tail_x, bubble.size.y + LineBubble.TAIL)
	_check(tail.distance_to(settled) < 1.0, "the bubble's tail lands on its speaker's face")
	bubble.dismiss()
	bubble.queue_free()
	_check(strip.anchor_of(StudentGen.make(1, 4)) == Vector2.INF, "a student not in line has none")
	Settings.reduced_motion = true
	strip.update_moods(100.0, LineChatter.setting("fan_after_minutes"))
	_check(_bobbing(strip) == 0, "reduced motion stops the bobbing")
	_check(_tells(strip, "fan") == 4, "reduced motion keeps the tells, just still")
	_check(_moving_tells(strip) == 0, "reduced motion stops the fans swaying")
	strip.refresh(line, 100.0, 0.0)
	_check(_bobbing(strip) == 0, "a fresh row under reduced motion doesn't bob either")
	strip.queue_free()
	Settings.reduced_motion = false


func _bobbing(strip: LineStrip) -> int:
	var count := 0
	for entry: Dictionary in strip._shown:
		var frame: Control = entry["frame"]
		if frame.has_meta("bob") and frame.get_meta("bob") is Tween and frame.get_meta("bob").is_valid():
			count += 1
	return count


func _tells(strip: LineStrip, kind: String) -> int:
	var count := 0
	for entry: Dictionary in strip._shown:
		if entry["tell"].kind == kind:
			count += 1
	return count


func _moving_tells(strip: LineStrip) -> int:
	var count := 0
	for entry: Dictionary in strip._shown:
		var tween: Tween = entry["tell"]._tween
		if tween != null and tween.is_valid():
			count += 1
	return count
