class_name ShiftState
extends RefCounted
## One shift at Window 3, without any scenes: the clock, the line, patience, the hold bench and
## students coming back from other offices. Scenes call tick() and act() and listen to signals.

signal student_joined_line(student: Dictionary)
signal student_called(student: Dictionary)
signal bench_changed
signal office_changed(office: String, status: String)
signal shift_ended(reason: String)

const BENCH_SEATS := 3

var day: int
var minute: float = 0.0
var patience: float
var line: Array = []
var current: Dictionary = {}
var bench: Array = []
var served: int = 0
var mistakes: int = 0
var walked_out: int = 0
var caught: int = 0
var false_alarms: int = 0
var total_students: int = 0
var history: Array = []
var ended: bool = false
var end_reason: String = ""

var _arrivals: Array = []
var _away: Array = []
var _office_status: Dictionary = {}


func _init(day_number: int, base_seed: int) -> void:
	day = day_number
	patience = GameData.balance("patience_start")
	var info := GameData.day(day)
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed * 100 + day
	var number := int(GameData.balance("first_queue_number")) + rng.randi_range(0, 200)
	var total := int(info["students"])
	var start_line := int(info["start_line"])
	var times: Array = []
	for i in total:
		var at := 0.0 if i < start_line else lerpf(10.0, 200.0, float(i - start_line) / maxf(1.0, total - start_line - 1))
		times.append(at)
	for rush: Dictionary in info.get("rush", []):
		for i in int(rush["count"]):
			times.append(float(rush["at"]))
	times.sort()
	total_students = times.size()
	for i in times.size():
		var student := StudentGen.make(base_seed * 100000 + day * 1000 + i, day)
		student["number"] = number + i
		_arrivals.append({ "student": student, "at": times[i] })
	_office_status = _statuses()
	tick(0.0)


func offices() -> Dictionary:
	return OfficeSchedule.snapshot(day, minute)


## Game time as a clock string, like "10:45 AM".
func clock_text() -> String:
	return OfficeSchedule.clock(minute, true)


func tick(delta_seconds: float) -> void:
	if ended:
		return
	minute = minf(minute + delta_seconds * GameData.balance("shift_minutes") / GameData.balance("shift_seconds"),
			GameData.balance("shift_minutes"))
	while not _arrivals.is_empty() and _arrivals[0]["at"] <= minute:
		_join_line(_arrivals.pop_front()["student"])
	for trip: Dictionary in _away.duplicate():
		if trip["back_at"] <= minute:
			_away.erase(trip)
			var student: Dictionary = trip["student"]
			if trip["resolve"] != "":
				student["problems"].erase(trip["resolve"])
			student["returning"] = true
			_join_line(student)
	_release_bench()
	_emit_office_changes()
	var waiting := line.size()
	patience -= delta_seconds * (GameData.balance("patience_drain_base") + GameData.balance("patience_drain_per_waiting") * waiting)
	_check_end()


## Brings the next student to the window. Returns them, or {} if nobody is waiting.
func call_next() -> Dictionary:
	if ended or not current.is_empty() or line.is_empty():
		return {}
	current = line.pop_front()
	student_called.emit(current)
	return current


## Calls a priority student (graduating or PWD) to the front of the line.
func call_out_of_turn(index: int) -> bool:
	if index < 0 or index >= line.size() or line[index]["priority"] == "":
		return false
	line.push_front(line.pop_at(index))
	return true


func bench_full() -> bool:
	return bench.size() >= BENCH_SEATS


## Asking the student about a flag takes a few minutes and tries the line's patience.
func ask() -> void:
	if ended:
		return
	minute += GameData.balance("ask_minutes")
	patience -= GameData.balance("ask_patience")
	tick(0.0)


