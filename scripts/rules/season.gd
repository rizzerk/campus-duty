class_name Season
extends RefCounted
## The season calendar's data: what each day's square shows. Pure, so the calendar and the tests
## agree. The text lives in data/season.json.


## "today", "past", "failed" (the line gave up), "future", or "locked" for days the game
## doesn't have yet.
static func state(number: int, today: int, results: Dictionary) -> String:
	var days: Dictionary = GameData.json("days")
	if number < int(days["first_day"]) or number > int(days["last_day"]):
		return "locked"
	if number == today:
		return "today"
	if number > today:
		return "future"
	if results.get(number, {}).get("reason", "") == "patience":
		return "failed"
	return "past"


## The season.json entry for a day, or an empty one if the day isn't listed.
static func entry(number: int) -> Dictionary:
	for item: Dictionary in GameData.json("season")["days"]:
		if int(item["day"]) == number:
			return item
	return {}
