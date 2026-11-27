extends SceneTree
## Run: godot --headless --path . --script res://tests/test_save_slots.gd

const TEST_DIR := "user://test_saves"

var _failures: int = 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	SaveSlots.directory = TEST_DIR
	_clear_dir()
	_test_round_trip_keeps_the_season()
	_test_every_summary_key_is_saved()
	_test_resume_day()
	_test_unusable_data()
	_test_hand_edited_values()
	_test_files()
	_test_temp_file_recovery()
	_test_failed_write_keeps_old_save()
	_test_latest()
	_test_overview()
	_test_days_ago()
	await _test_screen()
	_clear_dir()
	DirAccess.remove_absolute(TEST_DIR)
	print("save_slots: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _clear_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for name: String in dir.get_directories():
		DirAccess.remove_absolute("%s/%s" % [TEST_DIR, name])
	for name: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [TEST_DIR, name])


## A finished shift's summary, through the same Scoring.finish that GameState.finish_shift uses.
func _finished_summary(day: int, seed_value: int) -> Dictionary:
	var shift := ShiftState.new(day, seed_value)
	var acted := 0
	for student_seed in 3000:
		var student := StudentGen.make(student_seed, day)
		if student["no_id"]:
			continue
		student["number"] = 500 + acted
		shift.current = student
		shift.act("approve" if student["problems"].is_empty() else "reject", { "reason": "missing_requirement" })
		acted += 1
		if acted >= 6:
			break
	return Scoring.finish(shift.summary(), shift.history, seed_value, day)


## Through a real file, the way a saved season comes back.
func _through_file(day: int, seed_value: int, results: Dictionary) -> Dictionary:
	_check(SaveSlots.write(1, SaveSlots.pack(day, seed_value, results, 1700000000)), "the save is written")
	var entry := SaveSlots.read(1)
	_check(entry["state"] == SaveSlots.STATE_OK, "the save reads back")
	return entry["save"]


func _test_round_trip_keeps_the_season() -> void:
	var results := {}
	for day in range(1, 4):
		results[day] = _finished_summary(day, 42)
	results[2]["regulars"] = { "r112": { "right": 2, "wrong": 1, "bent": 0 } }
	var save := _through_file(3, 42, results)
	_check(save["seed"] == 42, "the seed comes back")
	_check(save["results"].keys() == [1, 2, 3], "results come back keyed by day number")
	var before := Evaluation.season(results)
	var after := Evaluation.season(save["results"])
	# JSON can round a float's last bit; nothing the player sees can move that little.
	_check(is_equal_approx(before["accuracy"], after["accuracy"]) and before["integrity"] == after["integrity"]
			and before["failed_days"] == after["failed_days"] and before["days"] == after["days"],
			"the season's numbers are the same (%s vs %s)" % [before, after])
	_check(Evaluation.ending(results)["id"] == Evaluation.ending(save["results"])["id"], "the same ending")
	_check(Evaluation.season_totals(results) == Evaluation.season_totals(save["results"]), "the same totals")
	_check(Evaluation.regulars(results) == Evaluation.regulars(save["results"]), "the regulars' visits come back")
	for day: int in results:
		_check(int(save["results"][day]["stars"]) == int(results[day]["stars"]), "day %d keeps its stars" % day)
		_check(save["results"][day]["reason"] == results[day]["reason"], "day %d keeps why it ended" % day)
	_check(not save["results"][1].has("spot_check"), "the spot check's rows stay out of the file")
	_check(save["saved_at"] == 1700000000, "the save time comes back")
	var season := {}
	for day in range(1, 11):
		season[day] = { "stars": 1 }
	var full := SaveSlots.unpack(JSON.parse_string(JSON.stringify(SaveSlots.pack(10, 1, season, 1), "", true)))
	_check(full["results"].keys() == range(1, 11), "days come back in day order, not text order (got %s)" % [full["results"].keys()])


## A new key in the shift summary has to be listed in SaveSlots, or a continued season loses it.
func _test_every_summary_key_is_saved() -> void:
	var known: Array = SaveSlots.SUMMARY_COUNTS + SaveSlots.SUMMARY_RATIOS + SaveSlots.SUMMARY_TEXTS \
			+ [SaveSlots.SUMMARY_REGULARS] + SaveSlots.SUMMARY_DROPPED
	for day in [1, 6, 10]:
		for key: String in _finished_summary(day, 7):
			_check(key in known, "summary key '%s' is either saved or dropped on purpose (SaveSlots lists)" % key)


