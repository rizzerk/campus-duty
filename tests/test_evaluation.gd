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
	var summary := shift.summary()
	for key: String in ["weighted_accuracy", "hard_calls", "best_streak", "streak_bonus"]:
		_check(summary.has(key), "summary has %s" % key)
