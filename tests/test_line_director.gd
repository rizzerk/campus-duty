extends SceneTree
## Run: godot --headless --path . --script res://tests/test_line_director.gd

const SEEDS := 30

var _failures: int = 0


func _init() -> void:
	_test_new_problems_per_day()
	_test_same_seed_same_order()
	_test_only_reorders_when_teacher_exists()
	_test_new_problem_comes_early_and_alone()
	_test_warmup_is_easy()
	_test_no_long_streaks()
	_test_forced_problems()
	_test_pressure_builds()
	_test_short_lines_and_disabled()
	_test_shift_uses_director()
	_test_no_student_twice()
	_test_regulars_get_their_problem()
	_test_regular_brings_their_department()
	_test_shift_line_keeps_streak_cap()
	print("line_director: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


## The students a shift would generate, in generator order, with rush flags.
func _raw(day: int, seed_value: int) -> Dictionary:
	var info := GameData.day(day)
	var total := int(info["students"])
	var rush: Array = []
	for i in total:
		rush.append(false)
	for wave: Dictionary in info.get("rush", []):
		for i in int(wave["count"]):
			rush.append(true)
	var students: Array = []
	for i in rush.size():
		students.append(StudentGen.make(seed_value * 100000 + day * 1000 + i, day))
	return { "students": students, "rush": rush }


func _ordered(day: int, seed_value: int) -> Array:
	var raw := _raw(day, seed_value)
	return LineDirector.order(raw["students"], day, seed_value, raw["rush"])


func _seeds_of(line: Array) -> Array:
	var seeds: Array = line.map(func(s: Dictionary) -> int: return int(s["seed"]))
	seeds.sort()
	return seeds


func _test_new_problems_per_day() -> void:
	_check(LineDirector.new_problems(2).is_empty(), "day 2 adds no new problem")
	_check(LineDirector.new_problems(3) == ["closed_section"], "day 3 introduces closed sections")
	_check(LineDirector.new_problems(4) == ["unpaid_balance"], "day 4 introduces unpaid balances")
	var day7 := LineDirector.new_problems(7)
	_check(day7.has("missing_signature") and day7.has("fake_signature") and day7.size() == 2, "day 7 introduces both signature problems")
	_check(day7[0] == "missing_signature", "the more common new problem is taught first")


func _test_same_seed_same_order() -> void:
	var a := _ordered(6, 11)
	var b := _ordered(6, 11)
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i]["seed"] == b[i]["seed"]
	_check(same, "same seed gives the same order")
	var c := _ordered(6, 12)
	var classes := func(line: Array) -> Array: return line.map(func(s: Dictionary) -> String: return LineDirector.problem_class(s))
	_check(classes.call(a) != classes.call(c), "a different seed gives a different sequence of problems")


func _test_only_reorders_when_teacher_exists() -> void:
	var reordered := 0
	for seed_value in range(1, SEEDS + 1):
		for day in range(2, _last_day() + 1):
			var raw := _raw(day, seed_value)
			var line := LineDirector.order(raw["students"], day, seed_value, raw["rush"])
			_check(line.size() == raw["students"].size(), "day %d seed %d keeps the line length" % [day, seed_value])
			var needs_search := false
			for problem: String in LineDirector.new_problems(day):
				if raw["students"].filter(func(s: Dictionary) -> bool: return LineDirector._teaches(s, problem)).is_empty():
					needs_search = true
			if not needs_search:
				_check(_seeds_of(line) == _seeds_of(raw["students"]), "day %d seed %d only reorders the day's students" % [day, seed_value])
				reordered += 1
	_check(reordered > SEEDS * 4, "most days need no swapped-in student (%d)" % reordered)


func _test_new_problem_comes_early_and_alone() -> void:
	for seed_value in range(1, SEEDS + 1):
		for day in range(3, _last_day() + 1):
			var line := _ordered(day, seed_value)
			var problems := LineDirector.new_problems(day)
			var window := 1 + problems.size()
			for problem: String in problems:
				var at := -1
				for i in window:
					if LineDirector._teaches(line[i], problem):
						at = i
						break
				_check(at != -1, "day %d seed %d: %s comes alone within the first %d students" % [day, seed_value, problem, window])


