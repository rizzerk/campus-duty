extends Node
## The season in progress: which day it is, the seed that makes it replayable, and how each shift
## went. Also moves between the daily screens.

const SCENES := {
	"calendar": "res://scenes/day/calendar.tscn",
	"memo": "res://scenes/day/memo.tscn",
	"window": "res://scenes/day/window.tscn",
	"report": "res://scenes/day/day_report.tscn",
	"title": "res://scenes/main/title.tscn",
}
## Screens a debug launch may jump to. The report needs a finished shift, so it isn't one.
const DEBUG_SCENES := ["calendar", "memo", "window"]

var day: int = 1
var base_seed: int = 1
var last_summary: Dictionary = {}
var last_history: Array = []
var results: Dictionary = {}


func start_new_game(seed_value: int = 0) -> void:
	base_seed = seed_value if seed_value > 0 else randi_range(1, 99999)
	day = int(GameData.json("days")["first_day"])
	results.clear()
	go_to("calendar")


func start_shift() -> void:
	go_to("window")


func finish_shift(summary: Dictionary, history: Array) -> void:
	summary["spot_check"] = []
	summary["caught_bends"] = 0
	if summary["reason"] != "patience":
		var check: Dictionary = SpotCheck.run(history, base_seed * 1000 + day, day)
		summary["spot_check"] = check["rows"]
		summary["caught_bends"] = check["caught_bends"]
	summary["stars"] = Scoring.stars(summary)
	PlaytestLog.append(PlaytestLog.entry(summary, history, day, base_seed))
	last_summary = summary
	last_history = history
	results[day] = summary
	Achievements.record_shift(summary, history, day, { "stars": season_stars(), "last_day": is_last_day() })
	go_to("report")


## Plays the same day again with the same students, after the line gave up.
func retry_day() -> void:
	go_to("window")


func season_stars() -> int:
	var total := 0
	for number: int in results:
		total += int(results[number].get("stars", 0))
	return total


func next_day() -> void:
	if is_last_day():
		# A new season: the old season's stars don't carry over.
		results.clear()
		day = int(GameData.json("days")["first_day"])
	else:
		day += 1
	go_to("calendar")


func is_last_day() -> bool:
	return day >= int(GameData.json("days")["last_day"])


## Buttons the player has learned so far. Each day can unlock new ones.
func unlocked_actions() -> Array:
	var actions: Array = []
	for number in range(int(GameData.json("days")["first_day"]), day + 1):
		actions.append_array(GameData.day(number).get("actions", []))
	return actions


## Reject reasons the player has learned so far, in the order they were introduced.
func unlocked_reject_reasons() -> Array:
	var reasons: Array = []
	for number in range(int(GameData.json("days")["first_day"]), day + 1):
		reasons.append_array(GameData.day(number).get("reject_reasons", []))
	return reasons


func go_to(scene: String) -> void:
	get_tree().call_deferred("change_scene_to_file", SCENES[scene])


## Debug builds only: `godot --path . -- --day=6 --seed=42 --scene=memo` starts straight at that
## day for playtesting. Returns true when it took over, so the splash can skip its intro.
func debug_jump() -> bool:
	if not OS.is_debug_build():
		return false
	var args := debug_args()
	if not args.has("day") or not String(args["day"]).is_valid_int():
		return false
	var days: Dictionary = GameData.json("days")
	day = clampi(String(args["day"]).to_int(), int(days["first_day"]), int(days["last_day"]))
	var seed_text := String(args.get("seed", ""))
	base_seed = maxi(1, seed_text.to_int()) if seed_text.is_valid_int() else 1
	results.clear()
	var scene := String(args.get("scene", "window"))
	if scene not in DEBUG_SCENES:
		scene = "window"
	# tests/smoke.sh looks for this line to know the jump really happened.
	print("debug_jump: day %d seed %d -> %s" % [day, base_seed, scene])
	go_to(scene)
	return true


## A shift the line gave up on, logged before the player retries it (finish_shift never runs then).
func log_failed_attempt(summary: Dictionary, history: Array) -> void:
	summary["stars"] = 0
	PlaytestLog.append(PlaytestLog.entry(summary, history, day, base_seed, { "retried": true }))


## The `--key=value` arguments after `--` on the command line. A bare `--key` reads as "true".
static func debug_args() -> Dictionary:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "true"
	return args
