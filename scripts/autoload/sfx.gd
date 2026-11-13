class_name Sfx
extends RefCounted
## Plays short UI and office window sound effects from audio/sfx/ and looping background music
## from audio/bgm/. Uses a lazy pool of AudioStreamPlayers attached to the root viewport so
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
]
const BGM_IDS := [
	"menu",
	"shift",
]
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


static func play(id: String, pitch_jitter: float = 0.03) -> void:
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
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
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
	var audio := bgm_stream(id)
	if audio == null:
		return
	_current_bgm = id
	_bgm_player.stream = audio
	_bgm_player.volume_db = bgm_volume_db
	if _bgm_player.is_inside_tree():
		_bgm_player.play()
	elif not _bgm_player.ready.is_connected(_bgm_player.play):
		_bgm_player.ready.connect(_bgm_player.play, CONNECT_ONE_SHOT)


static func stop_bgm() -> void:
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