func _test_warmup_is_easy() -> void:
	var easy := 0
	for seed_value in range(1, SEEDS + 1):
		for day in range(2, _last_day() + 1):
			var line := _ordered(day, seed_value)
			var first: Dictionary = line[0]
			_check(not LineDirector.new_problems(day).has(LineDirector.problem_class(first)), "day %d seed %d: the first student isn't the new problem" % [day, seed_value])
			if LineDirector.difficulty(first) <= 1.0:
				easy += 1
	_check(easy >= SEEDS * 7 * 0.9, "the first student is easy in nearly every shift (%d of %d)" % [easy, SEEDS * 7])


func _longest_run(line: Array) -> int:
	var run := 1
	var worst := 1
	for i in range(1, line.size()):
		var key := LineDirector.problem_class(line[i])
		run = run + 1 if key != "" and key == LineDirector.problem_class(line[i - 1]) else 1
		worst = maxi(worst, run)
	return worst


## Two in a row at most, whenever the day's mix allows it. When one problem outnumbers everyone
## else more than two to one, a run is unavoidable; then it must still be no worse than the raw roll.
func _test_no_long_streaks() -> void:
	var possible := 0
	for seed_value in range(1, SEEDS + 1):
		for day in range(2, _last_day() + 1):
			var raw := _raw(day, seed_value)
			var line := LineDirector.order(raw["students"], day, seed_value, raw["rush"])
			var counts := {}
			for student: Dictionary in line:
				var key := LineDirector.problem_class(student)
				if key != "":
					counts[key] = int(counts.get(key, 0)) + 1
			var most := 0
			for key: String in counts:
				most = maxi(most, int(counts[key]))
			# The opening (an easy student, then the new problem) already spends one separator.
			if most <= 2 * (line.size() - most):
				possible += 1
				_check(_longest_run(line) <= 2, "day %d seed %d: no problem three times in a row (longest %d)" % [day, seed_value, _longest_run(line)])
			else:
				_check(_longest_run(line) <= _longest_run(raw["students"]), "day %d seed %d: a crowded day is no streakier than the raw roll" % [day, seed_value])
	_check(possible > SEEDS * 6, "most shifts can avoid streaks entirely (%d of %d)" % [possible, SEEDS * 7])


func _test_forced_problems() -> void:
	var same := true
	for seed_value in range(1, 40):
		same = same and StudentGen.make(seed_value, 6)["problems"] == StudentGen.make(seed_value, 6, [])["problems"]
	_check(same, "no forced problems leaves the generator unchanged")
	for seed_value in range(1, 21):
		var student := StudentGen.make(seed_value, 6, ["inc_prereq"])
		_check(student["problems"].size() <= 1, "a forced student gets nothing else")
		for problem: String in ["failed_prereq", "inc_prereq", "fake_signature", "identity_mismatch"]:
			var day := 7 if problem == "fake_signature" else (5 if problem == "identity_mismatch" else 6)
			_check(not LineDirector.search_student(problem, day, seed_value).is_empty(), "the director always finds a %s student (seed %d)" % [problem, seed_value])
	var both := StudentGen.make(3, 5, ["identity_mismatch", "ismis_login"])
	_check(both["problems"].has("identity_mismatch") and both["problems"].has("ismis_login"), "a problem and what it requires can be forced together")
	_check(both["visit"] == "first_year", "the visit fits the forced problems")


func _test_pressure_builds() -> void:
	var early := 0.0
	var peak := 0.0
	for seed_value in range(1, SEEDS + 1):
		for day in range(4, _last_day() + 1):
			var line := _ordered(day, seed_value)
			var n := line.size()
			var opening := 1 + LineDirector.new_problems(day).size()
			for i in range(opening, opening + 3):
				early += LineDirector.difficulty(line[i])
			var mid := int(n * 0.7)
			for i in range(mid - 1, mid + 2):
				peak += LineDirector.difficulty(line[i])
	_check(peak > early * 1.2, "students near the peak are harder than the early ones (%.0f vs %.0f)" % [peak, early])


