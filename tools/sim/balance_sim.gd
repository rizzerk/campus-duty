extends SceneTree
## Plays whole shifts headless with bot players and reports how hard each day is.
##
## Run from the repo root:
##   godot --headless --path . --script res://tools/sim/balance_sim.gd -- [options]
##
## Options:
##   --days=1-8                 days to play (a range or a single day; default: the whole season)
##   --seeds=20                 shifts per day and bot
##   --seed-base=1              first seed, so a second run can use fresh seeds
##   --bots=careful,average     which bots play (see BOTS)
##   --set=key=value            override a balance.json key, or dayN.key[.sub] in days.json.
##                              Repeat for several. Nothing is written to disk.
##   --json                     print machine-readable results instead of a table
##   --bench                    time the generator and one shift per day, then stop

## One simulation step, in real seconds, like the shift tests.
const STEP := 0.25
## Seconds the window itself spends per decision, whoever plays: calling the next student,
## handing papers back and showing the verdict (CALL_DELAY + HAND_BACK + REACT in window.gd).
const WINDOW_OVERHEAD := 2.4

## How each bot plays. Times are real seconds, like a person at the keyboard.
##   overhead   the window's own dead time per decision (WINDOW_OVERHEAD; 0 for the ideal bot)
##   think      reading the papers and the record before deciding
##   per_paper  extra time per paper on the desk
##   tool       extra time when the section picker or the reset tool is needed
##   jitter     random spread on that time (0.3 = ±30%)
##   error      chance of a wrong call on a problem the player already knows
##   new_error  chance of a wrong call on the problem introduced today
##   clean_error  chance of wrongly turning away a student who had nothing wrong
##   flag       chance to flag each real mismatch it notices
##   favor      chance to accept a favor when a student offers one
##   priority   calls graduating and PWD students out of turn
const BOTS := {
	"perfect": { "overhead": 0.0, "think": 0.0, "per_paper": 0.0, "tool": 0.0, "jitter": 0.0, "error": 0.0, "new_error": 0.0, "clean_error": 0.0, "flag": 0.0, "favor": 0.0, "priority": true },
	"careful": { "overhead": WINDOW_OVERHEAD, "think": 6.0, "per_paper": 2.5, "tool": 8.0, "jitter": 0.25, "error": 0.0, "new_error": 0.0, "clean_error": 0.0, "flag": 0.8, "favor": 0.0, "priority": true },
	"average": { "overhead": WINDOW_OVERHEAD, "think": 7.0, "per_paper": 3.0, "tool": 10.0, "jitter": 0.4, "error": 0.07, "new_error": 0.18, "clean_error": 0.04, "flag": 0.5, "favor": 0.15, "priority": false },
	"sloppy": { "overhead": WINDOW_OVERHEAD, "think": 3.0, "per_paper": 1.0, "tool": 5.0, "jitter": 0.3, "error": 0.3, "new_error": 0.45, "clean_error": 0.15, "flag": 0.2, "favor": 0.6, "priority": false },
}
const ROUTES := ["route:cashier", "route:consultation", "route:dean"]

var _failures: Array[String] = []


func _init() -> void:
	var options := _parse(OS.get_cmdline_user_args())
	if not _failures.is_empty():
		for message in _failures:
			printerr(message)
		quit(2)
		return
	_apply_overrides(options["set"])
	if not _failures.is_empty():
		for message in _failures:
			printerr(message)
		quit(2)
		return
	if options["bench"]:
		_bench(options["days"])
		quit(0)
		return
	var results: Array = []
	var mistakes: Dictionary = {}
	for day: int in options["days"]:
		for bot: String in options["bots"]:
			var runs: Array = []
			for n in int(options["seeds"]):
				runs.append(_play_shift(day, int(options["seed_base"]) + n, bot))
			results.append(_aggregate(day, bot, runs))
			for run: Dictionary in runs:
				var by_bot: Dictionary = mistakes.get(bot, {})
				for problem: String in run["mistakes_by_problem"]:
					by_bot[problem] = int(by_bot.get(problem, 0)) + int(run["mistakes_by_problem"][problem])
				mistakes[bot] = by_bot
	if options["json"]:
		print(JSON.stringify({
			"days": options["days"],
			"bots": options["bots"],
			"seeds": options["seeds"],
			"seed_base": options["seed_base"],
			"set": options["set"],
			"results": results,
			"mistakes_by_problem": mistakes,
		}, "\t"))
	else:
		_print_table(results, mistakes, options)
	quit(0)


