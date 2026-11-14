class_name ShiftState
extends RefCounted
## One shift at Window 3, without any scenes: the clock, the line, patience, the hold bench and
## students coming back from other offices. Scenes call tick() and act() and listen to signals.

signal student_joined_line(student: Dictionary)
signal student_called(student: Dictionary)
signal bench_changed
signal office_changed(office: String, status: String)
signal rush_arrived(count: int)
signal event_triggered(event: Dictionary)
signal spot_inspected(inspection: Dictionary)
signal slots_changed
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
## Favors done for students who had a problem: rule bending, for Ma'am Lorna's spot check.
var bends: int = 0
var total_students: int = 0
var history: Array = []
var ended: bool = false
## True while the player has the section picker open. Open market seats only drain then.
var choosing_section: bool = false
var end_reason: String = ""

var _arrivals: Array = []
var _away: Array = []
var _office_status: Dictionary = {}
var _drain_rng := RandomNumberGenerator.new()
var _drain_clock: float = 0.0
var _base_seed: int = 1
var _scheduled_events: Array = []


func _init(day_number: int, base_seed: int) -> void:
	day = day_number
	_base_seed = base_seed
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
	var rush_times := {}
	for rush: Dictionary in info.get("rush", []):
		rush_times[float(rush["at"])] = true
		for i in int(rush["count"]):
			times.append(float(rush["at"]))
	times.sort()
	total_students = times.size()
	var students: Array = []
	var rush_slots: Array = []
	for i in times.size():
		students.append(StudentGen.make(base_seed * 100000 + day * 1000 + i, day))
		rush_slots.append(rush_times.has(times[i]))
	# The director paces the line (day 1 keeps its scripted tutorial order).
	if not ShiftEvents.is_onboarding(day):
		students = LineDirector.order(students, day, base_seed, rush_slots)
	for i in times.size():
		var student: Dictionary = students[i]
		student["number"] = number + i
		_arrivals.append({ "student": student, "at": times[i], "rush": rush_slots[i] })
	if ShiftEvents.is_onboarding(day):
		ShiftEvents.prepare_day_one_line(_arrivals)
	else:
		ShiftEvents.apply_daily_flavor(_arrivals, day, base_seed)
		_scheduled_events = ShiftEvents.events_for_day(day)
	_drain_rng.seed = base_seed * 7 + day
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
	var before := minute
	minute = minf(minute + delta_seconds * GameData.balance("shift_minutes") / GameData.balance("shift_seconds"),
			GameData.balance("shift_minutes"))
	var rushed := 0
	while not _arrivals.is_empty() and _arrivals[0]["at"] <= minute:
		var arrival: Dictionary = _arrivals.pop_front()
		if arrival["rush"]:
			rushed += 1
		_join_line(arrival["student"])
	if rushed > 0:
		rush_arrived.emit(rushed)
	while not _scheduled_events.is_empty() and float(_scheduled_events[0]["at"]) <= minute:
		event_triggered.emit(_scheduled_events.pop_front())
	_drain_slots(minute - before)
	for trip: Dictionary in _away.duplicate():
		if trip["back_at"] <= minute:
			_away.erase(trip)
			var student: Dictionary = trip["student"]
			if trip["resolve"] != "":
				student["problems"].erase(trip["resolve"])
				StudentGen.resolve(student, trip["resolve"])
			student["returning"] = true
			# Where they went, so the window can say how it went.
			student["trip"] = { "office": trip.get("office", ""), "wrong": trip.get("wrong", false), "closed": trip.get("closed", false) }
			_join_line(student)
	_release_bench()
	_emit_office_changes()
	patience -= delta_seconds * (GameData.balance("patience_drain_base") + GameData.balance("patience_drain_per_waiting") * waiting_weight())
	_check_end()


## How heavily the line weighs on patience. Everyone waiting counts once, an impatient student
## twice and one with a parent half; whoever is at the window adds their extra on top.
func waiting_weight() -> float:
	var total := 0.0
	for student: Dictionary in line:
		total += trait_weight(student)
	if not current.is_empty():
		total += trait_weight(current) - 1.0
	return maxf(total, 0.0)