## The player's decision on the student at the window. details holds "section" (section picker)
## and "flags" (the player's flagged mismatches, judged now). Returns the rules result plus an
## outcome: served, stays, routed, held, let_through, sent_back_wrong or walked_out.
func act(action: String, details: Dictionary = {}) -> Dictionary:
	if ended or current.is_empty():
		return {}
	if action == "hold" and bench_full():
		return { "error": "bench_full" }
	var student := current
	var result := RulesCheck.judge(student, action, offices(), details)
	var flag_score := Mismatch.score_flags(student, details.get("flags", []))
	caught += flag_score["caught"]
	false_alarms += flag_score["false_alarms"]
	patience += flag_score["caught"] * GameData.balance("patience_flag_bonus")
	patience -= flag_score["false_alarms"] * GameData.balance("patience_false_flag_penalty")
	patience = minf(patience, GameData.balance("patience_start"))
	var outcome := ""
	if result["correct"]:
		patience = minf(patience + GameData.balance("patience_correct_bonus"), GameData.balance("patience_start"))
		if action == "fix":
			student["problems"].erase(result["problem"])
			if result["problem"] == "closed_section":
				student["request"]["section"] = details.get("section", "")
			outcome = "stays" if not student["problems"].is_empty() else _finish("served")
		elif action.begins_with("route:"):
			var office := action.trim_prefix("route:")
			_away.append({ "student": student, "back_at": minute + OfficeSchedule.return_minutes(day, office, minute), "resolve": result["problem"] })
			outcome = "routed"
		elif action == "hold":
			bench.append(student)
			bench_changed.emit()
			outcome = "held"
		else:
			outcome = _finish("served")
	else:
		mistakes += 1
		patience -= GameData.balance("patience_mistake_penalty")
		if action == "approve":
			outcome = _finish("let_through")
		elif student["returns"] < int(GameData.balance("max_returns")):
			student["returns"] += 1
			student["mood"] = "angry"
			_away.append({ "student": student, "back_at": minute + GameData.balance("wrong_return_minutes"), "resolve": "" })
			outcome = "sent_back_wrong"
		else:
			walked_out += 1
			patience -= GameData.balance("patience_walkout_penalty")
			outcome = "walked_out"
	history.append({
		"number": student["number"],
		"name": student["name"],
		"action": action,
		"correct": result["correct"],
		"expected": result["expected"],
		"problem": result["problem"],
		"reason": result["reason"],
		"outcome": outcome,
		"caught": flag_score["caught"],
		"false_alarms": flag_score["false_alarms"],
		"clock": clock_text(),
	})
	if outcome != "stays":
		current = {}
	_check_end()
	result["outcome"] = outcome
	return result


func summary() -> Dictionary:
	var correct := 0
	for entry: Dictionary in history:
		if entry["correct"]:
			correct += 1
	return {
		"reason": end_reason,
		"served": served,
		"decisions": history.size(),
		"correct": correct,
		"mistakes": mistakes,
		"walked_out": walked_out,
		"caught": caught,
		"false_alarms": false_alarms,
		"total": total_students,
		"served_ratio": float(served) / maxi(1, total_students),
		"clock": OfficeSchedule.clock(minute, true),
		# No decisions at all counts as 0%, so waiting out the clock earns nothing.
		"accuracy": float(correct) / history.size() if not history.is_empty() else 0.0,
	}


func _finish(outcome: String) -> String:
	served += 1
	return outcome


func _join_line(student: Dictionary) -> void:
	line.append(student)
	student_joined_line.emit(student)


## Students on the bench go to their office as soon as it opens.
func _release_bench() -> void:
	var released := false
	for student: Dictionary in bench.duplicate():
		var problem := RulesCheck.top_problem(student)
		var action: String = GameData.problem(problem)["action"] if problem != "" else ""
		if not action.begins_with("route:"):
			continue
		var office := action.trim_prefix("route:")
		if OfficeSchedule.is_open(day, office, minute):
			bench.erase(student)
			_away.append({ "student": student, "back_at": minute + OfficeSchedule.return_minutes(day, office, minute), "resolve": problem })
			released = true
	if released:
		bench_changed.emit()


func _statuses() -> Dictionary:
	var result := {}
	for office: String in GameData.json("offices"):
		result[office] = OfficeSchedule.status(day, office, minute)
	return result


func _emit_office_changes() -> void:
	var now := _statuses()
	for office: String in now:
		if now[office] != _office_status.get(office):
			office_changed.emit(office, now[office])
	_office_status = now


func _check_end() -> void:
	if ended:
		return
	if patience <= 0.0:
		_end("patience")
	elif minute >= GameData.balance("shift_minutes"):
		_end("time")
	elif line.is_empty() and current.is_empty() and bench.is_empty() and _away.is_empty() and _arrivals.is_empty():
		_end("clear")


func _end(reason: String) -> void:
	ended = true
	end_reason = reason
	shift_ended.emit(reason)
