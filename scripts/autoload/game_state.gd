extends Node
## The season in progress: which day it is, the seed that makes it replayable, and how each shift
## went. Also moves between the daily screens, and saves the season to its slot (see SaveSlots)
## when it starts, after every shift and at the start of every day.

const SCENES := {
	"calendar": "res://scenes/day/calendar.tscn",
	"memo": "res://scenes/day/memo.tscn",
	"window": "res://scenes/day/window.tscn",
	"report": "res://scenes/day/day_report.tscn",
	"evaluation": "res://scenes/day/evaluation.tscn",
	"freedom_wall": "res://scenes/day/freedom_wall.tscn",
	"title": "res://scenes/main/title.tscn",
}
## Screens a debug launch may jump to. The report needs a finished shift, so it isn't one. The
## evaluation and the Freedom Wall get a made-up season (see DebugSeason).
const DEBUG_SCENES := ["calendar", "memo", "window", "evaluation", "freedom_wall"]

var day: int = 1
var base_seed: int = 1
var last_summary: Dictionary = {}
var last_history: Array = []
var results: Dictionary = {}
## The save slot this season is written to, 1 to SaveSlots.SLOTS, or 0 for a season that isn't
## saved (a debug jump).
var slot: int = 0
## Set by the evaluation's New season, so the title opens the save slots: the player picks where
## the next season goes instead of it replacing the finished one.
var open_slots_on_title: bool = false


## Starts a season in in_slot (1 to SaveSlots.SLOTS, from the title's save slots), or unsaved
## when it's 0.
func start_new_game(seed_value: int = 0, in_slot: int = 0) -> void:
	slot = in_slot
	base_seed = seed_value if seed_value > 0 else randi_range(1, 99999)
	day = int(GameData.json("days")["first_day"])
	results.clear()
	save_game()
	go_to("calendar")


## Picks a saved season back up where it stopped: the day it was on (from the calendar), the next
## day if that day's shift was finished, or the evaluation once the last day is done. Returns
## false, and changes nothing, if the slot holds no usable save.
func continue_game(from_slot: int) -> bool:
	var entry := SaveSlots.read(from_slot)
	if entry["state"] != SaveSlots.STATE_OK:
		return false
	var save: Dictionary = entry["save"]
	slot = from_slot
	day = save["day"]
	base_seed = save["seed"]
	results = save["results"]
	last_summary = {}
	last_history = []
	go_to("evaluation" if save["complete"] else "calendar")
	return true


## From the evaluation: back to the title with the save slots open.
func choose_new_season() -> void:
	open_slots_on_title = true
	go_to("title")


## Writes the season to its slot. A failed write keeps the last good save and only warns.
func save_game() -> void:
	if SaveSlots.valid_slot(slot):
		SaveSlots.write(slot, SaveSlots.pack(day, base_seed, results, int(Time.get_unix_time_from_system())))


func start_shift() -> void:
	go_to("window")


func finish_shift(summary: Dictionary, history: Array) -> void:
	Scoring.finish(summary, history, base_seed, day)
	PlaytestLog.append(PlaytestLog.entry(summary, history, day, base_seed))
	last_summary = summary
	last_history = history
	results[day] = summary
	save_game()
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


## After the last day the Freedom Wall opens the evaluation instead, and a new season goes
## through start_new_game, so this never runs past the last day.
func next_day() -> void:
	day = mini(day + 1, int(GameData.json("days")["last_day"]))
	save_game()
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
## --day is required, even with --scene=evaluation (which plays out a made-up season, see
## DebugSeason, and opens the end-of-season evaluation).
func debug_jump() -> bool:
	if not OS.is_debug_build():
		return false
	var args := debug_args()
	if not args.has("day") or not String(args["day"]).is_valid_int():
		return false
	var days: Dictionary = GameData.json("days")
	# A jump plays a made-up season, so it never touches the player's saves.
	slot = 0
	day = clampi(String(args["day"]).to_int(), int(days["first_day"]), int(days["last_day"]))
	var seed_text := String(args.get("seed", ""))
	base_seed = maxi(1, seed_text.to_int()) if seed_text.is_valid_int() else 1
	results.clear()
	var scene := String(args.get("scene", "window"))
	if scene not in DEBUG_SCENES:
		scene = "window"
	if scene == "evaluation":
		day = int(days["last_day"])
		results = DebugSeason.make(args)
	elif scene == "freedom_wall":
		# Today's made-up summary; no calls, so only the day's outcome posts and filler show.
		results = DebugSeason.make(args)
		last_summary = results.get(day, {})
		last_history = []
	# tests/smoke.sh looks for this line to know the jump really happened.
	print("debug_jump: day %d seed %d -> %s" % [day, base_seed, scene])
	go_to(scene)
	return true


## A shift the line gave up on, logged before the player retries it (finish_shift never runs then).
func log_failed_attempt(summary: Dictionary, history: Array) -> void:
	summary["stars"] = 0
	summary["integrity"] = Evaluation.integrity(summary)
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