static func trait_weight(student: Dictionary) -> float:
	var id: String = student.get("trait", "")
	if id == "":
		return 1.0
	return float(GameData.json("traits")[id].get("drain_weight", 1.0))


## A parent arguing about a routing slows the window down.
func argue() -> void:
	if ended:
		return
	minute += GameData.balance("parent_argue_minutes")
	tick(0.0)


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


## Patience a wrong call costs. A day can set its own (the day 1 tutorial is gentler), otherwise
## the season-wide value in balance.json applies.
func mistake_penalty() -> float:
	return float(GameData.day(day).get("patience_mistake_penalty", GameData.balance("patience_mistake_penalty")))


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
## outcome: served, stays, routed, held, let_through, wrong_fix, bent, sent_back_wrong or walked_out.
## "favor" waves the student through without the checks: fine if nothing was wrong, rule bending
## if something was.
func act(action: String, details: Dictionary = {}) -> Dictionary:
	if ended or current.is_empty():
		return {}
	if action == "hold" and bench_full():
		return { "error": "bench_full" }
	var student := current
	# Taken before a fix clears one, so the score knows what the call was really about.
	var problems_before: Array = student["problems"].duplicate()
	var favor := action == "favor"
	var result := RulesCheck.judge(student, "approve" if favor else action, offices(), details)
	var bent: bool = favor and not result["correct"]
	var flag_score := Mismatch.score_flags(student, details.get("flags", []))
	caught += flag_score["caught"]
	false_alarms += flag_score["false_alarms"]
	patience += flag_score["caught"] * GameData.balance("patience_flag_bonus")
	patience -= flag_score["false_alarms"] * GameData.balance("patience_false_flag_penalty")
	patience = minf(patience, GameData.balance("patience_start"))
	var outcome := ""
	if bent:
		bends += 1
		patience -= GameData.balance("bend_patience")
		outcome = _finish("bent")
	elif result["correct"]:
		patience = minf(patience + GameData.balance("patience_correct_bonus"), GameData.balance("patience_start"))
		if action == "fix":
			student["problems"].erase(result["problem"])
			if result["problem"] == "closed_section":
				student["request"]["section"] = details.get("section", "")
			outcome = "stays" if not student["problems"].is_empty() else _finish("served")
		elif action.begins_with("route:"):
			var office := action.trim_prefix("route:")
			_away.append({ "student": student, "back_at": minute + OfficeSchedule.return_minutes(day, office, minute), "resolve": result["problem"], "office": office })
			outcome = "routed"
		elif action == "hold":
			bench.append(student)
			bench_changed.emit()
			outcome = "held"
		else:
			outcome = _finish("served")
	else:
		mistakes += 1
		patience -= mistake_penalty()
		if action == "approve":
			outcome = _finish("let_through")
		elif action == "fix" and result["expected"] != "fix":
			# A fix they didn't need (or not yet): they leave with it, so there's nothing to come
			# back about. A fix that was needed but done wrong (a clashing section) brings them back.
			outcome = _finish("wrong_fix")
		elif student["returns"] < int(GameData.balance("max_returns")):
			student["returns"] += 1
			student["mood"] = "angry"
			var trip := { "student": student, "back_at": minute + GameData.balance("wrong_return_minutes"), "resolve": "" }
			if action.begins_with("route:"):
				var office := action.trim_prefix("route:")
				trip["office"] = office
				trip["wrong"] = true
				trip["closed"] = not OfficeSchedule.is_open(day, office, minute)
			_away.append(trip)
			outcome = "sent_back_wrong"
		else:
			walked_out += 1
			patience -= GameData.balance("patience_walkout_penalty")
			outcome = "walked_out"
	history.append({
		"number": student["number"],
		"name": student["name"],
		"action": action,
		"correct": result["correct"] and not bent,
		"bent": bent,
		"favor": student.get("favor", "") if favor else "",
		"expected": result["expected"],
		"problem": result["problem"],
		"problem_count": problems_before.size(),
		"problems": problems_before,
		"reason": result["reason"],
		"outcome": outcome,
		"reason_id": details.get("reason", ""),
		"section": details.get("section", ""),
		"items": details.get("items", []),
		"office_open": OfficeSchedule.is_open(day, action.trim_prefix("route:"), minute) if action.begins_with("route:") else true,
		"caught": flag_score["caught"],
		"false_alarms": flag_score["false_alarms"],
		"clock": clock_text(),
	})
	if outcome != "stays":
		current = {}
	if SpotCheck.should_inspect_mid_shift(history, _base_seed, day):
		spot_inspected.emit(SpotCheck.inspect_latest(history, _base_seed, day))
	_check_end()
	result["outcome"] = outcome
	result["bent"] = bent
	if bent:
		result["correct"] = false
		result["reason"] = "You did them a favor. %s" % result["reason"]
	return result


