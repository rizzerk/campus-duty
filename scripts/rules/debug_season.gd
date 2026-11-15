class_name DebugSeason
extends RefCounted
## Debug launches only (`--scene=evaluation`): a made-up season so the end-of-season evaluation
## can be opened on any ending without playing ten days. Pure, so the tests can check that every
## ending is reachable this way.

## How the season treats the regulars, by --regulars=.
const REGULARS := ["good", "mixed", "bad", "missed"]


## A whole season with the same numbers every day, from --accuracy=0.93 (0 to 1), --integrity=98,
## --failed=0 (shifts the line gave up on, counted from day one) and
## --regulars=good|mixed|bad|missed. Values that aren't numbers fall back to these defaults; the
## rest are clamped to what a season can hold.
static func make(args: Dictionary) -> Dictionary:
	var days: Dictionary = GameData.json("days")
	var first := int(days["first_day"])
	var last := int(days["last_day"])
	var accuracy := clampf(_number(args, "accuracy", 0.93), 0.0, 1.0)
	var integrity := clampi(int(_number(args, "integrity", 98.0)), 0, Evaluation.integrity_max())
	var failed := clampi(int(_number(args, "failed", 0.0)), 0, last - first + 1)
	var mood := String(args.get("regulars", "good"))
	if mood not in REGULARS:
		mood = "good"
	var season := {}
	for number in range(first, last + 1):
		var lost := number - first < failed
		var summary := {
			"reason": "patience" if lost else "clear", "accuracy": accuracy, "weighted_accuracy": accuracy,
			"integrity": integrity, "served": 0 if lost else 20, "total": 22, "served_ratio": 0.0 if lost else 0.95,
			"walked_out": 0, "bends": 0, "caught_bends": 0, "regulars": {},
		}
		summary["stars"] = Scoring.stars(summary)
		season[number] = summary
	# Each regular's visits, one call each: all right, the first one wrong, all wrong, or never at
	# the window.
	for regular: Dictionary in GameData.json("events")["regulars"]:
		var visits: Array = regular["appearances"].keys().map(func(key: String) -> int: return int(key))
		visits.sort()
		for i in visits.size():
			var number: int = visits[i]
			if mood == "missed" or not season.has(number):
				continue
			var right := mood == "good" or (mood == "mixed" and i > 0)
			season[number]["regulars"][regular["id"]] = { "right": 1 if right else 0, "wrong": 0 if right else 1, "bent": 0 }
	return season


static func _number(args: Dictionary, key: String, fallback: float) -> float:
	var text := String(args.get(key, ""))
	# 1e999 parses as a float but overflows to inf; treat it as not a number.
	if not text.is_valid_float() or not is_finite(text.to_float()):
		return fallback
	return text.to_float()
