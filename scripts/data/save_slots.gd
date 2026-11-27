class_name SaveSlots
extends RefCounted
## Three save slots for seasons in progress, one JSON file each in user://saves/. A save holds the
## day, the seed and each finished day's shift summary (which also carries the regulars' visits),
## so a continued season plays the same students and reaches the same ending.
##
## Save files are untrusted: anyone can edit them. They are read as JSON (never ConfigFile or
## str_to_var, which can build objects while parsing), refused when bigger than MAX_BYTES, and
## every value is checked: a number out of range is clamped, a field of the wrong type is dropped
## so the reader's own default applies, and a file without a usable day and seed reads as damaged.
## Nothing in a bad file can crash the game.
##
## Writes go to a temp file first, are read back, and only then replace the old save, so a crash
## or a full disk mid-write never destroys the save that was already there. A checked temp file
## that never took its place (the rename failed, or a crash came between removing the old save and
## renaming) is read when the save is missing, damaged or older, and moved into place before the
## next write so that write can't empty it.

const SLOTS := 3
const VERSION := 1
const DIRECTORY := "user://saves"
const TEMP_SUFFIX := ".tmp"
## Far more than a full season needs (about 10 KB), small enough that reading one is instant.
const MAX_BYTES := 65536
const MAX_SEED := 2147483647
const MAX_COUNT := 1000000
const MAX_TIME := 99999999999
const MAX_TEXT := 32
const MAX_REGULARS := 64

const STATE_EMPTY := "empty"
const STATE_OK := "ok"
const STATE_DAMAGED := "damaged"

## The shift summary keys a save keeps, by type. Everything else in a summary (like the spot
## check's rows, which only the day report shows) stays out of the file. test_save_slots.gd checks
## that a real summary has no key missing from these lists, so a new one can't be lost silently.
const SUMMARY_COUNTS := [
	"served", "decisions", "correct", "mistakes", "walked_out", "caught", "false_alarms", "bends",
	"total", "elsewhere", "stars", "integrity", "caught_bends", "hard_calls", "hard_right", "best_streak",
]
const SUMMARY_RATIOS := ["served_ratio", "accuracy", "weighted_accuracy", "weighted_base", "streak_bonus"]
const SUMMARY_TEXTS := ["reason", "clock"]
## Kept as { regular id: { right, wrong, bent } }, see Evaluation.regular_calls.
const SUMMARY_REGULARS := "regulars"
## Left out on purpose.
const SUMMARY_DROPPED := ["spot_check"]
const REGULAR_COUNTS := ["right", "wrong", "bent"]

## Where the slot files live. Tests point it somewhere else.
static var directory: String = DIRECTORY


static func valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOTS


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [directory, slot]


## What gets written: the season as plain JSON values, with the day numbers as text keys.
static func pack(day: int, seed_value: int, results: Dictionary, saved_at: int) -> Dictionary:
	var saved := {}
	for number: Variant in results:
		saved[str(number)] = clean_summary(results[number])
	return { "version": VERSION, "day": day, "seed": seed_value, "saved_at": saved_at, "results": saved }


