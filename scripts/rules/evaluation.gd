class_name Evaluation
extends RefCounted
## How well a shift and the season went, beyond counting right calls. Hard calls weigh more, a long
## run of right calls earns a small bonus, and integrity is scored on its own. Pure, so the day
## report, the balance sim and the tests all agree. Numbers live in balance.json ("scoring") and
## data/endings.json.

## Problem id -> first day it shows up. Filled on first use; days.json doesn't change mid-game.
static var _first_days: Dictionary = {}


static func settings() -> Dictionary:
	return GameData.json("balance")["scoring"]


## The first day a problem can show up, from days.json, or -1 if no day has it.
static func first_day_of(problem: String) -> int:
	if _first_days.is_empty():
		var days: Dictionary = GameData.json("days")
		for number in range(int(days["first_day"]), int(days["last_day"]) + 1):
			for id: String in GameData.day(number).get("problems", {}):
				if not _first_days.has(id):
					_first_days[id] = number
	return int(_first_days.get(problem, -1))


## How much one call counts. 1 for a plain call, more when the student had several problems, when
## one of them is the problem introduced today, or when the right answer was to turn them away.
## The problem count is taken before the call, so once a fix or a route clears one, the next call
## on the same student counts as a single problem.
static func call_weight(entry: Dictionary, day: int, extra: Dictionary = {}) -> float:
	if extra.is_empty():
		extra = settings()["weights"]
	var weight := 1.0
	if int(entry.get("problem_count", 0)) >= 2:
		weight += float(extra["multi_problem"])
	var problems: Array = entry.get("problems", [])
	if problems.is_empty() and String(entry.get("problem", "")) != "":
		problems = [entry["problem"]]
	if problems.any(func(id: String) -> bool: return first_day_of(id) == day):
		weight += float(extra["new_today"])
	if String(entry.get("expected", "")) == "reject":
		weight += float(extra["turn_away"])
	return weight


## The longest run of right calls in a row. A favor or a wrong call breaks it.
static func best_streak(history: Array) -> int:
	var best := 0
	var run := 0
	for entry: Dictionary in history:
		run = run + 1 if entry.get("correct", false) else 0
		best = maxi(best, run)
	return best


## streak_bonus for every full streak_every right calls in a row, up to streak_cap.
static func streak_bonus(streak: int) -> float:
	var scoring := settings()
	return minf(floorf(float(streak) / float(scoring["streak_every"])) * float(scoring["streak_bonus"]), float(scoring["streak_cap"]))


## The weighted side of a shift: weighted_accuracy (what stars use, bonus included), plus the parts
## the day report shows. Favors are left out here, as in the plain accuracy: integrity deals with them.
static func shift(history: Array, day: int) -> Dictionary:
	var extra: Dictionary = settings()["weights"]
	var right := 0.0
	var total := 0.0
	var hard := 0
	var hard_right := 0
	var bends := 0
	for entry: Dictionary in history:
		if entry.get("bent", false):
			bends += 1
			continue
		var weight := call_weight(entry, day, extra)
		total += weight
		if weight > 1.0:
			hard += 1
		if entry.get("correct", false):
			right += weight
			if weight > 1.0:
				hard_right += 1
	var streak := best_streak(history)
	var bonus := streak_bonus(streak) if total > 0.0 else 0.0
	# Same rule as the plain accuracy: no calls at all is 0%, only favors is 100% (integrity pays).
	var base := right / total if total > 0.0 else (1.0 if bends > 0 else 0.0)
	return {
		"weighted_accuracy": minf(base + bonus, 1.0),
		"weighted_base": base,
		"hard_calls": hard,
		"hard_right": hard_right,
		"best_streak": streak,
		"streak_bonus": bonus,
	}


## The most integrity a shift can have.
static func integrity_max() -> int:
	return int(settings()["integrity"]["start"])


## What moved integrity this shift, as { favor, caught_favor, false_alarm, flag } points (penalties
## negative). Honest flags only earn back what false alarms cost: they never cancel a favor.
static func integrity_parts(summary: Dictionary) -> Dictionary:
	var points: Dictionary = settings()["integrity"]
	var false_alarms := int(summary.get("false_alarms", 0)) * int(points["per_false_alarm"])
	return {
		"favor": -int(summary.get("bends", 0)) * int(points["per_favor"]),
		"caught_favor": -int(summary.get("caught_bends", 0)) * int(points["per_caught_favor"]),
		"false_alarm": -false_alarms,
		"flag": mini(int(summary.get("caught", 0)) * int(points["per_flag"]), false_alarms),
	}


## Integrity out of integrity_max() for one shift, from the summary after the spot check. Favors
## cost points, more if Ma'am Lorna caught them; false alarms cost a little; honest flags earn
## those back.
static func integrity(summary: Dictionary) -> int:
	var score := integrity_max()
	var parts := integrity_parts(summary)
	for key: String in parts:
		score += int(parts[key])
	return clampi(score, 0, integrity_max())