func _test_short_lines_and_disabled() -> void:
	var two := [StudentGen.make(1, 4), StudentGen.make(2, 4)]
	_check(LineDirector.order(two, 4, 1) == two, "a line too short to pace is left as is")
	var days: Dictionary = GameData.json("days")["days"]
	days["4"]["director"] = { "enabled": false }
	var raw := _raw(4, 3)
	var line := LineDirector.order(raw["students"], 4, 3, raw["rush"])
	days["4"].erase("director")
	var same := true
	for i in line.size():
		same = same and line[i]["seed"] == raw["students"][i]["seed"]
	_check(same, "a day can turn the director off")


func _test_shift_uses_director() -> void:
	var shift := ShiftState.new(5, 21)
	var everyone: Array = shift.line.duplicate()
	for arrival: Dictionary in shift._arrivals:
		everyone.append(arrival["student"])
	var expected := _ordered(5, 21)
	var numbers_in_order := true
	for i in range(1, everyone.size()):
		numbers_in_order = numbers_in_order and (int(everyone[i]["number"]) > int(everyone[i - 1]["number"]) or everyone[i].has("regular_id") or everyone[i - 1].has("regular_id"))
	_check(numbers_in_order, "queue numbers still count up in arrival order")
	_check(everyone[1]["seed"] == expected[1]["seed"], "the shift's second student is the director's choice")
	var day_one := ShiftState.new(1, 21)
	_check(day_one.line[0].get("onboarding_step", "") == "clean_approve", "day 1 keeps its scripted tutorial order")


## Swapped-in students come from their own seeds, so nobody shows up twice in a shift, even when
## two new problems both need a search.
func _test_no_student_twice() -> void:
	for seed_value in range(1, SEEDS + 1):
		for day in range(2, _last_day() + 1):
			var shift := ShiftState.new(day, seed_value)
			var everyone: Array = shift.line.duplicate()
			for arrival: Dictionary in shift._arrivals:
				everyone.append(arrival["student"])
			var seen := {}
			var twice := false
			for student: Dictionary in everyone:
				twice = twice or seen.has(student["seed"])
				seen[student["seed"]] = true
			_check(not twice, "day %d seed %d: no student appears twice" % [day, seed_value])


## A regular whose line is about a problem arrives with it. With "problem_chance" the line goes
## either way by seed (Mae on day 6: sometimes right, sometimes an INC twist), and both happen.
func _test_regulars_get_their_problem() -> void:
	var matched := 0
	var total := 0
	for regular: Dictionary in GameData.json("events")["regulars"]:
		for day_key: String in regular["appearances"]:
			var appearance: Dictionary = regular["appearances"][day_key]
			var problems: Array = appearance.get("problem", [])
			if problems.is_empty():
				continue
			var day := int(day_key)
			for problem: String in problems:
				_check(GameData.day(day).get("problems", {}).has(problem), "%s's day %d problem %s is in that day's mix" % [regular["name"], day, problem])
			_check(int(appearance["slot"]) >= 1 + LineDirector.new_problems(day).size(), "%s's day %d slot comes after the opening" % [regular["name"], day])
			var outcomes := {}
			for seed_value in range(1, SEEDS + 1):
				var wanted := ShiftEvents.regular_problems(appearance, day, seed_value, int(regular["number"]))
				outcomes[wanted == [""]] = true
				var shift := ShiftState.new(day, seed_value)
				var everyone: Array = shift.line.duplicate()
				for arrival: Dictionary in shift._arrivals:
					everyone.append(arrival["student"])
				for student: Dictionary in everyone:
					if student.get("regular_id", "") == regular["id"]:
						total += 1
						if wanted.has(LineDirector.problem_class(student)):
							matched += 1
			if appearance.has("problem_chance"):
				_check(outcomes.size() == 2, "%s's day %d line goes both ways across seeds" % [regular["name"], day])
	var regulars: Array = GameData.json("events")["regulars"]
	_check(LineDirector.REGULAR_RANGE + regulars.size() <= (1000 - LineDirector.SEARCH_OFFSET) / LineDirector.SEARCH_LIMIT, "every regular has its own block of search seeds under 1000")
	var days: Dictionary = GameData.json("days")
	for day in range(int(days["first_day"]), int(days["last_day"]) + 1):
		_check(LineDirector.new_problems(day).size() <= LineDirector.REGULAR_RANGE, "day %d's new-problem searches stay clear of the regulars' seeds" % day)
	_check(total > 0 and matched >= total * 0.97, "regulars arrive with the problem their line is about (%d of %d)" % [matched, total])
	# A regular brings their own department: on a day with a list, the turn-away follows it.
	for day in range(int(days["first_day"]), _last_day() + 1):
		if GameData.day(day).get("departments", []).is_empty():
			continue
		for seed_value in range(1, SEEDS + 1):
			var shift := ShiftState.new(day, seed_value)
			var everyone: Array = shift.line.duplicate()
			for arrival: Dictionary in shift._arrivals:
				everyone.append(arrival["student"])
			for student: Dictionary in everyone:
				_check(student["problems"].has("wrong_department") == StudentGen.outside_departments(student), "day %d seed %d #%s department and turn-away agree" % [day, seed_value, student.get("number", "?")])


