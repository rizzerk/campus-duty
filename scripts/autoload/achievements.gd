extends Node
## Achievements earned across every season: which ones are unlocked, the lifetime counters behind
## the progress ones, and the "Achievement unlocked" toast. Saved to user:// so they survive
## quitting and new seasons. What earns what is decided in AchievementRules.

signal unlocked(achievement: Dictionary)

const SAVE_PATH := "user://achievements.json"
const TOAST_SECONDS := 3.2
const TOAST_SLIDE := 0.25
const TOAST_WIDTH := 380.0

## Where the file is saved. Tests point this elsewhere (or at "" to not save at all).
var save_path: String = SAVE_PATH
## id -> unix time it was unlocked.
var earned: Dictionary = {}
## Lifetime counters, like "correct_calls". "regulars" is a set of regular ids.
var stats: Dictionary = {}
## Ids unlocked since the last day report, so the report can point them out.
var fresh: Array = []

var _queue: Array = []
var _toast_layer: CanvasLayer
var _showing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()


func is_unlocked(id: String) -> bool:
	return earned.has(id)


func unlocked_count() -> int:
	var count := 0
	for item: Dictionary in AchievementRules.all():
		if earned.has(item["id"]):
			count += 1
	return count


## How far along a counter achievement is, from 0 to 1. Others are 0 or 1.
func progress(item: Dictionary) -> float:
	if earned.has(item["id"]):
		return 1.0
	if not item.has("stat"):
		return 0.0
	return clampf(float(AchievementRules.stat_value(stats, item["stat"])) / float(item["goal"]), 0.0, 1.0)


## Unlocks an achievement and shows its toast. Does nothing if it's already unlocked or unknown.
func unlock(id: String) -> bool:
	if earned.has(id):
		return false
	var item := AchievementRules.find(id)
	if item.is_empty():
		push_warning("Unknown achievement: %s" % id)
		return false
	earned[id] = int(Time.get_unix_time_from_system())
	fresh.append(id)
	_save()
	unlocked.emit(item)
	_queue_toast(item)
	return true


## After each call at the window. `student` is who was at the window when the call was made.
func record_decision(shift: ShiftState, student: Dictionary) -> void:
	if shift.history.is_empty():
		return
	var entry: Dictionary = shift.history[-1]
	var context := {
		"favor_offered": str(student.get("favor", "")) != "",
		"bench": shift.bench.size(),
	}
	var deltas := AchievementRules.stat_deltas(entry)
	for stat: String in deltas:
		stats[stat] = int(stats.get(stat, 0)) + int(deltas[stat])
	var regular: String = student.get("regular_id", "")
	if regular != "" and entry["correct"]:
		var regulars: Dictionary = stats.get("regulars", {})
		regulars[regular] = true
		stats["regulars"] = regulars
	_unlock_all(AchievementRules.after_decision(shift.history, context) + AchievementRules.from_stats(stats))
	_save()


## When a shift is over and scored (or the line gave up).
func record_shift(summary: Dictionary, history: Array, day: int, season: Dictionary = {}) -> void:
	_unlock_all(AchievementRules.after_shift(summary, history, day, season))


## One-off moments the rules can't see in the history, like calling a priority student.
func record_event(id: String) -> void:
	unlock(id)


## Clears everything. For a future settings screen and for tests.
func reset() -> void:
	earned.clear()
	stats.clear()
	fresh.clear()
	_save()


func load_progress() -> void:
	earned.clear()
	stats.clear()
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (data is Dictionary):
		push_warning("Couldn't read %s; starting achievements fresh." % save_path)
		return
	earned = data.get("earned", {})
	stats = data.get("stats", {})


func _save() -> void:
	if save_path == "":
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Couldn't save achievements to %s" % save_path)
		return
	file.store_string(JSON.stringify({ "earned": earned, "stats": stats }, "\t"))


func _unlock_all(ids: Array) -> void:
	for id: String in ids:
		unlock(id)


func _queue_toast(item: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	_queue.append(item)
	if not _showing:
		_show_next_toast()


## One toast at a time, sliding in at the top right, above every screen and the pause menu.
func _show_next_toast() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 100
		add_child(_toast_layer)
	var item: Dictionary = _queue.pop_front()
	var toast := _build_toast(item)
	_toast_layer.add_child(toast)
	var shown := Vector2(1280 - TOAST_WIDTH - 20, 20)
	toast.position = Vector2(shown.x, -140)
	Sfx.play("correct", 0.0)
	var tween := create_tween()
	tween.tween_property(toast, "position", shown, TOAST_SLIDE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(toast, "position:y", -140.0, TOAST_SLIDE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		toast.queue_free()
		_show_next_toast())


func _build_toast(item: Dictionary) -> Control:
	var card := UiKit.card(UiKit.GOLD_PALE, 10, 5)
	card.custom_minimum_size = Vector2(TOAST_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	row.add_child(AchievementBadge.make(item, true, 56))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UiKit.label("ACHIEVEMENT UNLOCKED", 16, UiKit.GOLD_DARK))
	text.add_child(UiKit.label(item["name"], 26))
	var desc := UiKit.wrapped(item["desc"], 15, UiKit.MUTED)
	# A wrapped label needs a width up front, or the card sizes itself one word per line.
	desc.custom_minimum_size.x = TOAST_WIDTH - 110
	text.add_child(desc)
	return card

