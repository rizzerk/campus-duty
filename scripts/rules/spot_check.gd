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