func _test_resume_day() -> void:
	var played := { "version": 1, "seed": 5, "results": { "1": { "stars": 2 }, "2": { "stars": 1 }, "3": { "stars": 3 } } }
	var mid := played.duplicate(true)
	mid["day"] = 3
	var save := SaveSlots.unpack(mid)
	_check(save["day"] == 4 and not save["complete"], "a finished day 3 picks up on day 4")
	var unplayed := played.duplicate(true)
	unplayed["day"] = 3
	unplayed["results"].erase("3")
	save = SaveSlots.unpack(unplayed)
	_check(save["day"] == 3 and not save["complete"], "a day not yet played is played again")
	var last := int(GameData.json("days")["last_day"])
	var done := { "version": 1, "seed": 5, "day": last, "results": { str(last): { "stars": 1 } } }
	save = SaveSlots.unpack(done)
	_check(save["day"] == last and save["complete"], "a played last day is a complete season")


func _test_unusable_data() -> void:
	for data: Variant in [null, [], "save", 3, {}, { "day": 2, "seed": 4 }, { "version": 2, "day": 2, "seed": 4 },
			{ "version": "1", "day": 2, "seed": 4 }, { "version": 1, "day": "two", "seed": 4 }, { "version": 1, "day": 2 },
			{ "version": 1, "day": 2, "seed": null }, { "version": 1, "day": true, "seed": 4 }]:
		_check(SaveSlots.unpack(data).is_empty(), "unusable data reads as no save: %s" % [data])
	var clamped := SaveSlots.unpack({ "version": 1, "day": 99, "seed": -5, "saved_at": "soon" })
	_check(clamped["day"] == int(GameData.json("days")["last_day"]), "a day past the season clamps to the last day")
	_check(clamped["seed"] == 1, "a seed below 1 clamps to 1")
	_check(clamped["saved_at"] == 0, "a save time that isn't a number reads as unknown")
	_check(clamped["results"].is_empty(), "missing results read as none")


func _test_hand_edited_values() -> void:
	var data := { "version": 1, "day": 4, "seed": 9, "results": {
		"1": { "stars": 999, "integrity": -40, "accuracy": 7, "weighted_accuracy": -1, "reason": 123, "clock": "x".repeat(500),
			"served": "lots", "spot_check": "drop me", "favorite": { "deep": [1, 2, 3] },
			"regulars": { "r112": { "right": "2", "wrong": 1.6, "bent": -3 }, "r104": "bad", "": { "right": 1 } } },
		"2": "not a summary",
		"abc": { "stars": 3 },
		"9": { "stars": 3 },
		"-1": { "stars": 3 },
		"0003": { "stars": 2 },
	} }
	var save := SaveSlots.unpack(data)
	var results: Dictionary = save["results"]
	_check(results.keys() == [1], "only real, already-played days are kept (got %s)" % [results.keys()])
	var day_one: Dictionary = results[1]
	var max_stars := (GameData.json("balance")["star_thresholds"] as Array).size()
	_check(day_one["stars"] == max_stars, "stars clamp to the most a day gives")
	_check(day_one["integrity"] == 0, "integrity clamps at 0")
	_check(day_one["accuracy"] == 1.0 and day_one["weighted_accuracy"] == 0.0, "accuracies clamp to 0..1")
	_check(not day_one.has("reason") and not day_one.has("clock"), "text that isn't short text is dropped")
	_check(not day_one.has("served"), "a count that isn't a number is dropped")
	_check(not day_one.has("spot_check") and not day_one.has("favorite"), "unknown keys are dropped")
	_check(day_one["regulars"].keys() == ["r112"], "only well-formed regulars are kept")
	_check(day_one["regulars"]["r112"] == { "right": 0, "wrong": 2, "bent": 0 }, "regular counts are whole numbers from 0")
	# Whatever was in the file, every screen's numbers can be worked out.
	Evaluation.ending(results)
	Evaluation.season_totals(results)
	Evaluation.regulars(results)
	for number in range(1, 11):
		Season.state(number, save["day"], results)
	_check(SaveSlots.overview(save)["stars"] == max_stars, "the slot card's stars add up")


