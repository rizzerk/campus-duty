class_name OfficeSchedule
extends RefCounted
## Live office status by day and minute (0 = 8:00, 240 = 12:00), from data/offices.json plus
## each day's overrides in data/days.json.

const OPEN_STATUSES := ["open", "long_line"]


static func status(day_number: int, office: String, minute: float) -> String:
	var plan := _plan(day_number, office)
	for window: Dictionary in plan["windows"]:
		if minute >= window["from"] and minute < window["to"]:
			return window["status"]
	return plan["default"]


static func is_open(day_number: int, office: String, minute: float) -> bool:
	return OPEN_STATUSES.has(status(day_number, office, minute))


## True when the office is shut now but opens again before the shift ends.
static func reopens(day_number: int, office: String, minute: float) -> bool:
	var shift_end := GameData.balance("shift_minutes")
	for window: Dictionary in _plan(day_number, office)["windows"]:
		for edge: float in [float(window["from"]), float(window["to"])]:
			if edge > minute and edge < shift_end and is_open(day_number, office, edge):
				return true
	return false


static func snapshot(day_number: int, minute: float) -> Dictionary:
	var result := {}
	for office: String in GameData.json("offices"):
		result[office] = {
			"status": status(day_number, office, minute),
			"open": is_open(day_number, office, minute),
			"reopens": reopens(day_number, office, minute),
		}
	return result


static func return_minutes(day_number: int, office: String, minute: float) -> float:
	var info: Dictionary = GameData.json("offices")[office]
	var wait := float(info["return_minutes"])
	if status(day_number, office, minute) == "long_line":
		wait += float(info["long_line_extra_minutes"])
	return wait


## Game minutes as a clock, like "10:30" (0 is 8:00).
static func clock(minute: float, with_suffix: bool = false) -> String:
	var total := 8 * 60 + int(minute)
	var hour := floori(total / 60.0)
	var shown := hour if hour <= 12 else hour - 12
	var text := "%d:%02d" % [shown, total % 60]
	if with_suffix:
		text += " AM" if hour < 12 else " PM"
	return text


## The next minute today when the office's status changes, or -1 if it doesn't.
static func next_change(day_number: int, office: String, minute: float) -> float:
	var shift_end := GameData.balance("shift_minutes")
	var best := -1.0
	for window: Dictionary in _plan(day_number, office)["windows"]:
		for edge: float in [float(window["from"]), float(window["to"])]:
			if edge > minute and edge < shift_end and (best < 0.0 or edge < best):
				best = edge
	return best


## A short live note for the offices panel and the route menu, like "Back at 11:00".
static func detail(day_number: int, office: String, minute: float) -> String:
	var now := status(day_number, office, minute)
	var change := next_change(day_number, office, minute)
	match now:
		"break":
			return "Back at %s" % clock(change) if change >= 0.0 else "On break"
		"long_line":
			return "Long line, slow trip"
		"closed":
			return "Opens %s" % clock(change) if reopens(day_number, office, minute) else "Closed today"
	if change >= 0.0:
		var next := status(day_number, office, change)
		if next == "closed":
			return "Open until %s" % clock(change)
		if next == "break":
			return "Break at %s" % clock(change)
	return "Open"


## One line for the memo, like "Advisers on break 10:30–11:00".
static func describe(day_number: int, office: String) -> String:
	var plan := _plan(day_number, office)
	var parts: Array = []
	parts.append("Open all morning" if OPEN_STATUSES.has(plan["default"]) else "Closed today")
	for window: Dictionary in plan["windows"]:
		var span := "%s–%s" % [clock(window["from"]), clock(window["to"])]
		match window["status"]:
			"break":
				parts.append("on break %s" % span)
			"long_line":
				parts.append("long line after %s" % clock(window["from"]))
			"closed":
				parts.append("closes at %s" % clock(window["from"]))
			"open":
				parts.append("open %s" % span)
	return ", ".join(parts)


static func _plan(day_number: int, office: String) -> Dictionary:
	var override: Dictionary = GameData.day(day_number).get("offices", {}).get(office, {})
	return {
		"default": override.get("default", GameData.json("offices")[office]["default"]),
		"windows": override.get("windows", []),
	}
