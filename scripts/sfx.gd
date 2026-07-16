extends Node
## Загрузка и проигрывание процедурных звуков (assets/sfx/*.wav).
## Плееры пулятся — никакого создания/удаления узлов на каждый звук.

const NAMES := [
	"swing", "hit", "gnome_death", "war_cry", "player_hurt", "block",
	"fireball", "explode", "pickup", "wave_horn", "roll", "player_death", "victory",
	"blip",
]
const POOL_3D := 16
const POOL_2D := 6

var streams: Dictionary = {}
var _pool_3d: Array = []
var _pool_2d: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# отдельная шина игровых звуков: голос и музыка регулируются независимо
	if AudioServer.get_bus_index("Sfx") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Sfx")
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.max_distance = 60.0
		p.unit_size = 6.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_pool_2d.append(p)


func _grab(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[randi() % pool.size()] # все заняты — крадём случайный


## Плоский (интерфейсный) звук.
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(name):
		return
	var p: AudioStreamPlayer = _grab(_pool_2d)
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## Позиционный 3D-звук.
func play_at(name: String, pos: Vector3, volume_db: float = 3.0, pitch: float = 1.0) -> void:
	if not streams.has(name):
		return
	var p: AudioStreamPlayer3D = _grab(_pool_3d)
	p.global_position = pos
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()