## A regular brings their own program into the slot, so on a day with a department list the
## turn-away follows the regular, not the student they replaced.
func _test_regular_brings_their_department() -> void:
	var day := -1
	for number in range(int(GameData.json("days")["first_day"]), _last_day() + 1):
		if not GameData.day(number).get("departments", []).is_empty():
			day = number
			break
	if day == -1:
		return
	var allowed: Array = GameData.day(day)["departments"]
	var listed := {}
	var unlisted := {}
	for regular: Dictionary in GameData.json("events")["regulars"]:
		var department: String = ShiftEvents._program_info(regular["program"])["department"]
		if allowed.has(department):
			listed = regular
		else:
			unlisted = regular
	_check(not listed.is_empty() and not unlisted.is_empty(), "day %d has regulars on both sides of the list" % day)
	var appearance := { "slot": 3, "ceb": "x", "en": "x" }
	var outsider := StudentGen.make(21, day, ["wrong_department"])
	_check(outsider["problems"].has("wrong_department"), "the outsider starts with the turn-away")
	ShiftEvents._apply_regular(outsider, listed, appearance)
	_check(not outsider["problems"].has("wrong_department"), "%s on the list clears the turn-away" % listed["name"])
	var insider := StudentGen.make(21, day, ["overload"])
	_check(not insider["problems"].has("wrong_department"), "the insider starts without the turn-away")
	ShiftEvents._apply_regular(insider, unlisted, appearance)
	_check(insider["problems"].has("wrong_department"), "%s off the list brings the turn-away" % unlisted["name"])


## The line the player meets (after regulars are placed) still keeps runs at two whenever the mix
## allows it. Day 4 seeds 95 and 134 once made three in a row when a regular's problem was swapped in.
func _test_shift_line_keeps_streak_cap() -> void:
	for day in [3, 4, 7]:
		for seed_value: int in range(1, SEEDS + 1) + [95, 134]:
			var shift := ShiftState.new(day, seed_value)
			var everyone: Array = shift.line.duplicate()
			for arrival: Dictionary in shift._arrivals:
				everyone.append(arrival["student"])
			var counts := {}
			for student: Dictionary in everyone:
				var key := LineDirector.problem_class(student)
				if key != "":
					counts[key] = int(counts.get(key, 0)) + 1
			var most := 0
			for key: String in counts:
				most = maxi(most, int(counts[key]))
			if most <= 2 * (everyone.size() - most):
				_check(_longest_run(everyone) <= 2, "day %d seed %d: the shift's line has no problem three times in a row (longest %d)" % [day, seed_value, _longest_run(everyone)])


func _last_day() -> int:
	return int(GameData.json("days")["last_day"])
