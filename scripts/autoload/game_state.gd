extends Node
## The season in progress: which day it is, the seed that makes it replayable, and how each shift
## went. Also moves between the daily screens.

const SCENES := {
	"memo": "res://scenes/day/memo.tscn",
	"window": "res://scenes/day/window.tscn",
	"report": "res://scenes/day/day_report.tscn",
}

var day: int = 2
var base_seed: int = 1
var last_summary: Dictionary = {}
var last_history: Array = []
var results: Dictionary = {}


func start_new_game(seed_value: int = 0) -> void:
	base_seed = seed_value if seed_value > 0 else randi_range(1, 99999)
	day = int(GameData.json("days")["first_day"])
	results.clear()
	go_to("memo")


func start_shift() -> void:
	go_to("window")


func finish_shift(summary: Dictionary, history: Array) -> void:
	summary["stars"] = stars_for(summary)
	last_summary = summary
	last_history = history
	results[day] = summary
	go_to("report")


func next_day() -> void:
	day = int(GameData.json("days")["first_day"]) if is_last_day() else day + 1
	go_to("memo")


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


## 3 stars needs 90% correct, 90% of the line served and no walkouts. A failed shift gets none.
static func stars_for(summary: Dictionary) -> int:
	if summary["reason"] == "patience":
		return 0
	var score := minf(summary["accuracy"], summary["served_ratio"])
	var stars := 0
	for threshold: float in GameData.json("balance")["star_thresholds"]:
		if score >= threshold:
			stars += 1
	if summary["walked_out"] > 0:
		stars = mini(stars, 2)
	return stars


func go_to(scene: String) -> void:
	get_tree().call_deferred("change_scene_to_file", SCENES[scene])
