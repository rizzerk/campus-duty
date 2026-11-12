extends SceneTree
## Run: godot --headless --path . --script res://tests/test_achievements.gd

const TEST_SAVE := "user://test_achievements.json"

var _failures: int = 0


func _init() -> void:
	_test_data()
	_test_decisions()
	_test_shift_end()
	_test_stats()
	_test_progress_saves()
	_test_real_shift()
	print("achievements: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _entry(correct: bool, action: String = "approve", problem: String = "", extra: Dictionary = {}) -> Dictionary:
	var entry := { "correct": correct, "action": action, "problem": problem, "bent": false, "caught": 0 }
	entry.merge(extra, true)
	return entry


func _summary(extra: Dictionary = {}) -> Dictionary:
	var summary := { "reason": "time", "stars": 1, "decisions": 4, "mistakes": 1, "false_alarms": 0, "bends": 0, "caught": 0, "caught_bends": 0 }
	summary.merge(extra, true)
	return summary


## Every achievement has the fields the screen needs, ids are unique, and every id the rules can
## return exists in the data.
func _test_data() -> void:
	var ids := {}
	for item: Dictionary in AchievementRules.all():
		_check(not ids.has(item["id"]), "%s is listed once" % item["id"])
		ids[item["id"]] = true
		for key: String in ["name", "desc", "badge"]:
			_check(str(item.get(key, "")) != "", "%s has a %s" % [item["id"], key])
		_check(str(item["badge"]).length() <= 3, "%s's badge text fits" % item["id"])
		if item.has("stat"):
			_check(int(item.get("goal", 0)) > 0, "%s has a goal" % item["id"])
	for id: String in ["first_call", "streak_10", "streak_25", "just_this_once", "not_today", "full_bench",
			"right_office", "lorna_takes_over", "first_shift", "three_stars", "market_survivor", "flawless",
			"line_cleared", "sharp_eye", "caught_red_handed", "star_employee", "season_done", "priority_call"]:
		_check(ids.has(id), "%s is defined in achievements.json" % id)
	_check(AchievementRules.find("nope").is_empty(), "find() is empty for an unknown id")


func _test_decisions() -> void:
	var history: Array = [_entry(true)]
	_check(AchievementRules.after_decision(history).has("first_call"), "a correct call earns first_call")
	_check(not AchievementRules.after_decision([_entry(false)]).has("first_call"), "a wrong call doesn't")
	_check(AchievementRules.after_decision([]).is_empty(), "no history, nothing earned")

	history = []
	for i in 9:
		history.append(_entry(true))
	_check(not AchievementRules.after_decision(history).has("streak_10"), "9 in a row isn't 10")
	history.append(_entry(true))
	_check(AchievementRules.after_decision(history).has("streak_10"), "10 in a row earns streak_10")
	history.append(_entry(false))
	_check(AchievementRules.correct_streak(history) == 0, "a wrong call breaks the streak")
	_check(AchievementRules.correct_streak([_entry(false), _entry(true), _entry(true)]) == 2, "the streak counts back from the latest")

	_check(AchievementRules.after_decision([_entry(false, "favor", "", { "bent": true })]).has("just_this_once"), "a favor earns just_this_once")
	_check(AchievementRules.after_decision([_entry(true, "reject")], { "favor_offered": true }).has("not_today"), "turning down a favor and getting it right earns not_today")
	_check(not AchievementRules.after_decision([_entry(false, "reject")], { "favor_offered": true }).has("not_today"), "turning it down but getting it wrong doesn't")
	_check(not AchievementRules.after_decision([_entry(true, "favor")], { "favor_offered": true }).has("not_today"), "a harmless favor isn't turning one down")
	_check(AchievementRules.after_decision([_entry(true, "hold")], { "bench": 3 }).has("full_bench"), "three on the bench earns full_bench")
	_check(not AchievementRules.after_decision([_entry(true, "hold")], { "bench": 2 }).has("full_bench"), "two on the bench doesn't")

	var routes: Array = [_entry(true, "route:cashier"), _entry(true, "route:consultation"), _entry(false, "route:dean")]
	_check(not AchievementRules.routed_everywhere(routes), "a wrong trip to the Dean doesn't count")
	routes.append(_entry(true, "route:dean"))
	_check(AchievementRules.after_decision(routes).has("right_office"), "right routes to all three offices earn right_office")


func _test_shift_end() -> void:
	var failed := AchievementRules.after_shift(_summary({ "reason": "patience", "stars": 0 }), [], 1)
	_check(failed == ["lorna_takes_over"], "a failed shift earns only lorna_takes_over")
	_check(AchievementRules.after_shift(_summary(), [], 1).has("first_shift"), "finishing day 1 earns first_shift")
	_check(not AchievementRules.after_shift(_summary(), [], 2).has("first_shift"), "day 2 isn't day 1")
	var market := AchievementRules.after_shift(_summary({ "stars": 3 }), [], 6)
	_check(market.has("three_stars") and market.has("market_survivor"), "3 stars on open market day earns both")
	_check(not AchievementRules.after_shift(_summary({ "stars": 3 }), [], 5).has("market_survivor"), "3 stars on another day isn't the market")
	var clean := _summary({ "decisions": 8, "mistakes": 0 })
	_check(AchievementRules.after_shift(clean, [], 2).has("flawless"), "8 clean calls earn flawless")
	clean["false_alarms"] = 1
	_check(not AchievementRules.after_shift(clean, [], 2).has("flawless"), "a false alarm spoils flawless")
	_check(not AchievementRules.after_shift(_summary({ "decisions": 7, "mistakes": 0 }), [], 2).has("flawless"), "7 calls is too short for flawless")
	_check(AchievementRules.after_shift(_summary({ "reason": "clear" }), [], 2).has("line_cleared"), "an empty line earns line_cleared")
	_check(AchievementRules.after_shift(_summary({ "caught": 10 }), [], 2).has("sharp_eye"), "10 catches earn sharp_eye")
	_check(not AchievementRules.after_shift(_summary({ "caught": 10, "false_alarms": 1 }), [], 2).has("sharp_eye"), "not with a false alarm")
	_check(AchievementRules.after_shift(_summary({ "caught_bends": 1 }), [], 4).has("caught_red_handed"), "a caught favor earns caught_red_handed")
	_check(AchievementRules.after_shift(_summary(), [], 3, { "stars": 20 }).has("star_employee"), "20 season stars earn star_employee")
	_check(AchievementRules.after_shift(_summary(), [], 8, { "last_day": true }).has("season_done"), "the last day earns season_done")


func _test_stats() -> void:
	var deltas := AchievementRules.stat_deltas(_entry(true, "fix", "closed_section", { "caught": 2 }))
	_check(deltas.get("sections_fixed", 0) == 1 and deltas.get("correct_calls", 0) == 1, "a section fix counts")
	_check(deltas.get("mismatches_caught", 0) == 2, "catches count")
	_check(AchievementRules.stat_deltas(_entry(true, "fix", "ismis_login")).get("ismis_resets", 0) == 1, "an ISMIS reset counts")
	_check(AchievementRules.stat_deltas(_entry(true, "reject", "fake_signature")).get("fakes_rejected", 0) == 1, "a fake signature rejected counts")
	var wrong := AchievementRules.stat_deltas(_entry(false, "fix", "closed_section", { "caught": 1 }))
	_check(not wrong.has("sections_fixed") and not wrong.has("correct_calls"), "a wrong fix doesn't count")
	_check(wrong.get("mismatches_caught", 0) == 1, "but its catches still do")
	var earned := AchievementRules.from_stats({ "correct_calls": 100, "regulars": { "a": true, "b": true, "c": true } })
	_check(earned.has("veteran") and earned.has("familiar_faces"), "goals reached unlock counter achievements")
	_check(not AchievementRules.from_stats({ "correct_calls": 99 }).has("veteran"), "99 isn't 100")


## The autoload saves what's unlocked and the counters, and reads them back.
func _test_progress_saves() -> void:
	var manager: Node = load("res://scripts/autoload/achievements.gd").new()
	manager.save_path = TEST_SAVE
	manager.reset()
	_check(manager.unlock("first_call"), "unlock() unlocks")
	_check(not manager.unlock("first_call"), "but only once")
	_check(not manager.unlock("not_a_real_one"), "unknown ids are ignored")
	_check(manager.fresh == ["first_call"], "a new unlock is fresh")
	manager.stats["correct_calls"] = 40
	manager.record_shift(_summary({ "stars": 3 }), [], 2)
	_check(manager.is_unlocked("three_stars"), "record_shift unlocks")
	var item := AchievementRules.find("veteran")
	_check(is_equal_approx(manager.progress(item), 0.4), "progress follows the counter")
	var again: Node = load("res://scripts/autoload/achievements.gd").new()
	again.save_path = TEST_SAVE
	again.load_progress()
	_check(again.is_unlocked("first_call") and again.is_unlocked("three_stars"), "unlocks survive a reload")
	_check(int(again.stats.get("correct_calls", 0)) == 40, "counters survive a reload")
	_check(again.unlocked_count() == 2, "unlocked_count counts them")
	manager.reset()
	manager.free()
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


## A real shift through ShiftState: record_decision keeps up with every call without errors and
## counts correct calls the same way the summary does.
func _test_real_shift() -> void:
	var manager: Node = load("res://scripts/autoload/achievements.gd").new()
	manager.save_path = ""
	var shift := ShiftState.new(3, 4242)
	var guard := 0
	while not shift.ended and guard < 2000:
		guard += 1
		if shift.current.is_empty() and shift.call_next().is_empty():
			shift.tick(1.0)
			continue
		var student := shift.current
		var expected: String = RulesCheck.judge(student, "approve", shift.offices(), {})["expected"]
		var details := {}
		if expected == "fix" and student["problems"].has("closed_section"):
			var fits := Timetable.fitting_sections(student)
			details["section"] = fits[0] if not fits.is_empty() else ""
		shift.act(expected if expected != "" else "approve", details)
		manager.record_decision(shift, student)
	var summary := shift.summary()
	_check(int(manager.stats.get("correct_calls", 0)) == summary["correct"], "lifetime correct calls match the shift (%d vs %d)" % [manager.stats.get("correct_calls", 0), summary["correct"]])
	_check(summary["correct"] == 0 or manager.is_unlocked("first_call"), "a shift with a correct call unlocks first_call")
	manager.free()
