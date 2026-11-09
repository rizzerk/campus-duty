class_name SpotCheck
extends RefCounted
## Ma'am Lorna's end-of-day spot check: she pulls a few of the day's transactions and looks at
## them again. Favors done for students with a problem are more likely to catch her eye. Pure and
## seeded, so a replayed day gets the same check.


static func applies(day: int) -> bool:
	return day >= int(GameData.json("balance")["spot_check"]["from_day"])


## Indices into history, drawn without replacement. Bent transactions weigh bend_weight, the rest 1.
static func pick(history: Array, seed_value: int, count: int, bend_weight: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = range(history.size())
	var picks: Array = []
	while picks.size() < count and not pool.is_empty():
		var weights := PackedFloat32Array()
		for index: int in pool:
			weights.append(bend_weight if history[index].get("bent", false) else 1.0)
		var chosen: int = pool[rng.rand_weighted(weights)]
		pool.erase(chosen)
		picks.append(chosen)
	picks.sort()
	return picks


## "fine", "wrong" or "bent".
static func verdict(entry: Dictionary) -> String:
	if entry.get("bent", false):
		return "bent"
	return "fine" if entry["correct"] else "wrong"


## Runs the check and marks caught favors in history ("spotted"), so the report's stories can say
## Ma'am Lorna found them. Returns the rows to show and how many favors she caught.
static func run(history: Array, seed_value: int, day: int) -> Dictionary:
	if not applies(day):
		return { "rows": [], "caught_bends": 0 }
	var settings: Dictionary = GameData.json("balance")["spot_check"]
	var rows: Array = []
	var caught := 0
	for index: int in pick(history, seed_value, int(settings["count"]), float(settings["bend_weight"])):
		var entry: Dictionary = history[index]
		var result := verdict(entry)
		if result == "bent":
			entry["spotted"] = true
			caught += 1
		rows.append({ "number": entry["number"], "name": entry["name"], "action": entry["action"], "verdict": result, "reason": entry["reason"] })
	return { "rows": rows, "caught_bends": caught }


## Instead of repeating tutorials on Day 2+, Ma'am Lorna randomly inspects processed documents
## during the shift—or steps in right away if the player makes a mistake or bends a rule.
static func should_inspect_mid_shift(history: Array, seed_value: int, day: int) -> bool:
	if day <= 1 or history.is_empty():
		return false
	var latest: Dictionary = history[-1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1009 + day * 37 + history.size()
	if latest.get("bent", false) or not latest["correct"]:
		return history.size() <= 2 or rng.randf() < 0.75
	if int(latest.get("false_alarms", 0)) > 0:
		return history.size() <= 2 or rng.randf() < 0.65
	if history.size() == 2:
		return true
	return history.size() >= 3 and rng.randf() < 0.35


## Builds Ma'am Lorna's live inspection feedback: praise for accurate work, warnings for rule
## bending or false alarms, or a specific reminder of the rule the player forgot.
static func inspect_latest(history: Array, seed_value: int, day: int) -> Dictionary:
	if history.is_empty():
		return {}
	var latest: Dictionary = history[-1]
	var spot_data: Dictionary = GameData.json("dialogue")["spot_check"]
	var number := str(latest.get("number", ""))
	if latest.get("bent", false):
		var line: Dictionary = spot_data["mid_warn"][0]
		return {
			"kind": "warning",
			"ceb": line["ceb"].format({ "number": number }),
			"en": line["en"].format({ "number": number }),
			"banner": line["en"].format({ "number": number }),
		}
	if not latest["correct"]:
		var reminders: Dictionary = spot_data["rule_reminders"]
		var problem: String = str(latest.get("problem", ""))
		var key := problem if problem != "" and reminders.has(problem) else "clean"
		if latest.get("action", "").begins_with("route:") and not latest.get("office_open", true):
			key = "office_closed"
		var reminder: String = reminders.get(key, reminders["clean"]).format({ "number": number })
		return {
			"kind": "rule_reminder",
			"problem": key,
			"ceb": spot_data["wrong"][(seed_value + day + history.size()) % spot_data["wrong"].size()]["ceb"],
			"en": reminder,
			"banner": reminder,
		}
	if int(latest.get("false_alarms", 0)) > 0:
		var warn_line: Dictionary = spot_data["mid_warn"][1]
		return {
			"kind": "warning",
			"ceb": warn_line["ceb"].format({ "number": number }),
			"en": warn_line["en"].format({ "number": number }),
			"banner": warn_line["en"].format({ "number": number }),
		}
	var praise_options: Array = spot_data["mid_praise"]
	var chosen: Dictionary = praise_options[(seed_value + day + history.size()) % praise_options.size()]
	return {
		"kind": "praise",
		"ceb": chosen["ceb"].format({ "number": number }),
		"en": chosen["en"].format({ "number": number }),
		"banner": chosen["en"].format({ "number": number }),
	}