func _test_files() -> void:
	_clear_dir()
	_check(SaveSlots.read(1)["state"] == SaveSlots.STATE_EMPTY, "no file is an empty slot")
	_check(SaveSlots.write(2, SaveSlots.pack(5, 77, {}, 1)), "a save is written")
	_check(SaveSlots.read(2)["state"] == SaveSlots.STATE_OK, "and read back")
	_check(not FileAccess.file_exists(SaveSlots.path(2) + SaveSlots.TEMP_SUFFIX), "no temp file is left behind")
	_check(not SaveSlots.write(0, {}) and not SaveSlots.write(SaveSlots.SLOTS + 1, {}), "slots outside 1..SLOTS can't be written")
	_check(SaveSlots.read(0)["state"] == SaveSlots.STATE_EMPTY, "slots outside 1..SLOTS read as empty")
	for text: String in ["{ not json", "", "[1, 2, 3]", "{\"version\": 1}", "\u0001\u0002 garbage"]:
		_write_raw(SaveSlots.path(3), text)
		_check(SaveSlots.read(3)["state"] == SaveSlots.STATE_DAMAGED, "a broken file is a damaged slot: %s" % text.c_escape())
	_write_raw(SaveSlots.path(3), "{\"version\": 1, \"day\": 1e400, \"seed\": 4}")
	_check(SaveSlots.read(3)["state"] == SaveSlots.STATE_DAMAGED, "an infinite day is a damaged save")
	_write_raw(SaveSlots.path(3), "{\"version\": 1, \"day\": 2, \"seed\": 4, \"results\": {\"1\": {\"stars\": 1e400, \"accuracy\": -1e400}}}")
	var infinite: Dictionary = SaveSlots.read(3)["save"]["results"][1]
	_check(not infinite.has("stars") and not infinite.has("accuracy"), "infinite values are dropped")
	_write_raw(SaveSlots.path(3), "{\"version\": 1, \"day\": 2, \"seed\": 4, \"x\": " + "[".repeat(30000) + "]".repeat(30000) + "}")
	_check(SaveSlots.read(3)["state"] == SaveSlots.STATE_DAMAGED, "deeply nested data is a damaged save")
	var crowd := {}
	for i in SaveSlots.MAX_REGULARS + 10:
		crowd["r%d" % i] = { "right": 1, "wrong": 0, "bent": 0 }
	var crowded := SaveSlots.unpack({ "version": 1, "day": 2, "seed": 4, "results": { "1": { "regulars": crowd } } })
	_check(crowded["results"][1]["regulars"].size() == SaveSlots.MAX_REGULARS, "regulars are capped at MAX_REGULARS")
	var big := { "version": 1, "day": 2, "seed": 3, "padding": "x".repeat(SaveSlots.MAX_BYTES) }
	_write_raw(SaveSlots.path(3), JSON.stringify(big))
	_check(SaveSlots.read(3)["state"] == SaveSlots.STATE_DAMAGED, "a file over MAX_BYTES isn't read")
	SaveSlots.delete(3)
	_check(SaveSlots.read(3)["state"] == SaveSlots.STATE_EMPTY, "a deleted slot is empty")
	SaveSlots.delete(3)
	SaveSlots.delete(0)
	_check(SaveSlots.all().size() == SaveSlots.SLOTS, "all() lists every slot")


