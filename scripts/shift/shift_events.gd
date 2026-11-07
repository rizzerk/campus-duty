class_name ShiftEvents
extends RefCounted
## Day 1 onboarding with Ma'am Lorna, Day 2+ office bulletins, mid-shift special events
## (announcements, network lag, printer hiccups, scholarship rushes) and recurring regulars.


static func is_onboarding(day: int) -> bool:
	return day == 1 and bool(GameData.day(day).get("onboarding", false))


static func bulletin_for_day(day: int) -> Dictionary:
	return GameData.json("events")["bulletins"].get(str(day), {})


static func events_for_day(day: int) -> Array:
	var raw: Array = GameData.json("events")["day_events"].get(str(day), [])
	var list: Array = []
	for item: Dictionary in raw:
		list.append(item.duplicate(true))
	return list


## Shapes the first few students of Day 1 into a step-by-step onboarding sequence with Ma'am Lorna,
## while keeping every student a valid graduation_clearance case for RulesCheck and Mismatch.
static func prepare_day_one_line(arrivals: Array) -> void:
	if arrivals.size() < 4:
		return
	_set_clearance_case(arrivals[0]["student"], [], "clean_approve")
	arrivals[0]["student"]["line"] = {
		"ceb": "Maayong buntag! Mag-file unta ko sa akong graduation clearance. Kompleto na ni tanan.",
		"en": "Good morning! I'm here to file my graduation clearance. Everything is attached.",
	}
	_set_clearance_case(arrivals[1]["student"], ["req_library"], "flag_and_reject")
	arrivals[1]["student"]["line"] = {
		"ceb": "Pa-check ko sa akong clearance, palihug. Murag naay usa nga nakalimtan nako...",
		"en": "Please check my clearance. I think I might have forgotten one attachment...",
	}
	_set_clearance_case(arrivals[2]["student"], [], "triage_and_windows")
	arrivals[3]["student"]["priority"] = "pwd"
	arrivals[3]["student"]["onboarding_step"] = "triage_target"
	for i in range(4, arrivals.size()):
		arrivals[i]["student"]["onboarding_step"] = "practice"


static func _set_clearance_case(student: Dictionary, missing_keys: Array, step: String) -> void:
	student["onboarding_step"] = step
	student["problems"].clear()
	if not missing_keys.is_empty():
		student["problems"].append("missing_requirement")
	for paper: Dictionary in student["papers"]:
		if paper["form"] == "grad_checklist":
			for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
				var key: String = requirement["key"]
				paper["fields"][key] = "Missing" if missing_keys.has(key) else "Attached"


## Ma'am Lorna's live coaching prompts during Day 1. Never returns anything on Day 2+.
static func onboarding_banner(student: Dictionary, stage: String) -> String:
	if int(student.get("day", 0)) != 1:
		return ""
	var prompts: Dictionary = GameData.json("events")["onboarding"]
	var step: String = student.get("onboarding_step", "practice")
	match step:
		"clean_approve":
			if stage == "called":
				return prompts["welcome"]
			if stage == "scanned":
				return prompts["after_scan_clean"]
		"flag_and_reject":
			if stage == "called":
				return prompts["missing_intro"]
			if stage == "scanned":
				return prompts["missing_after_scan"]
			if stage == "flagged":
				return prompts["missing_after_flag"]
			if stage == "asked":
				return prompts["missing_after_ask"]
		"triage_and_windows", "triage_target":
			if stage == "called":
				return prompts["triage_intro"]
		"practice":
			if stage == "called":
				return prompts["solo_practice"]
	return ""


## Weaves recurring regulars (#112 Jericho, #104 Carlo, #118 Mae) and special customer moments
## into the Day 2+ queue without altering any underlying problem or paper validity.
static func apply_daily_flavor(arrivals: Array, day: int, base_seed: int) -> void:
	if day <= 1 or arrivals.is_empty():
		return
	var events_data: Dictionary = GameData.json("events")
	var used_slots := {}
	for regular: Dictionary in events_data["regulars"]:
		var day_key := str(day)
		if not regular["appearances"].has(day_key):
			continue
		var appearance: Dictionary = regular["appearances"][day_key]
		var slot: int = clampi(int(appearance["slot"]), 0, arrivals.size() - 1)
		var student: Dictionary = arrivals[slot]["student"]
		if student["no_id"] or student["favor"] != "":
			continue
		used_slots[slot] = true
		student["regular_id"] = regular["id"]
		student["number"] = int(regular["number"])
		student["name"] = regular["name"]
		student["record"]["name"] = regular["name"]
		for paper: Dictionary in student["papers"]:
			if paper["fields"].has("name") and not student["harmless"].has("name"):
				paper["fields"]["name"] = regular["name"]
		var line := { "ceb": str(appearance["ceb"]), "en": str(appearance["en"]) }
		_format_student_line(line, student)
		student["line"] = line
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed * 97 + day * 13
	var specials: Array = events_data["special_customers"]
	if specials.is_empty():
		return
	for attempt in 2:
		var slot := rng.randi_range(1, arrivals.size() - 1)
		if used_slots.has(slot):
			continue
		var student: Dictionary = arrivals[slot]["student"]
		if student["no_id"] or student["favor"] != "" or student["trait"] != "":
			continue
		used_slots[slot] = true
		var special: Dictionary = specials[(day * 2 + attempt + base_seed) % specials.size()]
		student["special_event"] = special["id"]
		student["personality"] = special["personality"]
		if special.has("expression"):
			student["portrait"]["expression"] = special["expression"]
		var line := { "ceb": str(special["ceb"]), "en": str(special["en"]) }
		_format_student_line(line, student)
		student["line"] = line


static func _format_student_line(line: Dictionary, student: Dictionary) -> void:
	var request: Dictionary = student["request"]
	var section: String = request.get("section", "")
	for lang: String in ["ceb", "en"]:
		line[lang] = line[lang].format({
			"course": request.get("course", ""),
			"section": section.get_slice("-", 1),
			"id": student["record"]["id_number"],
		})

