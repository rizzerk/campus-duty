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
	for day in range(2, 9):
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
	var game_state: GDScript = load("res://scripts/autoload/game_state.gd")
	var idle := ShiftState.new(2, 42)
	_play(idle, func(_s: ShiftState) -> Array: return [])
	_check(game_state.stars_for(idle.summary()) == 0, "waiting out the clock earns no stars (%s)" % idle.end_reason)
	var perfect := ShiftState.new(2, 42)
	_play(perfect, _perfect)
	_check(game_state.stars_for(perfect.summary()) == 3, "perfect day 2 earns 3 stars")
	var walkout := perfect.summary()
	walkout["walked_out"] = 1
	_check(game_state.stars_for(walkout) == 2, "a walkout caps stars at 2")
	var failed := perfect.summary()
	failed["reason"] = "patience"
	_check(game_state.stars_for(failed) == 0, "a failed shift earns no stars")
	var half := perfect.summary()
	half["served_ratio"] = 0.6
	_check(game_state.stars_for(half) == 1, "serving only 60% of the line caps stars at 1")


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
