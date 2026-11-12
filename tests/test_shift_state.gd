extends SceneTree
## Run: godot --headless --path . --script res://tests/test_shift_state.gd

const STEP := 0.25

var _failures: int = 0


func _init() -> void:
	_test_perfect_player_never_fails()
	_test_always_approve_makes_mistakes()
	_test_hold_waits_for_break_to_end()
	_test_wrong_call_comes_back_then_walks_out()
	_test_idle_player_runs_out()
	_test_same_seed_same_line()
	_test_stars()
	_test_flags_and_asking()
	_test_routing_round_trips()
	_test_wrong_office_trip()
	_test_open_market_drain()
	_test_routed_late_counts_as_handled()
	_test_careful_player_never_fails()
	_test_wrong_fix_doesnt_come_back()
	_test_favors()
	_test_trait_weights()
	_test_own_section_never_drains()
	_test_caught_favors_cost_stars()
	_test_day_one_onboarding_and_events()
	print("shift_state: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


## Plays a whole shift. The policy returns [action, section] or [] to wait.
func _play(shift: ShiftState, policy: Callable) -> void:
	for i in 100000:
		if shift.ended:
			return
		shift.tick(STEP)
		if shift.current.is_empty():
			shift.call_next()
		if not shift.current.is_empty():
			var choice: Array = policy.call(shift)
			if not choice.is_empty():
				shift.act(choice[0], {
					"section": choice[1],
					"flags": choice[2] if choice.size() > 2 else [],
					"reason": choice[3] if choice.size() > 3 else "",
					"items": choice[4] if choice.size() > 4 else [],
				})


func _perfect(shift: ShiftState) -> Array:
	var want := RulesCheck.expected(shift.current, shift.offices())
	if want["action"] == "hold" and shift.bench_full():
		return []
	var section := ""
	if want["problem"] == "closed_section":
		section = Timetable.fitting_sections(shift.current)[0]
	return [want["action"], section, [], want["reason_id"], want["items"]]


func _test_perfect_player_never_fails() -> void:
	for day in range(1, 9):
		var shift := ShiftState.new(day, 42)
		_play(shift, _perfect)
		var summary := shift.summary()
		_check(shift.ended, "day %d ends" % day)
		_check(summary["reason"] != "patience", "day %d perfect play keeps patience (%.0f left)" % [day, shift.patience])
		_check(summary["mistakes"] == 0, "day %d perfect play has no mistakes" % day)
		_check(summary["served"] > 0, "day %d serves students" % day)


func _test_always_approve_makes_mistakes() -> void:
	var shift := ShiftState.new(2, 42)
	_play(shift, func(_s: ShiftState) -> Array: return ["approve", ""])
	_check(shift.mistakes > 0, "approving everyone makes mistakes on day 2")
	_check(shift.summary()["accuracy"] < 1.0, "accuracy drops")


func _test_hold_waits_for_break_to_end() -> void:
	var shift := ShiftState.new(7, 1)
	var student := StudentGen.make(1, 7)
	for seed_value in 5000:
		student = StudentGen.make(seed_value, 7)
		if student["problems"] == ["missing_signature"]:
			break
	student["number"] = 999
	shift.minute = 160.0
	shift.current = student
	var result := shift.act("hold")
	_check(result["correct"] and result["outcome"] == "held", "hold is right during the advisers' break")
	_check(shift.bench.size() == 1, "student sits on the bench")
	while shift.minute < 179.0:
		shift.tick(STEP)
	_check(shift.bench.size() == 1, "still on the bench during the break")
	while shift.minute < 182.0:
		shift.tick(STEP)
	_check(shift.bench.is_empty(), "leaves the bench when consultation reopens")
	var back := false
	while shift.minute < 230.0 and not back:
		shift.tick(STEP)
		back = shift.line.any(func(s: Dictionary) -> bool: return s["number"] == 999)
	_check(back, "comes back from consultation")
	var returned: Array = shift.line.filter(func(s: Dictionary) -> bool: return s["number"] == 999)
	_check(not returned.is_empty() and returned[0]["problems"].is_empty(), "signature problem is solved on return")


func _test_wrong_call_comes_back_then_walks_out() -> void:
	var shift := ShiftState.new(2, 3)
	var student := {}
	for seed_value in 5000:
		student = StudentGen.make(seed_value, 2)
		if student["problems"].is_empty():
			break
	student["number"] = 998
	shift.current = student
	_check(shift.act("reject")["outcome"] == "sent_back_wrong", "wrong reject sends them away angry")
	_check(student["mood"] == "angry", "student is angry")
	shift.current = student
	_check(shift.act("reject")["outcome"] == "walked_out", "second wrong call and they walk out")
	_check(shift.walked_out == 1, "walkout counted")


func _test_idle_player_runs_out() -> void:
	var shift := ShiftState.new(6, 42)
	_play(shift, func(_s: ShiftState) -> Array: return [])
	_check(shift.ended and shift.end_reason in ["patience", "time"], "doing nothing ends the shift (%s)" % shift.end_reason)


func _test_same_seed_same_line() -> void:
	var a := ShiftState.new(4, 9)
	var b := ShiftState.new(4, 9)
	_check(a.line.size() == b.line.size() and a.line[0]["name"] == b.line[0]["name"], "same seed gives the same line")


func _test_stars() -> void:
	var idle := ShiftState.new(2, 42)
	_play(idle, func(_s: ShiftState) -> Array: return [])
	_check(Scoring.stars(idle.summary()) == 0, "waiting out the clock earns no stars (%s)" % idle.end_reason)
	var perfect := ShiftState.new(2, 42)
	_play(perfect, _perfect)
	_check(Scoring.stars(perfect.summary()) == 3, "perfect day 2 earns 3 stars")
	var walkout := perfect.summary()
	walkout["walked_out"] = 1
	_check(Scoring.stars(walkout) == 2, "a walkout caps stars at 2")
	var failed := perfect.summary()
	failed["reason"] = "patience"
	_check(Scoring.stars(failed) == 0, "a failed shift earns no stars")
	var half := perfect.summary()
	half["served_ratio"] = 0.6
	_check(Scoring.stars(half) == 1, "serving only 60% of the line caps stars at 1")
	var early := perfect.summary()
	early["served_ratio"] = 0.2
	early["reason"] = ""
	_check(Scoring.projected(early) == 3, "mid-shift projection doesn't count students still to come")
	var none := idle.summary()
	_check(Scoring.projected(none) == 0, "no calls yet projects nothing")


func _test_flags_and_asking() -> void:
	var shift := ShiftState.new(2, 5)
	var student := {}
	for seed_value in 5000:
		student = StudentGen.make(seed_value, 2)
		if student["problems"] == ["missing_requirement"]:
			break
	student["number"] = 997
	var real: Array = Mismatch.real_differences(student)[0]
	shift.patience = 50.0
	shift.current = student
	var flags := [{ "form": real[0], "key": real[1], "context": "" }, { "form": 0, "key": "id_number", "context": "" }]
	shift.act("reject", { "flags": flags, "reason": "missing_requirement", "items": RulesCheck.missing_items(student) })
	_check(shift.caught == 1 and shift.false_alarms == 1, "one catch and one false alarm counted")
	var expected := 50.0 + GameData.balance("patience_correct_bonus") + GameData.balance("patience_flag_bonus") - GameData.balance("patience_false_flag_penalty")
	_check(is_equal_approx(shift.patience, expected), "flag bonus and penalty applied (%.1f vs %.1f)" % [shift.patience, expected])
	_check(shift.summary()["caught"] == 1 and shift.summary()["false_alarms"] == 1, "summary counts flags")
	var before_minute := shift.minute
	var before_patience := shift.patience
	shift.ask()
	_check(is_equal_approx(shift.minute - before_minute, GameData.balance("ask_minutes")), "asking takes game time")
	_check(shift.patience < before_patience, "asking costs patience")


func _student_with(day: int, problems: Array) -> Dictionary:
	for seed_value in 20000:
		var student := StudentGen.make(seed_value, day)
		if student["problems"] == problems and not student["no_id"]:
			return student
	return {}


## Routed correctly: they come back with proof, nothing left to flag, and Approve is right.
func _test_routing_round_trips() -> void:
	for case: Array in [[4, "unpaid_balance", "cashier"], [7, "missing_signature", "consultation"], [6, "inc_prereq", "consultation"], [8, "overload", "dean"]]:
		var shift := ShiftState.new(case[0], 11)
		var student := _student_with(case[0], [case[1]])
		_check(not student.is_empty(), "found a %s student" % case[1])
		if student.is_empty():
			continue
		student["number"] = 990
		shift.minute = 40.0
		shift.current = student
		var papers_before: int = student["papers"].size()
		var result := shift.act("route:" + case[2])
		_check(result["correct"] and result["outcome"] == "routed", "%s routes to %s" % [case[1], case[2]])
		var back := {}
		while back.is_empty() and shift.minute < 200.0:
			shift.tick(STEP)
			for waiting: Dictionary in shift.line:
				if waiting["number"] == 990:
					back = waiting
		_check(not back.is_empty(), "%s student comes back" % case[1])
		if back.is_empty():
			continue
		_check(back["problems"].is_empty(), "%s solved on return" % case[1])
		_check(Mismatch.real_differences(back).is_empty(), "%s papers no longer show the problem" % case[1])
		_check(back["trip"]["office"] == case[2] and not back["trip"]["wrong"], "%s trip remembered" % case[1])
		if case[1] != "missing_signature":
			_check(back["papers"].size() == papers_before + 1, "%s brings proof from %s" % [case[1], case[2]])
		_check(RulesCheck.judge(back, "approve", shift.offices())["correct"], "%s approved after the trip" % case[1])


func _test_wrong_office_trip() -> void:
	var shift := ShiftState.new(7, 12)
	var student := _student_with(7, [])
	student["number"] = 989
	shift.minute = 40.0
	shift.current = student
	var result := shift.act("route:cashier")
	_check(not result["correct"] and result["outcome"] == "sent_back_wrong", "routing a clean student is wrong")
	var back := {}
	while back.is_empty() and shift.minute < 200.0:
		shift.tick(STEP)
		for waiting: Dictionary in shift.line:
			if waiting["number"] == 989:
				back = waiting
	_check(not back.is_empty() and back["trip"]["office"] == "cashier" and back["trip"]["wrong"], "wrong trip remembered for the complaint")
	var closed := ShiftState.new(7, 13)
	var needs_adviser := _student_with(7, ["missing_signature"])
	needs_adviser["number"] = 988
	closed.minute = 160.0
	closed.current = needs_adviser
	closed.act("route:consultation")
	var trips: Array = closed._away.filter(func(t: Dictionary) -> bool: return t["student"]["number"] == 988)
	_check(not trips.is_empty() and trips[0]["closed"], "sending them to an office on break is a wasted trip")


## Day 6: seats drain while the player decides, but one fitting section always survives.
func _test_open_market_drain() -> void:
	var shift := ShiftState.new(6, 21)
	var student := _student_with(6, ["closed_section"])
	student["number"] = 987
	var sections: Array = student["record"]["sections"][student["request"]["course"]]
	var seats_before := 0
	for section: Dictionary in sections:
		seats_before += section["seats"]
	shift.current = student
	shift.choosing_section = true
	var drained := [false]
	shift.slots_changed.connect(func() -> void: drained[0] = true)
	for i in 600:
		shift.minute = 20.0
		shift.tick(0.25)
	var seats_after := 0
	for section: Dictionary in sections:
		seats_after += section["seats"]
	_check(drained[0] and seats_after < seats_before, "open market drains seats (%d -> %d)" % [seats_before, seats_after])
	_check(not Timetable.fitting_sections(student).is_empty(), "a fitting section always survives")
	shift.choosing_section = false
	var frozen: Array = sections.map(func(x: Dictionary) -> int: return x["seats"])
	for i in 200:
		shift.minute = 20.0
		shift.tick(0.25)
	_check(sections.map(func(x: Dictionary) -> int: return x["seats"]) == frozen, "seats stop draining once the picker closes")
	var quiet := ShiftState.new(3, 21)
	var calm := _student_with(3, ["closed_section"])
	calm["number"] = 986
	var calm_sections: Array = calm["record"]["sections"][calm["request"]["course"]]
	var calm_before: Array = calm_sections.map(func(x: Dictionary) -> int: return x["seats"])
	quiet.current = calm
	quiet.choosing_section = true
	for i in 200:
		quiet.minute = 20.0
		quiet.tick(0.25)
	_check(calm_sections.map(func(x: Dictionary) -> int: return x["seats"]) == calm_before, "seats stay put on other days")
	var rushes := [0]
	var market := ShiftState.new(6, 22)
	market.rush_arrived.connect(func(count: int) -> void: rushes[0] += count)
	while market.minute < 160.0:
		market.tick(0.5)
		market.patience = 100.0
	var expected_rush := 0
	for rush: Dictionary in GameData.day(6)["rush"]:
		expected_rush += int(rush["count"])
	_check(rushes[0] == expected_rush, "rush waves announced (%d of %d)" % [rushes[0], expected_rush])


func _test_routed_late_counts_as_handled() -> void:
	var shift := ShiftState.new(4, 31)
	var student := _student_with(4, ["unpaid_balance"])
	student["number"] = 985
	shift.minute = 235.0
	shift.current = student
	shift.act("route:cashier")
	var summary := shift.summary()
	_check(summary["elsewhere"] == 1, "a correct late route is handled elsewhere")
	_check(is_equal_approx(summary["served_ratio"], (summary["served"] + 1.0) / summary["total"]), "handled elsewhere counts toward the served ratio")
	var wrong := ShiftState.new(4, 32)
	var clean := _student_with(4, [])
	clean["number"] = 984
	wrong.current = clean
	wrong.act("route:cashier")
	_check(wrong.summary()["elsewhere"] == 0, "a wrong trip doesn't count as handled")


## Balance guard: a careful player who takes 15 seconds per student (half that for someone back
## from an office) and gets 1 call in 10 wrong never loses the line, and earns 2 stars or more.
func _test_careful_player_never_fails() -> void:
	for day in range(2, 9):
		var shift := ShiftState.new(day, 7)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var timer := 0.0
		while not shift.ended:
			shift.tick(STEP)
			if shift.current.is_empty():
				shift.call_next()
				timer = 0.0
			if shift.current.is_empty():
				continue
			timer += STEP
			var trip: Dictionary = shift.current.get("trip", {})
			var back_ok: bool = trip.get("office", "") != "" and not trip.get("wrong", false)
			if timer < (7.5 if back_ok else 15.0):
				continue
			var want := RulesCheck.expected(shift.current, shift.offices())
			if want["action"] == "hold" and shift.bench_full():
				continue
			var action: String = want["action"]
			if rng.randf() < 0.1:
				action = "reject" if action == "approve" else "approve"
			var section := ""
			if want["problem"] == "closed_section":
				section = Timetable.fitting_sections(shift.current)[0]
			shift.act(action, { "section": section, "reason": want["reason_id"], "items": want["items"] })
		var summary := shift.summary()
		_check(summary["reason"] != "patience", "careful player keeps the line on day %d" % day)
		_check(Scoring.stars(summary) >= 2, "careful player earns 2+ stars on day %d (got %d)" % [day, Scoring.stars(summary)])


func _student(day: int, wanted: Array, visit: String = "") -> Dictionary:
	for seed_value in 20000:
		var student := StudentGen.make(seed_value, day)
		var problems: Array = student["problems"].duplicate()
		problems.sort()
		if problems == wanted and (visit == "" or student["visit"] == visit) and not student["no_id"]:
			student["number"] = 900
			return student
	return {}


func _test_wrong_fix_doesnt_come_back() -> void:
	var shift := ShiftState.new(3, 5)
	var student := _student(3, [], "enroll_subject")
	shift.current = student
	var other := ""
	for code: String in Timetable.fitting_sections(student):
		if code != student["request"]["section"]:
			other = code
	var result := shift.act("fix", { "section": other })
	_check(not result["correct"] and result["outcome"] == "wrong_fix", "moving a student with nothing wrong is a wrong fix (%s)" % result["outcome"])
	_check(shift.mistakes == 1 and shift.served == 1, "it's a mistake, and they leave")
	_check(student["mood"] != "angry", "they don't come back angry")
	for i in 400:
		shift.tick(STEP)
	_check(not shift.line.has(student), "they never rejoin the line")
	var history: Array = [shift.history[-1]]
	_check(Consequences.build(history)[0]["text"].contains("changed things"), "the report tells the wrong fix story")
	# A fix they did need, done wrong, brings them back for a second try.
	var needs := ShiftState.new(3, 5)
	var full := _student(3, ["closed_section"])
	needs.current = full
	var clashing := ""
	for section: Dictionary in full["record"]["sections"][full["request"]["course"]]:
		if section["seats"] > 0 and Timetable.clashes_schedule(section["slots"], full["record"]["schedule"]):
			clashing = section["code"]
	_check(clashing != "", "found a clashing section")
	_check(needs.act("fix", { "section": clashing })["outcome"] == "sent_back_wrong", "a clashing section sends them back to try again")


func _test_favors() -> void:
	var clean_shift := ShiftState.new(4, 5)
	clean_shift.current = _student(4, [])
	var clean := clean_shift.act("favor")
	_check(clean["correct"] and clean["outcome"] == "served" and not clean["bent"], "a favor for a clean student is just an approval")
	_check(clean_shift.bends == 0, "no bend counted")
	var shift := ShiftState.new(4, 5)
	shift.patience = 50.0
	var student := _student(4, ["unpaid_balance"])
	shift.current = student
	var result := shift.act("favor")
	_check(result["bent"] and result["outcome"] == "bent", "a favor with a balance owed is rule bending")
	_check(shift.bends == 1 and shift.mistakes == 0 and shift.served == 1, "bent: served, not a mistake (%d %d %d)" % [shift.bends, shift.mistakes, shift.served])
	_check(is_equal_approx(shift.patience, 50.0 - GameData.balance("bend_patience")), "the line saw it (%.1f)" % shift.patience)
	_check(shift.history[-1]["bent"] and not shift.history[-1]["correct"], "logged as bent")
	_check(shift.summary()["bends"] == 1, "summary counts favors")
	_check(shift.summary()["accuracy"] == 1.0, "favors aren't counted in accuracy")
	_check(Consequences.build(shift.history)[0]["text"].contains("favor"), "the report tells the favor story")


func _test_own_section_never_drains() -> void:
	var shift := ShiftState.new(6, 5)
	var student := _student(6, [], "enroll_subject")
	shift.current = student
	shift.choosing_section = true
	var own: Dictionary = Timetable.find_section(student, student["request"]["section"])
	var seats: int = own["seats"]
	for i in 2000:
		shift._drain_slots(1.0)
	_check(own["seats"] == seats, "open market never takes the seat a student already holds (%d -> %d)" % [seats, own["seats"]])


func _test_trait_weights() -> void:
	var shift := ShiftState.new(2, 5)
	shift.line = [{ "trait": "impatient" }, { "trait": "" }]
	_check(is_equal_approx(shift.waiting_weight(), 3.0), "an impatient student counts twice")
	shift.line = [{ "trait": "with_parent" }, { "trait": "" }]
	_check(is_equal_approx(shift.waiting_weight(), 1.5), "a student with a parent counts half")
	shift.line = []
	shift.current = { "trait": "impatient" }
	_check(is_equal_approx(shift.waiting_weight(), 1.0), "an impatient student at the window still drains extra")
	var before := shift.minute
	shift.argue()
	_check(is_equal_approx(shift.minute - before, GameData.balance("parent_argue_minutes")), "a parent arguing costs minutes")


func _test_caught_favors_cost_stars() -> void:
	var perfect := ShiftState.new(2, 42)
	_play(perfect, _perfect)
	var summary := perfect.summary()
	summary["caught_bends"] = 1
	_check(Scoring.stars(summary) == 2, "a caught favor costs a star")
	summary["caught_bends"] = 5
	_check(Scoring.stars(summary) == 0, "stars never go below zero")
	summary["reason"] = ""
	_check(Scoring.projected(summary) == 3, "the pause projection ignores the spot check")


func _test_day_one_onboarding_and_events() -> void:
	_check(ShiftEvents.is_onboarding(1), "day 1 is onboarding")
	for day in range(2, 9):
		_check(not ShiftEvents.is_onboarding(day), "day %d never repeats the tutorial" % day)
		var bulletin := ShiftEvents.bulletin_for_day(day)
		_check(bulletin.has("schedule") and bulletin.has("announcement") and bulletin.has("policy") and bulletin.has("event_preview"),
			"day %d has a complete office bulletin" % day)
		_check(not ShiftEvents.events_for_day(day).is_empty(), "day %d has mid-shift events" % day)
	var day1 := ShiftState.new(1, 42)
	_check(day1.line[0]["problems"].is_empty(), "day 1 first student is a clean approval tutorial case")
	_check(ShiftEvents.onboarding_banner(day1.line[0], "called").contains("Welcome to Window 3"), "day 1 shows Ma'am Lorna's welcome")
	_check(day1.line[1]["problems"] == ["missing_requirement"], "day 1 second student teaches flagging and rejection")
	_check(RulesCheck.missing_items(day1.line[1]) == ["req_library"], "day 1 second student is missing library clearance")
	_check(day1.line[0]["priority"] == "" and day1.line[1]["priority"] == "" and day1.line[2]["priority"] == "",
		"day 1 earlier students have no priority badge so triage stands out")
	_check(day1.line[3]["priority"] == "pwd", "day 1 fourth student teaches priority triage")
	var day2 := ShiftState.new(2, 42)
	_check(ShiftEvents.onboarding_banner(day2.line[0], "called") == "", "day 2+ never shows onboarding banners")
	var fired := [0]
	var day6 := ShiftState.new(6, 42)
	day6.event_triggered.connect(func(_e: Dictionary) -> void: fired[0] += 1)
	_play(day6, _perfect)
	_check(fired[0] > 0, "mid-shift events fire during a day 2+ shift")
	for regular: Dictionary in GameData.json("events")["regulars"]:
		var expected_portrait := PortraitGen.roll(int(regular["portrait_seed"]), false, int(regular["year"]))
		_check(expected_portrait["gender"] == regular["gender"], "%s portrait_seed rolls %s" % [regular["id"], regular["gender"]])
		for day_key: String in regular["appearances"]:
			var shift := ShiftState.new(int(day_key), 4242)
			var slot := int(regular["appearances"][day_key]["slot"])
			var s: Dictionary = shift.line[slot] if slot < shift.line.size() else shift._arrivals[slot - shift.line.size()]["student"]
			_check(s["name"] == regular["name"] and s["number"] == int(regular["number"]), "%s day %s name and number" % [regular["id"], day_key])
			_check(s["program"] == regular["program"] and s["record"]["program"] == regular["program"], "%s day %s program" % [regular["id"], day_key])
			_check(s["year"] == int(regular["year"]) and s["record"]["year"] == str(int(regular["year"])), "%s day %s year" % [regular["id"], day_key])
			_check(s["record"]["id_number"] == regular["id_number"], "%s day %s fixed id_number" % [regular["id"], day_key])
			_check(s["portrait"] == expected_portrait, "%s day %s portrait matches portrait_seed" % [regular["id"], day_key])
	for sound_id: String in Sfx.SOUND_IDS:
		_check(Sfx.has_sound(sound_id) and Sfx.stream(sound_id) != null, "sfx %s loads" % sound_id)
