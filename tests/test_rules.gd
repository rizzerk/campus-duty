extends SceneTree
## Run: godot --headless --path . --script res://tests/test_rules.gd

## The problem table from CLAUDE.md, so the data can't drift from the design.
const TABLE := {
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
	"missing_requirement": 2, "closed_section": 3, "unpaid_balance": 4, "ismis_login": 5,
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
	print("rules: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _find(day: int, wanted: Array) -> Dictionary:
	for seed_value in 20000:
		var student := StudentGen.make(seed_value, day)
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
		var student := _find(DAY_FOR[id], [id])
		_check(not student.is_empty(), "generator makes %s on day %d" % [id, DAY_FOR[id]])
		if student.is_empty():
			continue
		var section := ""
		if id == "closed_section":
			section = Timetable.fitting_sections(student)[0]
		for action: String in ACTIONS:
			var result := RulesCheck.judge(student, action, _offices(true), section)
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
	_check(not RulesCheck.judge(student, "fix", _offices(true), student["request"]["section"])["correct"], "picking the full section is wrong")
	var clashing := ""
	for section: Dictionary in student["record"]["sections"][student["request"]["course"]]:
		if section["seats"] > 0 and Timetable.clashes_schedule(section["slots"], student["record"]["schedule"]):
			clashing = section["code"]
	if clashing != "":
		_check(not RulesCheck.judge(student, "fix", _offices(true), clashing)["correct"], "picking a clashing section is wrong")
	_check(RulesCheck.judge(student, "fix", _offices(true), fits[0])["correct"], "picking a fitting section is right")


func _test_office_schedule() -> void:
	_check(OfficeSchedule.status(7, "consultation", 160) == "break", "advisers on break at 10:40 on day 7")
	_check(OfficeSchedule.reopens(7, "consultation", 160), "consultation reopens at 11:00")
	_check(OfficeSchedule.is_open(7, "consultation", 185), "consultation open after break")
	_check(not OfficeSchedule.is_open(7, "dean", 100), "dean closed on day 7")
	_check(OfficeSchedule.is_open(8, "dean", 100), "dean open on day 8")
	_check(not OfficeSchedule.reopens(8, "dean", 220), "dean done for the day at 11:40")
	_check(OfficeSchedule.status(4, "cashier", 130) == "long_line", "long cashier line after 10:00")
	_check(OfficeSchedule.return_minutes(4, "cashier", 130) > OfficeSchedule.return_minutes(4, "cashier", 60), "long line takes longer")


func _test_mismatch() -> void:
	var fake := _find(7, ["fake_signature"])
	var flagged := Mismatch.all_differences(fake)
	_check(flagged.any(func(pair: Array) -> bool: return pair[1] == "signature"), "fake signature shows up as a mismatch")
	var clean := _find(7, [])
	_check(Mismatch.all_differences(clean).is_empty(), "clean papers have no mismatches")


func _test_timetable_clash() -> void:
	var mon_930 := [{ "day": "Mon", "start": 1, "length": 1 }]
	var mon_morning := [{ "day": "Mon", "start": 0, "length": 2 }]
	var tue_930 := [{ "day": "Tue", "start": 1, "length": 1 }]
	_check(Timetable.clashes(mon_930, mon_morning), "overlapping blocks clash")
	_check(not Timetable.clashes(mon_930, tue_930), "different days don't clash")
	_check(Timetable.label([{ "day": "Fri", "start": 4, "length": 2 }]) == "Fri 1:30–4:30", "long block label")
