class_name Sfx
extends RefCounted
## Plays short UI and office window sound effects from audio/sfx/.
## Uses a lazy pool of AudioStreamPlayers attached to the root viewport so overlapping sounds
## (e.g., bell + paper slide) never cut each other off, and works while paused or in tests.

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
const POOL_SIZE := 8

static var muted: bool = false
static var volume_db: float = 0.0
static var _streams: Dictionary = {}
static var _host: Node = null
static var _players: Array[AudioStreamPlayer] = []
static var _next: int = 0
static var _rng := RandomNumberGenerator.new()


static func has_sound(id: String) -> bool:
	return SOUND_IDS.has(id) and FileAccess.file_exists(_path(id))


static func stream(id: String) -> AudioStreamWAV:
	if not SOUND_IDS.has(id):
		return null
	if not _streams.has(id):
		_streams[id] = AudioStreamWAV.load_from_file(_path(id))
	return _streams[id]


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
	player.play()


static func _path(id: String) -> String:
	return "res://audio/sfx/%s.wav" % id


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
	tree.root.add_child(_host)
	_players.clear()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		_host.add_child(player)
		_players.append(player)
	return _players
