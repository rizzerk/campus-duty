class_name PortraitGen
extends RefCounted
## Builds portrait part sets from data/portrait_parts.json. No scenes needed, so it can be unit tested.

const DATA_PATH := "res://data/portrait_parts.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return _data


## Returns the same part set every time for the same seed.
## Pass with_parent = true for the "With parent" trait.
## The lanyard color shows the year level (1 to 4). Year 0 picks one at random.
static func roll(seed_value: int, with_parent: bool = false, year: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := data()

	var gender: String = "male" if rng.randf() < 0.5 else "female"
	var tone: Dictionary = _pick(rng, d["skin_tones"])
	var year_level: int = year if year > 0 else rng.randi_range(1, 4)
	var parts := {
		"gender": gender,
		"skin": tone["skin"],
		"brow_color": tone["brow"],
		"hair": _pick(rng, _hair_for(gender)),
		"hair_color": d["hair_colors"][rng.rand_weighted(PackedFloat32Array(d["hair_color_weights"]))],
		"clothes": d["uniforms"][gender],
		"clothes_color": "#ffffff",
		"eye_style": _roll_eye_style(rng, gender),
		"year": year_level,
		"accessories": [],
		"accessory_colors": { "accessory_lanyard": d["lanyard_colors"][str(year_level)] },
		"expression": "neutral",
	}
	if rng.randf() < d["civilian_chance"]:
		parts["clothes"] = d["civilian_clothes"]
		parts["clothes_color"] = _pick(rng, d["shirt_colors"])
	for accessory: Dictionary in d["accessories"]:
		if rng.randf() < accessory["chance"]:
			parts["accessories"].append(accessory["name"])
	if with_parent:
		var parent: Dictionary = _pick(rng, d["parents"]).duplicate(true)
		parent["skin"] = tone["skin"]
		parent["brow_color"] = tone["brow"]
		parts["parent"] = parent
	return parts


## All part names in a slot folder, found by scanning so a new PNG needs no code change.
static func list_parts(slot: String) -> PackedStringArray:
	var names := PackedStringArray()
	for file: String in ResourceLoader.list_directory(_folder(slot)):
		if file.get_extension() == "png":
			names.append(file.get_basename())
	names.sort()
	return names


static func part_path(slot: String, part_name: String) -> String:
	return "%s/%s.png" % [_folder(slot), part_name]


static func eye_part(eye_style: String, expression: String) -> String:
	return "eye_%s_%s" % [eye_style, data()["expressions"][expression]["eye"]]


## True when one of these accessories covers the eyes, like sunglasses.
static func hides_eyes(accessories: Array) -> bool:
	for accessory: Dictionary in data()["accessories"]:
		if accessory.get("hides_eyes", false) and accessories.has(accessory["name"]):
			return true
	return false


static func _folder(slot: String) -> String:
	return "%s/%s" % [data()["root"], data()["folders"][slot]]


static func _hair_for(gender: String) -> Array:
	var excluded: Array = data()["female_only_hair" if gender == "male" else "male_only_hair"]
	var retired: Array = data()["retired_hair"]
	var options: Array = []
	for hair: String in list_parts("hair"):
		if not excluded.has(hair) and not retired.has(hair):
			options.append(hair)
	return options


static func _roll_eye_style(rng: RandomNumberGenerator, gender: String) -> String:
	var style: String = _pick(rng, data()["eye_shapes"])
	if rng.randf() < data()["pretty_eye_chance"][gender]:
		style += "_pretty"
	return style


static func _pick(rng: RandomNumberGenerator, options: Array) -> Variant:
	return options[rng.randi_range(0, options.size() - 1)]
