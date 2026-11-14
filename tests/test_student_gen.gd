extends SceneTree
## Run: godot --headless --path . --script res://tests/test_student_gen.gd

const SEEDS := 300

var _failures: int = 0


func _init() -> void:
	_check(StudentGen.make(5, 7) == StudentGen.make(5, 7), "same seed gives the same student")
	_check(StudentGen.make(5, 7)["name"] != StudentGen.make(6, 7)["name"] or StudentGen.make(5, 7)["record"]["id_number"] != StudentGen.make(6, 7)["record"]["id_number"], "different seeds differ")
	var seen := {}
	for day in range(1, _last_day() + 1):
		for seed_value in SEEDS:
			var student := StudentGen.make(seed_value, day)
			_check_student(student, day)
			for id: String in student["problems"]:
				seen[id] = true
	for id: String in GameData.json("problems"):
		_check(seen.has(id), "problem %s shows up somewhere in the season" % id)
	_test_traits()
	_test_traits_dont_change_problems()
	_test_favors()
	_test_personalities()
	_test_department_list()
	print("student_gen: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _paper(student: Dictionary, form: String) -> Dictionary:
	for paper: Dictionary in student["papers"]:
		if paper["form"] == form:
			return paper
	return {}


func _check_student(s: Dictionary, day: int) -> void:
	var info := GameData.day(day)
	var tag := "day %d seed %d" % [day, s["seed"]]
	var problems: Array = s["problems"]
	var record: Dictionary = s["record"]
	_check(problems.size() <= int(info["max_problems"]), "%s too many problems" % tag)
	for id: String in problems:
		_check(info["problems"].has(id), "%s %s not enabled today" % [tag, id])
		_check(GameData.problem(id)["visits"].has(s["visit"]), "%s %s doesn't fit visit %s" % [tag, id, s["visit"]])
		for other: String in GameData.problem(id)["excludes"]:
			_check(not problems.has(other), "%s %s with %s" % [tag, id, other])
	_check(s["visit"] == "first_year" or info["years"].has(float(s["year"])), "%s year %d" % [tag, s["year"]])
	if s["no_id"]:
		_check(day >= 3, "%s no ID card only from day 3" % tag)
		_check(_paper(s, "id_card").is_empty(), "%s no-ID student has no card" % tag)
		_check(s["line"]["en"].contains(record["id_number"]), "%s no-ID student says their number" % tag)
	else:
		_check(_paper(s, "id_card")["fields"]["id_number"] == record["id_number"], "%s id card matches" % tag)
	_check(s["line"]["ceb"] != "" and s["line"]["en"] != "" and not s["line"]["en"].contains("{"), "%s line filled in" % tag)
	_check(problems.has("missing_requirement") == _paper(s, "grad_checklist").get("fields", {}).values().has("Missing"), "%s missing requirement shown" % tag)
	_check(problems.has("ismis_login") == (record["account"] == "Locked"), "%s locked account" % tag)
	var admission := _paper(s, "admission_slip")
	_check((s["visit"] == "first_year") == not admission.is_empty(), "%s admission slip only for first years" % tag)
	if not admission.is_empty():
		_check(problems.has("identity_mismatch") == (admission["fields"]["birthday"] != record["birthday"]), "%s birthday mismatch means an impostor" % tag)
	if problems.has("identity_mismatch"):
		_check(problems.has("ismis_login"), "%s impostors only come for a reset" % tag)
	_check(problems.has("unpaid_balance") == (record["balance"] != "PHP 0.00"), "%s balance" % tag)
	_check(problems.has("wrong_department") == StudentGen.outside_departments(s), "%s wrong department exactly when off today's list" % tag)
	if not info.get("departments", []).is_empty():
		_check(info["departments"].has(record["department"]) != problems.has("wrong_department"), "%s department decides the turn-away" % tag)
	if problems.has("unpaid_balance") and not _paper(s, "assessment").is_empty():
		_check(Mismatch.differs(s, _paper(s, "assessment"), "balance"), "%s balance mismatch flaggable" % tag)
	var cash := _paper(s, "cash")
	_check((s["visit"] == "tuition_payment") == not cash.is_empty(), "%s cash only at the payment window" % tag)
	_check((s["visit"] == "tuition_payment") == record.has("amount_due"), "%s amount due only at the payment window" % tag)
	if not cash.is_empty():
		var paid := Money.parse(cash["fields"]["amount_due"])
		var due := Money.parse(record["amount_due"])
		_check(Money.parse(_paper(s, "assessment")["fields"]["amount_due"]) == due, "%s assessment slip matches ISMIS" % tag)
		_check(problems.has("short_payment") == (paid < due), "%s short exactly when the cash is less" % tag)
		_check(problems.has("overpayment") == (paid > due), "%s over exactly when the cash is more" % tag)
		_check(paid > 0 and due > 0, "%s amounts are positive" % tag)
	var slip := _paper(s, "consultation_slip")
	if not slip.is_empty():
		var bad_signature: bool = problems.has("fake_signature") or problems.has("missing_signature")
		_check(bad_signature == Mismatch.differs(s, slip, "signature"), "%s signature mismatch" % tag)
	var form := _paper(s, "add_drop")
	if not form.is_empty():
		_check(problems.has("overload") == (int(form["fields"]["units_after"]) > 24), "%s overload units" % tag)
		var request: Dictionary = s["request"]
		var fits := Timetable.section_fits(s, request["section"])
		_check(problems.has("closed_section") != fits, "%s requested section fit" % tag)
		_check(not Timetable.fitting_sections(s).is_empty(), "%s an open section fits" % tag)
		var prereq: String = request["prereq"]
		if prereq != "" and record["grades"].has(prereq):
			_check(problems.has("failed_prereq") == (record["grades"][prereq] == "5.0"), "%s failed prereq grade" % tag)
			_check(problems.has("inc_prereq") == (record["grades"][prereq] == "INC"), "%s INC grade" % tag)
	if problems.is_empty():
		_check(Mismatch.real_differences(s).is_empty(), "%s clean student has no real mismatches" % tag)
	_check(day >= 3 or s["harmless"].is_empty(), "%s harmless quirks only from day 3" % tag)
	for key: String in s["harmless"]:
		_check(Mismatch.differs(s, _paper(s, "id_card"), key), "%s harmless %s shows on the ID" % [tag, key])
		_check(not Mismatch.real_differs(s, _paper(s, "id_card"), key), "%s harmless %s isn't real" % [tag, key])


## Extension day: both sides of the list show up, roughly at the day's rate, and days without a
## list pick programs exactly as before (wrong_department never appears there).
func _test_department_list() -> void:
	var day := -1
	var plain := -1
	for number in range(int(GameData.json("days")["first_day"]), _last_day() + 1):
		if GameData.day(number).get("departments", []).is_empty():
			plain = number
		elif day == -1:
			day = number
	_check(day != -1 and plain != -1, "the season has a day with a department list and one without")
	if day == -1 or plain == -1:
		return
	var outside := 0
	for seed_value in SEEDS:
		if StudentGen.make(seed_value, day)["problems"].has("wrong_department"):
			outside += 1
	var rate := float(GameData.day(day)["problems"]["wrong_department"])
	_check(absf(float(outside) / SEEDS - rate) < 0.1, "day %d turn-aways near %.2f (got %d of %d)" % [day, rate, outside, SEEDS])
	var forced := StudentGen.make(11, day, ["wrong_department"])
	_check(forced["problems"] == ["wrong_department"], "forced wrong_department lands on its own")
	var clean := StudentGen.make(11, day, ["overload"])
	_check(not clean["problems"].has("wrong_department"), "forcing another problem keeps the department on the list")
	var student := StudentGen.make(3, day)
	student["record"]["department"] = GameData.day(day)["departments"][0]
	StudentGen.sync_department(student)
	_check(not student["problems"].has("wrong_department"), "sync removes it for a listed department")
	student["record"]["department"] = "Dept. of Nowhere"
	StudentGen.sync_department(student)
	_check(student["problems"].count("wrong_department") == 1, "sync adds it once for an unlisted department")
	var other := StudentGen.make(3, plain)
	other["record"]["department"] = "Dept. of Nowhere"
	StudentGen.sync_department(other)
	_check(not other["problems"].has("wrong_department"), "no department rule on a day without a list")


func _test_traits() -> void:
	var traits: Dictionary = GameData.json("traits")
	var seen := {}
	for day in range(2, _last_day() + 1):
		var allowed: Dictionary = GameData.day(day).get("traits", {})
		for id: String in allowed:
			_check(traits.has(id), "day %d trait %s exists" % [day, id])
		for seed_value in SEEDS:
			var student := StudentGen.make(seed_value, day)
			var id: String = student["trait"]
			var accessories: Array = student["portrait"]["accessories"]
			_check(accessories.has("accessory_sweat_drop") == (id == "impatient"), "sweat drop only on impatient students")
			_check(accessories.has("accessory_sunglasses") == (id == "kapit"), "sunglasses only on kapit students")
			_check(student["portrait"].has("parent") == (id == "with_parent"), "parent only with the trait")
			if id == "":
				continue
			seen[id] = true
			_check(allowed.has(id), "day %d only rolls its own traits (%s)" % [day, id])
			var visits: Array = traits[id].get("visits", [])
			_check(visits.is_empty() or visits.has(student["visit"]), "%s only on %s" % [id, visits])
			var tell: Dictionary = traits[id]["tell"]
			if tell.has("expression"):
				_check(student["portrait"]["expression"] == tell["expression"], "%s rests with its face" % id)
			if id == "kapit":
				_check(student["favor"] == "connections", "kapit always pushes for a favor")
	for id: String in traits:
		_check(seen.has(id), "trait %s shows up somewhere" % id)
		var info: Dictionary = traits[id]
		_check(info.has("lines") or info.has("favor"), "trait %s has something to say" % id)


## Traits use their own random numbers, so turning them off leaves every problem and paper as is.
func _test_traits_dont_change_problems() -> void:
	var days: Dictionary = GameData.json("days")["days"]
	var with_traits := {}
	for seed_value in 200:
		with_traits[seed_value] = StudentGen.make(seed_value, 7)
	var saved: Dictionary = days["7"]["traits"]
	var saved_favors: float = days["7"]["favor_chance"]
	days["7"]["traits"] = {}
	days["7"]["favor_chance"] = 0.0
	for seed_value in 200:
		var plain := StudentGen.make(seed_value, 7)
		var traited: Dictionary = with_traits[seed_value]
		_check(plain["problems"] == traited["problems"], "seed %d keeps its problems" % seed_value)
		_check(plain["papers"] == traited["papers"], "seed %d keeps its papers" % seed_value)
		_check(plain["record"] == traited["record"], "seed %d keeps its record" % seed_value)
	days["7"]["traits"] = saved
	days["7"]["favor_chance"] = saved_favors


func _test_favors() -> void:
	var favors: Dictionary = GameData.json("favors")
	for id: String in favors:
		_check(not favors[id]["lines"].is_empty(), "favor %s has lines" % id)
	var on_clean := 0
	var on_problem := 0
	for seed_value in 1000:
		var student := StudentGen.make(seed_value, 7)
		if student["favor"] == "":
			continue
		_check(favors.has(student["favor"]), "favor %s exists" % student["favor"])
		if student["problems"].is_empty():
			on_clean += 1
		else:
			on_problem += 1
	_check(on_clean > 10 and on_problem > 10, "favors come from clean and problem students alike (%d, %d)" % [on_clean, on_problem])
	for seed_value in 300:
		_check(StudentGen.make(seed_value, 3)["favor"] == "", "no favors before day 4")
	var both := 0
	for seed_value in 5000:
		var student := StudentGen.make(seed_value, 7)
		if student["no_id"] and student["favor"] != "":
			both += 1
			_check(student["line"]["en"].contains(student["record"]["id_number"]), "no ID: they still say their number")
			var offers: Array = favors[student["favor"]]["lines"]
			_check(offers.any(func(o: Dictionary) -> bool: return student["line"]["en"].ends_with(o["en"])), "no ID: they still ask for the favor")
	_check(both > 0, "some students have no ID and ask for a favor")


func _test_personalities() -> void:
	var personalities: Dictionary = GameData.json("dialogue")["personalities"]
	var seen_personalities := {}
	var routine_count := 0
	for seed_value in 400:
		var student := StudentGen.make(seed_value, 2)
		var p: String = student.get("personality", "")
		_check(p == "routine" or personalities.has(p), "valid personality %s" % p)
		if p == "routine":
			routine_count += 1
		else:
			seen_personalities[p] = true
	_check(routine_count > 150, "most normal transactions use concise routine dialogue (%d/400)" % routine_count)
	for p: String in personalities:
		_check(seen_personalities.has(p), "personality %s appears" % p)


func _last_day() -> int:
	return int(GameData.json("days")["last_day"])
