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
	_test_slice_two_effects()
	_test_music_layers()
	await _test_drop_out()
	await _test_hit_stop_always_recovers()
	await _test_star_reveal()
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


func _test_slice_two_effects() -> void:
	Settings.reduced_motion = false
	Settings.screen_shake = true
	var panel := _box()
	_check(Juice.slide_in(panel, Vector2(-28, 0)) != null and panel.position == Vector2(-18, 20), "slide in starts from the offset")
	Juice.settle(panel)
	_check(panel.position == Vector2(10, 20), "and settles back home")
	_check(not panel.has_meta("juice_slide"), "settle also stops the slide, so it can't move the node again")
	var beats := [0]
	_check(Juice.heartbeat(panel, 1.0, func() -> void: beats[0] += 1) != null, "heartbeat starts")
	Juice.stop_heartbeat(panel)
	_check(not panel.has_meta("juice_heartbeat") and panel.scale == Vector2.ONE, "heartbeat stops and leaves the bar at normal size")
	var room := _box()
	room.size = Vector2(600, 300)
	_check(Juice.banner(room, "RUSH!  +4 in line", Color.GOLD, 84.0) != null, "banner runs")
	Juice.banner(room, "RUSH!  +2 in line", Color.GOLD, 84.0)
	var cards := room.get_children().filter(func(child: Node) -> bool: return child is PanelContainer and not child.is_queued_for_deletion())
	_check(cards.size() == 1, "a new banner replaces the old one")
	_check(cards.size() == 1 and (cards[0] as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "the banner lets clicks through")
	var bits := Juice.confetti(room, Vector2(100, 100), 500)
	_check(bits != null and bits.amount == 40 and bits.one_shot, "confetti is one burst of at most 40")
	Settings.reduced_motion = true
	_check(Juice.slide_in(panel, Vector2(-28, 0)) == null and panel.position == Vector2(10, 20), "reduced motion: no slide, it just appears")
	_check(Juice.confetti(room, Vector2(100, 100)) == null, "reduced motion: no confetti")
	_check(Juice.heartbeat(panel, 1.0, func() -> void: pass) != null, "reduced motion keeps the heartbeat (a brightness beat, no swelling)")
	Juice.stop_heartbeat(panel)
	_check(panel.modulate == Color.WHITE, "stopping a reduced-motion heartbeat restores the color")
	Juice.banner(room, "RUSH!", Color.GOLD, 84.0)
	var still := room.get_children().filter(func(child: Node) -> bool: return child is PanelContainer and not child.is_queued_for_deletion())
	_check(still.size() == 1 and is_equal_approx((still[0] as Control).position.y, 84.0), "reduced motion: the banner appears in place")
	Settings.reduced_motion = false
	_check(Sfx.SOUND_IDS.has("heartbeat") and Sfx.SOUND_IDS.has("pop"), "the new sounds are registered")
	_check(FileAccess.file_exists("res://audio/sfx/heartbeat.wav") and FileAccess.file_exists("res://audio/sfx/pop.wav"), "the new sound files exist")
	panel.queue_free()
	room.queue_free()


func _test_hit_stop_always_recovers() -> void:
	Settings.reduced_motion = true
	var box := _box()
	_check(not Juice.hit_stop(box), "reduced motion: no hit stop")
	_check(Engine.time_scale == 1.0, "and the game keeps full speed")
	Settings.reduced_motion = false
	_check(Juice.hit_stop(box, 5.0), "hit stop runs")
	_check(Engine.time_scale < 1.0, "it slows the game")
	_check(not Juice.hit_stop(box), "a second one can't overlap the first")
	# Real time, ignoring the slowed clock: the cap is 0.06 s, so 0.2 s is plenty.
	await create_timer(0.2, true, false, true).timeout
	_check(Engine.time_scale == 1.0, "full speed comes back, even when asked for 5 s")
	_check(Juice.hit_stop(box), "and the next hit stop can run")
	await create_timer(0.2, true, false, true).timeout
	box.queue_free()


func _test_star_reveal() -> void:
	var stars := StarRow.new()
	root.add_child(stars)
	stars.reveal(7, 0.01)
	await stars.revealed
	_check(stars.filled == stars.total, "a reveal never fills more stars than the row has")
	stars.reveal(0, 0.01)
	await stars.revealed
	_check(stars.filled == 0, "no stars, nothing filled")
	var shown := [0]
	stars.revealed.connect(func() -> void: shown[0] += 1)
	stars.reveal(3, 0.01)
	stars.reveal(1, 0.01)
	await create_timer(0.6).timeout
	_check(shown[0] == 1 and stars.filled == 1, "a second reveal replaces the first instead of running alongside it")
	stars.queue_free()


## The shift's stems loop in sync with it: same rate, same length, one synchronized stream, and
## set_bgm_layers turns on exactly the first n.
func _test_music_layers() -> void:
	for track: String in Sfx.BGM_LAYERS:
		var base := Sfx.bgm_stream(track)
		for stem: String in Sfx.BGM_LAYERS[track]:
			var part := Sfx.bgm_stream(stem)
			_check(part != null and part.mix_rate == base.mix_rate and part.stereo == base.stereo and part.data.size() == base.data.size(),
					"%s is the same rate and length as %s, so they loop together" % [stem, track])
		var synced := Sfx.layered_stream(track)
		_check(synced != null and synced.stream_count == Sfx.BGM_LAYERS[track].size() + 1, "%s plays as one stream with its stems" % track)
	var before := Sfx._current_bgm
	Sfx._current_bgm = "shift"
	var shift := Sfx.layered_stream("shift")
	Sfx.set_bgm_layers(2, true)
	_check(Sfx.layers_on() == 2, "two stems on")
	_check(shift.get_sync_stream_volume(0) == 0.0 and shift.get_sync_stream_volume(1) == 0.0 and shift.get_sync_stream_volume(2) == 0.0, "the track and the first two stems play")
	_check(shift.get_sync_stream_volume(3) == Sfx.LAYER_SILENT_DB, "the third stem stays silent")
	Sfx.set_bgm_layers(99, true)
	_check(Sfx.layers_on() == Sfx.BGM_LAYERS["shift"].size(), "more tiers than stems: all stems on")
	Sfx.set_bgm_layers(0, true)
	_check(Sfx.layers_on() == 0 and shift.get_sync_stream_volume(1) == Sfx.LAYER_SILENT_DB, "a broken streak silences every stem")
	Sfx._current_bgm = "menu"
	Sfx.set_bgm_layers(2, true)
	_check(Sfx.layers_on() == 0, "a track without stems ignores layers")
	Sfx._current_bgm = before


## A lost badge falls and fades, or only fades with reduced motion, and ends where it started.
func _test_drop_out() -> void:
	for reduced: bool in [false, true]:
		Settings.reduced_motion = reduced
		var box := _box()
		var home := box.position
		var tween := Juice.drop_out(box, 18.0, 0.05)
		_check(tween != null, "drop out runs (reduced motion %s)" % reduced)
		await process_frame
		_check(box.position.y == home.y or not reduced, "reduced motion: the badge never moves")
		# Wait it out by frames, capped: the tween may already be done, so never await its signal.
		for i in 300:
			if not tween.is_valid() or not tween.is_running():
				break
			await process_frame
		await process_frame
		_check(box.position == home and is_equal_approx(box.modulate.a, 0.0), "it ends faded, back where it was (reduced motion %s)" % reduced)
		box.modulate.a = 1.0
		Juice.drop_out(box, 18.0, 1.0)
		await process_frame
		Juice.cancel_drop(box)
		_check(box.position == home, "cancelling puts it back (reduced motion %s)" % reduced)
		box.queue_free()
	Settings.reduced_motion = false
