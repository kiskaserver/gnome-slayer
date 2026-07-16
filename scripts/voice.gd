extends Node
## Голосовой чат: push-to-talk (V). Микрофон -> AudioEffectCapture ->
## гейн -> прореживание до ~11 кГц -> мю-лоу 8 бит -> ENet (канал 2).
## Приём: AudioStreamGenerator на узле говорящего (позиционный звук).
## Есть выбор устройства, гейн и локальная проверка микрофона.

const VOICE_RATE := 11025.0
const CHUNK := 550 # ~50 мс на пакет
const MIC_RETRY := 5.0

var capture: AudioEffectCapture = null
var mic_player: AudioStreamPlayer = null
var mic_ready := false
var _mic_retry := 0.0

var playbacks: Dictionary = {}   # peer_id -> {"player", "pb"}
var _accum := PackedFloat32Array()

# локальная проверка микрофона (слышишь сам себя), старт/стоп
var test_active := false
var _test_player: AudioStreamPlayer = null
var _test_pb: AudioStreamGeneratorPlayback = null

signal mic_level(level: float) # для индикатора в настройках

# автоприглушение игры при входящем голосе
const DUCK_DB := -9.0
var _last_voice_rx := -10.0
var _duck_now := 0.0
var _duck_fx: Dictionary = {} # имя шины -> AudioEffectAmplify


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Voice") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Voice")


func apply_input_device() -> void:
	if Settings.mic_device != "" and Settings.mic_device in AudioServer.get_input_device_list():
		AudioServer.input_device = Settings.mic_device
	else:
		AudioServer.input_device = "Default"


func _ensure_mic() -> void:
	if mic_ready:
		return
	if _mic_retry > 0:
		return
	_mic_retry = MIC_RETRY
	apply_input_device()
	if AudioServer.get_bus_index("Record") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
		AudioServer.set_bus_mute(idx, true)
		capture = AudioEffectCapture.new()
		capture.buffer_length = 0.25
		AudioServer.add_bus_effect(idx, capture)
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		mic_player.stream = AudioStreamMicrophone.new()
		mic_player.bus = "Record"
		add_child(mic_player)
	if not mic_player.playing:
		mic_player.play()
	mic_ready = mic_player.playing and capture != null


## Пересоздать вход после смены устройства в настройках.
func restart_mic() -> void:
	if mic_player != null and mic_player.playing:
		mic_player.stop()
	mic_ready = false
	_mic_retry = 0.0


## Переключает проверку микрофона. Возвращает новое состояние.
func toggle_mic_test() -> bool:
	if test_active:
		stop_mic_test()
	else:
		test_active = true
		restart_mic()
		_ensure_mic()
		if _test_player == null:
			_test_player = AudioStreamPlayer.new()
			var gen := AudioStreamGenerator.new()
			gen.mix_rate = VOICE_RATE
			gen.buffer_length = 0.4
			_test_player.stream = gen
			_test_player.bus = "Voice"
			add_child(_test_player)
		_test_player.play()
		_test_pb = _test_player.get_stream_playback()
	return test_active


func stop_mic_test() -> void:
	if not test_active:
		return
	test_active = false
	if _test_player != null:
		_test_player.stop()
	mic_level.emit(0.0)


func _ensure_duck_fx() -> void:
	for bus_name in ["Sfx", "Music"]:
		if _duck_fx.has(bus_name):
			continue
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			continue
		var amp := AudioEffectAmplify.new()
		AudioServer.add_bus_effect(idx, amp)
		_duck_fx[bus_name] = amp


func _update_duck(delta: float) -> void:
	_ensure_duck_fx()
	var now := Time.get_ticks_msec() / 1000.0
	var want: float = DUCK_DB if (Settings.voice_duck and (now - _last_voice_rx < 0.35 or test_active)) else 0.0
	# быстро приседаем, плавно возвращаемся
	var speed: float = 40.0 if want < _duck_now else 12.0
	_duck_now = move_toward(_duck_now, want, speed * delta)
	for amp in _duck_fx.values():
		amp.volume_db = _duck_now


