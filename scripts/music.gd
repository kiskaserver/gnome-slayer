extends Node
## Фоновая музыка: свой трек у каждой локации, плавный кроссфейд.

const TRACKS := ["menu", "meadow", "winter", "autumn", "night"]
const FADE := 2.0

var streams: Dictionary = {}
var _players: Array = []
var _active := 0
var current := ""
var _fade_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	for t in TRACKS:
		var path := "res://assets/music/%s.wav" % t
		if ResourceLoader.exists(path):
			var s: AudioStreamWAV = load(path).duplicate()
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = s.data.size() / 2 # 16 бит моно
			streams[t] = s
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	# шины Voice/Music созданы позже загрузки настроек — применяем повторно
	Settings.apply_all()


## Переключает трек с кроссфейдом (повторный вызов того же — ничего).
func play_track(name: String) -> void:
	if current == name or not streams.has(name):
		return
	current = name
	# гасим прежний кроссфейд: иначе быстрый A→B→A останавливал уже активный трек
	# отложенным колбэком old.stop от старого твина
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var new_p: AudioStreamPlayer = _players[_active]
	new_p.stream = streams[name]
	new_p.volume_db = -80.0
	new_p.play()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(new_p, "volume_db", 0.0, FADE)
	if old.playing:
		_fade_tween.tween_property(old, "volume_db", -80.0, FADE)
		_fade_tween.chain().tween_callback(old.stop)
