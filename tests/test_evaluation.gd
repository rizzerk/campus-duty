extends SceneTree
## Run: godot --headless --path . --script res://tests/test_evaluation.gd
## Thresholds are read from data/, so retuning a number doesn't break these tests.

const EPSILON := 0.0001

var _failures: int = 0


func _init() -> void:
	_test_call_weights()
	_test_streaks()
	_test_shift()
	_test_integrity()
	_test_season()
	_test_ending_boundaries()
	_test_reasons_match_numbers()
	_test_stars_use_weighted_accuracy()
	_test_shift_state_records_it()
	_test_regular_calls()
	_test_regular_outcomes()
	_test_regulars_over_the_season()
	_test_ending_target()
	_test_ending_screen_data()
	_test_season_totals()
	_test_debug_season_reaches_every_ending()
	print("evaluation: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPSILON


func _weights() -> Dictionary:
	return GameData.json("balance")["scoring"]["weights"]


func _entry(correct: bool, problem: String = "", expected: String = "approve", count: int = 0, bent: bool = false) -> Dictionary:
	return { "correct": correct, "problem": problem, "expected": expected, "problem_count": count, "bent": bent }


func _test_call_weights() -> void:
	var w := _weights()
	_check(Evaluation.first_day_of("closed_section") == 3, "closed sections start on day 3")
	_check(Evaluation.first_day_of("no_such_problem") == -1, "unknown problem has no first day")
	_check(_near(Evaluation.call_weight(_entry(true), 4), 1.0), "a clean student weighs 1")
	_check(_near(Evaluation.call_weight(_entry(true, "unpaid_balance", "route:cashier", 1), 5), 1.0), "an old problem weighs 1")
	_check(_near(Evaluation.call_weight(_entry(true, "unpaid_balance", "route:cashier", 2), 5), 1.0 + w["multi_problem"]), "two problems weigh more")
	_check(_near(Evaluation.call_weight(_entry(true, "unpaid_balance", "route:cashier", 1), 4), 1.0 + w["new_today"]), "today's new problem weighs more")
	_check(_near(Evaluation.call_weight(_entry(true, "failed_prereq", "reject", 1), 7), 1.0 + w["turn_away"]), "a turn-away weighs more")
	_check(_near(Evaluation.call_weight(_entry(true, "failed_prereq", "reject", 2), 6), 1.0 + w["multi_problem"] + w["new_today"] + w["turn_away"]),
			"the extras stack")
	_check(_near(Evaluation.call_weight({}, 4), 1.0), "a bare entry weighs 1")
	# Judged on an old problem, but today's new one was also there: it still counts as new.
	var both := { "correct": true, "problem": "unpaid_balance", "problems": ["ismis_login", "unpaid_balance"], "problem_count": 2, "expected": "route:cashier" }
	_check(_near(Evaluation.call_weight(both, 5), 1.0 + w["multi_problem"] + w["new_today"]), "any of the student's problems can be today's new one")


func _test_streaks() -> void:
	var scoring: Dictionary = GameData.json("balance")["scoring"]
	var every := int(scoring["streak_every"])
	var bonus := float(scoring["streak_bonus"])
	var cap := float(scoring["streak_cap"])
	_check(_near(Evaluation.streak_bonus(0), 0.0), "no streak, no bonus")
	_check(_near(Evaluation.streak_bonus(every - 1), 0.0), "one short of a streak earns nothing")
	_check(_near(Evaluation.streak_bonus(every), bonus), "a full streak earns the bonus")
	_check(_near(Evaluation.streak_bonus(every * 2 - 1), bonus), "partway to the second streak still earns one")
	_check(_near(Evaluation.streak_bonus(every * 2), minf(bonus * 2, cap)), "two streaks earn two")
	_check(_near(Evaluation.streak_bonus(every * 100), cap), "the bonus stops at the cap")
	var history: Array = [_entry(true), _entry(true), _entry(false), _entry(true), _entry(true), _entry(true), _entry(false, "x", "reject", 1, true), _entry(true)]
	_check(Evaluation.best_streak(history) == 3, "a wrong call or a favor breaks the streak")
	_check(Evaluation.best_streak([]) == 0, "an empty day has no streak")


func _test_shift() -> void:
	var w := _weights()
	var empty := Evaluation.shift([], 4)
	_check(_near(empty["weighted_accuracy"], 0.0), "no calls is 0%")
	var favors_only := Evaluation.shift([_entry(false, "unpaid_balance", "route:cashier", 1, true)], 4)
	_check(_near(favors_only["weighted_accuracy"], 1.0) and _near(favors_only["streak_bonus"], 0.0), "only favors is 100% with no bonus, like plain accuracy")
	# Day 4: one right plain call and one wrong call on today's new problem.
	var history: Array = [_entry(true), _entry(false, "unpaid_balance", "route:cashier", 1)]
	var result := Evaluation.shift(history, 4)
	var heavy: float = 1.0 + w["new_today"]
	_check(_near(result["weighted_base"], 1.0 / (1.0 + heavy)), "a missed hard call costs more than a plain one")
	_check(result["hard_calls"] == 1 and result["hard_right"] == 0, "hard calls counted")
	_check(result["best_streak"] == 1, "streak counted")
	history.append(_entry(false, "unpaid_balance", "route:cashier", 1, true))
	_check(_near(Evaluation.shift(history, 4)["weighted_base"], result["weighted_base"]), "favors are left out of accuracy")
	var perfect: Array = []
	for i in 40:
		perfect.append(_entry(true))
	_check(_near(Evaluation.shift(perfect, 4)["weighted_accuracy"], 1.0), "the bonus can't push past 100%")
	var nearly: Array = perfect.duplicate()
	nearly.append(_entry(false))
	var with_bonus := Evaluation.shift(nearly, 4)
	_check(_near(with_bonus["weighted_accuracy"], minf(with_bonus["weighted_base"] + with_bonus["streak_bonus"], 1.0)), "accuracy is base plus bonus")
	_check(with_bonus["streak_bonus"] > 0.0, "a long run earns a bonus")


func _test_integrity() -> void:
	var points: Dictionary = GameData.json("balance")["scoring"]["integrity"]
	var start := int(points["start"])
	_check(Evaluation.integrity({}) == start, "a clean shift keeps full integrity")
	_check(Evaluation.integrity({ "bends": 1 }) == start - int(points["per_favor"]), "a favor costs points")
	_check(Evaluation.integrity({ "bends": 1, "caught_bends": 1 }) == start - int(points["per_favor"]) - int(points["per_caught_favor"]), "a caught favor costs more")
	_check(Evaluation.integrity({ "false_alarms": 1 }) == start - int(points["per_false_alarm"]), "a false alarm costs points")
	_check(Evaluation.integrity({ "false_alarms": 2, "caught": 1 }) == start - 2 * int(points["per_false_alarm"]) + int(points["per_flag"]), "honest flags earn false-alarm points back")
	_check(Evaluation.integrity({ "false_alarms": 1, "caught": 50 }) == start, "flags earn back no more than false alarms cost")
	_check(Evaluation.integrity({ "bends": 1, "caught": 50 }) == start - int(points["per_favor"]), "flags never cancel a favor")
	_check(Evaluation.integrity({ "caught": 50 }) == start, "integrity never goes over the start")
	_check(Evaluation.integrity({ "bends": 100 }) == 0, "integrity never goes below zero")
	_check(Evaluation.integrity_max() == start, "the max is the start")
	_check(Evaluation.integrity_story({ "caught": 3 }) == "", "nothing to explain on a clean shift")
	var story := Evaluation.integrity_story({ "bends": 1, "caught_bends": 1, "false_alarms": 1, "caught": 1 })
	var expected := Evaluation.integrity({ "bends": 1, "caught_bends": 1, "false_alarms": 1, "caught": 1 })
	_check(story.contains("%d / %d" % [expected, start]), "the story shows the score (%s)" % story)
	_check(story.contains("−%d" % int(points["per_favor"])) and story.contains("+%d" % int(points["per_flag"])), "the story shows each part, signed")
	_check(not story.contains("{"), "no unfilled placeholder in the story")


func _test_season() -> void:
	var numbers := Evaluation.season({
		1: { "weighted_accuracy": 0.8, "integrity": 90, "reason": "clear" },
		2: { "weighted_accuracy": 0.6, "integrity": 71, "reason": "patience" },
	})
	_check(numbers["days"] == 2, "two days")
	_check(_near(numbers["accuracy"], 0.7), "mean accuracy")
	_check(numbers["integrity"] == 81, "mean integrity, rounded")
	_check(numbers["failed_days"] == 1, "failed shifts counted")
	var old := Evaluation.season({ 1: { "accuracy": 0.5, "bends": 1, "reason": "time" } })
	_check(_near(old["accuracy"], 0.5) and old["integrity"] == Evaluation.integrity({ "bends": 1 }), "older results without the new keys still work")
	_check(Evaluation.season({})["days"] == 0, "no days")


## A season whose numbers come out exactly as given.
func _results(accuracy: float, integrity: int, failed: int) -> Dictionary:
	var results := {}
	var days := maxi(failed, 1) + 1
	for number in range(1, days + 1):
		results[number] = { "weighted_accuracy": accuracy, "integrity": integrity, "reason": "patience" if number <= failed else "clear" }
	return results


func _test_ending_boundaries() -> void:
	var endings: Dictionary = GameData.json("endings")["endings"]
	var kept: Dictionary = endings["kept"]
	var probation: Dictionary = endings["probation"]
	var ka := float(kept["min_accuracy"])
	var ki := int(kept["min_integrity"])
	var kf := int(kept["max_failed_days"])
	var pa := float(probation["min_accuracy"])
	var pi := int(probation["min_integrity"])
	var pf := int(probation["max_failed_days"])
	_check(Evaluation.ending(_results(ka, ki, kf))["id"] == "kept", "exactly on every kept bar keeps the post")
	_check(Evaluation.ending(_results(ka - 0.001, ki, kf))["id"] == "probation", "just under kept accuracy is probation")
	_check(Evaluation.ending(_results(ka, ki - 1, kf))["id"] == "probation", "just under kept integrity is probation")
	_check(Evaluation.ending(_results(ka, ki, kf + 1))["id"] == "probation", "one failed day too many is probation")
	_check(Evaluation.ending(_results(pa, pi, pf))["id"] == "probation", "exactly on every probation bar is probation")
	_check(Evaluation.ending(_results(pa - 0.001, pi, pf))["id"] == "not_renewed", "just under probation accuracy is not renewed")
	_check(Evaluation.ending(_results(pa, pi - 1, pf))["id"] == "not_renewed", "just under probation integrity is not renewed")
	_check(Evaluation.ending(_results(pa, pi, pf + 1))["id"] == "not_renewed", "too many failed days is not renewed")
	_check(Evaluation.ending({})["id"] == "not_renewed", "no shifts at all is not renewed")
	_check(Evaluation.ending(_results(1.0, 100, 0))["title"] == kept["title"], "the title comes from data")
	_check(Evaluation.meets({ "accuracy": 0.0, "integrity": 0, "failed_days": 99 }, {}), "an ending with no bars takes anyone")
	_check(not Evaluation.meets({ "accuracy": 0.5, "integrity": 0, "failed_days": 99 }, { "min_accuracy": 0.6 }), "a bar that's set still counts")
	_check(Evaluation.meets({ "accuracy": 0.7, "integrity": 0, "failed_days": 99 }, { "min_accuracy": 0.6 }), "bars left out are open")


func _test_reasons_match_numbers() -> void:
	var endings: Dictionary = GameData.json("endings")["endings"]
	var kept: Dictionary = endings["kept"]
	var good_integrity := int(kept["min_integrity"]) + (1 if int(kept["min_integrity"]) < 100 else 0)
	var good := Evaluation.ending(_results(0.95, good_integrity, 0))
	_check(good["id"] == "kept", "a strong season keeps the post")
	_check(good["reasons"].size() == 3, "kept lists all three bars it met")
	_check(String(good["reasons"][0]).contains("95%") and String(good["reasons"][0]).contains("%d%%" % roundi(float(kept["min_accuracy"]) * 100.0)),
			"accuracy reason shows the number and the bar")
	_check(String(good["reasons"][1]).contains(str(good_integrity)), "integrity reason shows the number")
	# Great accuracy, poor integrity: probation, and the only reason is integrity.
	var low_integrity := int(kept["min_integrity"]) - 5
	var shady := Evaluation.ending(_results(0.99, low_integrity, 0))
	_check(shady["id"] == "probation", "favors alone can cost the post")
	_check(shady["reasons"].size() == 1 and String(shady["reasons"][0]).contains(str(low_integrity)), "probation says which bar was missed")
	var bad := Evaluation.ending(_results(0.3, 100, 0))
	_check(bad["id"] == "not_renewed" and bad["reasons"].size() == 1 and String(bad["reasons"][0]).contains("30%"), "not renewed names the probation bar missed")
	# Just under the bar must not show as the bar: 89.7% against 90% reads 89%, on the screen and in the reason.
	var under := float(kept["min_accuracy"]) - 0.003
	var close := Evaluation.ending(_results(under, 100, 0))
	_check(close["id"] != "kept", "just under the accuracy bar doesn't keep the post")
	_check(Evaluation.percent(under) < roundi(float(kept["min_accuracy"]) * 100.0), "the shown percent is under the bar (%d%%)" % Evaluation.percent(under))
	_check(String(close["reasons"][0]).contains("%d%%" % Evaluation.percent(under)), "the reason shows the same rounded-down number")
	_check(Evaluation.percent(float(kept["min_accuracy"])) == roundi(float(kept["min_accuracy"]) * 100.0), "exactly on the bar shows the bar")
	_check(Evaluation.percent(0.95) == 95 and Evaluation.percent(1.0) == 100 and Evaluation.percent(0.0) == 0, "whole percents stay whole")
	for reason: String in good["reasons"] + shady["reasons"] + bad["reasons"]:
		_check(not reason.contains("{"), "no unfilled placeholder in '%s'" % reason)


func _test_stars_use_weighted_accuracy() -> void:
	var summary := { "reason": "clear", "accuracy": 1.0, "weighted_accuracy": 0.6, "served_ratio": 1.0, "walked_out": 0 }
	var weighted := Scoring.stars(summary)
	summary.erase("weighted_accuracy")
	_check(weighted < Scoring.stars(summary), "stars follow weighted accuracy when it's there")


func _test_shift_state_records_it() -> void:
	var shift := ShiftState.new(6, 42)
	var student := shift.call_next()
	_check(not student.is_empty(), "someone is at the window")
	var count: int = student["problems"].size()
	shift.act("approve")
	_check(int(shift.history[0].get("problem_count", -1)) == count, "history records how many problems the student had")
	_check(shift.history[0].has("regular_id"), "history says whether the student was a regular")
	# Day 3: Jericho (#112) comes to the window. His call is filed under his regular id.
	var day3 := ShiftState.new(3, 42)
	var seen := ""
	for i in 40:
		var at_window := day3.call_next()
		if at_window.is_empty():
			break
		day3.act("approve")
		if at_window.get("regular_id", "") != "":
			seen = String(day3.history.back()["regular_id"])
			break
	_check(seen == "jericho_112", "a regular's call is filed under their id (got '%s')" % seen)
	_check(Evaluation.regular_calls(day3.history).has("jericho_112"), "the day's regular calls include them")
	var summary := shift.summary()
	for key: String in ["weighted_accuracy", "hard_calls", "best_streak", "streak_bonus"]:
		_check(summary.has(key), "summary has %s" % key)


func _regular_entry(id: String, correct: bool, bent: bool = false) -> Dictionary:
	return { "regular_id": id, "correct": correct and not bent, "bent": bent }


func _test_regular_calls() -> void:
	var history: Array = [
		_entry(true),
		_regular_entry("jericho_112", true),
		_regular_entry("jericho_112", false),
		_regular_entry("mae_118", false, true),
		{ "correct": true },
	]
	var calls := Evaluation.regular_calls(history)
	_check(calls.size() == 2, "only regulars who reached the window are listed")
	_check(calls["jericho_112"] == { "right": 1, "wrong": 1, "bent": 0 }, "right and wrong calls counted per regular")
	_check(calls["mae_118"] == { "right": 0, "wrong": 0, "bent": 1 }, "a favor counts as bent, not wrong")
	_check(Evaluation.regular_calls([]).is_empty(), "no history, no regulars")


func _test_regular_outcomes() -> void:
	_check(Evaluation.regular_outcome({}) == "missed", "never at the window is missed")
	_check(Evaluation.regular_outcome({ "right": 3 }) == "good", "every call right is good")
	_check(Evaluation.regular_outcome({ "right": 2, "wrong": 1 }) == "mixed", "more right than wrong is mixed")
	_check(Evaluation.regular_outcome({ "right": 1, "wrong": 1 }) == "mixed", "as many right as wrong is mixed")
	_check(Evaluation.regular_outcome({ "right": 1, "wrong": 1, "bent": 1 }) == "bad", "favors count against them")
	_check(Evaluation.regular_outcome({ "wrong": 2 }) == "bad", "only wrong calls is bad")
	_check(Evaluation.regular_outcome({ "bent": 1 }) == "bad", "only a favor is bad")


func _test_regulars_over_the_season() -> void:
	var results := {
		3: { "regulars": { "jericho_112": { "right": 1, "wrong": 0, "bent": 0 } } },
		4: { "regulars": { "jericho_112": { "right": 0, "wrong": 2, "bent": 0 }, "mae_118": { "right": 1, "wrong": 0, "bent": 0 } } },
		5: {},
	}
	var list := Evaluation.regulars(results)
	var events: Array = GameData.json("events")["regulars"]
	_check(list.size() == events.size(), "every regular is listed")
	_check(list.map(func(r: Dictionary) -> String: return r["id"]) == events.map(func(r: Dictionary) -> String: return r["id"]), "in events.json order")
	var by_id := {}
	for regular: Dictionary in list:
		by_id[regular["id"]] = regular
	_check(by_id["jericho_112"]["visits"] == { "right": 1, "wrong": 1, "bent": 0 }, "each day is one visit, wrong if any call was wrong")
	_check(by_id["jericho_112"]["outcome"] == "mixed", "one good visit and one botched one is mixed")
	# A wrong call fixed when they came back still botches that visit.
	var bounced := Evaluation.regulars({
		3: { "regulars": { "jericho_112": { "right": 1, "wrong": 1, "bent": 0 } } },
		4: { "regulars": { "jericho_112": { "right": 1, "wrong": 1, "bent": 0 } } },
		6: { "regulars": { "jericho_112": { "right": 1, "wrong": 0, "bent": 0 } } },
	})
	_check(bounced[0]["visits"] == { "right": 1, "wrong": 2, "bent": 0 } and bounced[0]["outcome"] == "bad",
			"two botched visits out of three is bad, even when the calls balance out")
	_check(by_id["mae_118"]["outcome"] == "good", "one right visit is good")
	_check(by_id["carlo_104"]["outcome"] == "missed", "a regular never seen is missed")
	_check(by_id["carlo_104"]["number"] == 104 and by_id["carlo_104"]["name"] == "Carlo Bacalso", "number and name from events.json")
	for regular: Dictionary in list:
		_check(String(regular["text"]) != "" and not String(regular["text"]).contains("{"), "%s has a filled outcome line" % regular["id"])
	_check(Evaluation.regulars({}).all(func(r: Dictionary) -> bool: return r["outcome"] == "missed"), "an empty season misses everyone")


func _test_ending_target() -> void:
	var endings: Dictionary = GameData.json("endings")["endings"]
	_check(Evaluation.ending(_results(1.0, 100, 0))["target"] == "kept", "kept is measured against its own bars")
	var probation := Evaluation.ending(_results(float(endings["probation"]["min_accuracy"]), int(endings["probation"]["min_integrity"]), 0))
	_check(probation["id"] == "probation" and probation["target"] == "kept", "probation is measured against the kept bars it missed")
	_check(Evaluation.ending(_results(0.1, 0, 9))["target"] == "probation", "not renewed is measured against the probation bars")


func _test_ending_screen_data() -> void:
	var data: Dictionary = GameData.json("endings")
	var expressions: Dictionary = GameData.json("portrait_parts")["expressions"]
	for id: String in data["order"]:
		var ending_data: Dictionary = data["endings"][id]
		for key: String in ["title", "stamp", "stamp_note", "rank", "look", "lorna_expression"]:
			_check(String(ending_data.get(key, "")) != "", "%s has %s" % [id, key])
		_check(expressions.has(ending_data.get("lorna_expression", "")), "%s uses a real expression" % id)
		var verdict: Dictionary = ending_data.get("verdict", {})
		_check(String(verdict.get("ceb", "")) != "" and String(verdict.get("en", "")) != "", "%s has Lorna's verdict in Bisaya and English" % id)
	for key: String in ["office", "heading", "intro", "accuracy", "integrity", "failed_days", "stars", "bars_for", "met", "not_met", "signature",
			"regulars_title", "served", "correct", "star_total", "favors", "endings_note", "main_menu", "new_season"]:
		_check(String(data["screen"].get(key, "")) != "", "screen text has %s" % key)
	for outcome: String in ["good", "mixed", "bad", "missed"]:
		_check(String(data["regular_default"].get(outcome, "")) != "", "a fallback line for %s" % outcome)
		_check(expressions.has(data["regular_expressions"].get(outcome, "")), "a real face for %s" % outcome)
		for regular: Dictionary in GameData.json("events")["regulars"]:
			_check(String(data["regulars"].get(regular["id"], {}).get(outcome, "")) != "", "%s has a %s line" % [regular["id"], outcome])


func _test_season_totals() -> void:
	var per_day: int = GameData.json("balance")["star_thresholds"].size()
	var totals := Evaluation.season_totals({
		1: { "served": 10, "total": 12, "stars": 3, "bends": 1, "caught_bends": 1 },
		2: { "served": 5, "total": 14, "stars": 0 },
	})
	_check(totals["served"] == 15 and totals["students"] == 26, "served and students add up")
	_check(totals["stars"] == 3 and totals["max_stars"] == per_day * 2, "stars out of the most two days can earn")
	_check(totals["bends"] == 1 and totals["caught_bends"] == 1, "favors and caught favors add up")
	_check(Evaluation.season_totals({})["max_stars"] == 0, "an empty season has no stars to earn")


## The debug launch (`--scene=evaluation`) must be able to show all three endings.
func _test_debug_season_reaches_every_ending() -> void:
	var days: Dictionary = GameData.json("days")
	var cases := [
		[{ "accuracy": "0.95", "integrity": "99" }, "kept", "good"],
		[{ "accuracy": "0.8", "integrity": "70", "failed": "2", "regulars": "mixed" }, "probation", "mixed"],
		[{ "accuracy": "0.5", "integrity": "40", "failed": "4", "regulars": "bad" }, "not_renewed", "bad"],
		[{ "regulars": "missed" }, "kept", "missed"],
	]
	for case: Array in cases:
		var season: Dictionary = DebugSeason.make(case[0])
		_check(season.size() == int(days["last_day"]) - int(days["first_day"]) + 1, "a debug season has every day")
		_check(Evaluation.ending(season)["id"] == case[1], "%s reaches %s" % [case[0], case[1]])
		_check(Evaluation.regulars(season).all(func(r: Dictionary) -> bool: return r["outcome"] == case[2]), "%s gives every regular %s" % [case[0], case[2]])
	var junk: Dictionary = DebugSeason.make({ "accuracy": "lots", "integrity": "-5", "failed": "99", "regulars": "../x" })
	var numbers := Evaluation.season(junk)
	_check(numbers["integrity"] == 0 and numbers["failed_days"] == junk.size(), "bad debug numbers are clamped")
	_check(_near(numbers["accuracy"], 0.93), "a debug accuracy that isn't a number falls back")
