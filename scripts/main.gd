extends Node
## Точка входа: главное меню, создание/подключение к серверу, пауза,
## экраны конца игры. Также тестовые режимы для запуска из командной строки.

var game: Game = null
var ui: CanvasLayer = null
var menu_root: Control = null
var pause_root: Control = null
var gameover_root: Control = null
var settings_root: Control = null
var status_label: Label = null
var fps_label: Label = null

var _harness: TestHarness = null


func _ready() -> void:
	_setup_input()
	get_tree().set_auto_accept_quit(true)
	# меню и оверлеи должны жить во время паузы дерева
	process_mode = Node.PROCESS_MODE_ALWAYS

	# дефолтное имя героя — на языке игрока (пока он не ввёл своё)
	if Net.my_name == "Рыцарь":
		Net.my_name = tr("Рыцарь")

	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	menu = MenuBuilder.new(self)
	settings_ui = SettingsUi.new(self)
	_build_menu()

	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps_label.position = Vector2(10, 2)
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	fps_label.add_theme_constant_override("outline_size", 6)
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	fps_label.visible = false
	ui.add_child(fps_label)

	Net.main = self
	Net.session_failed.connect(_on_session_failed)
	Net.session_ended.connect(_on_session_ended)
	Achievements.unlocked.connect(_on_achievement_unlocked)
	Discord.join_requested.connect(_on_discord_join)
	Music.play_track("menu")

	_harness = TestHarness.new()
	_harness.main = self
	add_child(_harness)
	_harness.handle_cmdline()


func _on_achievement_unlocked(id: String) -> void:
	var def: Dictionary = Achievements.DEFS.get(id, {})
	if def.is_empty():
		return
	if game != null and game.hud != null:
		game.hud.banner(tr("ДОСТИЖЕНИЕ: %s") % tr(def.name), 3.2)
	Sfx.play("pickup")


# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------
const REBIND_ACTIONS := [
	["move_forward", "Вперёд"], ["move_back", "Назад"], ["move_left", "Влево"], ["move_right", "Вправо"],
	["run", "Бег"], ["dodge", "Кувырок"], ["attack", "Атака"], ["block", "Блок"],
	["interact", "Поднять друга"], ["voice", "Рация (голос)"], ["chat", "Чат"], ["stats", "Персонаж"],
	["inventory", "Инвентарь"],
]

var _rebind_action := ""
var _rebind_button: Button = null


func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("run", KEY_SHIFT)
	_add_key("dodge", KEY_SPACE)
	_add_key("interact", KEY_E)
	_add_key("voice", KEY_V)
	_add_key("chat", KEY_T)
	_add_key("stats", KEY_C)
	_add_key("inventory", KEY_I)
	_add_mouse("attack", MOUSE_BUTTON_LEFT)
	_add_mouse("block", MOUSE_BUTTON_RIGHT)
	Settings.apply_keybinds()


## Человекочитаемое имя клавиши действия (для подсказок и кнопок настроек).
func key_name(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var ev: InputEvent = events[0]
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return tr("ЛКМ")
			MOUSE_BUTTON_RIGHT: return tr("ПКМ")
			MOUSE_BUTTON_MIDDLE: return tr("СКМ")
			_: return tr("Мышь %d") % ev.button_index
	if ev is InputEventKey:
		return OS.get_keycode_string(ev.physical_keycode)
	return "?"


func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _input(event: InputEvent) -> void:
	# режим «нажми клавишу» для переназначения управления
	if _rebind_action != "":
		if event is InputEventKey and event.pressed:
			if event.physical_keycode != KEY_ESCAPE:
				Settings.set_keybind(_rebind_action, event)
			_finish_rebind()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			Settings.set_keybind(_rebind_action, event)
			_finish_rebind()
			get_viewport().set_input_as_handled()
		return

	# диалог с НПС: E/ЛКМ/пробел — далее
	if game != null and game.hud != null and game.hud.is_dialog_open():
		if event.is_action_pressed("interact") or event.is_action_pressed("attack") \
				or event.is_action_pressed("dodge"):
			game.hud.dialog_next()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			game.hud.close_dialog()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if game != null and game.hud.is_stats_open():
			game.hud.toggle_stats({})
			game.ui_blocked = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif game != null and game.hud.is_shop_open():
			game.close_shop()
		elif game != null and game.hud.is_inventory_open():
			game.hud.toggle_inventory([], {})
			game.ui_blocked = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif game != null and game.hud.is_chat_open():
			game.hud.close_chat()
		elif settings_root != null:
			_close_settings()
		elif game != null and gameover_root == null:
			_toggle_pause()
		elif game == null and menu_root != null and menu_root.visible and not menu_on_main_page():
			_set_status("")
			_show_page("main")
		return

	if game == null:
		return

	# окно персонажа (C)
	if pause_root == null and gameover_root == null and settings_root == null \
			and event.is_action_pressed("stats") and not game.hud.is_chat_open():
		var opened: bool = game.hud.toggle_stats(Net.players.get(Net.my_id, {}))
		game.ui_blocked = opened
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opened else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	# инвентарь (I)
	if pause_root == null and gameover_root == null and settings_root == null \
			and event.is_action_pressed("inventory") and not game.hud.is_chat_open() \
			and not game.hud.is_stats_open():
		var iopened: bool = game.hud.toggle_inventory(game.inventory, game.my_equip)
		game.ui_blocked = iopened
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if iopened else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	# открыть текстовый чат
	if not game.ui_blocked and pause_root == null and gameover_root == null \
			and event.is_action_pressed("chat"):
		game.ui_blocked = true
		game.hud.open_chat()
		get_viewport().set_input_as_handled()
	# если захват мыши слетел (алт-таб и т.п.) — вернуть по клику
	elif event is InputEventMouseButton and event.pressed \
			and not game.ui_blocked and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _finish_rebind() -> void:
	if _rebind_button != null and _rebind_action != "":
		_rebind_button.text = key_name(_rebind_action)
	_rebind_action = ""
	_rebind_button = null


# ---------------------------------------------------------------------------
# Меню
# ---------------------------------------------------------------------------
func _styled_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 46)
	b.add_theme_font_size_override("font_size", 19)
	return b


