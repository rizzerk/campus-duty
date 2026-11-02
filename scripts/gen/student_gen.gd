class_name StudentGen
extends RefCounted
## Builds a student from a seed and the day's rules in data/days.json: ID, name, program, ISMIS
## record, the papers they hand over, their problems and their portrait. Same seed, same student.

const SECTION_LETTERS := ["A", "B", "C", "D", "E", "F"]
const SEASON_YEAR := 2026


static func make(seed_value: int, day_number: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var day := GameData.day(day_number)
	var visit: String = _pick_weighted(rng, day["visits"])
	var year: int = 1 if visit == "first_year" else int(_pick(rng, day["years"]))
	var program: Dictionary = _pick(rng, GameData.json("students")["programs"])
	var portrait := PortraitGen.roll(seed_value, false, year)
	var student := {
		"seed": seed_value,
		"day": day_number,
		"visit": visit,
		"year": year,
		"program": program["code"],
		"name": _make_name(rng, portrait["gender"]),
		"priority": _roll_priority(rng, year, day_number),
		"portrait": portrait,
		"request": {},
		"problems": [],
		"harmless": [],
		"no_id": false,
		"returns": 0,
		"mood": "calm",
	}
	student["record"] = _make_record(rng, student, program)
	if visit in ["enroll_subject", "add_subject"]:
		_add_course_request(rng, student, program)
	student["papers"] = _make_papers(rng, student, program)
	_roll_problems(rng, student, day)
	# Some students come without their ID card; the player searches ISMIS by number instead.
	if rng.randf() < float(day.get("no_id_chance", 0.0)):
		student["papers"].remove_at(0)
		student["no_id"] = true
	_roll_harmless(rng, student, program, day)
	student["line"] = _make_line(rng, student)
	return student


static func _make_name(rng: RandomNumberGenerator, gender: String) -> String:
	var names: Dictionary = GameData.json("students")
	return "%s %s" % [_pick(rng, names["first_names"][gender]), _pick(rng, names["last_names"])]


static func _roll_priority(rng: RandomNumberGenerator, year: int, day_number: int) -> String:
	# On day 2 everyone is graduating, so GRAD only stands out on other days.
	if year == 4 and day_number != 2 and rng.randf() < 0.2:
		return "grad"
	if rng.randf() < 0.05:
		return "pwd"
	return ""


static func _make_record(rng: RandomNumberGenerator, student: Dictionary, program: Dictionary) -> Dictionary:
	var data: Dictionary = GameData.json("students")
	var entry_year: int = SEASON_YEAR - (int(student["year"]) - 1)
	var grades := {}
	for past_year in range(1, student["year"]):
		for course: Dictionary in program["courses"][str(past_year)]:
			grades[course["code"]] = _pick(rng, data["passing_grades"])
	var record := {
		"id_number": "%d%04d" % [entry_year, rng.randi_range(1000, 9999)],
		"name": student["name"],
		"program": program["code"],
		"year": str(student["year"]),
		"department": program["department"],
		"balance": "PHP 0.00",
		"account": "Active",
		"max_units": 24,
		"units_enrolled": int(_pick(rng, data["unit_loads"])),
		"grades": grades,
		"schedule": [],
		"sections": {},
		"advisers": program["advisers"].duplicate(true),
	}
	if student["visit"] == "graduation_clearance":
		for requirement: Dictionary in data["grad_requirements"]:
			record[requirement["key"]] = "Attached"
	return record


## Picks a course from the student's year, fills their current schedule and lays out sections so
## at least three open sections fit (so one can be closed and two still fit) and some clash.
static func _add_course_request(rng: RandomNumberGenerator, student: Dictionary, program: Dictionary) -> void:
	var courses: Array = program["courses"][str(student["year"])]
	var wanted: Dictionary = _pick(rng, courses)
	var record: Dictionary = student["record"]
	var options := Timetable.all_options()
	for course: Dictionary in courses:
		if course["code"] == wanted["code"]:
			continue
		var free := options.filter(func(slots: Array) -> bool: return not Timetable.clashes_schedule(slots, record["schedule"]))
		if free.is_empty():
			break
		record["schedule"].append({
			"course": course["code"],
			"section": "%s-%s" % [course["code"], _pick(rng, SECTION_LETTERS)],
			"slots": _pick(rng, free),
		})
	var fitting := options.filter(func(slots: Array) -> bool: return not Timetable.clashes_schedule(slots, record["schedule"]))
	var clashing := options.filter(func(slots: Array) -> bool: return Timetable.clashes_schedule(slots, record["schedule"]))
	_shuffle(rng, fitting)
	_shuffle(rng, clashing)
	var layouts: Array = fitting.slice(0, 3) + clashing.slice(0, 3)
	_shuffle(rng, layouts)
	var sections: Array = []
	for i in layouts.size():
		sections.append({
			"code": "%s-%s" % [wanted["code"], SECTION_LETTERS[i]],
			"slots": layouts[i],
			"seats": rng.randi_range(1, 12),
			"capacity": 40,
		})
	# One clashing section is already full, like the mockup's "Window 1 took the last one".
	for section: Dictionary in sections:
		if Timetable.clashes_schedule(section["slots"], record["schedule"]):
			section["seats"] = 0
			break
	record["sections"][wanted["code"]] = sections
	var fits := Timetable.fitting_sections({ "request": { "course": wanted["code"] }, "record": record })
	var section_code: String = _pick(rng, fits)
	student["request"] = {
		"course": wanted["code"],
		"title": wanted["title"],
		"prereq": wanted.get("prereq", ""),
		"section": section_code,
		"units": 3,
	}


static func _make_papers(rng: RandomNumberGenerator, student: Dictionary, program: Dictionary) -> Array:
	var record: Dictionary = student["record"]
	var papers: Array = [{
		"form": "id_card",
		"title": "Student ID",
		"fields": { "id_number": record["id_number"], "name": record["name"], "program": record["program"], "year": record["year"] },
	}]
	match student["visit"]:
		"graduation_clearance":
			var fields := {}
			for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
				fields[requirement["key"]] = "Attached"
			papers.append({ "form": "grad_checklist", "title": "Graduation clearance", "fields": fields })
		"enrollment_payment", "first_year":
			papers.append({ "form": "assessment", "title": "Assessment slip", "fields": { "id_number": record["id_number"], "balance": "PHP 0.00" } })
		"enroll_subject", "add_subject":
			var request: Dictionary = student["request"]
			papers.append({
				"form": "add_drop",
				"title": "Enrollment form" if student["visit"] == "enroll_subject" else "Add/drop form",
				"fields": {
					"id_number": record["id_number"],
					"course": request["course"],
					"section": request["section"],
					"units_after": record["units_enrolled"] + request["units"],
				},
			})
			if student["visit"] == "add_subject":
				var adviser: Dictionary = _pick(rng, program["advisers"])
				papers.append({ "form": "consultation_slip", "title": "Consultation slip", "fields": { "adviser": adviser["name"], "signature": adviser["specimen"] } })
	return papers


static func _roll_problems(rng: RandomNumberGenerator, student: Dictionary, day: Dictionary) -> void:
	var candidates: Array = day["problems"].keys()
	_shuffle(rng, candidates)
	for id: String in candidates:
		if student["problems"].size() >= int(day["max_problems"]):
			break
		var info := GameData.problem(id)
		if not info["visits"].has(student["visit"]):
			continue
		if info["excludes"].any(func(other: String) -> bool: return student["problems"].has(other)):
			continue
		if rng.randf() < float(day["problems"][id]) and _apply_problem(rng, student, id):
			student["problems"].append(id)


## What an office hands back once it has sorted a problem out: the record or papers change so the
## problem is gone, and the student usually carries proof.
static func resolve(student: Dictionary, problem: String) -> void:
	var record: Dictionary = student["record"]
	match problem:
		"unpaid_balance":
			student["papers"].append({
				"form": "receipt",
				"title": "Official receipt",
				"fields": { "id_number": record["id_number"], "amount_paid": record["balance"] },
			})
			record["balance"] = "PHP 0.00"
			var assessment := _paper(student, "assessment")
			if not assessment.is_empty():
				assessment["fields"]["balance"] = "PHP 0.00"
		"missing_signature":
			var slip := _paper(student, "consultation_slip")
			for adviser: Dictionary in record["advisers"]:
				if adviser["name"] == slip["fields"]["adviser"]:
					slip["fields"]["signature"] = adviser["specimen"]
		"inc_prereq":
			var adviser: Dictionary = record["advisers"][0]
			student["papers"].append({
				"form": "adviser_note",
				"title": "Adviser's note",
				"fields": { "note": "OK to take %s" % student["request"]["course"], "adviser": adviser["name"], "signature": adviser["specimen"] },
			})
		"overload":
			student["papers"].append({
				"form": "dean_approval",
				"title": "Dean's approval",
				"fields": { "approved_units": _paper(student, "add_drop")["fields"]["units_after"], "note": "Overload approved" },
			})


## A difference that doesn't matter: a shortened first name or another way of writing the
## program on the ID card. The record keeps the official spelling.
static func _roll_harmless(rng: RandomNumberGenerator, student: Dictionary, program: Dictionary, day: Dictionary) -> void:
	if rng.randf() >= float(day.get("harmless_chance", 0.0)):
		return
	var card := _paper(student, "id_card")
	if card.is_empty():
		return
	if rng.randf() < 0.5:
		var first: String = student["name"].get_slice(" ", 0)
		var short := "Ma." if first == "Maria" else first.left(1) + "."
		card["fields"]["name"] = student["name"].replace(first, short)
		student["harmless"].append("name")
	else:
		card["fields"]["program"] = _pick(rng, program["aliases"])
		student["harmless"].append("program")


## Changes the papers or record so the problem is really there to find. False if it can't apply.
static func _apply_problem(rng: RandomNumberGenerator, student: Dictionary, id: String) -> bool:
	var record: Dictionary = student["record"]
	match id:
		"missing_requirement":
			var checklist := _paper(student, "grad_checklist")
			var keys: Array = checklist["fields"].keys()
			_shuffle(rng, keys)
			for key: String in keys.slice(0, rng.randi_range(1, 2)):
				checklist["fields"][key] = "Missing"
		"closed_section":
			Timetable.find_section(student, student["request"]["section"])["seats"] = 0
		"unpaid_balance":
			record["balance"] = _pick(rng, GameData.json("students")["balances"])
		"ismis_login":
			record["account"] = "Locked"
		"missing_signature":
			_paper(student, "consultation_slip")["fields"]["signature"] = ""
		"fake_signature":
			var slip := _paper(student, "consultation_slip")
			slip["fields"]["signature"] = _forge(rng, slip["fields"]["signature"])
		"overload":
			record["units_enrolled"] = rng.randi_range(22, 24)
			_paper(student, "add_drop")["fields"]["units_after"] = record["units_enrolled"] + student["request"]["units"]
		"failed_prereq", "inc_prereq":
			var prereq: String = student["request"].get("prereq", "")
			if prereq == "" or not record["grades"].has(prereq):
				return false
			record["grades"][prereq] = "5.0" if id == "failed_prereq" else "INC"
		_:
			return false
	return true


## A near miss of the real signature: a doubled letter, a dropped letter, a stray dot or a case slip.
static func _forge(rng: RandomNumberGenerator, specimen: String) -> String:
	match rng.randi_range(0, 3):
		0:
			return specimen + specimen.right(1)
		1:
			return specimen.left(specimen.length() - 1)
		2:
			return specimen.insert(1, ".") if not specimen.contains(".") else specimen.replace(".", "")
		_:
			return specimen.to_lower() if specimen != specimen.to_lower() else specimen.capitalize()


static func _make_line(rng: RandomNumberGenerator, student: Dictionary) -> Dictionary:
	var dialogue: Dictionary = GameData.json("dialogue")
	var options: Array = dialogue["visits"][student["visit"]]
	for id: String in student["problems"]:
		if dialogue["problems"].has(id):
			options = dialogue["problems"][id]
	if student["no_id"]:
		options = dialogue["no_id"]
	var line: Dictionary = _pick(rng, options).duplicate()
	var request: Dictionary = student["request"]
	var section: String = request.get("section", "")
	for lang: String in ["ceb", "en"]:
		line[lang] = line[lang].format({ "course": request.get("course", ""), "section": section.get_slice("-", 1), "id": student["record"]["id_number"] })
	return line


static func _paper(student: Dictionary, form: String) -> Dictionary:
	for paper: Dictionary in student["papers"]:
		if paper["form"] == form:
			return paper
	return {}


static func _pick(rng: RandomNumberGenerator, options: Array) -> Variant:
	return options[rng.randi_range(0, options.size() - 1)]


static func _pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	var values := PackedFloat32Array()
	for key: String in keys:
		values.append(float(weights[key]))
	return keys[rng.rand_weighted(values)]


static func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: Variant = items[i]
		items[i] = items[j]
		items[j] = temp
