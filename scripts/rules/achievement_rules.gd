class_name AchievementRules
extends RefCounted
## Which achievements a call or a finished shift earns. Pure, like Scoring: it only reads the
## shift's history and summary, so the tests can check it without scenes. The Achievements
## autoload keeps what was earned and shows the toasts. Definitions live in data/achievements.json.

const ROUTED_OFFICES := ["cashier", "consultation", "dean"]


static func all() -> Array:
	return GameData.json("achievements")["achievements"]


static func find(id: String) -> Dictionary:
	for item: Dictionary in all():
		if item["id"] == id:
			return item
	return {}


## Lifetime counters a call adds to. Regulars are tracked by the Achievements autoload, since the
## history entry doesn't say who was a regular.
static func stat_deltas(entry: Dictionary) -> Dictionary:
	var deltas := {}
	if int(entry.get("caught", 0)) > 0:
		deltas["mismatches_caught"] = int(entry["caught"])
	if not entry.get("correct", false):
		return deltas
	deltas["correct_calls"] = 1
	var problem: String = entry.get("problem", "")
	match entry.get("action", ""):
		"fix":
			if problem == "closed_section":
				deltas["sections_fixed"] = 1
			elif problem == "ismis_login":
				deltas["ismis_resets"] = 1
		"reject":
			if problem == "fake_signature":
				deltas["fakes_rejected"] = 1
	return deltas


## Achievements earned by the call just made (the last entry in `history`). `context` holds
## "favor_offered" (the student asked for a favor) and "bench" (seats taken after the call).
static func after_decision(history: Array, context: Dictionary = {}) -> Array:
	if history.is_empty():
		return []
	var entry: Dictionary = history[-1]
	var earned: Array = []
	if entry["correct"]:
		earned.append("first_call")
	var streak := correct_streak(history)
	if streak >= 10:
		earned.append("streak_10")
	if streak >= 25:
		earned.append("streak_25")
	if entry.get("bent", false):
		earned.append("just_this_once")
	if context.get("favor_offered", false) and entry["action"] != "favor" and entry["correct"]:
		earned.append("not_today")
	if int(context.get("bench", 0)) >= ShiftState.BENCH_SEATS:
		earned.append("full_bench")
	if routed_everywhere(history):
		earned.append("right_office")
	return earned


## Achievements earned when a shift ends. `season` holds "stars" (the season's total so far)
## and "last_day" (this was the season's final day).
static func after_shift(summary: Dictionary, history: Array, day: int, season: Dictionary = {}) -> Array:
	var earned: Array = []
	if summary["reason"] == "patience":
		earned.append("lorna_takes_over")
		return earned
	var stars := int(summary.get("stars", 0))
	if day == int(GameData.json("days")["first_day"]):
		earned.append("first_shift")
	if stars >= 3:
		earned.append("three_stars")
		if GameData.day(day).has("live_slots"):
			earned.append("market_survivor")
	if summary["decisions"] >= 8 and summary["mistakes"] == 0 and summary["false_alarms"] == 0 and summary.get("bends", 0) == 0:
		earned.append("flawless")
	if summary["reason"] == "clear":
		earned.append("line_cleared")
	if summary["caught"] >= 10 and summary["false_alarms"] == 0:
		earned.append("sharp_eye")
	if int(summary.get("caught_bends", 0)) > 0:
		earned.append("caught_red_handed")
	if int(season.get("stars", 0)) >= 20:
		earned.append("star_employee")
	if season.get("last_day", false):
		earned.append("season_done")
	return earned


## Counter achievements whose goal `stats` has reached.
static func from_stats(stats: Dictionary) -> Array:
	var earned: Array = []
	for item: Dictionary in all():
		if item.has("stat") and stat_value(stats, item["stat"]) >= int(item["goal"]):
			earned.append(item["id"])
	return earned


## A counter's value. Regulars are kept as a set, so the same regular twice counts once.
static func stat_value(stats: Dictionary, stat: String) -> int:
	if stat == "regulars_helped":
		return stats.get("regulars", {}).size()
	return int(stats.get(stat, 0))


## Correct calls in a row, counting back from the latest.
static func correct_streak(history: Array) -> int:
	var count := 0
	for i in range(history.size() - 1, -1, -1):
		if not history[i]["correct"]:
			break
		count += 1
	return count


## True once this shift has a correct routing to every office.
static func routed_everywhere(history: Array) -> bool:
	var seen := {}
	for entry: Dictionary in history:
		if entry["correct"] and str(entry["action"]).begins_with("route:"):
			seen[str(entry["action"]).trim_prefix("route:")] = true
	return ROUTED_OFFICES.all(func(office: String) -> bool: return seen.has(office))
