extends SceneTree
## Run: godot --headless --path . --script res://tests/test_playtest_log.gd

const TEST_PATH := "user://test_playtest_log.jsonl"

var _failures: int = 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_test_entry_counts_mistakes_by_problem()
	_test_entry_has_no_names()
	_test_entry_survives_missing_keys()
	_test_favors_are_not_mistakes()
	_test_extra_fields_and_time()
	_test_append_writes_one_json_line_each()
	_test_append_stops_when_full()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("playtest_log: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _shift_with_mistakes() -> ShiftState:
	var shift := ShiftState.new(2, 7)
	for seed_value in 5000:
		var student := StudentGen.make(seed_value, 2)
		if student["problems"] == ["missing_requirement"] and not student["no_id"]:
			student["number"] = 901
			shift.current = student
			shift.act("approve")
			break
	for seed_value in 5000:
		var student := StudentGen.make(seed_value, 2)
		if student["problems"].is_empty() and not student["no_id"]:
			student["number"] = 902
			shift.current = student
			shift.act("reject", { "reason": "missing_requirement" })
			break
	return shift


func _scored_summary(shift: ShiftState) -> Dictionary:
	var summary := shift.summary()
	summary["caught_bends"] = 0
	summary["stars"] = Scoring.stars(summary)
	return summary


func _test_entry_counts_mistakes_by_problem() -> void:
	var shift := _shift_with_mistakes()
	var line := PlaytestLog.entry(_scored_summary(shift), shift.history, 2, 7)
	_check(line["day"] == 2 and line["seed"] == 7, "day and seed recorded")
	_check(line["mistakes"] == 2, "two wrong calls counted (got %d)" % line["mistakes"])
	_check(line["mistakes_by_problem"].get("missing_requirement", 0) == 1, "letting a missing requirement through is a missing_requirement mistake")
	_check(line["mistakes_by_problem"].get(PlaytestLog.CLEAN, 0) == 1, "turning away a clean student is filed under clean")


func _test_entry_has_no_names() -> void:
	var shift := _shift_with_mistakes()
	var text := JSON.stringify(PlaytestLog.entry(_scored_summary(shift), shift.history, 2, 7))
	for record: Dictionary in shift.history:
		_check(not text.contains(String(record["name"])), "student name %s stays out of the log" % record["name"])


func _test_entry_survives_missing_keys() -> void:
	var line := PlaytestLog.entry({}, [{}], 1, 1)
	_check(line["stars"] == 0 and line["mistakes"] == 0, "an empty summary gives zeros instead of crashing")


func _test_favors_are_not_mistakes() -> void:
	var history := [
		{ "correct": false, "bent": true, "problem": "unpaid_balance" },
		{ "correct": false, "bent": false, "problem": "overload" },
	]
	var line := PlaytestLog.entry({ "mistakes": 1, "bends": 1 }, history, 4, 1)
	_check(not line["mistakes_by_problem"].has("unpaid_balance"), "a favor isn't counted as a mistake")
	_check(line["mistakes_by_problem"].get("overload", 0) == 1, "a real wrong call is counted")
	_check(line["favors"] == 1, "the favor shows under favors")


func _test_extra_fields_and_time() -> void:
	var line := PlaytestLog.entry({}, [], 6, 3, { "retried": true }, "2026-11-13T10:00:00")
	_check(line["retried"] == true, "extra fields are merged in")
	_check(line["time"] == "2026-11-13T10:00:00", "a passed-in time is used as is")


func _test_append_writes_one_json_line_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_check(PlaytestLog.append({ "day": 1 }, TEST_PATH), "first append succeeds")
	_check(PlaytestLog.append({ "day": 2 }, TEST_PATH), "second append succeeds")
	var lines := FileAccess.get_file_as_string(TEST_PATH).strip_edges().split("\n")
	_check(lines.size() == 2, "two lines written (got %d)" % lines.size())
	var second: Variant = JSON.parse_string(lines[lines.size() - 1])
	_check(typeof(second) == TYPE_DICTIONARY and int(second["day"]) == 2, "each line is JSON, appended in order")


func _test_append_stops_when_full() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("x".repeat(PlaytestLog.MAX_BYTES + 10))
	file.close()
	_check(not PlaytestLog.append({ "day": 3 }, TEST_PATH), "a full log refuses new lines")
	_check(FileAccess.open(TEST_PATH, FileAccess.READ).get_length() == PlaytestLog.MAX_BYTES + 10, "a full log isn't touched")
