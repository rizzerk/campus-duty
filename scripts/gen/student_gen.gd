class_name StudentGen
extends RefCounted
## Builds a student from a seed and the day's rules in data/days.json: ID, name, program, ISMIS
## record, the papers they hand over, their problems and their portrait. Same seed, same student.

const SECTION_LETTERS := ["A", "B", "C", "D", "E", "F"]
const SEASON_YEAR := 2026
## Some students come in worried about an ISMIS error, problem or not.
const WORRIED_CHANCE := 0.2
const RANDOM_FAVORS := ["sob_story", "merienda"]
## Decided by the student's program, not by a roll among the other problems (see _pick_program).
const WRONG_DEPARTMENT := "wrong_department"


## forced, when given, replaces the problem roll with exactly these problems (the line director
## uses it to find a student who shows a new problem on its own). The visit is picked among the
## day's visits those problems allow. Without it, nothing changes from the plain roll.
static func make(seed_value: int, day_number: int, forced: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var day := GameData.day(day_number)
	var visit: String = _pick_weighted(rng, day["visits"] if forced.is_empty() else _visits_for(day["visits"], forced))
	var year: int = 1 if visit == "first_year" else int(_pick(rng, day["years"]))
	var program := _pick_program(rng, day, visit, forced)
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
		"trait": "",
		"favor": "",
		"personality": "routine",
	}
	student["record"] = _make_record(rng, student, program)
	if visit in ["enroll_subject", "add_subject"]:
		_add_course_request(rng, student, program)
	student["papers"] = _make_papers(rng, student, program)
	if forced.is_empty():
		_roll_problems(rng, student, day)
	else:
		_force_problems(rng, student, forced)
	# Some students come without their ID card; the player searches ISMIS by number instead.
	if rng.randf() < float(day.get("no_id_chance", 0.0)):
		student["papers"].remove_at(0)
		student["no_id"] = true
	_roll_harmless(rng, student, program, day)
	# Traits and favors use their own generator, so adding them never changes anyone's problems.
	var extra_rng := RandomNumberGenerator.new()
	extra_rng.seed = seed_value * 31 + 7
	_roll_trait(extra_rng, student, day)
	_roll_favor(extra_rng, student, day)
	student["worried"] = extra_rng.randf() < WORRIED_CHANCE
	var flavor_rng := RandomNumberGenerator.new()
	flavor_rng.seed = seed_value * 53 + 19
	_roll_personality(flavor_rng, student)
	student["line"] = _make_line(rng, student)
	return student


## Most students are routine so repetitive work stays brisk; some show a distinct personality.
static func _roll_personality(rng: RandomNumberGenerator, student: Dictionary) -> void:
	if rng.randf() >= 0.35:
		student["personality"] = "routine"
		return
	var keys: Array = GameData.json("dialogue")["personalities"].keys()
	var picked: String = _pick(rng, keys)
	student["personality"] = picked
	if student["trait"] == "":
		var info: Dictionary = GameData.json("dialogue")["personalities"][picked]
		if info.has("expression"):
			student["portrait"]["expression"] = info["expression"]


## At most one trait. Traits change how a student behaves, never what the right call is.
static func _roll_trait(rng: RandomNumberGenerator, student: Dictionary, day: Dictionary) -> void:
	var traits: Dictionary = GameData.json("traits")
	for id: String in day.get("traits", {}):
		var visits: Array = traits[id].get("visits", [])
		if not visits.is_empty() and not visits.has(student["visit"]):
			continue
		if rng.randf() < float(day["traits"][id]):
			student["trait"] = id
			break
	if student["trait"] != "":
		student["portrait"] = PortraitGen.with_tell(student["portrait"], student["seed"], traits[student["trait"]]["tell"])


## Kapit students always push for a favor; anyone else might, whether or not they need one, so
## an offer on its own gives nothing away.
static func _roll_favor(rng: RandomNumberGenerator, student: Dictionary, day: Dictionary) -> void:
	var from_trait: String = GameData.json("traits")[student["trait"]].get("favor", "") if student["trait"] != "" else ""
	if from_trait != "":
		student["favor"] = from_trait
	elif rng.randf() < float(day.get("favor_chance", 0.0)):
		student["favor"] = _pick(rng, RANDOM_FAVORS)


