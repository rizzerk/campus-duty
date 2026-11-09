extends SceneTree
## Run: godot --headless --path . --script res://tests/test_spot_check.gd

var _failures: int = 0


func _init() -> void:
	_test_picks()
	_test_bends_are_likelier()
	_test_run()
	_test_mid_shift_inspections()
	print("spot_check: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _history(size: int, bent_at: int = -1) -> Array:
	var history: Array = []
	for i in size:
		var bent := i == bent_at
		history.append({ "number": 100 + i, "name": "Student %d" % i, "action": "favor" if bent else "approve", "correct": not bent,
			"bent": bent, "reason": "ISMIS shows an unpaid balance.", "expected": "route:cashier" if bent else "approve",
			"outcome": "bent" if bent else "served", "problem": "unpaid_balance" if bent else "", "false_alarms": 0 })
	return history


func _test_picks() -> void:
	var history := _history(20)
	var picks := SpotCheck.pick(history, 7, 3, 3.0)
	_check(picks.size() == 3, "three transactions")
	_check(picks == SpotCheck.pick(history, 7, 3, 3.0), "same seed, same check")
	var unique := {}
	for index: int in picks:
		unique[index] = true
		_check(index >= 0 and index < history.size(), "index in range")
	_check(unique.size() == 3, "no transaction twice")
	_check(SpotCheck.pick(_history(2), 7, 3, 3.0).size() == 2, "a short day checks what there is")
	_check(SpotCheck.pick([], 7, 3, 3.0).is_empty(), "an empty day checks nothing")


func _test_bends_are_likelier() -> void:
	var history := _history(20, 5)
	var plain := 0
	var weighted := 0
	for seed_value in 1000:
		if SpotCheck.pick(history, seed_value, 3, 1.0).has(5):
			plain += 1
		if SpotCheck.pick(history, seed_value, 3, 3.0).has(5):
			weighted += 1
	_check(plain > 100 and plain < 200, "unweighted catch rate is about 3 in 20 (%d/1000)" % plain)
	_check(weighted > plain + 100, "favors catch her eye more often (%d vs %d)" % [weighted, plain])


func _test_run() -> void:
	var early := SpotCheck.run(_history(10, 3), 1, 2)
	_check(early["rows"].is_empty(), "no spot check before favors exist")
	var from_day: int = int(GameData.json("balance")["spot_check"]["from_day"])
	var caught_any := false
	for seed_value in 50:
		var history := _history(6, 3)
		var check := SpotCheck.run(history, seed_value, from_day)
		_check(check["rows"].size() == 3, "three rows")
		var bent_rows: int = check["rows"].filter(func(row: Dictionary) -> bool: return row["verdict"] == "bent").size()
		_check(bent_rows == check["caught_bends"], "caught count matches the rows")
		_check(history[3].get("spotted", false) == (check["caught_bends"] == 1), "a caught favor is marked in history")
		if check["caught_bends"] == 1:
			caught_any = true
			_check(Consequences.build(history)[0]["text"].contains("spot check"), "the story says she found it")
	_check(caught_any, "a favor gets caught sometimes")
	_check(SpotCheck.verdict({ "correct": true }) == "fine", "fine")
	_check(SpotCheck.verdict({ "correct": false }) == "wrong", "wrong")
	_check(SpotCheck.verdict({ "correct": false, "bent": true }) == "bent", "bent")


func _test_mid_shift_inspections() -> void:
	var h := _history(5)
	_check(not SpotCheck.should_inspect_mid_shift(h, 7, 1), "no mid-shift spot check on day 1 onboarding")
	var praise := SpotCheck.inspect_latest(h, 7, 3)
	_check(praise["kind"] == "praise" and praise["banner"] != "", "accurate work gets praise from Ma'am Lorna")
	var bent_h := _history(4, 3)
	var warn := SpotCheck.inspect_latest(bent_h, 7, 4)
	_check(warn["kind"] == "warning" and warn["banner"].contains("favor"), "rule bending gets a warning")
	var wrong_entry := [{
		"number": 115, "name": "Juan Cruz", "action": "approve", "correct": false, "bent": false,
		"problem": "failed_prereq", "reason": "A 5.0 in the prerequisite.", "office_open": true, "false_alarms": 0,
	}]
	var reminder := SpotCheck.inspect_latest(wrong_entry, 7, 6)
	_check(reminder["kind"] == "rule_reminder" and reminder["banner"].contains("5.0"), "wrong call reminds the player of the forgotten rule")
