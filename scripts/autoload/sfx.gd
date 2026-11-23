class_name Sfx
extends RefCounted
## Plays short UI and office window sound effects from audio/sfx/ and looping background music
## from audio/bgm/. A track can have stems (BGM_LAYERS) that play with it in sync and join one by
## one, like the shift music while the player is in the zone. Uses a lazy pool of AudioStreamPlayers attached to the root viewport so
## overlapping sounds never cut each other off, and works while paused or in tests.

const SOUND_IDS := [
	"click",
	"bell",
	"stamp",
	"stamp_lift",
	"paper_slide",
	"scan",
	"flag",
	"correct",
	"wrong",
	"alert",
	"heartbeat",
	"pop",
	"murmur",
	"record_scratch",
]
const BGM_IDS := [
	"menu",
	"shift",
	"shift_zone1",
	"shift_zone2",
	"shift_zone3",
]
## Stems that play over a track, in sync, from the first loop. Each starts silent and joins when
## set_bgm_layers turns it on. Every stem is the same length as its track (tools/audio/make_sfx.py).
const BGM_LAYERS := {
	"shift": ["shift_zone1", "shift_zone2", "shift_zone3"],
}
## A stem that is off: quiet enough to vanish, without stopping it (it keeps its place in the bar).
const LAYER_SILENT_DB := -60.0
const LAYER_FADE_IN := 1.2
const LAYER_FADE_OUT := 0.4
const POOL_SIZE := 8

static var muted: bool = false
static var volume_db: float = 0.0
static var bgm_volume_db: float = -8.0
static var _streams: Dictionary = {}
static var _bgm_streams: Dictionary = {}
static var _host: Node = null
static var _players: Array[AudioStreamPlayer] = []
static var _bgm_player: AudioStreamPlayer = null
static var _current_bgm: String = ""
## Stems of the current track that are on (0 = the plain track).
static var _layers_on: int = 0
static var _layer_tween: Tween = null
static var _synced: Dictionary = {}
static var _next: int = 0
static var _rng := RandomNumberGenerator.new()


static func has_sound(id: String) -> bool:
	return SOUND_IDS.has(id) and FileAccess.file_exists(_path(id))


static func has_bgm(id: String) -> bool:
	return BGM_IDS.has(id) and FileAccess.file_exists(_bgm_path(id))


static func stream(id: String) -> AudioStreamWAV:
	if not SOUND_IDS.has(id):
		return null
	if not _streams.has(id):
		_streams[id] = AudioStreamWAV.load_from_file(_path(id))
	return _streams[id]


static func bgm_stream(id: String) -> AudioStreamWAV:
	if not BGM_IDS.has(id):
		return null
	if not _bgm_streams.has(id):
		var audio := AudioStreamWAV.load_from_file(_bgm_path(id))
		if audio != null:
			audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
			audio.loop_begin = 0
			audio.loop_end = audio.data.size() >> 1
		_bgm_streams[id] = audio
	return _bgm_streams[id]


## A track and its stems as one stream, so they always start and loop together. Stems start
## silent. null if the track has no stems or a file won't load.
static func layered_stream(id: String) -> AudioStreamSynchronized:
	if not BGM_LAYERS.has(id):
		return null
	if not _synced.has(id):
		var parts: Array = [id] + BGM_LAYERS[id]
		var synced := AudioStreamSynchronized.new()
		synced.stream_count = parts.size()
		for i in parts.size():
			var part := bgm_stream(parts[i])
			if part == null:
				_synced[id] = null
				return null
			synced.set_sync_stream(i, part)
			synced.set_sync_stream_volume(i, layer_volume_db(i - 1, 0) if i > 0 else 0.0)
		_synced[id] = synced
	return _synced[id]


## How loud stem `layer` (0 = the first stem) is with `on` stems turned on.
static func layer_volume_db(layer: int, on: int) -> float:
	return 0.0 if layer < on else LAYER_SILENT_DB


