class_name Consequences
extends RefCounted
## Turns a shift's history into the "Because of you" stories on the day report: every wrong call
## first (the player needs those), then good calls worth remembering, up to a limit.


static func build(history: Array, max_items: int = 6) -> Array:
	var templates: Dictionary = GameData.json("consequences")
	var bad: Array = []
	var good: Array = []
	var good_seen := {}
	var bad_seen := {}
	var false_alarms := 0
	for entry: Dictionary in history:
		false_alarms += int(entry.get("false_alarms", 0))
		if entry["correct"]:
			var key := _good_key(entry)
			if key != "" and templates["good"].has(key):
				var index: int = int(good_seen.get(key, 0))
				good_seen[key] = index + 1
				good.append({ "text": _fill(_pick_variant(templates["good"][key], index), entry), "good": true })
		else:
			var bad_key := _bad_key(entry)
			var index: int = int(bad_seen.get(bad_key, 0))
			bad_seen[bad_key] = index + 1
			bad.append({ "text": _fill(_pick_variant(templates["bad"][bad_key], index), entry), "good": false })
	if false_alarms > 0:
		bad.push_front({ "text": _fill(templates["bad"]["false_alarms"], { "count": false_alarms }), "good": false })
	var items: Array = bad
	if bad.size() > max_items:
		# Keep room for a line saying how many more there were.
		items = bad.slice(0, max_items - 1)
		items.append({ "text": _fill(templates["bad"]["more"], { "count": bad.size() - items.size() }), "good": false })
	for story: Dictionary in good:
		if items.size() >= max_items:
			break
		items.append(story)
	return items


static func _pick_variant(options: Variant, index: int) -> String:
	if options is Array:
		return String(options[index % options.size()])
	return String(options)


static func _good_key(entry: Dictionary) -> String:
	if entry["action"] == "hold":
		return "held"
	if entry.get("reason_id", "") == "office_closed":
		return "office_closed"
	return entry["problem"]


static func _bad_key(entry: Dictionary) -> String:
	var action: String = entry["action"]
	var expected: String = entry["expected"]
	if entry.get("bent", false):
		return "bent_caught" if entry.get("spotted", false) else "bent"
	if entry["outcome"] == "walked_out":
		return "walked_out"
	if entry.get("reason", "").begins_with("Right idea, wrong order"):
		return "wrong_order"
	if entry["outcome"] == "wrong_fix":
		return "wrong_fix"
	if action.begins_with("route:") and not entry.get("office_open", true):
		return "closed_office"
	if action.begins_with("route:") and expected.begins_with("route:"):
		return "wrong_office"
	if action.begins_with("route:"):
		return "needless_trip"
	if action == "approve":
		return "let_through"
	if action == expected:
		return "right_call_wrong_detail"
	return "wrong_call"


## "There was nothing wrong..." reads as "...but there was nothing wrong..." inside a story.
static func _lower_first(text: String) -> String:
	if text == "" or text.begins_with("ISMIS") or text.begins_with("INC"):
		return text
	return text.left(1).to_lower() + text.substr(1)


## Past-tense story clause for what was actually going on with the student's papers, so templates
## never paste two-sentence rulebook commands ("...Approve it.") mid-sentence.
static func _clause(entry: Dictionary, templates: Dictionary) -> String:
	var clauses: Dictionary = templates.get("problem_clauses", {})
	var problem: String = String(entry.get("problem", ""))
	var reason: String = String(entry.get("reason", ""))
	if problem != "" and clauses.has(problem):
		return String(clauses[problem])
	if problem == "" and (reason == "" or reason.begins_with("There was nothing wrong")):
		return String(clauses.get("clean", "there was nothing wrong with their papers"))
	var first_sentence := reason.get_slice(".", 0).strip_edges()
	return _lower_first(first_sentence if first_sentence != "" else reason)


static func _fill(template: String, entry: Dictionary) -> String:
	var templates: Dictionary = GameData.json("consequences")
	var offices: Dictionary = GameData.json("offices")
	var action: String = entry.get("action", "")
	var expected: String = entry.get("expected", "")
	var reason: String = entry.get("reason", "")
	var count: int = entry.get("count", 0)
	var base := {
		"number": entry.get("number", ""),
		"name": entry.get("name", ""),
	}
	var verb_template: String = templates.get("action_verbs", {}).get(action, action)
	var values := {
		"number": base["number"],
		"name": base["name"],
		"section": entry.get("section", ""),
		"office": offices[action.trim_prefix("route:")]["phrase"] if action.begins_with("route:") else "",
		"expected": offices[expected.trim_prefix("route:")]["phrase"] if expected.begins_with("route:") else expected,
		"reason": _lower_first(reason) if template.contains("but {reason}") else reason,
		"reason_lower": _lower_first(reason),
		"clause": _clause(entry, templates),
		"action": verb_template.format(base),
		"count": count,
		"plural": "" if count == 1 else "s",
	}
	return template.format(values)