## Plays one shift and scores it the way GameState.finish_shift does.
func _play_shift(day: int, seed_value: int, bot_name: String) -> Dictionary:
	var bot: Dictionary = BOTS[bot_name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([bot_name, day, seed_value])
	var shift := ShiftState.new(day, seed_value)
	var choices := _unlocked_actions(day)
	var decision_key := ""
	var waited := 0.0
	var think := 0.0
	var decision := {}
	var mistakes_by_problem := {}
	# Enough steps for the whole shift plus slack; a shift still running after this is flagged.
	var max_steps := int(GameData.balance("shift_seconds") / STEP * 1.5) + 100
	for i in max_steps:
		if shift.ended:
			break
		shift.tick(STEP)
		if shift.ended:
			break
		if shift.current.is_empty():
			if bot["priority"]:
				_call_priority(shift)
			shift.call_next()
		if shift.current.is_empty():
			continue
		var student: Dictionary = shift.current
		var key := "%d:%d" % [int(student["number"]), shift.history.size()]
		if key != decision_key:
			decision_key = key
			waited = 0.0
			think = float(bot["overhead"]) + _think_time(bot, student, rng)
			decision = {}
		waited += STEP
		var want := RulesCheck.expected(student, shift.offices())
		# The picker is only open for the tool part of the thinking, so open market seats drain then.
		var picking: bool = want["problem"] == "closed_section" and waited < think and waited > think - float(bot["tool"])
		shift.choosing_section = picking
		if waited < think:
			continue
		shift.choosing_section = false
		# Decide once per student; while waiting for a bench seat, only the seat is re-checked.
		if decision.is_empty():
			decision = _decide(bot, student, want, choices, rng, day)
		if decision["action"] == "hold" and shift.bench_full():
			continue
		if decision["action"] == "fix" and want["problem"] == "closed_section":
			var fitting := Timetable.fitting_sections(student)
			decision["details"]["section"] = fitting[0] if not fitting.is_empty() else ""
		var result := shift.act(decision["action"], decision["details"])
		if result.is_empty() or result.has("error"):
			continue
		if not result.get("correct", true) and not result.get("bent", false):
			var problem: String = want["problem"] if want["problem"] != "" else PlaytestLog.CLEAN
			mistakes_by_problem[problem] = int(mistakes_by_problem.get(problem, 0)) + 1
		# A parent argues every routing, which costs the window minutes (window.gd _parent_argues).
		if String(decision["action"]).begins_with("route:") and student.get("trait", "") == "with_parent" and result.get("outcome", "") != "walked_out":
			shift.argue()
	var summary := shift.summary()
	summary["spot_check"] = []
	summary["caught_bends"] = 0
	if summary["reason"] != "patience":
		var check := SpotCheck.run(shift.history, seed_value * 1000 + day, day)
		summary["caught_bends"] = check["caught_bends"]
	summary["stars"] = Scoring.stars(summary)
	summary["patience_left"] = maxf(shift.patience, 0.0)
	summary["minute"] = shift.minute
	summary["mistakes_by_problem"] = mistakes_by_problem
	summary["unfinished"] = not shift.ended
	return summary


## What the bot does with the student at the window. The section for a fix is picked at the moment
## of acting, since open market seats can drain while the bot waits.
func _decide(bot: Dictionary, student: Dictionary, want: Dictionary, choices: Array, rng: RandomNumberGenerator, day: int) -> Dictionary:
	if String(student.get("favor", "")) != "" and rng.randf() < float(bot["favor"]):
		return { "action": "favor", "details": {} }
	var action: String = want["action"]
	var details := {
		"section": "",
		"flags": _flags(bot, student, rng),
		"reason": want.get("reason_id", ""),
		"items": want.get("items", []),
	}
	var clean: bool = want["problem"] == ""
	var new_today: bool = not clean and GameData.day(day)["problems"].has(want["problem"]) and _first_day_of(want["problem"]) == day
	var error_chance: float = bot["clean_error"] if clean else (bot["new_error"] if new_today else bot["error"])
	if rng.randf() < error_chance:
		var wrong: Array = choices.filter(func(choice: String) -> bool: return choice != action)
		if not wrong.is_empty():
			action = wrong[rng.randi_range(0, wrong.size() - 1)]
			if action == "reject":
				var reasons := _unlocked_reject_reasons(day)
				details["reason"] = reasons[rng.randi_range(0, reasons.size() - 1)] if not reasons.is_empty() else ""
	return { "action": action, "details": details }


## Flags each real mismatch the bot notices. A signature flag compares against the adviser on the slip.
func _flags(bot: Dictionary, student: Dictionary, rng: RandomNumberGenerator) -> Array:
	var flags: Array = []
	for pair: Array in Mismatch.real_differences(student):
		if rng.randf() >= float(bot["flag"]):
			continue
		var form: Dictionary = student["papers"][pair[0]]
		var context := String(form["fields"].get("adviser", "")) if pair[1] == "signature" else ""
		flags.append({ "form": pair[0], "key": pair[1], "context": context })
	return flags


func _think_time(bot: Dictionary, student: Dictionary, rng: RandomNumberGenerator) -> float:
	var seconds: float = bot["think"] + bot["per_paper"] * student["papers"].size()
	for problem: String in student["problems"]:
		if problem in ["closed_section", "ismis_login"]:
			seconds += bot["tool"]
	var spread: float = bot["jitter"]
	return maxf(0.0, seconds * rng.randf_range(1.0 - spread, 1.0 + spread))


## Calls the first graduating or PWD student to the front, as a careful player would.
func _call_priority(shift: ShiftState) -> void:
	for index in shift.line.size():
		if String(shift.line[index].get("priority", "")) != "":
			if index > 0:
				shift.call_out_of_turn(index)
			return


## The concrete actions a player has on this day, as GameState.unlocked_actions builds them.
func _unlocked_actions(day: int) -> Array:
	var actions: Array = []
	for number in range(int(GameData.json("days")["first_day"]), day + 1):
		for action: String in GameData.day(number).get("actions", []):
			if action == "route":
				actions.append_array(ROUTES)
			elif not actions.has(action):
				actions.append(action)
	return actions


func _unlocked_reject_reasons(day: int) -> Array:
	var reasons: Array = []
	for number in range(int(GameData.json("days")["first_day"]), day + 1):
		reasons.append_array(GameData.day(number).get("reject_reasons", []))
	return reasons


func _first_day_of(problem: String) -> int:
	var days: Dictionary = GameData.json("days")
	for number in range(int(days["first_day"]), int(days["last_day"]) + 1):
		if GameData.day(number).get("problems", {}).has(problem):
			return number
	return -1


func _aggregate(day: int, bot: String, runs: Array) -> Dictionary:
	var count := float(maxi(runs.size(), 1))
	var histogram := [0, 0, 0, 0]
	var totals := { "stars": 0.0, "accuracy": 0.0, "served_ratio": 0.0, "patience_left": 0.0, "mistakes": 0.0, "bends": 0.0, "caught_bends": 0.0, "walked_out": 0.0, "minute": 0.0 }
	var fails := 0
	var unfinished := 0
	for run: Dictionary in runs:
		if run.get("unfinished", false):
			unfinished += 1
		histogram[clampi(int(run["stars"]), 0, 3)] += 1
		if run["reason"] == "patience":
			fails += 1
		for key: String in totals:
			totals[key] += float(run[key])
	var row := { "day": day, "bot": bot, "runs": runs.size(), "fail_rate": fails / count, "stars_histogram": histogram, "unfinished": unfinished }
	for key: String in totals:
		row[key] = totals[key] / count
	return row


func _print_table(results: Array, mistakes: Dictionary, options: Dictionary) -> void:
	print("Balance sim: %d seeds from %d, days %s" % [options["seeds"], options["seed_base"], options["days"]])
	if not options["set"].is_empty():
		print("Overrides: %s" % ", ".join(options["set"]))
	print("")
	print("%-4s %-8s %6s %-13s %6s %6s %7s %6s %6s %6s" % ["day", "bot", "stars", "0/1/2/3", "fail", "acc", "served", "pat", "mist", "favor"])
	for row: Dictionary in results:
		var histogram: Array = row["stars_histogram"]
		print("%-4d %-8s %6.2f %-13s %5.0f%% %5.0f%% %6.0f%% %6.0f %6.1f %6.1f" % [
			row["day"], row["bot"], row["stars"], "/".join(histogram.map(func(n: int) -> String: return str(n))),
			row["fail_rate"] * 100.0, row["accuracy"] * 100.0, row["served_ratio"] * 100.0,
			row["patience_left"], row["mistakes"], row["bends"],
		])
	var unfinished: Array = results.filter(func(row: Dictionary) -> bool: return row["unfinished"] > 0)
	for row: Dictionary in unfinished:
		print("WARNING: day %d %s: %d shifts hit the step cap before ending; their numbers are wrong" % [row["day"], row["bot"], row["unfinished"]])
	print("")
	print("Wrong calls by problem (all days, all seeds):")
	for bot: String in mistakes:
		var by_problem: Dictionary = mistakes[bot]
		var keys := by_problem.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return by_problem[a] > by_problem[b])
		var parts: Array = keys.map(func(key: String) -> String: return "%s %d" % [key, by_problem[key]])
		print("  %-8s %s" % [bot, ", ".join(parts) if not parts.is_empty() else "none"])