## Students sent to the right office (or held for it) who aren't back yet. They were handled
## correctly, so they count toward the line being served even if the window closes first.
func handled_elsewhere() -> int:
	var count := bench.size()
	for trip: Dictionary in _away:
		if trip["resolve"] != "":
			count += 1
	return count


func summary() -> Dictionary:
	var correct := 0
	for entry: Dictionary in history:
		if entry["correct"]:
			correct += 1
	var totals := {
		"reason": end_reason,
		"served": served,
		"decisions": history.size(),
		"correct": correct,
		"mistakes": mistakes,
		"walked_out": walked_out,
		"caught": caught,
		"false_alarms": false_alarms,
		"bends": bends,
		"total": total_students,
		"elsewhere": handled_elsewhere(),
		"served_ratio": float(served + handled_elsewhere()) / maxi(1, total_students),
		"clock": OfficeSchedule.clock(minute, true),
		# No decisions at all counts as 0%, so waiting out the clock earns nothing.
		# Favors aren't judged here; Ma'am Lorna's spot check deals with them.
		"accuracy": float(correct) / (history.size() - bends) if history.size() > bends else (1.0 if bends > 0 else 0.0),
	}
	# Hard calls weigh more and a run of right calls earns a little; stars use weighted_accuracy.
	totals.merge(Evaluation.shift(history, day))
	return totals


## Open market: other windows keep enrolling students, so while the player has the section picker
## open, the sections they're looking at lose seats. The last section that still fits is spared,
## so there's always a right answer, but a slow pick can end up full.
func _drain_slots(minutes: float) -> void:
	var live: Dictionary = GameData.day(day).get("live_slots", {})
	if live.is_empty() or not choosing_section or current.is_empty() or not current["request"].has("course"):
		return
	_drain_clock += minutes
	var changed := false
	while _drain_clock >= float(live["every_minutes"]):
		_drain_clock -= float(live["every_minutes"])
		var fits := Timetable.fitting_sections(current)
		for section: Dictionary in current["record"]["sections"][current["request"]["course"]]:
			if section["seats"] <= 0 or _drain_rng.randf() >= float(live["chance"]):
				continue
			# The seat they already hold is theirs; other windows can't take it.
			if section["code"] == current["request"]["section"]:
				continue
			if fits.has(section["code"]) and fits.size() <= 1 and section["seats"] <= 1:
				continue
			section["seats"] -= 1
			changed = true
			if section["seats"] == 0:
				fits.erase(section["code"])
	if changed:
		slots_changed.emit()


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
		for problem: String in RulesCheck.by_priority(student):
			var action: String = GameData.problem(problem)["action"]
			if not action.begins_with("route:"):
				continue
			var office := action.trim_prefix("route:")
			if OfficeSchedule.is_open(day, office, minute):
				bench.erase(student)
				_away.append({ "student": student, "back_at": minute + OfficeSchedule.return_minutes(day, office, minute), "resolve": problem, "office": office })
				released = true
				break
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
