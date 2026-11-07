extends SceneTree
## Run: godot --headless --path . --script res://tests/test_calendar.gd

var _failures: int = 0


func _init() -> void:
	_test_season_data()
	_test_states()
	print("calendar: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


## Ten days, two working weeks, in order, and the built days' phases match days.json.
func _test_season_data() -> void:
	var season: Dictionary = GameData.json("season")
	var entries: Array = season["days"]
	_check(entries.size() == 10, "the season has 10 days")
	_check(season["weekdays"].size() == 5, "one weekday name per column")
	var last_date := 0
	for i in entries.size():
		var item: Dictionary = entries[i]
		_check(int(item["day"]) == i + 1, "day %d is listed in order" % (i + 1))
		_check(int(item["date"]) > last_date, "day %d's date comes after the day before" % (i + 1))
		last_date = int(item["date"])
		_check(str(item.get("phase", "")) != "" and str(item.get("teaser", "")) != "", "day %d has a phase and a teaser" % (i + 1))
		if GameData.json("days")["days"].has(str(item["day"])):
			_check(item["phase"] == GameData.day(int(item["day"]))["phase"], "day %d's phase matches days.json" % (i + 1))
	_check(Season.entry(4)["phase"] == "2nd-year enrollment", "entry() finds a day")
	_check(Season.entry(99).is_empty(), "entry() is empty for a day that isn't listed")


func _test_states() -> void:
	var days: Dictionary = GameData.json("days")
	var first := int(days["first_day"])
	var last := int(days["last_day"])
	var today := first + 2
	var results := { first: { "reason": "", "stars": 3 }, first + 1: { "reason": "patience", "stars": 0 } }
	_check(Season.state(first, today, results) == "past", "a worked day is past")
	_check(Season.state(first + 1, today, results) == "failed", "a day the line gave up on is failed")
	_check(Season.state(today, today, results) == "today", "today is today")
	_check(Season.state(today + 1, today, results) == "future", "a later day is future")
	_check(Season.state(first - 1, today, results) == "locked", "a day before the first built day is locked")
	_check(Season.state(last + 1, today, results) == "locked", "a day after the last built day is locked")
	_check(Season.state(first, first, {}) == "today", "the first day of a new season is today")