## On a day with a department list (extension day), the program decides wrong_department: the
## problem's roll happens here and picks a program from outside the list, otherwise from inside it.
## Other days pick from every program, exactly as before.
static func _pick_program(rng: RandomNumberGenerator, day: Dictionary, visit: String, forced: Array) -> Dictionary:
	var programs: Array = GameData.json("students")["programs"]
	var allowed: Array = day.get("departments", [])
	if allowed.is_empty():
		return _pick(rng, programs)
	var outside := forced.has(WRONG_DEPARTMENT)
	if forced.is_empty() and GameData.problem(WRONG_DEPARTMENT)["visits"].has(visit):
		outside = rng.randf() < float(day.get("problems", {}).get(WRONG_DEPARTMENT, 0.0))
	var pool := programs.filter(func(program: Dictionary) -> bool: return allowed.has(program["department"]) != outside)
	return _pick(rng, pool if not pool.is_empty() else programs)


## Is this student's department missing from today's list? Always false on days without one.
static func outside_departments(student: Dictionary) -> bool:
	var allowed: Array = GameData.day(int(student["day"])).get("departments", [])
	return not allowed.is_empty() and not allowed.has(student["record"]["department"])


## Keeps wrong_department in step with the student's department after something changes it (a
## regular brings their own program into the slot they take). Adding it can put a student one
## over max_problems; the call stays right, because a turn-away outranks everything else.
static func sync_department(student: Dictionary) -> void:
	var outside := outside_departments(student)
	var has: bool = student["problems"].has(WRONG_DEPARTMENT)
	if outside and not has:
		student["problems"].append(WRONG_DEPARTMENT)
	elif has and not outside:
		student["problems"].erase(WRONG_DEPARTMENT)


static func _make_name(rng: RandomNumberGenerator, gender: String) -> String:
	var names: Dictionary = GameData.json("students")
	return "%s %s" % [_pick(rng, names["first_names"][gender]), _pick(rng, names["last_names"])]


static func _roll_priority(rng: RandomNumberGenerator, year: int, day_number: int) -> String:
	# On days 1 and 2 everyone is graduating, so GRAD only stands out on other days.
	if year == 4 and not (day_number in [1, 2]) and rng.randf() < 0.2:
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
		"birthday": _birthday(rng, student["year"]),
		"grades": grades,
		"schedule": [],
		"sections": {},
		"advisers": program["advisers"].duplicate(true),
	}
	if student["visit"] == "graduation_clearance":
		for requirement: Dictionary in data["grad_requirements"]:
			record[requirement["key"]] = "Attached"
	if student["visit"] == "tuition_payment":
		var payment: Dictionary = data["payment"]
		var step := int(payment["due_step"])
		@warning_ignore("integer_division")
		record["amount_due"] = Money.format(rng.randi_range(int(payment["due_min"]) / step, int(payment["due_max"]) / step) * step)
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
		"tuition_payment":
			papers.append({ "form": "assessment", "title": "Assessment slip", "fields": { "id_number": record["id_number"], "amount_due": record["amount_due"] } })
			# The cash in the tray. Exact unless a payment problem changes it.
			papers.append({ "form": "cash", "title": "Cash in tray", "fields": { "amount_due": record["amount_due"] } })
		"enrollment_payment":
			papers.append({ "form": "assessment", "title": "Assessment slip", "fields": { "id_number": record["id_number"], "balance": "PHP 0.00" } })
		"first_year":
			papers.append({ "form": "assessment", "title": "Assessment slip", "fields": { "id_number": record["id_number"], "balance": "PHP 0.00" } })
			papers.append({ "form": "admission_slip", "title": "Admission slip", "fields": { "id_number": record["id_number"], "birthday": record["birthday"] } })
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
	# Problems that build on another one (an impostor needs a locked account to reset) go last.
	candidates.sort_custom(func(a: String, b: String) -> bool: return GameData.problem(a).get("requires", []).size() < GameData.problem(b).get("requires", []).size())
	# The program was already picked inside or outside today's list, so this one is settled first.
	if outside_departments(student):
		student["problems"].append(WRONG_DEPARTMENT)
	for id: String in candidates:
		if id == WRONG_DEPARTMENT:
			continue
		if student["problems"].size() >= int(day["max_problems"]):
			break
		var info := GameData.problem(id)
		if not info["visits"].has(student["visit"]):
			continue
		if info["excludes"].any(func(other: String) -> bool: return student["problems"].has(other)):
			continue
		if not info.get("requires", []).all(func(other: String) -> bool: return student["problems"].has(other)):
			continue
		if rng.randf() < float(day["problems"][id]) and _apply_problem(rng, student, id):
			student["problems"].append(id)


