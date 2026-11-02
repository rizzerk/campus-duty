class_name GameData
extends RefCounted
## Loads and caches the JSON files in data/ so content stays editable without touching code.

static var _cache: Dictionary = {}


static func json(file_name: String) -> Variant:
	if not _cache.has(file_name):
		var path := "res://data/%s.json" % file_name
		_cache[file_name] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _cache[file_name]


static func day(number: int) -> Dictionary:
	return json("days")["days"][str(number)]


static func balance(key: String) -> float:
	return float(json("balance")[key])


static func problem(id: String) -> Dictionary:
	return json("problems")[id]