## Times the generator and one perfect shift per day, for spotting slowdowns.
func _bench(days: Array) -> void:
	var day_for_gen: int = days[days.size() - 1]
	var started := Time.get_ticks_usec()
	for seed_value in 1000:
		StudentGen.make(seed_value, day_for_gen)
	var gen_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("bench: StudentGen.make x1000 (day %d): %.1f ms" % [day_for_gen, gen_ms])
	var total_ms := 0.0
	for day: int in days:
		started = Time.get_ticks_usec()
		_play_shift(day, 1, "perfect")
		var shift_ms := (Time.get_ticks_usec() - started) / 1000.0
		total_ms += shift_ms
		print("bench: day %d shift (perfect bot): %.1f ms" % [day, shift_ms])
	print("bench: all shifts: %.1f ms" % total_ms)


func _parse(args: PackedStringArray) -> Dictionary:
	var days_data: Dictionary = GameData.json("days")
	var options := {
		"days": range(int(days_data["first_day"]), int(days_data["last_day"]) + 1),
		"seeds": 20,
		"seed_base": 1,
		"bots": ["careful", "average", "sloppy"],
		"set": [],
		"json": false,
		"bench": false,
	}
	for arg: String in args:
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var key := pair[0]
		var value := pair[1] if pair.size() > 1 else ""
		match key:
			"days":
				var bounds := value.split("-")
				if not bounds[0].is_valid_int() or (bounds.size() > 1 and not bounds[1].is_valid_int()):
					_failures.append("--days takes a day or a range, like 6 or 1-8")
					continue
				var low := bounds[0].to_int()
				var high := bounds[1].to_int() if bounds.size() > 1 else low
				options["days"] = range(maxi(low, int(days_data["first_day"])), mini(high, int(days_data["last_day"])) + 1)
			"seeds":
				options["seeds"] = clampi(value.to_int(), 1, 1000)
			"seed-base":
				options["seed_base"] = maxi(1, value.to_int())
			"bots":
				var bots: Array = []
				for name in value.split(","):
					if BOTS.has(name):
						bots.append(name)
					else:
						_failures.append("unknown bot '%s' (have %s)" % [name, ", ".join(BOTS.keys())])
				options["bots"] = bots
			"set":
				options["set"].append(value)
			"json":
				options["json"] = true
			"bench":
				options["bench"] = true
			_:
				_failures.append("unknown option --%s" % key)
	return options