## Turns on the first `count` stems of the current track and silences the rest: they fade in
## (LAYER_FADE_IN) and drop out quicker (LAYER_FADE_OUT), unless instant. Nothing to do for a
## track without stems.
static func set_bgm_layers(count: int, instant: bool = false) -> void:
	if _layer_tween != null and _layer_tween.is_valid():
		_layer_tween.kill()
	_layer_tween = null
	var synced := layered_stream(_current_bgm)
	if synced == null:
		_layers_on = 0
		return
	count = clampi(count, 0, synced.stream_count - 1)
	var rising := count > _layers_on
	_layers_on = count
	var can_fade := not instant and _host != null and is_instance_valid(_host) and _host.is_inside_tree()
	for i in range(1, synced.stream_count):
		var target := layer_volume_db(i - 1, count)
		var from := synced.get_sync_stream_volume(i)
		if not can_fade or is_equal_approx(from, target):
			synced.set_sync_stream_volume(i, target)
			continue
		if _layer_tween == null:
			_layer_tween = _host.create_tween().set_parallel()
		_layer_tween.tween_method(func(db: float) -> void: synced.set_sync_stream_volume(i, db),
				from, target, LAYER_FADE_IN if rising else LAYER_FADE_OUT)


static func layers_on() -> int:
	return _layers_on


## pitch sets the base pitch (1.0 is as recorded), for a run of sounds that climb, like the
## report's stars; pitch_jitter adds a little randomness on top so repeats don't sound copied.
static func play(id: String, pitch_jitter: float = 0.03, pitch: float = 1.0) -> void:
	if muted or not SOUND_IDS.has(id) or DisplayServer.get_name() == "headless":
		return
	var audio := stream(id)
	if audio == null:
		return
	var players := _ensure_pool()
	if players.is_empty():
		return
	var player: AudioStreamPlayer = players[_next]
	_next = (_next + 1) % players.size()
	player.stream = audio
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.25, 4.0) * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0)
	if player.is_inside_tree():
		player.play()
	elif not player.ready.is_connected(player.play):
		player.ready.connect(player.play, CONNECT_ONE_SHOT)


static func play_bgm(id: String) -> void:
	if muted or not BGM_IDS.has(id) or DisplayServer.get_name() == "headless":
		return
	_ensure_pool()
	if _bgm_player == null or not is_instance_valid(_bgm_player):
		return
	if _current_bgm == id and (_bgm_player.playing or not _bgm_player.is_inside_tree()):
		return
	var audio: AudioStream = layered_stream(id) if BGM_LAYERS.has(id) else bgm_stream(id)
	if audio == null:
		return
	# The old track's stems go quiet (and any fade stops) before the switch; the new track always
	# starts plain, its stems join later.
	set_bgm_layers(0, true)
	_current_bgm = id
	set_bgm_layers(0, true)
	_bgm_player.stream = audio
	_bgm_player.volume_db = bgm_volume_db
	if _bgm_player.is_inside_tree():
		_bgm_player.play()
	elif not _bgm_player.ready.is_connected(_bgm_player.play):
		_bgm_player.ready.connect(_bgm_player.play, CONNECT_ONE_SHOT)


static func stop_bgm() -> void:
	set_bgm_layers(0, true)
	_current_bgm = ""
	if _bgm_player != null and is_instance_valid(_bgm_player) and _bgm_player.is_inside_tree():
		_bgm_player.stop()


static func _path(id: String) -> String:
	return "res://audio/sfx/%s.wav" % id


static func _bgm_path(id: String) -> String:
	return "res://audio/bgm/%s.wav" % id


static func _ensure_pool() -> Array[AudioStreamPlayer]:
	if _host != null and is_instance_valid(_host):
		return _players
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return []
	_rng.randomize()
	_host = Node.new()
	_host.name = "SfxPool"
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	_players.clear()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		_host.add_child(player)
		_players.append(player)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"Master"
	_host.add_child(_bgm_player)
	if tree.root.is_node_ready():
		tree.root.add_child(_host)
	else:
		tree.root.add_child.call_deferred(_host)
	return _players