## The day report's line on what moved integrity today, from endings.json "integrity_story", e.g.
## "Integrity 76 / 100: favors done −20, false alarms −8, honest flags +4. Integrity decides…".
## Empty when nothing moved it.
static func integrity_story(summary: Dictionary) -> String:
	var text: Dictionary = GameData.json("endings").get("integrity_story", {})
	var parts := integrity_parts(summary)
	var pieces: Array = []
	for key: String in ["favor", "caught_favor", "false_alarm", "flag"]:
		var points := int(parts[key])
		if points != 0 and text.has(key):
			var signed := ("+%d" % points) if points > 0 else ("−%d" % -points)
			pieces.append(String(text[key]).format({ "points": signed }))
	if pieces.is_empty():
		return ""
	var intro := String(text.get("intro", "")).format({ "integrity": integrity(summary), "max_integrity": integrity_max() })
	return "%s %s. %s" % [intro, ", ".join(pieces), String(text.get("outro", ""))]


## The season's numbers from GameState.results (day -> summary): mean weighted accuracy, mean
## integrity, and how many shifts the line gave up on.
static func season(results: Dictionary) -> Dictionary:
	var accuracy := 0.0
	var integrity_total := 0.0
	var failed := 0
	for number: int in results:
		var summary: Dictionary = results[number]
		accuracy += float(summary.get("weighted_accuracy", summary.get("accuracy", 0.0)))
		integrity_total += float(summary.get("integrity", integrity(summary)))
		if summary.get("reason", "") == "patience":
			failed += 1
	var days := results.size()
	return {
		"days": days,
		"accuracy": accuracy / days if days > 0 else 0.0,
		"integrity": roundi(integrity_total / days) if days > 0 else 0,
		"failed_days": failed,
	}


## One ending's bars, with missing ones open: an ending can set just the bars it cares about.
static func bars(ending_data: Dictionary) -> Dictionary:
	return {
		"min_accuracy": float(ending_data.get("min_accuracy", 0.0)),
		"min_integrity": int(ending_data.get("min_integrity", 0)),
		"max_failed_days": int(ending_data.get("max_failed_days", 1_000_000)),
	}


## Which of the bars the numbers clear: { accuracy, integrity, failed_days } -> bool.
static func checks(numbers: Dictionary, ending_data: Dictionary) -> Dictionary:
	var bar := bars(ending_data)
	return {
		"accuracy": numbers["accuracy"] >= bar["min_accuracy"] - 0.00001,
		"integrity": numbers["integrity"] >= bar["min_integrity"],
		"failed_days": numbers["failed_days"] <= bar["max_failed_days"],
	}


## Whether the season's numbers clear one ending's bars.
static func meets(numbers: Dictionary, ending_data: Dictionary) -> bool:
	return checks(numbers, ending_data).values().all(func(ok: bool) -> bool: return ok)


## The end-of-season result: { id, title, reasons, numbers }. id is kept, probation or
## not_renewed. Endings are tried in order and the first whose bars are all met wins; the last
## one catches the rest. Reasons compare the numbers with the bars of the ending they got (the
## best one) or of the one just above it that they missed, so they always match the numbers.
static func ending(results: Dictionary) -> Dictionary:
	var data: Dictionary = GameData.json("endings")
	var numbers := season(results)
	var order: Array = data["order"]
	var index := order.size() - 1
	for i in order.size():
		if meets(numbers, data["endings"][order[i]]):
			index = i
			break
	var chosen: String = order[index]
	var reasons := reasons_against(numbers, data["endings"][chosen], true) if index == 0 \
			else reasons_against(numbers, data["endings"][order[index - 1]], false)
	return { "id": chosen, "title": String(data["endings"][chosen].get("title", chosen)), "reasons": reasons, "numbers": numbers }


## Player-facing lines comparing the numbers with one ending's bars. met lists the bars that were
## cleared; otherwise only the ones that fell short.
static func reasons_against(numbers: Dictionary, ending_data: Dictionary, met: bool) -> Array:
	var text: Dictionary = GameData.json("endings").get("reasons", {})
	var bar := bars(ending_data)
	var values := {
		"accuracy": roundi(numbers["accuracy"] * 100.0),
		"min_accuracy": roundi(bar["min_accuracy"] * 100.0),
		"integrity": numbers["integrity"],
		"min_integrity": bar["min_integrity"],
		"max_integrity": integrity_max(),
		"failed_days": numbers["failed_days"],
		"max_failed_days": bar["max_failed_days"],
	}
	var lines: Array = []
	var results := checks(numbers, ending_data)
	for key: String in ["accuracy", "integrity", "failed_days"]:
		# Skip bars this ending doesn't set, and lines the data doesn't have.
		var template := String(text.get("%s_%s" % [key, "ok" if results[key] else "low"], ""))
		if results[key] == met and template != "" and ending_data.has("max_failed_days" if key == "failed_days" else "min_" + key):
			lines.append(template.format(values))
	return lines
