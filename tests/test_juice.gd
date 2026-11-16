extends SceneTree
## Run: godot --headless --path . --script res://tests/test_juice.gd
## Settings must survive a bad file, and every Juice effect must honour reduced motion and the
## screen shake switch. The real settings file is never touched: these use a test path.

const TEST_PATH := "user://test_settings.json"

var _failures: int = 0


## The root window only joins the tree on the first frame, and effects skip nodes outside it.
func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Never read the developer's own settings file into these checks.
	Settings._loaded = true
	_test_settings_defaults_and_round_trip()
	_test_settings_reject_bad_values()
	_test_juice_respects_settings()
	_test_effects_never_take_input()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	# Back to the defaults, so nothing here leaks into whatever runs next.
	Settings.reduced_motion = false
	Settings.screen_shake = true
	print("juice: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _write(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_settings_defaults_and_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_check(not Settings.load_from(TEST_PATH), "a missing file reports false")
	_check(not Settings.reduced_motion and Settings.screen_shake, "a missing file gives the defaults")
	Settings.reduced_motion = true
	Settings.screen_shake = false
	_check(Settings.save_to(TEST_PATH), "settings save")
	Settings.reduced_motion = false
	Settings.screen_shake = true
	_check(Settings.load_from(TEST_PATH), "saved settings load")
	_check(Settings.reduced_motion and not Settings.screen_shake, "saved settings come back as saved")


func _test_settings_reject_bad_values() -> void:
	_write('{ "reduced_motion": "yes", "screen_shake": 3 }')
	Settings.load_from(TEST_PATH)
	_check(not Settings.reduced_motion and Settings.screen_shake, "wrong types fall back to the defaults")
	_write("this is not json {{{")
	Settings.reduced_motion = true
	_check(not Settings.load_from(TEST_PATH), "a broken file reports false")
	_check(not Settings.reduced_motion and Settings.screen_shake, "a broken file falls back to the defaults")
	_write("[true, false]")
	_check(not Settings.load_from(TEST_PATH), "a file that isn't an object is refused")
	_write('{ "reduced_motion": true }')
	Settings.load_from(TEST_PATH)
	_check(Settings.reduced_motion and Settings.screen_shake, "a missing key keeps its default")
	# A ConfigFile-style payload that would build an object running a script. In JSON it's text or
	# junk, so nothing runs: the marker is never set and the settings stay at their defaults.
	var payload := 'Object(RefCounted,"script":Object(GDScript,"script/source":"extends RefCounted\nfunc _init(): Engine.set_meta(\\"settings_probe\\", true)"))'
	_write("[comfort]\nreduced_motion=true\nother=%s\n" % payload)
	Settings.load_from(TEST_PATH)
	_write('{ "reduced_motion": %s, "screen_shake": true }' % JSON.stringify(payload))
	Settings.load_from(TEST_PATH)
	_check(not Engine.has_meta("settings_probe"), "a hostile file never runs code")
	_check(not Settings.reduced_motion and Settings.screen_shake, "a hostile file falls back to the defaults")


func _box() -> Control:
	var box := Control.new()
	box.size = Vector2(100, 40)
	box.position = Vector2(10, 20)
	root.add_child(box)
	return box


func _test_juice_respects_settings() -> void:
	Settings.reduced_motion = false
	Settings.screen_shake = true
	var box := _box()
	_check(Juice.shake(box) != null, "shake runs when allowed")
	_check(Juice.punch(box) != null, "punch runs when allowed")
	_check(Juice.flash(box, Color.RED) != null, "flash runs")
	_check(Juice.screen_flash(box, Color.RED) != null, "screen flash runs")
	_check(Juice.pop_text(box, "Right call", Color.GREEN, Vector2(50, 20)) != null, "pop text runs")
	Settings.screen_shake = false
	_check(Juice.shake(box) == null, "screen shake off stops shake")
	_check(Juice.punch(box) != null, "screen shake off keeps punch")
	Settings.screen_shake = true
	Settings.reduced_motion = true
	_check(Juice.shake(box) == null, "reduced motion stops shake")
	_check(Juice.punch(box) == null, "reduced motion stops punch")
	_check(Juice.flash(box, Color.RED) != null, "reduced motion keeps a short color change")
	_check(Juice.pop_text(box, "Wrong call", Color.RED, Vector2(50, 20)) != null, "reduced motion still shows the word")
	var loose := Control.new()
	_check(Juice.shake(null) == null and Juice.punch(loose) == null, "nodes outside the tree are skipped")
	loose.free()
	Settings.reduced_motion = false
	var home := box.position
	Juice.shake(box, 6.0)
	Juice.shake(box, 6.0)
	_check(box.get_meta("juice_home") == home, "a second shake keeps the first one's home, so the node can't drift")
	box.queue_free()


func _test_effects_never_take_input() -> void:
	Settings.reduced_motion = false
	var box := _box()
	Juice.screen_flash(box, Color.RED)
	Juice.pop_text(box, "Wrong call", Color.RED, Vector2(50, 20))
	for child: Node in box.get_children():
		_check(child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s lets clicks through" % child.get_class())
	_check(box.get_child_count() == 2, "one wash and one word")
	Juice.pop_text(box, "Right call", Color.GREEN, Vector2(50, 20))
	var words := box.get_children().filter(func(child: Node) -> bool: return child is Label and not child.is_queued_for_deletion())
	_check(words.size() == 1, "a new word replaces the one still showing")
	Juice.screen_flash(box, Color.GREEN)
	var washes := box.get_children().filter(func(child: Node) -> bool: return child is ColorRect and not child.is_queued_for_deletion())
	_check(washes.size() == 1, "a new wash replaces the old one instead of stacking")
	# A wash that already faded and freed itself must not break the next one.
	(washes[0] as Node).free()
	_check(Juice.screen_flash(box, Color.RED) != null, "a flash after the last wash was freed still runs")
	box.queue_free()
	var stamp := _box()
	Juice.shake(stamp, 6.0)
	Juice.punch(stamp)
	Juice.settle(stamp)
	_check(stamp.position == Vector2(10, 20) and stamp.scale == Vector2.ONE and not stamp.has_meta("juice_home"), "settle puts a node back where and how big it was")
	stamp.queue_free()
