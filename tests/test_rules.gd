extends SceneTree
## Run: godot --headless --path . --script res://tests/test_rules.gd

## The problem table from CLAUDE.md, so the data can't drift from the design. identity_mismatch
## comes from the S11 reset mockup ("getting a fact wrong prints a password for the wrong student").
const TABLE := {
	"identity_mismatch": "reject",
	"missing_requirement": "reject",
	"closed_section": "fix",
	"unpaid_balance": "route:cashier",
	"ismis_login": "fix",
	"missing_signature": "route:consultation",
	"overload": "route:dean",
	"fake_signature": "reject",
	"failed_prereq": "reject",
	"inc_prereq": "route:consultation",
}
const DAY_FOR := {
	"identity_mismatch": 5, "missing_requirement": 2, "closed_section": 3, "unpaid_balance": 4, "ismis_login": 5,
	"failed_prereq": 6, "inc_prereq": 6, "missing_signature": 7, "fake_signature": 7, "overload": 8,
}
const ACTIONS := ["approve", "fix", "hold", "reject", "route:cashier", "route:consultation", "route:dean"]

var _failures: int = 0


func _init() -> void:
	_test_table_matches_data()
	_test_each_problem_has_one_right_action()
	_test_clean_student_is_approved()
	_test_reject_beats_routing()
	_test_closed_office_means_hold_or_tomorrow()
	_test_section_pick_must_fit()
	_test_office_schedule()
	_test_mismatch()
	_test_timetable_clash()
	_test_flag_scoring()
	_test_reject_needs_reason()
	_test_days_teach_what_they_need()
	print("rules: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _find(day: int, wanted: Array) -> Dictionary:
	for seed_value in 20000:
		var student := StudentGen.make(seed_value, day)
		if student["no_id"]:
			continue
		var problems: Array = student["problems"].duplicate()
		problems.sort()
		var target := wanted.duplicate()
		target.sort()
		if problems == target:
			return student
	return {}


func _offices(open: bool, reopens: bool = false) -> Dictionary:
	var result := {}
	for office: String in GameData.json("offices"):
		result[office] = { "status": "open" if open else "break", "open": open, "reopens": reopens }
	return result


func _test_table_matches_data() -> void:
	for id: String in TABLE:
		_check(GameData.problem(id)["action"] == TABLE[id], "data action for %s" % id)
	_check(GameData.json("problems").size() == TABLE.size(), "every problem is in the table")


func _test_each_problem_has_one_right_action() -> void:
	for id: String in TABLE:
		var wanted: Array = [id] + GameData.problem(id).get("requires", [])
		var student := _find(DAY_FOR[id], wanted)
		_check(not student.is_empty(), "generator makes %s on day %d" % [id, DAY_FOR[id]])
		if student.is_empty():
			continue
		var section := ""
		if id == "closed_section":
			section = Timetable.fitting_sections(student)[0]
		var want := RulesCheck.expected(student, _offices(true))
		for action: String in ACTIONS:
			var result := RulesCheck.judge(student, action, _offices(true), { "section": section, "reason": want["reason_id"], "items": want["items"] })
			_check(result["correct"] == (action == TABLE[id]), "%s with %s" % [id, action])
			_check(result["reason"] != "", "%s has a reason" % id)


func _test_clean_student_is_approved() -> void:
	for day in range(2, 9):
		var student := _find(day, [])
		_check(RulesCheck.judge(student, "approve", _offices(true))["correct"], "clean approve day %d" % day)
		_check(not RulesCheck.judge(student, "reject", _offices(true))["correct"], "clean reject is wrong day %d" % day)


func _test_reject_beats_routing() -> void:
	var student := _find(7, ["fake_signature", "unpaid_balance"])
	if student.is_empty():
		student = _find(7, ["unpaid_balance"])
		student["problems"].append("fake_signature")
	_check(RulesCheck.expected(student, _offices(true))["action"] == "reject", "fake signature beats unpaid balance")
	var both := _find(4, ["unpaid_balance"])
	both["problems"].append("closed_section")
	_check(RulesCheck.expected(both, _offices(true))["action"] == "route:cashier", "cashier comes before the section picker")


func _test_closed_office_means_hold_or_tomorrow() -> void:
	var student := _find(7, ["missing_signature"])
	_check(RulesCheck.expected(student, _offices(false, true))["action"] == "hold", "break means hold")
	_check(not RulesCheck.judge(student, "route:consultation", _offices(false, true))["correct"], "routing to a closed office is wrong")
	_check(not RulesCheck.judge(student, "hold", _offices(true))["correct"], "hold while open is wrong")
	_check(RulesCheck.expected(student, _offices(false, false))["action"] == "reject", "closed for the day means come back tomorrow")


func _test_section_pick_must_fit() -> void:
	var student := _find(3, ["closed_section"])
	var fits := Timetable.fitting_sections(student)
	_check(fits.size() >= 2, "at least two open sections fit")
	_check(not fits.has(student["request"]["section"]), "requested section no longer fits")
	_check(not RulesCheck.judge(student, "fix", _offices(true), { "section": student["request"]["section"] })["correct"], "picking the full section is wrong")
	var clashing := ""
	for section: Dictionary in student["record"]["sections"][student["request"]["course"]]:
		if section["seats"] > 0 and Timetable.clashes_schedule(section["slots"], student["record"]["schedule"]):
			clashing = section["code"]
	if clashing != "":
		_check(not RulesCheck.judge(student, "fix", _offices(true), { "section": clashing })["correct"], "picking a clashing section is wrong")
	_check(RulesCheck.judge(student, "fix", _offices(true), { "section": fits[0] })["correct"], "picking a fitting section is right")


func _test_office_schedule() -> void:
	_check(OfficeSchedule.status(7, "consultation", 160) == "break", "advisers on break at 10:40 on day 7")
	_check(OfficeSchedule.reopens(7, "consultation", 160), "consultation reopens at 11:00")
	_check(OfficeSchedule.is_open(7, "consultation", 185), "consultation open after break")
	_check(not OfficeSchedule.is_open(7, "dean", 100), "dean closed on day 7")
	_check(OfficeSchedule.is_open(8, "dean", 100), "dean open on day 8")
	_check(not OfficeSchedule.reopens(8, "dean", 220), "dean done for the day at 11:40")
	_check(OfficeSchedule.status(4, "cashier", 130) == "long_line", "long cashier line after 10:00")
	_check(OfficeSchedule.return_minutes(4, "cashier", 130) > OfficeSchedule.return_minutes(4, "cashier", 60), "long line takes longer")
	_check(OfficeSchedule.detail(7, "consultation", 160) == "Back at 11:00", "break note says when they're back")
	_check(OfficeSchedule.detail(7, "consultation", 100) == "Break at 10:30", "warns before the break")
	_check(OfficeSchedule.detail(8, "dean", 100) == "Open until 11:30", "dean closing time shown")
	_check(OfficeSchedule.detail(8, "dean", 220) == "Closed today", "dean done for the day")
	_check(OfficeSchedule.detail(2, "cashier", 50) == "Open", "plain open")


func _test_mismatch() -> void:
	var fake := _find(7, ["fake_signature"])
	var flagged := Mismatch.real_differences(fake)
	_check(flagged.any(func(pair: Array) -> bool: return pair[1] == "signature"), "fake signature shows up as a mismatch")
	var clean := _find(7, [])
	_check(Mismatch.real_differences(clean).is_empty(), "clean papers have no mismatches")


func _test_timetable_clash() -> void:
	var mon_930 := [{ "day": "Mon", "start": 1, "length": 1 }]
	var mon_morning := [{ "day": "Mon", "start": 0, "length": 2 }]
	var tue_930 := [{ "day": "Tue", "start": 1, "length": 1 }]
	_check(Timetable.clashes(mon_930, mon_morning), "overlapping blocks clash")
	_check(not Timetable.clashes(mon_930, tue_930), "different days don't clash")
	_check(Timetable.label([{ "day": "Fri", "start": 4, "length": 2 }]) == "Fri 1:30–4:30", "long block label")


func _test_flag_scoring() -> void:
	var fake := _find(7, ["fake_signature"])
	var slip_index := -1
	for i in fake["papers"].size():
		if fake["papers"][i]["form"] == "consultation_slip":
			slip_index = i
	var adviser: String = fake["papers"][slip_index]["fields"]["adviser"]
	var other := ""
	for entry: Dictionary in fake["record"]["advisers"]:
		if entry["name"] != adviser:
			other = entry["name"]
	var right := { "form": slip_index, "key": "signature", "context": adviser }
	var wrong_adviser := { "form": slip_index, "key": "signature", "context": other }
	var matching := { "form": 0, "key": "id_number", "context": "" }
	var score := Mismatch.score_flags(fake, [right, wrong_adviser, matching])
	_check(score["caught"] == 1, "the real fake signature is caught")
	_check(score["false_alarms"] == 2, "wrong adviser and a matching field are false alarms")
	var quirky := {}
	for seed_value in 20000:
		var student := StudentGen.make(seed_value, 3)
		if student["harmless"].has("name") and student["problems"].is_empty():
			quirky = student
			break
	_check(not quirky.is_empty(), "day 3 makes harmless short names")
	_check(Mismatch.differs(quirky, quirky["papers"][0], "name"), "a short name differs")
	_check(Mismatch.score_flags(quirky, [{ "form": 0, "key": "name", "context": "" }])["false_alarms"] == 1, "flagging a short name is a false alarm")
	_check(RulesCheck.judge(quirky, "approve", _offices(true))["correct"], "a short name is still approved")


func _test_reject_needs_reason() -> void:
	var missing := _find(2, ["missing_requirement"])
	var items: Array = RulesCheck.missing_items(missing)
	_check(not items.is_empty(), "missing items listed")
	var good := { "reason": "missing_requirement", "items": items }
	_check(RulesCheck.judge(missing, "reject", _offices(true), good)["correct"], "right reason and list")
	_check(not RulesCheck.judge(missing, "reject", _offices(true), { "reason": "fake_signature", "items": items })["correct"], "wrong reason fails")
	_check(not RulesCheck.judge(missing, "reject", _offices(true), { "reason": "missing_requirement", "items": [] })["correct"], "empty list fails")
	var too_many := ["req_exit_survey", "req_grad_fee", "req_library", "req_photo"]
	_check(not RulesCheck.judge(missing, "reject", _offices(true), { "reason": "missing_requirement", "items": too_many })["correct"] or items == too_many, "over-ticked list fails")
	_check(not RulesCheck.judge(missing, "reject", _offices(true))["correct"], "no reason fails")
	var fake := _find(7, ["fake_signature"])
	_check(RulesCheck.judge(fake, "reject", _offices(true), { "reason": "fake_signature" })["correct"], "fake signature with its reason")
	var failed := _find(6, ["failed_prereq"])
	_check(RulesCheck.judge(failed, "reject", _offices(true), { "reason": "failed_prereq" })["correct"], "failed prerequisite with its reason")
	var overload := _find(8, ["overload"])
	var closed := RulesCheck.expected(overload, _offices(false, false))
	_check(closed["action"] == "reject" and closed["reason_id"] == "office_closed", "office shut for the day means reject: office_closed")
	_check(RulesCheck.judge(overload, "reject", _offices(false, false), { "reason": "office_closed" })["correct"], "come back tomorrow with its reason")


## Every problem a day can throw must be answerable with the buttons and reasons learned by then.
func _test_days_teach_what_they_need() -> void:
	var days: Dictionary = GameData.json("days")
	var actions: Array = []
	var reasons: Array = []
	for day in range(int(days["first_day"]), int(days["last_day"]) + 1):
		var info := GameData.day(day)
		actions.append_array(info.get("actions", []))
		reasons.append_array(info.get("reject_reasons", []))
		for problem: String in info["problems"]:
			var action: String = GameData.problem(problem)["action"]
			if action == "reject":
				_check(reasons.has(problem), "day %d: %s needs its reject reason unlocked" % [day, problem])
			elif action == "fix":
				_check(actions.has("fix"), "day %d: %s needs Fix" % [day, problem])
			elif action.begins_with("route:"):
				_check(actions.has("route"), "day %d: %s needs Route" % [day, problem])
				var office := action.trim_prefix("route:")
				for minute in range(0, 240, 5):
					if not OfficeSchedule.is_open(day, office, minute):
						if OfficeSchedule.reopens(day, office, minute):
							_check(actions.has("hold"), "day %d: %s office shut at minute %d needs Hold" % [day, problem, minute])
						else:
							_check(reasons.has("office_closed"), "day %d: %s office closed at minute %d needs the office_closed reason" % [day, problem, minute])
		for reason: String in reasons:
			_check(GameData.json("reject_reasons").has(reason), "reason %s has a label" % reason)
	_check(actions.has("approve") and actions.has("reject"), "approve and reject are taught")
