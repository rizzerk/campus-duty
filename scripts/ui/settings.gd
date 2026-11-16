class_name Settings
extends RefCounted
## Player comfort settings that every effect reads (see Juice): reduced motion and screen shake.
## Saved to user://settings.json. The file is treated as untrusted: it is JSON, never ConfigFile
## or str_to_var (those can build objects with scripts while parsing), and a missing file, a wrong
## type or a broken file falls back to the defaults and never crashes the game. Toggled from the
## pause menu until the settings screen exists.

const PATH := "user://settings.json"

## No shake, no particles, no hit stop; pops appear without moving.
static var reduced_motion: bool = false
## Screen shake on its own, for players who like motion but not shaking.
static var screen_shake: bool = true

static var _loaded: bool = false


## Reads the settings once per run. Safe to call often.
static func ensure_loaded(path: String = PATH) -> void:
	if _loaded:
		return
	_loaded = true
	load_from(path)


## Replaces the current settings with the file's, keeping the defaults for anything missing or
## of the wrong type. Returns false if the file was missing or unreadable.
static func load_from(path: String) -> bool:
	reduced_motion = false
	screen_shake = true
	if not FileAccess.file_exists(path):
		return false
	# JSON.parse (not parse_string) so a broken file is refused quietly instead of logging errors.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = json.data
	var motion: Variant = data.get("reduced_motion", false)
	var shake: Variant = data.get("screen_shake", true)
	reduced_motion = motion if motion is bool else false
	screen_shake = shake if shake is bool else true
	return true


## Writes the settings. A failed save only loses them for the next run, so it warns and goes on.
static func save_to(path: String = PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: could not save to %s" % path)
		return false
	file.store_string(JSON.stringify({ "reduced_motion": reduced_motion, "screen_shake": screen_shake }))
	file.close()
	return true


## Shake is allowed only when the player wants it and hasn't asked for reduced motion.
static func shake_allowed() -> bool:
	ensure_loaded()
	return screen_shake and not reduced_motion


static func motion_allowed() -> bool:
	ensure_loaded()
	return not reduced_motion
