class_name LineChatter
extends RefCounted
## The living line, without any scenes: what each waiting student is doing (checking a phone,
## fanning, sighing) and when someone in line says something out loud (a bark). Barks are rate
## limited so they never overlap or spam: one at a time, a gap after each, and the same situation
## not again for a while. The window feeds it the clock and what happened, and shows the result.
## Tuning lives in data/balance.json "line_life", the lines in data/dialogue.json "line_barks".
## Pure flavor: nothing here changes the right answer or the score.

const SITUATIONS := ["slow_service", "fast_streak", "priority_cut", "angry_return", "rush"]
## Used when a key is missing from balance.json, so a tuning slip never crashes a shift.
const DEFAULTS := {
	"bark_seconds": 3.0, "bark_gap_seconds": 8.0, "bark_repeat_seconds": 30.0,
	"phone_after_minutes": 15.0, "fan_after_minutes": 35.0, "sigh_after_minutes": 60.0, "sigh_patience": 40.0,
	"slow_service_minutes": 14.0, "fast_minutes": 8.0, "fast_streak": 3.0, "cheer_seconds": 2.5,
}

var _rng := RandomNumberGenerator.new()
## Real seconds when the last bark started, or a very old time if none yet.
var _last_bark: float = -1000.0
var _last_by_situation: Dictionary = {}
var _last_line: Dictionary = {}
## Game minute the student at the window was called, or -1 with nobody there.
var _called_at: float = -1.0
var _slow_said: bool = false
var _fast_run: int = 0


func _init(base_seed: int, day: int) -> void:
	_rng.seed = base_seed * 31 + day


static func setting(key: String) -> float:
	return float(GameData.json("balance").get("line_life", {}).get(key, DEFAULTS.get(key, 0.0)))


## What a waiting student is doing, from how long they've waited and the line's patience:
## "" (nothing yet), "phone", "fan" or "sigh". An impatient student gets there twice as fast,
## one with a parent half as fast (their trait's drain weight). Angry returners already show it
## on their face, so they get nothing extra.
static func idle_state(student: Dictionary, minute: float, patience: float) -> String:
	if student.get("mood", "") == "angry":
		return ""
	var waited := (minute - float(student.get("joined_at", minute))) * ShiftState.trait_weight(student)
	if patience < setting("sigh_patience") or waited >= setting("sigh_after_minutes"):
		return "sigh"
	if waited >= setting("fan_after_minutes"):
		return "fan"
	if waited >= setting("phone_after_minutes"):
		return "phone"
	return ""


## Asks for a bark. now is real seconds since the shift began; speakers are the indices of the
## faces that could say it. Returns {} when it's too soon, nobody can speak or the situation has no
## lines, otherwise { situation, index, line: { ceb, en } }.
func bark(situation: String, now: float, speakers: Array) -> Dictionary:
	if speakers.is_empty():
		return {}
	# Never two at once: the gap is at least as long as a bubble stays up.
	if now - _last_bark < maxf(setting("bark_gap_seconds"), setting("bark_seconds")):
		return {}
	if now - float(_last_by_situation.get(situation, -1000.0)) < setting("bark_repeat_seconds"):
		return {}
	var pool: Array = GameData.json("dialogue").get("line_barks", {}).get(situation, [])
	if pool.is_empty():
		return {}
	var line: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	# No line twice in a row.
	if pool.size() > 1 and line == _last_line:
		line = pool[(pool.find(line) + 1 + _rng.randi_range(0, pool.size() - 2)) % pool.size()]
	_last_bark = now
	_last_by_situation[situation] = now
	_last_line = line
	return { "situation": situation, "index": int(speakers[_rng.randi_range(0, speakers.size() - 1)]), "line": line }


## A student stepped up to the window at this game minute.
func note_called(minute: float) -> void:
	_called_at = minute
	_slow_said = false


## True once per student, when the one at the window has taken too long: the line grumbles.
func slow_due(minute: float) -> bool:
	if _called_at < 0.0 or _slow_said or minute - _called_at < setting("slow_service_minutes"):
		return false
	_slow_said = true
	return true


## A decision was handed back. Right calls made quickly in a row build a run; when it reaches
## fast_streak the line cheers (returns true) and the run starts over. A wrong or slow call breaks
## it (the window passes favors in as not right).
func note_decision(right: bool, minute: float) -> bool:
	var quick := _called_at >= 0.0 and minute - _called_at <= setting("fast_minutes")
	_called_at = -1.0
	if not (right and quick):
		_fast_run = 0
		return false
	_fast_run += 1
	if _fast_run >= int(setting("fast_streak")):
		_fast_run = 0
		return true
	return false