func _title_label(text: String, size: int, color := Color(0.95, 0.91, 0.78)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	return l


var menu: MenuBuilder
var settings_ui: SettingsUi


## Совместимость со старым кодом страниц (меню — в ui/menu_builder.gd).
func _show_page(page: String) -> void:
	menu.show_page(page)


func menu_on_main_page() -> bool:
	return menu.on_main_page()


func _show_section(section: String) -> void:
	menu.show_section(section)


## Общий хелпер строк «подпись + контрол» (меню, настройки).
func _row(box: Container, label_text: String, label_w := 170) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.custom_minimum_size = Vector2(label_w, 0)
	row.add_child(lbl)
	return row


func _refresh_slot_cards() -> void:
	menu.refresh_slot_cards()


func _build_menu() -> void:
	menu.build_menu()


## Вкладки настроек (ui/settings_ui.gd): и в меню, и в оверлее паузы.
func _build_settings_content() -> TabContainer:
	return settings_ui.build_content()

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


# ---------------------------------------------------------------------------
# Переходы
# ---------------------------------------------------------------------------
func enter_game() -> void:
	if game != null:
		return
	_joining = false # успешно вошли — прекращаем перебор адресов Discord-приглашения
	menu_root.visible = false
	_set_status("")
	game = Game.new()
	game.main = self
	# main работает и в паузе (ALWAYS), но игра обязана останавливаться —
	# иначе пауза дерева не действует на геймплей (наследование режима)
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.hud.chat_submitted.connect(func(t: String): Net.send_chat(t))
	game.hud.chat_closed.connect(func():
		if game != null and pause_root == null and settings_root == null and gameover_root == null:
			game.ui_blocked = false)
	game.hud.dialog_closed.connect(func(adv: String):
		if game != null:
			game.dialog_closed(adv))
	game.hud.stat_alloc.connect(func(stat: String): Net.req_stat(stat))
	game.hud.skill_unlock.connect(func(skill_id: String): Net.req_skill(skill_id))
	game.hud.inv_equip.connect(func(idx: int): Net.req_equip(idx))
	game.hud.inv_unequip.connect(func(slot: String): Net.req_unequip(slot))
	game.hud.inv_drop.connect(func(idx: int): Net.req_drop_item(idx))
	game.hud.shop_buy.connect(func(idx: int): Net.req_buy(idx))
	game.hud.shop_sell.connect(func(idx: int): Net.req_sell(idx))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Music.play_track(Net.biome)


## Переход между главами кампании: мир пересоздаётся, сессия и прокачка живут.
func goto_chapter() -> void:
	if game == null:
		return
	_close_overlays()
	Voice.clear_session()
	var old_game := game
	Net.game = null
	# queue_free (не free): переход может прийти изнутри физики старого мира.
	# Новый мир создаётся сразу же — rpc спавна главы попадут уже в него.
	old_game.process_mode = Node.PROCESS_MODE_DISABLED
	old_game.visible = false
	old_game.queue_free()
	game = Game.new()
	game.main = self
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.hud.chat_submitted.connect(func(t: String): Net.send_chat(t))
	game.hud.chat_closed.connect(func():
		if game != null and pause_root == null and settings_root == null and gameover_root == null:
			game.ui_blocked = false)
	game.hud.dialog_closed.connect(func(adv: String):
		if game != null:
			game.dialog_closed(adv))
	game.hud.stat_alloc.connect(func(stat: String): Net.req_stat(stat))
	game.hud.skill_unlock.connect(func(skill_id: String): Net.req_skill(skill_id))
	game.hud.inv_equip.connect(func(idx: int): Net.req_equip(idx))
	game.hud.inv_unequip.connect(func(slot: String): Net.req_unequip(slot))
	game.hud.inv_drop.connect(func(idx: int): Net.req_drop_item(idx))
	game.hud.shop_buy.connect(func(idx: int): Net.req_buy(idx))
	game.hud.shop_sell.connect(func(idx: int): Net.req_sell(idx))
	Music.play_track(Net.biome)
	game.hud.banner(tr("Глава %d") % Net.campaign_chapter, 3.0)


func leave_game() -> void:
	get_tree().paused = false
	_close_overlays()
	Voice.clear_session()
	if game != null:
		game.queue_free()
		game = null
	Net.shutdown()
	Net.game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_root.visible = true
	_show_page("main")
	_refresh_slot_cards()
	Music.play_track("menu")


func _on_session_failed(reason: String) -> void:
	# идёт присоединение по приглашению Discord — не показываем ошибку,
	# а пробуем следующий адрес хоста из списка
	if _joining:
		_join_next()
		return
	_set_status(reason)


# --- присоединение по приглашению Discord ---
var _join_ips: Array = []
var _join_port := 0
var _joining := false
var _join_gen := 0


## Игрок нажал «Join» в Discord: секрет содержит адреса и порт хоста.
func _on_discord_join(secret: String) -> void:
	if game != null or Net.mode != Net.Mode.NONE:
		return # уже в игре или подключаемся
	var info := Net.parse_join_secret(secret)
	_join_ips = info.get("ips", [])
	_join_port = int(info.get("port", Net.DEFAULT_PORT))
	if _join_ips.is_empty():
		_set_status(tr("Не удалось разобрать приглашение Discord."))
		return
	if menu_root != null:
		menu_root.visible = true
	_joining = true
	_join_next()


## Пробует очередной адрес хоста; провалы прокидываются через _on_session_failed.
func _join_next() -> void:
	if _join_ips.is_empty():
		_joining = false
		_set_status(tr("Не удалось подключиться к хосту из Discord (нужен VPN или проброс порта)."))
		return
	var ip: String = str(_join_ips.pop_front())
	_join_gen += 1
	var gen := _join_gen
	_set_status(tr("Discord: подключение к %s...") % ip)
	if Net.start_client(ip, _join_port) != OK:
		_join_next()
		return
	# страховочный таймаут: если ни успех (enter_game), ни явный отказ за 6 c
	await get_tree().create_timer(6.0).timeout
	if _joining and gen == _join_gen and game == null:
		Net.shutdown()
		_join_next()


func _on_session_ended(reason: String) -> void:
	get_tree().paused = false
	if game != null:
		_close_overlays()
		game.queue_free()
		game = null
		Net.game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_root.visible = true
	_show_page("main")
	Music.play_track("menu")
	_set_status(reason)


func _close_overlays() -> void:
	if pause_root != null:
		pause_root.queue_free()
		pause_root = null
	if gameover_root != null:
		gameover_root.queue_free()
		gameover_root = null
	if settings_root != null:
		settings_root.queue_free()
		settings_root = null
	if game != null:
		game.ui_blocked = false


func _toggle_pause() -> void:
	if pause_root != null:
		_resume()
		return
	game.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.mode == Net.Mode.SINGLE:
		get_tree().paused = true # в одиночке мир честно замирает

	pause_root = _overlay()
	var box := _overlay_box(pause_root)
	box.add_child(_title_label(tr("ПАУЗА"), 44))
	if Net.mode != Net.Mode.SINGLE:
		box.add_child(_title_label(tr("(бой продолжается — это мультиплеер)"), 14, Color(0.8, 0.8, 0.75)))
	box.add_child(_spacer(10))
	var b_resume := _styled_button(tr("ПРОДОЛЖИТЬ"))
	box.add_child(b_resume)
	b_resume.pressed.connect(_resume)
	var b_settings := _styled_button(tr("НАСТРОЙКИ"))
	box.add_child(b_settings)
	b_settings.pressed.connect(_open_settings)
	if game != null and game.tutorial != null and game.tutorial.active:
		var b_skip_tut := _styled_button(tr("Пропустить обучение"))
		box.add_child(b_skip_tut)
		b_skip_tut.pressed.connect(func():
			game.tutorial.skip()
			_resume())
	var b_leave := _styled_button(tr("ПОКИНУТЬ ИГРУ"))
	box.add_child(b_leave)
	b_leave.pressed.connect(func():
		leave_game())


func _resume() -> void:
	get_tree().paused = false
	if pause_root != null:
		pause_root.queue_free()
		pause_root = null
	if game != null:
		game.ui_blocked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_game_over(win: bool, text: String) -> void:
	var story_finale: bool = win and Net.game_mode == "story"
	if Net.mode != Net.Mode.SINGLE and not story_finale:
		return # в мультиплеере раунд перезапустится автоматически
	if gameover_root != null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.ui_blocked = true
	gameover_root = _overlay()
	var box := _overlay_box(gameover_root)
	if text.begins_with("ENDING:"):
		var parts := text.split(":")
		var ending_key: String = parts[1]
		var sides_done := int(parts[2])
		Achievements.unlock("story_complete")
		if ending_key == "gold":
			Achievements.unlock("golden_ending")
		if sides_done >= Quests.CHAPTERS.size():
			Achievements.unlock("side_master")
		box.add_child(_title_label(tr("ФИНАЛ КАМПАНИИ"), 46, Color(1.0, 0.85, 0.4)))
		var epilogue := Label.new()
		epilogue.text = tr(Quests.ENDINGS.get(ending_key, ""))
		epilogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		epilogue.custom_minimum_size = Vector2(640, 0)
		epilogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		epilogue.add_theme_font_size_override("font_size", 17)
		box.add_child(epilogue)
		box.add_child(_title_label(tr("Сайд-квестов выполнено: %d из %d") % [sides_done, Quests.CHAPTERS.size()], 16, Color(0.8, 0.9, 0.8)))
	elif win:
		if Net.game_mode == "pvp":
			Achievements.unlock("pvp_win")
		box.add_child(_title_label(tr("ПОБЕДА!"), 52, Color(0.6, 0.9, 0.5)))
		box.add_child(_title_label(tr("Племя гномов разбито. Королевство спасено... пока что."), 16, Color(0.85, 0.85, 0.8)))
	else:
		box.add_child(_title_label(tr("ТЫ ПАЛ В БОЮ"), 52, Color(1, 0.45, 0.4)))
		box.add_child(_title_label(tr("Гномы ликуют и уже делят твои доспехи."), 16, Color(0.85, 0.85, 0.8)))
	var kills: int = Net.players[Net.my_id].kills if Net.players.has(Net.my_id) else 0
	box.add_child(_title_label(tr("Гномов убито: %d · Волна: %d") % [kills, game.wave], 19))
	box.add_child(_spacer(12))

	if win:
		var b_endless := _styled_button(tr("БЕСКОНЕЧНЫЙ РЕЖИМ"))
		box.add_child(b_endless)
		b_endless.pressed.connect(func():
			_close_overlays()
			game.server_continue_endless()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	var b_again := _styled_button(tr("ЗАНОВО"))
	box.add_child(b_again)
	b_again.pressed.connect(func():
		_close_overlays()
		game.server_restart_single()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	var b_menu := _styled_button(tr("В МЕНЮ"))
	box.add_child(b_menu)
	b_menu.pressed.connect(func(): leave_game())


# ---------------------------------------------------------------------------
# Настройки
# ---------------------------------------------------------------------------
func _open_settings() -> void:
	if settings_root != null:
		return
	settings_root = _overlay()
	settings_root.theme = UiTheme.get_theme()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_title_label(tr("НАСТРОЙКИ"), 34))
	var tabs := _build_settings_content()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	var b_back := _styled_button(tr("НАЗАД"))
	box.add_child(b_back)
	b_back.pressed.connect(_close_settings)


func _close_settings() -> void:
	Voice.stop_mic_test()
	_finish_rebind()
	if settings_root != null:
		settings_root.queue_free()
		settings_root = null
	# если настройки открыты из главного меню/паузы — курсор оставляем видимым


## Пересобирает меню на новом языке (вызывается при смене языка).
func _rebuild_ui() -> void:
	var was_settings := settings_root != null
	var was_pause := pause_root != null  # настройки могли быть открыты из паузы
	_close_overlays()
	var menu_visible := menu_root.visible
	menu_root.queue_free()
	menu.reset()
	_build_menu()
	menu_root.visible = menu_visible
	if game != null:
		game.ui_blocked = was_settings or was_pause
	# восстанавливаем паузу ПОД настройками — иначе, закрыв настройки, игрок
	# оставался в замороженном мире без меню (get_tree().paused так и висел)
	if was_pause:
		_toggle_pause()
	if was_settings:
		_open_settings()


func _overlay() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	ui.add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06, 0.94)
	root.add_child(bg)
	return root


func _overlay_box(root: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


# Тестовые режимы (--test/--mp*/--screenshot) живут в scripts/test_harness.gd.
func _process(delta: float) -> void:
	fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		var ping := Net.ping_ms()
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second() \
			+ (tr("  ·  пинг: %d мс") % ping if ping >= 0 else "")

	_harness.tick(delta)