## Applies --set overrides to the cached data. balance keys: name=value. Day keys: day6.students=24
## or day6.problems.closed_section=0.5.
func _apply_overrides(sets: Array) -> void:
	for item: String in sets:
		var pair := item.split("=", true, 1)
		if pair.size() < 2:
			_failures.append("--set needs key=value, got '%s'" % item)
			continue
		var value: Variant = JSON.parse_string(pair[1])
		if value == null:
			value = pair[1]
		var path := pair[0].split(".")
		var target: Dictionary
		if path[0].begins_with("day") and path[0].trim_prefix("day").is_valid_int():
			var days: Dictionary = GameData.json("days")["days"]
			var number := path[0].trim_prefix("day")
			if not days.has(number):
				_failures.append("--set: there is no day %s" % number)
				continue
			target = days[number]
			path = path.slice(1)
			if path.is_empty():
				_failures.append("--set: name a key inside day %s, like day%s.students=20" % [number, number])
				continue
		else:
			target = GameData.json("balance")
			if path.size() == 1 and not target.has(path[0]):
				_failures.append("--set: balance.json has no key '%s'" % path[0])
				continue
		for i in path.size() - 1:
			if not target.has(path[i]) or typeof(target[path[i]]) != TYPE_DICTIONARY:
				target[path[i]] = {}
			target = target[path[i]]
		target[path[path.size() - 1]] = value
