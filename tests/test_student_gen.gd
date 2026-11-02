extends SceneTree
## Run: godot --headless --path . --script res://tests/test_student_gen.gd

const SEEDS := 300

var _failures: int = 0


func _init() -> void:
	_check(StudentGen.make(5, 7) == StudentGen.make(5, 7), "same seed gives the same student")
	_check(StudentGen.make(5, 7)["name"] != StudentGen.make(6, 7)["name"] or StudentGen.make(5, 7)["record"]["id_number"] != StudentGen.make(6, 7)["record"]["id_number"], "different seeds differ")
	var seen := {}
	for day in range(2, 9):
		for seed_value in SEEDS:
			var student := StudentGen.make(seed_value, day)
			_check_student(student, day)
			for id: String in student["problems"]:
				seen[id] = true
	for id: String in GameData.json("problems"):
		_check(seen.has(id), "problem %s shows up somewhere in days 2-8" % id)
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
	if problems.has("unpaid_balance") and not _paper(s, "assessment").is_empty():
		_check(Mismatch.differs(s, _paper(s, "assessment"), "balance"), "%s balance mismatch flaggable" % tag)
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
