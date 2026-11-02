class_name RulesCheck
extends RefCounted
## The rules engine. Pure: give it a student, the player's action and the offices' live status,
## and it says whether the call was right and why. Actions are approve, fix, hold, reject and
## route:<office>.


## The problem that decides the correct action: the highest priority one.
static func top_problem(student: Dictionary) -> String:
	var best := ""
	var best_priority := -1.0
	for id: String in student["problems"]:
		var priority := float(GameData.problem(id)["priority"])
		if priority > best_priority:
			best = id
			best_priority = priority
	return best


## Every right call for this student, best first. Problems come in three tiers (problems.json):
## 1 turn away, 2 send to an office, 3 fix at the window. Only the highest tier present counts,
## and inside it any problem is fine: with a balance and a missing signature, either office is
## right, and the student comes back for the other one. Each option carries what a Reject must
## say: reason_id (which rule) and, for a missing requirement, the items to bring back.
static func accepted(student: Dictionary, offices: Dictionary) -> Array:
	var tier := top_tier(student)
	if tier == 0:
		return [{ "action": "approve", "problem": "", "reason": "There was nothing wrong with the papers. Approve it.", "reason_id": "", "items": [] }]
	var options: Array = []
	var waiting: Array = []
	var closed_today: Array = []
	for problem: String in by_priority(student):
		var info := GameData.problem(problem)
		if int(info["tier"]) != tier:
			continue
		var action: String = info["action"]
		var option := { "action": action, "problem": problem, "reason": info["reason"], "reason_id": "", "items": [] }
		if action == "reject":
			option["reason_id"] = problem
			if problem == "missing_requirement":
				option["items"] = missing_items(student)
		elif action.begins_with("route:"):
			var live: Dictionary = offices[action.trim_prefix("route:")]
			if not live["open"]:
				(waiting if live["reopens"] else closed_today).append(option)
				continue
		options.append(option)
	if options.is_empty() and not waiting.is_empty():
		var first: Dictionary = waiting[0]
		options.append({ "action": "hold", "problem": first["problem"], "reason_id": "", "items": [],
			"reason": "%s is closed right now. Hold them on the bench until it reopens." % _office_name(first["action"]) })
	elif options.is_empty() and not closed_today.is_empty():
		var first: Dictionary = closed_today[0]
		options.append({ "action": "reject", "problem": first["problem"], "reason_id": "office_closed", "items": [],
			"reason": "%s is closed for the day. Ask them to come back tomorrow." % _office_name(first["action"]) })
	return options


## The best right call. Reports and the simulator use it; judge() accepts any of accepted().
static func expected(student: Dictionary, offices: Dictionary) -> Dictionary:
	return accepted(student, offices)[0]


## 1 turn away, 2 send out, 3 fix at the window; 0 when nothing is wrong.
static func top_tier(student: Dictionary) -> int:
	var best := 0
	for id: String in student["problems"]:
		var tier := int(GameData.problem(id)["tier"])
		if best == 0 or tier < best:
			best = tier
	return best


## "Missing adviser signature" reads as "missing adviser signature" mid-sentence, but acronyms
## like ISMIS and INC keep their capitals.
static func _lower_label(label: String) -> String:
	if label.length() > 1 and label[1] == label[1].to_upper() and label[1] != " ":
		return label
	return label.left(1).to_lower() + label.substr(1)


static func _needs(student: Dictionary, action: String) -> bool:
	return student["problems"].any(func(id: String) -> bool: return GameData.problem(id)["action"] == action)


static func by_priority(student: Dictionary) -> Array:
	var problems: Array = student["problems"].duplicate()
	problems.sort_custom(func(a: String, b: String) -> bool: return float(GameData.problem(a)["priority"]) > float(GameData.problem(b)["priority"]))
	return problems


static func _office_name(action: String) -> String:
	return GameData.json("offices")[action.trim_prefix("route:")]["name"]


## Clearance items the student didn't bring, as requirement keys.
static func missing_items(student: Dictionary) -> Array:
	var items: Array = []
	for paper: Dictionary in student["papers"]:
		if paper["form"] == "grad_checklist":
			for key: String in paper["fields"]:
				if paper["fields"][key] == "Missing":
					items.append(key)
	items.sort()
	return items


## details can carry what the decision needs: "section" for the section picker, "reason" and
## "items" for a Reject. The right call with the wrong reason or list still counts as wrong.
static func judge(student: Dictionary, action: String, offices: Dictionary, details: Dictionary = {}) -> Dictionary:
	var options := accepted(student, offices)
	var want: Dictionary = options[0]
	for option: Dictionary in options:
		if option["action"] == action and (action != "reject" or option["reason_id"] == details.get("reason", "")):
			want = option
			break
	var correct: bool = action == want["action"]
	var reason: String = want["reason"]
	if not correct:
		var order := _order_note(student, action, want)
		if order != "":
			reason = order
		elif action.begins_with("route:") and not offices[action.trim_prefix("route:")]["open"] and _needs(student, action):
			reason = "%s isn't open right now, so that trip was wasted. %s" % [_office_name(action), want["reason"]]
	if correct and want["problem"] == "closed_section" and not Timetable.section_fits(student, details.get("section", "")):
		correct = false
		reason = "That section is full or clashes with their schedule."
	if correct and action == "reject":
		var given: String = details.get("reason", "")
		if given != want["reason_id"]:
			correct = false
			reason = "Right call, wrong reason. %s" % want["reason"]
		elif given == "missing_requirement":
			var ticked: Array = details.get("items", []).duplicate()
			ticked.sort()
			if ticked != want["items"]:
				correct = false
				reason = "Right call, wrong list. They need: %s." % ", ".join(want["items"].map(_requirement_label))
	return { "correct": correct, "expected": want["action"], "problem": want["problem"], "reason": reason }


## When the player handled a real problem but a higher tier was waiting, say that it was the
## order, not the idea, that was wrong.
static func _order_note(student: Dictionary, action: String, want: Dictionary) -> String:
	var tier := top_tier(student)
	for problem: String in student["problems"]:
		var info := GameData.problem(problem)
		if int(info["tier"]) > tier and info["action"] == action:
			var first: String = GameData.problem(want["problem"])["label"] if want["problem"] != "" else ""
			return "Right idea, wrong order. They also have: %s. %s" % [_lower_label(first), TIER_RULE[tier]]
	return ""


const TIER_RULE := {
	1: "Turn-aways come before everything else.",
	2: "Office trips come before fixes at the window.",
}


static func _requirement_label(key: String) -> String:
	for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
		if requirement["key"] == key:
			return requirement["label"]
	return key