func _process(delta: float) -> void:
	_update_duck(delta)
	_mic_retry = maxf(0, _mic_retry - delta)
	var testing := test_active

	var in_session: bool = (Net.mode == Net.Mode.HOST or Net.mode == Net.Mode.CLIENT) and Net.game != null
	var talking: bool = testing or (in_session and Settings.voice_enabled
		and Input.is_action_pressed("voice") and not Net.game.ui_blocked)

	if not talking:
		if capture != null:
			capture.clear_buffer()
		_accum.clear()
		return

	_ensure_mic()
	if capture == null:
		return
	if in_session and not testing:
		Net.game.hud.show_talker(tr("Ты"))

	# захват -> моно с гейном
	var avail := capture.get_frames_available()
	if avail > 0:
		var frames := capture.get_buffer(avail)
		var div := maxi(1, roundi(AudioServer.get_mix_rate() / VOICE_RATE))
		var peak := 0.0
		var i := 0
		while i < avail:
			var s: float = (frames[i].x + frames[i].y) * 0.5 * Settings.mic_gain
			s = clampf(s, -1.0, 1.0)
			peak = maxf(peak, absf(s))
			_accum.append(s)
			i += div
		mic_level.emit(peak)

	# отправка/локальная проверка чанками
	while _accum.size() >= CHUNK:
		var chunk := _accum.slice(0, CHUNK)
		_accum = _accum.slice(CHUNK)
		if testing:
			if _test_pb != null:
				var room := _test_pb.get_frames_available()
				for k in mini(room, chunk.size()):
					_test_pb.push_frame(Vector2(chunk[k], chunk[k]))
		else:
			var out := PackedByteArray()
			out.resize(chunk.size())
			for k in chunk.size():
				out[k] = _mulaw_encode(chunk[k])
			Net.send_voice(out)


## Приём пакета голоса от игрока sender.
func receive(sender: int, data: PackedByteArray) -> void:
	if Net.game == null:
		return
	var node = Net.game.player_nodes.get(sender)
	if node == null or not is_instance_valid(node):
		return
	var entry: Dictionary = playbacks.get(sender, {})
	var player: AudioStreamPlayer3D = entry.get("player")
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = VOICE_RATE
		gen.buffer_length = 0.4
		player.stream = gen
		player.bus = "Voice"
		player.max_distance = 70.0
		player.unit_size = 16.0
		player.position = Vector3(0, 1.7, 0)
		node.add_child(player)
		player.play()
		entry = {"player": player, "pb": player.get_stream_playback()}
		playbacks[sender] = entry
	var pb: AudioStreamGeneratorPlayback = entry.pb
	if pb == null:
		return
	var room := pb.get_frames_available()
	var n := mini(room, data.size())
	for i in n:
		var s := _mulaw_decode(data[i])
		pb.push_frame(Vector2(s, s))
	_last_voice_rx = Time.get_ticks_msec() / 1000.0
	var pname: String = Net.players[sender].name if Net.players.has(sender) else "???"
	Net.game.hud.show_talker(pname)
	if Net.debug_log:
		print("[TEST] voice rx from=%d bytes=%d" % [sender, data.size()])


func clear_session() -> void:
	playbacks.clear()


# --- мю-лоу 8 бит ---
func _mulaw_encode(x: float) -> int:
	var sign := 0 if x >= 0.0 else 0x80
	var ax: float = minf(absf(x), 1.0)
	var mag := int(log(1.0 + 255.0 * ax) / log(256.0) * 127.0)
	return sign | mag


func _mulaw_decode(b: int) -> float:
	var sign := -1.0 if (b & 0x80) != 0 else 1.0
	var mag := float(b & 0x7F) / 127.0
	return sign * (pow(256.0, mag) - 1.0) / 255.0