## A parsed save file back as { day, seed, saved_at, results, complete }, with results keyed by day
## number like GameState.results. A season whose day was already played picks up at the next day;
## once the last day is played it is complete (it reopens on the evaluation). Returns {} when
## the data can't be a save: not a dictionary, a version this build doesn't know, or no
## usable day or seed.
static func unpack(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var version: Variant = data.get("version")
	if not _is_number(version) or float(version) < 1.0 or float(version) > VERSION:
		return {}
	var days: Dictionary = GameData.json("days")
	var first := int(days["first_day"])
	var last := int(days["last_day"])
	var day_value: Variant = _whole(data.get("day"), first, last)
	var seed_value: Variant = _whole(data.get("seed"), 1, MAX_SEED)
	if day_value == null or seed_value == null:
		return {}
	var day: int = day_value
	var results := {}
	var saved: Variant = data.get("results", {})
	if saved is Dictionary:
		var found := {}
		for key: Variant in saved:
			var number := _day_number(key)
			if number >= first and number <= day and saved[key] is Dictionary and not found.has(number):
				found[number] = saved[key]
		# In day order, as they were played: the file sorts its keys as text ("10" before "2"), and
		# the season's averages should add up in the same order as before the save.
		var numbers := found.keys()
		numbers.sort()
		for number: int in numbers:
			results[number] = clean_summary(found[number])
	var complete := false
	if results.has(day):
		if day < last:
			day += 1
		else:
			complete = true
	var saved_at: Variant = _whole(data.get("saved_at"), 0, MAX_TIME)
	return {
		"day": day,
		"seed": seed_value,
		"saved_at": saved_at if saved_at != null else 0,
		"results": results,
		"complete": complete,
	}


## One shift summary with only the keys a save keeps, each the right type and in range. Used both
## when writing and when reading, so a hand-edited value can't reach the game unchecked.
static func clean_summary(summary: Variant) -> Dictionary:
	var clean := {}
	if not (summary is Dictionary):
		return clean
	var caps := {
		"stars": (GameData.json("balance")["star_thresholds"] as Array).size(),
		"integrity": Evaluation.integrity_max(),
	}
	for key: String in SUMMARY_COUNTS:
		var value: Variant = _whole(summary.get(key), 0, int(caps.get(key, MAX_COUNT)))
		if value != null:
			clean[key] = value
	for key: String in SUMMARY_RATIOS:
		var value: Variant = summary.get(key)
		if _is_number(value):
			clean[key] = clampf(float(value), 0.0, 1.0)
	for key: String in SUMMARY_TEXTS:
		var value: Variant = summary.get(key)
		if value is String and (value as String).length() <= MAX_TEXT:
			clean[key] = value
	var regulars: Variant = summary.get(SUMMARY_REGULARS)
	if regulars is Dictionary:
		clean[SUMMARY_REGULARS] = _clean_regulars(regulars)
	return clean


## A slot as { slot, state, save }: state is STATE_EMPTY, STATE_OK (save is unpack()'s result) or
## STATE_DAMAGED (the file is there but can't be used; the player can only delete it).
static func read(slot: int) -> Dictionary:
	var entry := { "slot": slot, "state": STATE_EMPTY, "save": {} }
	if not valid_slot(slot):
		return entry
	var file_path := path(slot)
	# A good temp file holds a checked save that never took its place. A broken one is a write that
	# never finished: the slot is damaged if a save file is there, else still empty.
	var save := _newest(_load(file_path), _load(file_path + TEMP_SUFFIX))
	if not save.is_empty():
		entry["state"] = STATE_OK
		entry["save"] = save
	elif FileAccess.file_exists(file_path):
		entry["state"] = STATE_DAMAGED
	return entry


## Every slot, 1 to SLOTS, as read() gives them.
static func all() -> Array:
	var entries: Array = []
	for slot in range(1, SLOTS + 1):
		entries.append(read(slot))
	return entries


## The slot saved most recently among entries (from all()), or 0 if none holds a usable save.
static func latest(entries: Array) -> int:
	var best := 0
	var best_time := -1
	for entry: Dictionary in entries:
		if entry["state"] == STATE_OK and int(entry["save"]["saved_at"]) > best_time:
			best = int(entry["slot"])
			best_time = int(entry["save"]["saved_at"])
	return best


## Writes data (from pack()) to a slot through a temp file. Returns false, and leaves the old save
## as it was, if anything goes wrong.
static func write(slot: int, data: Dictionary) -> bool:
	if not valid_slot(slot):
		return false
	if not _recover(slot):
		push_warning("SaveSlots: couldn't move the newer temp file into place for slot %d" % slot)
		return false
	# Full precision, so accuracies read back exactly and a continued season ends the same way.
	var text := JSON.stringify(data, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		push_warning("SaveSlots: save for slot %d is too big to write" % slot)
		return false
	DirAccess.make_dir_recursive_absolute(directory)
	var final_path := path(slot)
	var temp_path := final_path + TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSlots: couldn't write %s" % temp_path)
		return false
	file.store_string(text)
	var failed := file.get_error() != OK
	file.close()
	# Read back before replacing the old save, so a full disk can't swap a good save for a cut-off one.
	if failed or FileAccess.get_file_as_string(temp_path) != text:
		DirAccess.remove_absolute(temp_path)
		push_warning("SaveSlots: couldn't write %s" % temp_path)
		return false
	if DirAccess.rename_absolute(temp_path, final_path) != OK:
		push_warning("SaveSlots: couldn't replace %s" % final_path)
		return false
	return true


## Removes a slot's save. The temp file goes first, so an interrupted delete can't leave a good temp
## file behind that read() would bring back. Returns false if a file couldn't be removed.
static func delete(slot: int) -> bool:
	if not valid_slot(slot):
		return false
	for file_path: String in [path(slot) + TEMP_SUFFIX, path(slot)]:
		if FileAccess.file_exists(file_path) and DirAccess.remove_absolute(file_path) != OK:
			return false
	return true


## What a slot card shows about a save: { day, phase, played, stars, max_stars, accuracy (whole
## percent), complete, ending (the ending's title once complete) }.
static func overview(save: Dictionary) -> Dictionary:
	var results: Dictionary = save.get("results", {})
	var stars := 0
	for number: int in results:
		stars += int(results[number].get("stars", 0))
	var per_day := (GameData.json("balance")["star_thresholds"] as Array).size()
	var complete := bool(save.get("complete", false))
	return {
		"day": int(save["day"]),
		"phase": String(Season.entry(int(save["day"])).get("phase", "")),
		"played": results.size(),
		"stars": stars,
		"max_stars": per_day * results.size(),
		"accuracy": Evaluation.percent(Evaluation.season(results)["accuracy"]),
		"complete": complete,
		"ending": String(Evaluation.ending(results)["title"]) if complete else "",
	}


## Whole calendar days between saved_at and now (unix seconds), in the player's time zone
## (bias_minutes from UTC): 0 is today, 1 yesterday.
static func days_ago(saved_at: int, now: int, bias_minutes: int = 0) -> int:
	var offset := bias_minutes * 60
	return maxi(0, floori((now + offset) / 86400.0) - floori((saved_at + offset) / 86400.0))


## When the temp file holds the newest good copy of a save (the save is missing, damaged or
## older), moves it into place. Returns false if it couldn't, so a write mustn't touch the temp file.
static func _recover(slot: int) -> bool:
	var temp_path := path(slot) + TEMP_SUFFIX
	if not FileAccess.file_exists(temp_path):
		return true
	var temp := _load(temp_path)
	if temp.is_empty() or _newest(_load(path(slot)), temp) != temp:
		return true
	return DirAccess.rename_absolute(temp_path, path(slot)) == OK


## Of two unpacked saves (either may be {}), the one saved later; the first on a tie.
static func _newest(first: Dictionary, second: Dictionary) -> Dictionary:
	if second.is_empty():
		return first
	if first.is_empty() or int(second["saved_at"]) > int(first["saved_at"]):
		return second
	return first


static func _load(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var text := file.get_as_text()
	file.close()
	# JSON.parse (not parse_string) so a broken file is refused quietly instead of logging errors.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return unpack(json.data)


static func _clean_regulars(regulars: Dictionary) -> Dictionary:
	var clean := {}
	for id: Variant in regulars:
		if clean.size() >= MAX_REGULARS:
			break
		var calls: Variant = regulars[id]
		if not (id is String) or (id as String).is_empty() or (id as String).length() > MAX_TEXT or not (calls is Dictionary):
			continue
		var counts := {}
		for key: String in REGULAR_COUNTS:
			var value: Variant = _whole(calls.get(key), 0, MAX_COUNT)
			counts[key] = value if value != null else 0
		clean[id] = counts
	return clean


## A day number from a results key ("3" in the file, 3 in memory), or 0 if it isn't one.
static func _day_number(key: Variant) -> int:
	if key is int:
		return key
	if key is String and (key as String).length() <= 3 and (key as String).is_valid_int():
		return (key as String).to_int()
	return 0


static func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


## value as a whole number clamped to [low, high], or null if it isn't a number at all.
static func _whole(value: Variant, low: int, high: int) -> Variant:
	if not _is_number(value):
		return null
	return clampi(roundi(clampf(float(value), low, high)), low, high)
