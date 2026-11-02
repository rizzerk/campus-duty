class_name Consequences
extends RefCounted
## Turns a shift's history into the "Because of you" stories on the day report: every wrong call
## first (the player needs those), then good calls worth remembering, up to a limit.


static func build(history: Array, max_items: int = 6) -> Array:
	var templates: Dictionary = GameData.json("consequences")
	var bad: Array = []
	var good: Array = []
	var false_alarms := 0
	for entry: Dictionary in history:
		false_alarms += int(entry.get("false_alarms", 0))
		if entry["correct"]:
			var key := _good_key(entry)
			if key != "" and templates["good"].has(key):
				good.append({ "text": _fill(templates["good"][key], entry), "good": true })
		else:
			bad.append({ "text": _fill(templates["bad"][_bad_key(entry)], entry), "good": false })
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


static func _good_key(entry: Dictionary) -> String:
	if entry["action"] == "hold":
		return "held"
	if entry.get("reason_id", "") == "office_closed":
		return "office_closed"
	return entry["problem"]


static func _bad_key(entry: Dictionary) -> String:
	var action: String = entry["action"]
	var expected: String = entry["expected"]
	if entry["outcome"] == "walked_out":
		return "walked_out"
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
	if text.begins_with("ISMIS"):
		return text
	return text.left(1).to_lower() + text.substr(1)


static func _fill(template: String, entry: Dictionary) -> String:
	var offices: Dictionary = GameData.json("offices")
	var action: String = entry.get("action", "")
	var expected: String = entry.get("expected", "")
	var reason: String = entry.get("reason", "")
	var count: int = entry.get("count", 0)
	var values := {
		"number": entry.get("number", ""),
		"name": entry.get("name", ""),
		"section": entry.get("section", ""),
		"office": offices[action.trim_prefix("route:")]["phrase"] if action.begins_with("route:") else "",
		"expected": offices[expected.trim_prefix("route:")]["phrase"] if expected.begins_with("route:") else expected,
		"reason": _lower_first(reason) if template.contains("but {reason}") else reason,
		"action": GameData.json("consequences")["action_names"].get(action, action),
		"count": count,
		"plural": "" if count == 1 else "s",
	}
	return template.format(values)
