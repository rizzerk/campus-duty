extends SceneTree
## Run: godot --headless --path . --script res://tests/test_consequences.gd

var _failures: int = 0


func _init() -> void:
	_test_wrong_calls_come_first()
	_test_every_template_fills()
	_test_limit_and_false_alarms()
	_test_real_shift_history()
	print("consequences: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _entry(action: String, expected: String, correct: bool, problem: String, extra: Dictionary = {}) -> Dictionary:
	var entry := {
		"number": 101, "name": "Maria Tan", "action": action, "expected": expected, "correct": correct,
		"problem": problem, "reason": "Something was wrong.", "outcome": "served", "caught": 0, "false_alarms": 0,
	}
	entry.merge(extra, true)
	return entry


func _test_wrong_calls_come_first() -> void:
	var history := [
		_entry("route:cashier", "route:cashier", true, "unpaid_balance"),
		_entry("approve", "reject", false, "missing_requirement"),
		_entry("fix", "fix", true, "closed_section", { "section": "IT 312-D" }),
	]
	var items := Consequences.build(history)
	_check(items.size() == 3, "three stories")
	_check(not items[0]["good"], "the wrong call is listed first")
	_check(items[1]["good"] and items[2]["good"], "good calls follow")
	_check(items[2]["text"].contains("IT 312-D"), "section filled in")


func _test_every_template_fills() -> void:
	var cases := [
		_entry("approve", "reject", false, "missing_requirement"),
		_entry("route:cashier", "route:consultation", false, "missing_signature"),
		_entry("route:consultation", "hold", false, "missing_signature", { "office_open": false }),
		_entry("reject", "reject", false, "missing_requirement"),
		_entry("hold", "approve", false, ""),
		_entry("reject", "reject", false, "missing_requirement", { "outcome": "walked_out" }),
		_entry("hold", "hold", true, "missing_signature"),
		_entry("reject", "reject", true, "overload", { "reason_id": "office_closed" }),
		_entry("favor", "route:cashier", false, "unpaid_balance", { "bent": true, "outcome": "bent" }),
		_entry("favor", "route:cashier", false, "unpaid_balance", { "bent": true, "spotted": true, "outcome": "bent" }),
		_entry("fix", "approve", false, "", { "outcome": "wrong_fix" }),
		_entry("route:cashier", "reject", false, "fake_signature", { "reason": "Right idea, wrong order. They also have: fake signature." }),
	]
	for problem: String in GameData.json("problems"):
		cases.append(_entry(GameData.problem(problem)["action"], GameData.problem(problem)["action"], true, problem, { "section": "IT 312-D" }))
	for item: Dictionary in Consequences.build(cases, 100):
		_check(not item["text"].contains("{") and not item["text"].contains("}"), "placeholders filled: %s" % item["text"])
	var office: String = Consequences.build([_entry("route:cashier", "route:consultation", false, "missing_signature")])[0]["text"]
	_check(office.contains("Cashier") and office.contains("Consultation"), "wrong office names both offices: %s" % office)
	var closed: String = Consequences.build([_entry("route:consultation", "hold", false, "missing_signature", { "office_open": false })])[0]["text"]
	_check(closed.contains("closed"), "closed office story: %s" % closed)
	var order: String = Consequences.build([_entry("route:cashier", "reject", false, "fake_signature", { "reason": "Right idea, wrong order. They also have: fake signature." })])[0]["text"]
	_check(order.contains("wrong order") and not order.contains("You sent"), "wrong order story: %s" % order)
	var caught: String = Consequences.build([_entry("favor", "route:cashier", false, "unpaid_balance", { "bent": true, "spotted": true, "outcome": "bent" })])[0]["text"]
	_check(caught.contains("spot check"), "caught favor story: %s" % caught)


func _test_limit_and_false_alarms() -> void:
	var history := []
	for i in 10:
		history.append(_entry("route:cashier", "route:cashier", true, "unpaid_balance"))
	history.append(_entry("approve", "approve", true, "", { "false_alarms": 3 }))
	var items := Consequences.build(history, 4)
	_check(items.size() == 4, "limit respected")
	_check(not items[0]["good"] and items[0]["text"].contains("3 things"), "false alarms summed and listed first")
	var many := []
	for i in 9:
		many.append(_entry("approve", "reject", false, "missing_requirement"))
	var capped := Consequences.build(many, 6)
	_check(capped.size() == 6 and capped[5]["text"].contains("4 more"), "overflow says how many more: %s" % capped[5]["text"])
	var trip: String = Consequences.build([_entry("route:consultation", "approve", false, "", { "reason": "There was nothing wrong with the papers. Approve it." })])[0]["text"]
	_check(trip.contains("to Consultation, but there was nothing wrong"), "needless trip reads naturally: %s" % trip)
	_check(not trip.contains("route:"), "no raw action names")


func _test_real_shift_history() -> void:
	var shift := ShiftState.new(4, 42)
	while not shift.ended:
		shift.tick(0.5)
		if shift.current.is_empty():
			shift.call_next()
		if not shift.current.is_empty():
			shift.act("approve")
	for item: Dictionary in Consequences.build(shift.history, 50):
		_check(not item["text"].contains("{"), "real history fills: %s" % item["text"])
