class_name PlaytestLog
extends RefCounted
## One JSON line per finished shift, so playtests can be read afterwards. Numbers only: no names,
## so testers can hand the file over. The file stays on the player's machine.
## entry() is pure (pass the time in tests); append() is the only part that touches the disk.

const PATH := "user://playtest_log.jsonl"
## Past this size the log stops growing, so a forgotten file can't fill a disk.
const MAX_BYTES := 1_000_000
## Where wrong calls on students who had nothing wrong are counted. The balance sim uses it too.
const CLEAN := "clean"


## The line for one shift. summary is ShiftState.summary() after scoring (stars, caught_bends).
## Favors are counted under "favors", not as mistakes, matching the summary's own "mistakes".
## extra adds fields such as { "retried": true }. time defaults to now.
static func entry(summary: Dictionary, history: Array, day: int, seed_value: int, extra: Dictionary = {}, time: String = "") -> Dictionary:
	var mistakes_by_problem := {}
	for record: Dictionary in history:
		if record.get("correct", true) or record.get("bent", false):
			continue
		var key := String(record.get("problem", ""))
		if key == "":
			key = CLEAN
		mistakes_by_problem[key] = int(mistakes_by_problem.get(key, 0)) + 1
	var line := {
		"time": time if time != "" else Time.get_datetime_string_from_system(),
		"day": day,
		"seed": seed_value,
		"stars": int(summary.get("stars", 0)),
		"reason": String(summary.get("reason", "")),
		"accuracy": snappedf(float(summary.get("accuracy", 0.0)), 0.01),
		"served": int(summary.get("served", 0)),
		"total": int(summary.get("total", 0)),
		"mistakes": int(summary.get("mistakes", 0)),
		"mistakes_by_problem": mistakes_by_problem,
		"walked_out": int(summary.get("walked_out", 0)),
		"favors": int(summary.get("bends", 0)),
		"caught_bends": int(summary.get("caught_bends", 0)),
		"caught": int(summary.get("caught", 0)),
		"false_alarms": int(summary.get("false_alarms", 0)),
		"clock": String(summary.get("clock", "")),
	}
	line.merge(extra, true)
	return line


## Appends a line. Returns false if the file can't be opened or is already full. A crash mid-write
## can leave a cut-off last line, so anything reading the log should skip lines that don't parse.
static func append(line: Dictionary, path: String = PATH) -> bool:
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null or file.get_length() > MAX_BYTES:
		return false
	file.seek_end()
	file.store_line(JSON.stringify(line))
	file.close()
	return true
