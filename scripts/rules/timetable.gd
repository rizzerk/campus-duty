class_name Timetable
extends RefCounted
## Weekly timetable helpers for the section picker. A slot is {day, start, length}, where start
## indexes TIMES and each block is 90 minutes.

const DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const TIMES := ["7:30", "9:00", "10:30", "12:00", "1:30", "3:00", "4:30"]
const LUNCH := 3
## Pairs meet twice a week for one block; single days meet once for two blocks.
const PATTERNS := [["Mon", "Wed"], ["Tue", "Thu"], ["Fri"], ["Sat"]]


## Every slot set a section could use, skipping the lunch block.
static func all_options() -> Array:
	var options: Array = []
	for pattern: Array in PATTERNS:
		var length := 1 if pattern.size() == 2 else 2
		for start in TIMES.size() - length + 1:
			if start <= LUNCH and start + length > LUNCH:
				continue
			var slots: Array = []
			for day: String in pattern:
				slots.append({ "day": day, "start": start, "length": length })
			options.append(slots)
	return options


static func clashes(a: Array, b: Array) -> bool:
	for x: Dictionary in a:
		for y: Dictionary in b:
			if x["day"] == y["day"] and x["start"] < y["start"] + y["length"] and y["start"] < x["start"] + x["length"]:
				return true
	return false


static func clashes_schedule(slots: Array, schedule: Array) -> bool:
	for entry: Dictionary in schedule:
		if clashes(slots, entry["slots"]):
			return true
	return false


## Human-readable times, like "Mon/Wed 10:30" or "Fri 1:30–4:30".
static func label(slots: Array) -> String:
	var days: Array = []
	for slot: Dictionary in slots:
		days.append(slot["day"])
	var first: Dictionary = slots[0]
	var start: String = TIMES[first["start"]]
	if first["length"] == 1:
		return "%s %s" % ["/".join(days), start]
	var end_index: int = first["start"] + first["length"]
	var end: String = TIMES[end_index] if end_index < TIMES.size() else "6:00"
	return "%s %s–%s" % ["/".join(days), start, end]


static func find_section(student: Dictionary, code: String) -> Dictionary:
	var course: String = student["request"].get("course", "")
	for section: Dictionary in student["record"]["sections"].get(course, []):
		if section["code"] == code:
			return section
	return {}


## Open and no clash with what the student is already enrolled in.
static func section_fits(student: Dictionary, code: String) -> bool:
	var section := find_section(student, code)
	if section.is_empty() or section["seats"] <= 0:
		return false
	return not clashes_schedule(section["slots"], student["record"]["schedule"])


static func fitting_sections(student: Dictionary) -> Array:
	var codes: Array = []
	var course: String = student["request"].get("course", "")
	for section: Dictionary in student["record"]["sections"].get(course, []):
		if section_fits(student, section["code"]):
			codes.append(section["code"])
	return codes