func _test_temp_file_recovery() -> void:
	_clear_dir()
	var good := JSON.stringify(SaveSlots.pack(6, 11, {}, 5))
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, good)
	var entry := SaveSlots.read(1)
	_check(entry["state"] == SaveSlots.STATE_OK and entry["save"]["day"] == 6, "a checked temp file with no save is recovered")
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, "{ cut off")
	_check(SaveSlots.read(1)["state"] == SaveSlots.STATE_EMPTY, "a cut-off first write leaves the slot empty")
	SaveSlots.write(1, SaveSlots.pack(3, 11, {}, 5))
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, "{ cut off")
	_check(SaveSlots.read(1)["save"]["day"] == 3, "a leftover temp file never hides the real save")
	_write_raw(SaveSlots.path(1), "{ damaged")
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, good)
	entry = SaveSlots.read(1)
	_check(entry["state"] == SaveSlots.STATE_OK and entry["save"]["day"] == 6, "a damaged save falls back to a good temp file")
	_check(SaveSlots.delete(1), "a slot deletes")
	_check(not FileAccess.file_exists(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX), "deleting a slot removes its temp file too")
	_check(SaveSlots.read(1)["state"] == SaveSlots.STATE_EMPTY, "and nothing comes back")
	# The temp file is the only copy: a write moves it into place before touching the temp file, so
	# even a write that then fails (too big here) keeps it.
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, good)
	_check(not SaveSlots.write(1, { "padding": "x".repeat(SaveSlots.MAX_BYTES) }), "a save too big to write is refused")
	_check(SaveSlots.read(1)["save"]["day"] == 6 and FileAccess.file_exists(SaveSlots.path(1)), "the only copy is moved into place first")
	_check(SaveSlots.write(1, SaveSlots.pack(8, 11, {}, 9)) and SaveSlots.read(1)["save"]["day"] == 8, "then the next write replaces it")
	# Both copies good: the one saved later wins, and is what the next write builds on.
	SaveSlots.write(1, SaveSlots.pack(3, 11, {}, 50))
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, JSON.stringify(SaveSlots.pack(5, 11, {}, 90)))
	_check(SaveSlots.read(1)["save"]["day"] == 5, "a newer temp file wins over an older save")
	_check(SaveSlots.write(1, SaveSlots.pack(6, 11, {}, 95)) and SaveSlots.read(1)["save"]["day"] == 6, "and the next write still lands")
	_write_raw(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX, JSON.stringify(SaveSlots.pack(2, 11, {}, 10)))
	_check(SaveSlots.read(1)["save"]["day"] == 6, "an older leftover temp file loses to the save")
	SaveSlots.write(1, SaveSlots.pack(7, 11, {}, 99))
	_check(SaveSlots.read(1)["save"]["day"] == 7, "and is simply replaced by the next write")
	SaveSlots.delete(1)


## A write that can't finish (here the temp path is a folder) keeps the save that was there.
func _test_failed_write_keeps_old_save() -> void:
	_clear_dir()
	SaveSlots.write(1, SaveSlots.pack(4, 21, {}, 5))
	DirAccess.make_dir_recursive_absolute(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX)
	_check(not SaveSlots.write(1, SaveSlots.pack(9, 21, {}, 6)), "a write that can't finish says so")
	_check(SaveSlots.read(1)["save"]["day"] == 4, "and the old save is untouched")
	DirAccess.remove_absolute(SaveSlots.path(1) + SaveSlots.TEMP_SUFFIX)


func _test_latest() -> void:
	_clear_dir()
	_check(SaveSlots.latest(SaveSlots.all()) == 0, "no saves: nothing to continue")
	SaveSlots.write(1, SaveSlots.pack(2, 1, {}, 100))
	SaveSlots.write(3, SaveSlots.pack(5, 1, {}, 300))
	SaveSlots.write(2, SaveSlots.pack(8, 1, {}, 200))
	_check(SaveSlots.latest(SaveSlots.all()) == 3, "Continue picks the slot saved last")
	_write_raw(SaveSlots.path(3), "{ broken")
	_check(SaveSlots.latest(SaveSlots.all()) == 2, "a damaged slot is never the one to continue")
	_clear_dir()


func _test_overview() -> void:
	var results := { 1: { "stars": 3, "weighted_accuracy": 0.9 }, 2: { "stars": 1, "weighted_accuracy": 0.7 } }
	var facts := SaveSlots.overview({ "day": 3, "results": results, "complete": false })
	_check(facts["day"] == 3 and facts["phase"] == Season.entry(3)["phase"], "the card shows the day and its phase")
	_check(facts["stars"] == 4 and facts["played"] == 2, "stars add up over the days played")
	_check(facts["max_stars"] == 2 * (GameData.json("balance")["star_thresholds"] as Array).size(), "out of the stars those days could give")
	_check(facts["accuracy"] == 80, "season accuracy as a whole percent (got %d)" % facts["accuracy"])
	_check(facts["ending"] == "", "no ending before the season is over")
	var last := int(GameData.json("days")["last_day"])
	facts = SaveSlots.overview({ "day": last, "results": results, "complete": true })
	_check(facts["ending"] == Evaluation.ending(results)["title"], "a complete season shows its ending")
	_check(SaveSlots.overview({ "day": 1, "results": {}, "complete": false })["accuracy"] == 0, "no shifts yet is 0%")


