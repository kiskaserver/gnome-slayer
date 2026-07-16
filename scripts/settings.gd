extends Node
## Настройки игры: хранение (user://settings.cfg), применение на лету.

const PATH := "user://settings.cfg"
const SHADOW_SIZES := [1024, 2048, 4096]

var master_volume := 0.8 # 0..1
var mouse_sens := 1.0    # множитель 0.2..3.0
var invert_y := false
var fullscreen := false
var vsync := true
var shadow_quality := 1  # 0 низкое, 1 среднее, 2 высокое
var show_fps := false
var voice_enabled := true
var voice_volume := 1.0
var music_volume := 0.55
var language := "ru" # ru | uk | en
var render_scale := 1.0 # 0.5..1.0 — масштаб 3D-рендера
var msaa := 1           # 0 выкл, 1 = 2x, 2 = 4x
var ssao := true
var glow := true
var discord_enabled := true
var mic_gain := 1.5   # усиление микрофона 0.5..4.0
var mic_device := ""  # выбранное устройство ввода ("" = системное)
var voice_duck := true # приглушать игру, когда говорят в рацию
var discord_app_id := "" # Application ID с discord.com/developers
# переназначение клавиш: действие -> {"type": "key"|"mouse", "code": int}
var keybinds: Dictionary = {}

signal changed

# применённые значения — чтобы не дёргать дорогие операции без изменений
var _applied_shadow := -1
var _applied_locale := ""
var _applied_scale := -1.0
var _applied_msaa := -1
var _save_pending := false
var _save_cooldown := 0.0


func _process(delta: float) -> void:
	# дебаунс записи на диск: ползунки дёргают apply десятки раз в секунду
	if _save_cooldown > 0:
		_save_cooldown -= delta
		if _save_cooldown <= 0 and _save_pending:
			_save_pending = false
			save_settings()


## Досрочный сброс отложенной записи — при закрытии окна и выходе из игры,
## иначе последнее изменение (в пределах 0.4 с) терялось.
func flush_pending() -> void:
	if _save_pending:
		_save_pending = false
		save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush_pending()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = clampf(cfg.get_value("audio", "master_volume", master_volume), 0.0, 1.0)
	mouse_sens = clampf(cfg.get_value("input", "mouse_sens", mouse_sens), 0.2, 3.0)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	shadow_quality = clampi(cfg.get_value("video", "shadow_quality", shadow_quality), 0, 2)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	voice_enabled = cfg.get_value("voice", "enabled", voice_enabled)
	voice_volume = clampf(cfg.get_value("voice", "volume", voice_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music_volume", music_volume), 0.0, 1.0)
	render_scale = clampf(cfg.get_value("video", "render_scale", render_scale), 0.5, 1.0)
	msaa = clampi(cfg.get_value("video", "msaa", msaa), 0, 2)
	ssao = cfg.get_value("video", "ssao", ssao)
	glow = cfg.get_value("video", "glow", glow)
	discord_enabled = cfg.get_value("discord", "enabled", discord_enabled)
	mic_gain = clampf(cfg.get_value("voice", "mic_gain", mic_gain), 0.5, 4.0)
	voice_duck = cfg.get_value("voice", "duck", voice_duck)
	mic_device = str(cfg.get_value("voice", "mic_device", mic_device))
	discord_app_id = str(cfg.get_value("discord", "app_id", discord_app_id))
	language = cfg.get_value("general", "language", language)
	if language not in ["ru", "uk", "en"]:
		language = "ru"
	keybinds = cfg.get_value("input", "keybinds", {})


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("input", "mouse_sens", mouse_sens)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "shadow_quality", shadow_quality)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("voice", "enabled", voice_enabled)
	cfg.set_value("voice", "volume", voice_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "msaa", msaa)
	cfg.set_value("video", "ssao", ssao)
	cfg.set_value("video", "glow", glow)
	cfg.set_value("discord", "enabled", discord_enabled)
	cfg.set_value("voice", "mic_gain", mic_gain)
	cfg.set_value("voice", "duck", voice_duck)
	cfg.set_value("voice", "mic_device", mic_device)
	cfg.set_value("discord", "app_id", discord_app_id)
	cfg.set_value("general", "language", language)
	cfg.set_value("input", "keybinds", keybinds)
	cfg.save(PATH)


func apply_all() -> void:
	# звуки игры — своя шина (Master не трогаем: на нём сидит голос друга)
	var sbus := AudioServer.get_bus_index("Sfx")
	if sbus != -1:
		AudioServer.set_bus_mute(sbus, master_volume <= 0.001)
		AudioServer.set_bus_volume_db(sbus, linear_to_db(maxf(master_volume * master_volume, 0.0001)))
	# видео
	var win_mode := DisplayServer.window_get_mode()
	if fullscreen and win_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and win_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	# масштаб 3D-рендера и сглаживание — только при реальном изменении
	var root_vp := get_tree().root
	if root_vp != null and (_applied_scale != render_scale or _applied_msaa != msaa):
		_applied_scale = render_scale
		_applied_msaa = msaa
		root_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if render_scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
		root_vp.scaling_3d_scale = render_scale
		root_vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa]
	# тени: пересоздание атласа — дорогое, только при смене качества
	var size: int = SHADOW_SIZES[shadow_quality]
	if _applied_shadow != size:
		_applied_shadow = size
		RenderingServer.directional_shadow_atlas_set_size(size, true)
		var root := get_tree().root
		if root != null:
			root.positional_shadow_atlas_size = size
	# громкость голосового чата
	var vbus := AudioServer.get_bus_index("Voice")
	if vbus != -1:
		AudioServer.set_bus_mute(vbus, voice_volume <= 0.001)
		AudioServer.set_bus_volume_db(vbus, linear_to_db(maxf(voice_volume * voice_volume, 0.0001)))
	# громкость музыки
	var mbus := AudioServer.get_bus_index("Music")
	if mbus != -1:
		AudioServer.set_bus_mute(mbus, music_volume <= 0.001)
		AudioServer.set_bus_volume_db(mbus, linear_to_db(maxf(music_volume * music_volume, 0.0001)))
	# язык — только при смене
	if _applied_locale != language:
		_applied_locale = language
		TranslationServer.set_locale(language)
	changed.emit()


## Применяет сохранённые переназначения клавиш поверх дефолтов.
func apply_keybinds() -> void:
	for action in keybinds:
		if not InputMap.has_action(action):
			continue
		var kb = keybinds[action]
		# защита от порчи cfg: битую запись просто пропускаем, а не роняем старт
		if not (kb is Dictionary) or not kb.has("type") or not kb.has("code"):
			continue
		InputMap.action_erase_events(action)
		var ev: InputEvent
		if kb.type == "mouse":
			ev = InputEventMouseButton.new()
			ev.button_index = int(kb.code)
		else:
			ev = InputEventKey.new()
			ev.physical_keycode = int(kb.code)
		InputMap.action_add_event(action, ev)


func set_keybind(action: String, ev: InputEvent) -> void:
	if ev is InputEventKey:
		keybinds[action] = {"type": "key", "code": ev.physical_keycode}
	elif ev is InputEventMouseButton:
		keybinds[action] = {"type": "mouse", "code": ev.button_index}
	apply_keybinds()
	save_settings()


func apply_and_save() -> void:
	apply_all()
	_save_pending = true
	if _save_cooldown <= 0:
		_save_cooldown = 0.4 # запись на диск не чаще, чем раз в 0.4 c