## The day's visit weights, narrowed to visits where every forced problem can happen.
static func _visits_for(visits: Dictionary, forced: Array) -> Dictionary:
	var allowed := {}
	for visit: String in visits:
		if forced.all(func(id: String) -> bool: return GameData.problem(id)["visits"].has(visit)):
			allowed[visit] = visits[visit]
	return allowed if not allowed.is_empty() else visits


## Applies exactly these problems, the ones others build on first. One that can't apply to this
## student is left out, so callers check the result.
static func _force_problems(rng: RandomNumberGenerator, student: Dictionary, forced: Array) -> void:
	var ordered := forced.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool: return GameData.problem(a).get("requires", []).size() < GameData.problem(b).get("requires", []).size())
	for id: String in ordered:
		if _apply_problem(rng, student, id):
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
		"identity_mismatch":
			var slip := _paper(student, "admission_slip")
			var real: String = record["birthday"]
			var fake := real
			while fake == real:
				fake = _birthday(rng, student["year"])
			slip["fields"]["birthday"] = fake
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
		"short_payment", "overpayment":
			var cash := _paper(student, "cash")
			if cash.is_empty():
				return false
			var payment: Dictionary = GameData.json("students")["payment"]
			var due := Money.parse(record["amount_due"])
			if id == "short_payment":
				cash["fields"]["amount_due"] = Money.format(due - int(_pick(rng, payment["short_by"])))
			else:
				# They hand over whole bills: the due amount rounded up past the next bill.
				var bill := int(_pick(rng, payment["bills"]))
				@warning_ignore("integer_division")
				cash["fields"]["amount_due"] = Money.format((due / bill + 1) * bill)
		WRONG_DEPARTMENT:
			# Only there when _pick_program chose a department off today's list.
			return outside_departments(student)
		_:
			return false
	return true


## MM/DD/YY, for someone starting college around 18.
static func _birthday(rng: RandomNumberGenerator, year: int) -> String:
	var born := SEASON_YEAR - 17 - year
	return "%02d/%02d/%02d" % [rng.randi_range(1, 12), rng.randi_range(1, 28), born % 100]


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


## The opening line. Most important first: no ID card (the player has to type the number), a
## favor, the trait, a worried question, a problem they know about, a personality moment, or a
## concise routine line so repetitive transactions don't chatter unnecessarily.
static func _make_line(rng: RandomNumberGenerator, student: Dictionary) -> Dictionary:
	var dialogue: Dictionary = GameData.json("dialogue")
	var options: Array = dialogue["routine"].get(student["visit"], dialogue["visits"][student["visit"]])
	var personality: String = student.get("personality", "routine")
	if personality != "routine" and dialogue.get("personalities", {}).has(personality):
		options = dialogue["personalities"][personality]["lines"]
	for id: String in student["problems"]:
		if dialogue["problems"].has(id):
			options = dialogue["problems"][id]
	if student["worried"]:
		options = dialogue["worried"]
	var trait_lines: Array = GameData.json("traits")[student["trait"]].get("lines", []) if student["trait"] != "" else []
	if not trait_lines.is_empty():
		options = trait_lines
	if student["favor"] != "":
		options = GameData.json("favors")[student["favor"]]["lines"]
	if student["no_id"]:
		options = dialogue["no_id"]
	var line: Dictionary = _pick(rng, options).duplicate()
	if student["no_id"] and student["favor"] != "":
		# They still need to say their number, but the favor is the point of the visit.
		var offer: Dictionary = _pick(rng, GameData.json("favors")[student["favor"]]["lines"])
		line = { "ceb": "%s %s" % [line["ceb"], offer["ceb"]], "en": "%s %s" % [line["en"], offer["en"]] }
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