func _test_days_ago() -> void:
	var noon := 1700049600  # 2023-11-15 12:00 UTC
	_check(SaveSlots.days_ago(noon, noon + 3600) == 0, "an hour later is today")
	_check(SaveSlots.days_ago(noon, noon + 86400) == 1, "a day later is yesterday")
	_check(SaveSlots.days_ago(noon, noon + 3 * 86400 + 60) == 3, "three days later")
	# Saved at 23:00 in Manila (UTC+8) and looked at two minutes past midnight: yesterday there,
	# though both times fall on the same UTC day.
	var night := noon - 21 * 3600
	var after_midnight := noon - 20 * 3600 + 120
	_check(SaveSlots.days_ago(night, after_midnight, 480) == 1, "days follow the player's time zone")
	_check(SaveSlots.days_ago(night, after_midnight) == 0, "the same two times are one day in UTC")
	_check(SaveSlots.days_ago(noon + 500, noon) == 0, "a save from the future is today")


func _test_screen() -> void:
	_clear_dir()
	SaveSlots.write(1, SaveSlots.pack(7, 4, { 1: { "stars": 2, "weighted_accuracy": 0.8 } }, int(Time.get_unix_time_from_system())))
	_write_raw(SaveSlots.path(2), "{ broken")
	var screen := SaveSlotsScreen.open(root)
	var loads: Array = []
	var news: Array = []
	screen.load_requested.connect(func(slot: int) -> void: loads.append(slot))
	screen.new_requested.connect(func(slot: int) -> void: news.append(slot))
	await process_frame
	_check(screen._selected == 3, "New season starts on the first empty slot")
	_check(screen._hint.text == GameData.json("saves")["hint"], "with a slot free, the hint says when the game saves")
	_press(screen, KEY_1)
	_check(screen._selected == 1, "1 selects slot 1")
	_check(screen._play_buttons.has(1) and screen._play_buttons.has(3), "a save has Load and an empty slot New season")
	_check(not screen._play_buttons.has(2), "a damaged save can't be played")
	_press(screen, KEY_2)
	_check(screen._selected == 2, "2 selects slot 2")
	_press(screen, KEY_ENTER)
	_check(loads.is_empty() and news.is_empty(), "Enter on a damaged save does nothing")
	_press(screen, KEY_DELETE)
	_check(FileAccess.file_exists(SaveSlots.path(2)), "the first Delete only asks")
	var asking: StyleBoxFlat = screen._card_nodes[2].get_theme_stylebox("panel")
	_check(asking.bg_color == UiKit.RED_PALE, "the card turns red while the delete waits")
	_press(screen, KEY_ESCAPE)
	_check(not screen._confirming and screen.is_inside_tree(), "Esc cancels the delete without closing")
	_press(screen, KEY_DELETE)
	_press(screen, KEY_DELETE)
	_check(not FileAccess.file_exists(SaveSlots.path(2)), "the second Delete deletes")
	_check(screen._play_buttons.has(2), "the deleted slot offers New season")
	_check(screen._delete_button.disabled, "an empty slot can't be deleted")
	_press(screen, KEY_UP)
	_check(screen._selected == 1, "Up moves to the slot above")
	_press(screen, KEY_ENTER)
	_press(screen, KEY_ENTER)
	_check(loads == [1] and news.is_empty(), "Enter loads the selected save, once")
	screen.queue_free()
	screen = SaveSlotsScreen.open(root)
	screen.new_requested.connect(func(slot: int) -> void: news.append(slot))
	await process_frame
	_press(screen, KEY_3)
	_screen_click(screen._play_buttons[3])
	_check(news == [3], "New season on slot 3 asks for a season there")
	screen.queue_free()
	for slot in range(1, SaveSlots.SLOTS + 1):
		SaveSlots.write(slot, SaveSlots.pack(2, slot, {}, slot * 100))
	screen = SaveSlotsScreen.open(root)
	await process_frame
	_check(screen._selected == SaveSlots.SLOTS, "with every slot full, the save played last starts selected")
	_check(screen._hint.text == GameData.json("saves")["hint_full"], "and the hint says to delete one for a new season")
	_press(screen, KEY_1 + SaveSlots.SLOTS as Key)
	_check(screen._selected == SaveSlots.SLOTS, "a number past the last slot does nothing")
	screen.queue_free()
	var closed: Array = []
	screen = SaveSlotsScreen.open(root)
	screen.closed.connect(func() -> void: closed.append(true))
	await process_frame
	_press(screen, KEY_ESCAPE)
	_check(closed == [true] and screen.is_queued_for_deletion(), "Esc closes the screen")
	await process_frame


func _press(screen: SaveSlotsScreen, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	screen._unhandled_key_input(event)


func _screen_click(button: Button) -> void:
	button.pressed.emit()


func _write_raw(file_path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveSlots.directory)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
