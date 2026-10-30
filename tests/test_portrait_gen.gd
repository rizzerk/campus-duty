extends SceneTree
## Run: godot --headless --path . --script res://tests/test_portrait_gen.gd

var _failures: int = 0


func _init() -> void:
	_test_same_seed_same_parts()
	_test_every_roll_uses_real_files()
	_test_every_eye_style_has_every_expression()
	_test_hair_matches_gender()
	_test_sunglasses_hide_eyes()
	_test_parent_shares_skin()
	_test_parent_parts_exist()
	_test_sweat_never_random()
	_test_lanyard_color_shows_year()
	_test_retired_hair_never_rolled()
	_test_team_parts_exist()
	print("portrait_gen: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _test_same_seed_same_parts() -> void:
	_check(PortraitGen.roll(42) == PortraitGen.roll(42), "same seed gives same parts")
	_check(PortraitGen.roll(42) != PortraitGen.roll(43), "different seeds differ")


func _test_every_roll_uses_real_files() -> void:
	for seed_value in 500:
		var parts := PortraitGen.roll(seed_value)
		_check(ResourceLoader.exists(PortraitGen.part_path("hair", parts["hair"])), "hair %s" % parts["hair"])
		_check(ResourceLoader.exists(PortraitGen.part_path("clothes", parts["clothes"])), "clothes %s" % parts["clothes"])
		for accessory: String in parts["accessories"]:
			_check(ResourceLoader.exists(PortraitGen.part_path("accessory", accessory)), "accessory %s" % accessory)


func _test_every_eye_style_has_every_expression() -> void:
	var data := PortraitGen.data()
	for shape: String in data["eye_shapes"]:
		for style: String in [shape, shape + "_pretty"]:
			for expression: String in data["expressions"]:
				var eye := PortraitGen.eye_part(style, expression)
				_check(ResourceLoader.exists(PortraitGen.part_path("eye", eye)), "eye %s" % eye)
	for expression: String in data["expressions"]:
		var face: Dictionary = data["expressions"][expression]
		_check(ResourceLoader.exists(PortraitGen.part_path("brow", face["brow"])), "brow %s" % face["brow"])
		_check(ResourceLoader.exists(PortraitGen.part_path("mouth", face["mouth"])), "mouth %s" % face["mouth"])


func _test_hair_matches_gender() -> void:
	var data := PortraitGen.data()
	for seed_value in 500:
		var parts := PortraitGen.roll(seed_value)
		var excluded: Array = data["female_only_hair" if parts["gender"] == "male" else "male_only_hair"]
		_check(not excluded.has(parts["hair"]), "%s on %s" % [parts["hair"], parts["gender"]])


func _test_sunglasses_hide_eyes() -> void:
	_check(PortraitGen.hides_eyes(["accessory_sunglasses"]), "sunglasses hide eyes")
	_check(not PortraitGen.hides_eyes(["accessory_lanyard"]), "lanyard keeps eyes")
	_check(not PortraitGen.hides_eyes([]), "no accessories keeps eyes")


func _test_parent_shares_skin() -> void:
	var parts := PortraitGen.roll(7, true)
	_check(parts.has("parent"), "parent present")
	_check(parts["parent"]["skin"] == parts["skin"], "parent skin matches")
	_check(parts["parent"]["brow_color"] == parts["brow_color"], "parent brows match")
	_check(not PortraitGen.roll(7).has("parent"), "no parent by default")


func _test_parent_parts_exist() -> void:
	for parent: Dictionary in PortraitGen.data()["parents"]:
		_check(ResourceLoader.exists(PortraitGen.part_path("hair", parent["hair"])), "parent hair %s" % parent["hair"])
		for slot: String in ["wrinkles", "facial_hair"]:
			if parent.has(slot):
				_check(ResourceLoader.exists(PortraitGen.part_path(slot, parent[slot])), "parent %s" % parent[slot])
		for expression: String in PortraitGen.data()["expressions"]:
			var eye := PortraitGen.eye_part(parent["eye_style"], expression)
			_check(ResourceLoader.exists(PortraitGen.part_path("eye", eye)), "parent eye %s" % eye)


func _test_sweat_never_random() -> void:
	for seed_value in 500:
		_check(not PortraitGen.roll(seed_value)["accessories"].has("accessory_sweat_drop"), "sweat stays for traits")


func _test_lanyard_color_shows_year() -> void:
	var colors: Dictionary = PortraitGen.data()["lanyard_colors"]
	for year in range(1, 5):
		var parts := PortraitGen.roll(9, false, year)
		_check(parts["year"] == year, "year %d kept" % year)
		_check(parts["accessory_colors"]["accessory_lanyard"] == colors[str(year)], "lanyard color year %d" % year)
	_check(colors.values().size() == 4, "four year colors")
	var unique := {}
	for color: String in colors.values():
		unique[color] = true
	_check(unique.size() == 4, "year colors all differ")


func _test_retired_hair_never_rolled() -> void:
	for seed_value in 500:
		_check(not PortraitGen.data()["retired_hair"].has(PortraitGen.roll(seed_value)["hair"]), "retired hair rolled")


func _test_team_parts_exist() -> void:
	for member: Dictionary in PortraitGen.data()["team"]:
		_check(ResourceLoader.exists(PortraitGen.part_path("hair", member["hair"])), "team hair %s" % member["hair"])
		var eye := PortraitGen.eye_part(member["eye_style"], member["expression"])
		_check(ResourceLoader.exists(PortraitGen.part_path("eye", eye)), "team eye %s" % eye)
