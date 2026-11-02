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


## The right call, plus what a Reject must say: reason_id (which rule) and, for a missing
## requirement, the items to bring back.
static func expected(student: Dictionary, offices: Dictionary) -> Dictionary:
	var problem := top_problem(student)
	if problem == "":
		return { "action": "approve", "problem": "", "reason": "Nothing wrong with the papers. Approve it.", "reason_id": "", "items": [] }
	var info := GameData.problem(problem)
	var action: String = info["action"]
	var reason: String = info["reason"]
	var reason_id := problem if action == "reject" else ""
	if action.begins_with("route:"):
		var office := action.trim_prefix("route:")
		var live: Dictionary = offices[office]
		var office_name: String = GameData.json("offices")[office]["name"]
		if not live["open"]:
			if live["reopens"]:
				action = "hold"
				reason = "%s is closed right now. Hold them on the bench until it reopens." % office_name
			else:
				action = "reject"
				reason_id = "office_closed"
				reason = "%s is closed for the day. Ask them to come back tomorrow." % office_name
	var items: Array = missing_items(student) if reason_id == "missing_requirement" else []
	return { "action": action, "problem": problem, "reason": reason, "reason_id": reason_id, "items": items }


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
	var want := expected(student, offices)
	var correct: bool = action == want["action"]
	var reason: String = want["reason"]
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


static func _requirement_label(key: String) -> String:
	for requirement: Dictionary in GameData.json("students")["grad_requirements"]:
		if requirement["key"] == key:
			return requirement["label"]
	return key
