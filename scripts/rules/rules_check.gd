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


static func expected(student: Dictionary, offices: Dictionary) -> Dictionary:
	var problem := top_problem(student)
	if problem == "":
		return { "action": "approve", "problem": "", "reason": "Nothing wrong with the papers. Approve it." }
	var info := GameData.problem(problem)
	var action: String = info["action"]
	var reason: String = info["reason"]
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
				reason = "%s is closed for the day. Ask them to come back tomorrow." % office_name
	return { "action": action, "problem": problem, "reason": reason }


static func judge(student: Dictionary, action: String, offices: Dictionary, picked_section: String = "") -> Dictionary:
	var want := expected(student, offices)
	var correct: bool = action == want["action"]
	var reason: String = want["reason"]
	if correct and want["problem"] == "closed_section" and not Timetable.section_fits(student, picked_section):
		correct = false
		reason = "That section is full or clashes with their schedule."
	return { "correct": correct, "expected": want["action"], "problem": want["problem"], "reason": reason }
