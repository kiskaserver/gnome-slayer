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


var _sections: Dictionary = {}
var _ach_progress_label: Label = null
var _ach_list: VBoxContainer = null
var _nav_buttons: Dictionary = {}
var _current_section := "play"
var _slot_cards: Array = []
var _restart_campaign_cb: CheckBox = null


## Совместимость со старым кодом страниц.
func _show_page(page: String) -> void:
	_show_section("play" if page in ["main", "play"] else ("mp" if page in ["mp", "host", "join"] else page))


func menu_on_main_page() -> bool:
	return _current_section == "play"


func _show_section(section: String) -> void:
	if section != "settings":
		Voice.stop_mic_test()
	if section == "achievements":
		_refresh_achievements_panel()
	_current_section = section
	for key in _sections:
		_sections[key].visible = (key == section)
	for key in _nav_buttons:
		var btn: Button = _nav_buttons[key]
		btn.add_theme_color_override("font_color", UiTheme.ACCENT if key == section else Color(0.9, 0.9, 0.88))


func _h1(text: String) -> Label:
	return _title_label(text, 38)


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


func _name_row(box: Container) -> void:
	var row := _row(box, tr("Имя:"))
	var edit := LineEdit.new()
	edit.text = Net.my_name
	edit.custom_minimum_size = Vector2(280, 40)
	edit.max_length = 16
	row.add_child(edit)
	edit.text_changed.connect(func(t): Net.my_name = t if t.strip_edges() != "" else tr("Рыцарь"))
	edit.visibility_changed.connect(func():
		if edit.is_visible_in_tree():
			edit.text = Net.my_name)


func _difficulty_row(box: Container, label_w := 170) -> void:
	var row := _row(box, tr("Сложность:"), label_w)
	var opt := OptionButton.new()
	var ids := ["easy", "normal", "hard"]
	for i in ids.size():
		opt.add_item(tr(Quests.DIFFICULTIES[ids[i]].title), i)
	opt.selected = maxi(0, ids.find(Net.difficulty))
	opt.custom_minimum_size = Vector2(220, 40)
	row.add_child(opt)
	opt.item_selected.connect(func(i: int): Net.difficulty = ids[i])


func _biome_row(box: Container) -> void:
	var row := _row(box, tr("Локация:"))
	var opt := OptionButton.new()
	opt.add_item(tr("Случайно"), 0)
	var ids := ["random"]
	for bid in WorldGen.BIOME_LIST:
		opt.add_item(tr(WorldGen.BIOMES[bid].title), ids.size())
		ids.append(bid)
	opt.selected = maxi(0, ids.find(Net.biome_choice))
	opt.custom_minimum_size = Vector2(280, 40)
	row.add_child(opt)
	opt.item_selected.connect(func(i: int): Net.biome_choice = ids[i])


# ---------------------------------------------------------------------------
# Слоты сохранений
# ---------------------------------------------------------------------------
func _slots_block(box: Container) -> void:
	var head := Label.new()
	head.text = tr("Сохранения")
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", Color(0.95, 0.91, 0.78))
	box.add_child(head)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	box.add_child(cards)
	_slot_cards.clear()
	for i in range(1, Save.SLOTS + 1):
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(226, 150)
		cards.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", UiTheme.ACCENT)
		v.add_child(title)
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82))
		v.add_child(info)
		var date := Label.new()
		date.add_theme_font_size_override("font_size", 11)
		date.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		v.add_child(date)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(spacer)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 6)
		v.add_child(btns)
		var b_sel := Button.new()
		b_sel.text = tr("Выбрать")
		b_sel.custom_minimum_size = Vector2(110, 32)
		b_sel.add_theme_font_size_override("font_size", 13)
		btns.add_child(b_sel)
		var b_del := Button.new()
		b_del.text = tr("Удалить")
		b_del.custom_minimum_size = Vector2(90, 32)
		b_del.add_theme_font_size_override("font_size", 13)
		btns.add_child(b_del)
		var slot_i := i
		b_sel.pressed.connect(func():
			Save.select_slot(slot_i)
			_refresh_slot_cards())
		b_del.pressed.connect(func():
			Save.delete_slot(slot_i)
			_refresh_slot_cards())
		_slot_cards.append({"panel": card, "title": title, "info": info, "date": date, "del": b_del, "slot": slot_i})
	_refresh_slot_cards()


func _refresh_slot_cards() -> void:
	if menu_root == null or not menu_root.visible:
		return # в бою карточки не видны — не читаем слоты с диска
	for c in _slot_cards:
		if not is_instance_valid(c.panel):
			continue
		var info: Dictionary = Save.slot_info(c.slot)
		var active: bool = c.slot == Save.active_slot
		c.title.text = ("● " if active else "") + tr("Слот %d") % c.slot
		if info.is_empty():
			c.info.text = tr("Пусто — новая игра")
			c.date.text = ""
			c.del.disabled = true
		else:
			var sides := 0
			for b in Quests.CHAPTERS.size():
				if int(info.sides) & (1 << b):
					sides += 1
			c.info.text = tr("Глава %d · Герой ур. %d") % [info.chapter, info.level] + "\n" + tr("Сайды: %d/%d") % [sides, Quests.CHAPTERS.size()]
			c.date.text = tr("Сохранено: %s") % info.saved_at
			c.del.disabled = false
		var style := UiTheme._box(UiTheme.BG_CARD, 12, UiTheme.ACCENT if active else Color(1, 1, 1, 0.08), 2 if active else 1)
		c.panel.add_theme_stylebox_override("panel", style)
	if _restart_campaign_cb != null and is_instance_valid(_restart_campaign_cb):
		_restart_campaign_cb.visible = Save.has_campaign()
		_restart_campaign_cb.button_pressed = false


# ---------------------------------------------------------------------------
# Построение меню: боковая панель + разделы
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = UiTheme.get_theme()
	ui.add_child(menu_root)

	# фон: градиент + тлеющие угольки
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.12, 0.17))
	grad.set_color(1, Color(0.03, 0.04, 0.06))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	bg.texture = gtex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	menu_root.add_child(bg)

	var embers := GPUParticles2D.new()
	embers.amount = 36
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(1000, 20, 1)
	em.direction = Vector3(0, -1, 0)
	em.spread = 12.0
	em.initial_velocity_min = 28.0
	em.initial_velocity_max = 70.0
	em.gravity = Vector3(6, -14, 0)
	em.scale_min = 0.12
	em.scale_max = 0.4
	em.color = Color(1.0, 0.6, 0.25, 0.5)
	embers.process_material = em
	var dot := GradientTexture2D.new()
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	embers.texture = dot
	embers.position = Vector2(640, 760)
	menu_root.add_child(embers)

	# --- боковая панель ---
	var side := PanelContainer.new()
	side.anchor_bottom = 1.0
	side.offset_left = 36
	side.offset_top = 36
	side.offset_bottom = -36
	side.custom_minimum_size = Vector2(300, 0)
	menu_root.add_child(side)
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	side.add_child(side_box)

	side_box.add_child(_spacer(16))
	side_box.add_child(_title_label(tr("ГНОМОБОЙ"), 42))
	var ver := _title_label(tr("Осколки Сердца Горы"), 13, Color(0.7, 0.72, 0.75))
	side_box.add_child(ver)
	var version_str: String = ProjectSettings.get_setting("application/config/version", "")
	if version_str != "":
		side_box.add_child(_title_label("v%s" % version_str, 12, Color(0.5, 0.52, 0.56)))
	side_box.add_child(_spacer(26))

	for entry in [["play", "ИГРАТЬ"], ["mp", "МУЛЬТИПЛЕЕР"], ["achievements", "ДОСТИЖЕНИЯ"], ["settings", "НАСТРОЙКИ"]]:
		var b := Button.new()
		b.text = tr(entry[1])
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 21)
		side_box.add_child(b)
		_nav_buttons[entry[0]] = b
		var sec: String = entry[0]
		b.pressed.connect(func(): _show_section(sec))

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_box.add_child(stretch)
	var b_quit := Button.new()
	b_quit.text = tr("ВЫХОД")
	b_quit.custom_minimum_size = Vector2(0, 48)
	b_quit.add_theme_font_size_override("font_size", 19)
	side_box.add_child(b_quit)
	b_quit.pressed.connect(func():
		Settings.flush_pending() # не потерять только что изменённую настройку
		get_tree().quit())
	side_box.add_child(_spacer(10))
	side_box.add_child(_title_label(
		tr("WASD · ЛКМ/ПКМ · Пробел · E · V · T · C"), 12, Color(0.55, 0.58, 0.62)))

	# --- область контента ---
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 372
	content.offset_top = 36
	content.offset_right = -36
	content.offset_bottom = -36
	menu_root.add_child(content)

	_sections["play"] = _build_play_section(content)
	_sections["mp"] = _build_mp_section(content)
	_sections["achievements"] = _build_achievements_section(content)
	_sections["settings"] = _build_settings_section(content)

	# общий статус внизу
	status_label = _title_label("", 15, Color(1, 0.6, 0.5))
	status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.position = Vector2(-400, -14)
	status_label.size = Vector2(800, 24)
	menu_root.add_child(status_label)

	# меню пересобирается (смена языка и т.п.) — не подключаемся повторно
	if not Save.slots_changed.is_connected(_refresh_slot_cards):
		Save.slots_changed.connect(_refresh_slot_cards)
	_show_section(_current_section)


# ===== ДОСТИЖЕНИЯ =====
func _build_achievements_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("ДОСТИЖЕНИЯ")))
	_ach_progress_label = _title_label("", 15, Color(0.7, 0.9, 0.7))
	box.add_child(_ach_progress_label)
	box.add_child(_spacer(6))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 8)
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ach_list)
	_refresh_achievements_panel()
	return root


func _refresh_achievements_panel() -> void:
	if _ach_list == null:
		return
	var lore_p: Vector2i = Achievements.lore_progress()
	_ach_progress_label.text = tr("Открыто: %d из %d  ·  лор мира: %d из %d") % [
		Achievements.count_unlocked(), Achievements.DEFS.size(), lore_p.x, lore_p.y]
	for c in _ach_list.get_children():
		c.queue_free()
	for id in Achievements.DEFS:
		var def: Dictionary = Achievements.DEFS[id]
		var got: bool = Achievements.is_unlocked(id)
		var row := PanelContainer.new()
		_ach_list.add_child(row)
		var row_box := VBoxContainer.new()
		row_box.add_theme_constant_override("separation", 2)
		row.add_child(row_box)
		var name_l := Label.new()
		name_l.text = ("✓ " if got else "🔒 ") + tr(def.name)
		name_l.add_theme_font_size_override("font_size", 18)
		name_l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4) if got else Color(0.6, 0.6, 0.6))
		row_box.add_child(name_l)
		var desc_l := Label.new()
		desc_l.text = tr(def.desc)
		desc_l.add_theme_font_size_override("font_size", 13)
		desc_l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65) if got else Color(0.5, 0.5, 0.5))
		row_box.add_child(desc_l)


func _section_root(content: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	panel.set_meta("box", box)
	return box


# ===== ИГРАТЬ =====
func _build_play_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("ИГРАТЬ")))
	_name_row(box)

	var mrow := _row(box, tr("Режим:"))
	var smode_opt := OptionButton.new()
	smode_opt.add_item(tr("Сюжет — Осколки Сердца Горы"), 0)
	smode_opt.add_item(tr("Волны — выживание"), 1)
	smode_opt.custom_minimum_size = Vector2(340, 40)
	mrow.add_child(smode_opt)

	box.add_child(_spacer(4))
	_slots_block(box)

	_restart_campaign_cb = CheckBox.new()
	_restart_campaign_cb.text = tr("Начать кампанию заново (герой сохранится)")
	_restart_campaign_cb.add_theme_font_size_override("font_size", 14)
	box.add_child(_restart_campaign_cb)
	_restart_campaign_cb.visible = Save.has_campaign()

	_difficulty_row(box)
	_biome_row(box)
	box.add_child(_title_label(tr("(в сюжете локации идут по главам)"), 12, Color(0.6, 0.62, 0.66)))

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(stretch)
	var b_go := _styled_button(tr("В БОЙ"))
	b_go.custom_minimum_size = Vector2(0, 56)
	box.add_child(b_go)
	b_go.pressed.connect(func():
		var story: bool = smode_opt.selected == 0
		if story and _restart_campaign_cb.button_pressed:
			Save.reset_campaign()
		Net.continue_campaign = Save.has_campaign()
		Net.start_single("story" if story else "pve")
		enter_game())
	return root


# ===== МУЛЬТИПЛЕЕР =====
func _build_mp_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("МУЛЬТИПЛЕЕР")))
	box.add_child(_title_label(tr("Кроссплей Windows и Linux. Порты или Radmin VPN."), 13, Color(0.7, 0.8, 0.7)))
	_name_row(box)
	box.add_child(_spacer(4))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	# --- создать сервер ---
	var host_panel := PanelContainer.new()
	host_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_panel.size_flags_stretch_ratio = 1.0
	host_panel.custom_minimum_size = Vector2(380, 0)
	host_panel.clip_contents = true
	host_panel.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.BG_CARD, 12))
	cols.add_child(host_panel)
	var hbox := VBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	host_panel.add_child(hbox)
	hbox.add_child(_title_label(tr("СОЗДАТЬ СЕРВЕР"), 22))
	var hm := _row(hbox, tr("Режим:"), 90)
	var mode_opt := OptionButton.new()
	mode_opt.add_item(tr("Сюжет — кооператив"), 0)
	mode_opt.add_item(tr("ПвЕ — вместе против волн"), 1)
	mode_opt.add_item(tr("ПвП — арена с руинами, до 10 убийств"), 2)
	mode_opt.custom_minimum_size = Vector2(240, 40)
	mode_opt.fit_to_longest_item = false
	hm.add_child(mode_opt)
	# тип сессии для приглашений через Discord
	var hs := _row(hbox, tr("Сессия:"), 90)
	var sess_opt := OptionButton.new()
	sess_opt.add_item(tr("Открытая — друзья могут зайти из Discord"), 0)
	sess_opt.add_item(tr("Приватная — только по прямому IP"), 1)
	sess_opt.custom_minimum_size = Vector2(240, 40)
	sess_opt.fit_to_longest_item = false
	hs.add_child(sess_opt)
	_difficulty_row(hbox, 90)
	var hp_row := _row(hbox, tr("Порт:"), 90)
	var hport_edit := LineEdit.new()
	hport_edit.text = str(Net.DEFAULT_PORT)
	hport_edit.custom_minimum_size = Vector2(120, 40)
	hp_row.add_child(hport_edit)
	var slot_lbl := _title_label("", 13, Color(0.75, 0.85, 0.75))
	hbox.add_child(slot_lbl)
	var refresh_slot := func():
		var info: Dictionary = Save.slot_info(Save.active_slot)
		var suffix: String = (" · " + tr("Глава %d") % info.chapter) if not info.is_empty() else ""
		slot_lbl.text = tr("Сохранение: слот %d") % Save.active_slot + suffix
	refresh_slot.call()
	Save.slots_changed.connect(refresh_slot)
	slot_lbl.tree_exiting.connect(func(): Save.slots_changed.disconnect(refresh_slot))
	var ips_lbl := _title_label(_local_ips_text(), 12, Color(0.7, 0.8, 0.7))
	ips_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(ips_lbl)
	var hstretch := Control.new()
	hstretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(hstretch)
	var b_host_go := _styled_button(tr("ЗАПУСТИТЬ СЕРВЕР"))
	hbox.add_child(b_host_go)
	b_host_go.pressed.connect(func():
		var port := int(hport_edit.text)
		if port < 1024 or port > 65535:
			_set_status(tr("Некорректный порт."))
			return
		var mode_name: String = ["story", "pve", "pvp"][mode_opt.selected]
		Net.continue_campaign = Save.has_campaign()
		var err := Net.start_host(port, mode_name, sess_opt.selected == 1)
		if err != OK:
			_set_status(tr("Не удалось открыть порт %d (занят?).") % port)
			return
		enter_game())

	# --- присоединиться ---
	var join_panel := PanelContainer.new()
	join_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_panel.size_flags_stretch_ratio = 1.0
	join_panel.custom_minimum_size = Vector2(380, 0)
	join_panel.clip_contents = true
	join_panel.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.BG_CARD, 12))
	cols.add_child(join_panel)
	var jbox := VBoxContainer.new()
	jbox.add_theme_constant_override("separation", 8)
	join_panel.add_child(jbox)
	jbox.add_child(_title_label(tr("ПРИСОЕДИНИТЬСЯ"), 22))
	var jip_row := _row(jbox, tr("IP сервера:"), 110)
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(180, 40)
	jip_row.add_child(ip_edit)
	var jp_row := _row(jbox, tr("Порт:"), 110)
	var jport_edit := LineEdit.new()
	jport_edit.text = str(Net.DEFAULT_PORT)
	jport_edit.custom_minimum_size = Vector2(120, 40)
	jp_row.add_child(jport_edit)
	var jhint := _title_label(tr("Интернет: IP хоста (нужен проброс порта)
Radmin VPN / Hamachi / LAN: IP из сети VPN (26.x.x.x и т.п.)"), 12, Color(0.7, 0.8, 0.7))
	jhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jbox.add_child(jhint)
	var jhero := _title_label(tr("Твой герой придёт из активного слота сохранения."), 12, Color(0.75, 0.85, 0.75))
	jhero.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jbox.add_child(jhero)
	var jstretch := Control.new()
	jstretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jbox.add_child(jstretch)
	var b_join_go := _styled_button(tr("ПОДКЛЮЧИТЬСЯ"))
	jbox.add_child(b_join_go)
	b_join_go.pressed.connect(func():
		var err := Net.start_client(ip_edit.text.strip_edges(), int(jport_edit.text))
		if err != OK:
			_set_status(tr("Некорректный адрес."))
			return
		_set_status(tr("Подключение к %s...") % ip_edit.text))
	return root


# ===== НАСТРОЙКИ (раздел меню) =====
func _build_settings_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("НАСТРОЙКИ")))
	var tabs := _build_settings_content()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	return root


## Вкладки настроек: используются и в меню, и в оверлее паузы.
func _build_settings_content() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 430)

	# --- Общие ---
	var t_common := VBoxContainer.new()
	t_common.name = tr("Общие")
	t_common.add_theme_constant_override("separation", 10)
	tabs.add_child(t_common)
	t_common.add_child(_spacer(8))
	var lang_row := _row(t_common, tr("Язык:"))
	var lang_opt := OptionButton.new()
	lang_opt.add_item("Русский", 0)
	lang_opt.add_item("Українська", 1)
	lang_opt.add_item("English", 2)
	var lang_ids := ["ru", "uk", "en"]
	lang_opt.selected = maxi(0, lang_ids.find(Settings.language))
	lang_opt.custom_minimum_size = Vector2(200, 40)
	lang_row.add_child(lang_opt)
	lang_opt.item_selected.connect(func(i: int):
		Settings.language = lang_ids[i]
		Settings.apply_and_save()
		_rebuild_ui())
	t_common.add_child(_spacer(10))
	var dc_check := _settings_check(t_common, tr("Discord: показывать статус игры"), Settings.discord_enabled)
	dc_check.toggled.connect(func(on: bool):
		Settings.discord_enabled = on
		Settings.apply_and_save())
	# свой Application ID (discord.com/developers) — под ним Discord покажет имя
	# твоего приложения; пусто = встроенный ID по умолчанию
	var dc_id_row := HBoxContainer.new()
	dc_id_row.add_theme_constant_override("separation", 10)
	t_common.add_child(dc_id_row)
	var dc_id_lbl := Label.new()
	dc_id_lbl.text = tr("Discord Application ID:")
	dc_id_lbl.add_theme_font_size_override("font_size", 17)
	dc_id_lbl.custom_minimum_size = Vector2(240, 0)
	dc_id_row.add_child(dc_id_lbl)
	var dc_id_edit := LineEdit.new()
	dc_id_edit.text = Settings.discord_app_id
	dc_id_edit.placeholder_text = tr("свой ID или пусто")
	dc_id_edit.custom_minimum_size = Vector2(280, 34)
	dc_id_row.add_child(dc_id_edit)
	dc_id_edit.text_changed.connect(func(t: String):
		Settings.discord_app_id = t.strip_edges())
	dc_id_edit.text_submitted.connect(func(_t: String):
		Settings.apply_and_save())
	dc_id_edit.focus_exited.connect(func():
		Settings.apply_and_save())
	var dc_hint := Label.new()
	dc_hint.text = tr("Для кнопки трансляции добавь игру в Discord: Настройки → Зарегистрированные игры → «Добавьте её!».")
	dc_hint.add_theme_font_size_override("font_size", 12)
	dc_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	dc_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dc_hint.custom_minimum_size = Vector2(540, 0)
	t_common.add_child(dc_hint)

	# --- Графика ---
	var t_gfx := VBoxContainer.new()
	t_gfx.name = tr("Графика")
	t_gfx.add_theme_constant_override("separation", 10)
	tabs.add_child(t_gfx)
	t_gfx.add_child(_spacer(8))
	var fs_check := _settings_check(t_gfx, tr("Полный экран"), Settings.fullscreen)
	fs_check.toggled.connect(func(on: bool):
		Settings.fullscreen = on
		Settings.apply_and_save())
	var vs_check := _settings_check(t_gfx, tr("Вертикальная синхронизация"), Settings.vsync)
	vs_check.toggled.connect(func(on: bool):
		Settings.vsync = on
		Settings.apply_and_save())
	var fps_check := _settings_check(t_gfx, tr("Счётчик FPS"), Settings.show_fps)
	fps_check.toggled.connect(func(on: bool):
		Settings.show_fps = on
		Settings.apply_and_save())
	var rs_slider := _settings_slider(t_gfx, tr("Масштаб 3D-рендера"), 50.0, 100.0, Settings.render_scale * 100.0, "%")
	rs_slider.value_changed.connect(func(v: float):
		Settings.render_scale = v / 100.0
		Settings.apply_and_save())
	var msaa_row := _row(t_gfx, tr("Сглаживание (MSAA):"))
	var msaa_opt := OptionButton.new()
	msaa_opt.add_item(tr("Выкл"), 0)
	msaa_opt.add_item("2x", 1)
	msaa_opt.add_item("4x", 2)
	msaa_opt.selected = Settings.msaa
	msaa_opt.custom_minimum_size = Vector2(160, 40)
	msaa_row.add_child(msaa_opt)
	msaa_opt.item_selected.connect(func(i: int):
		Settings.msaa = i
		Settings.apply_and_save())
	var ssao_check := _settings_check(t_gfx, tr("Мягкое затенение (SSAO)"), Settings.ssao)
	ssao_check.toggled.connect(func(on: bool):
		Settings.ssao = on
		Settings.apply_and_save())
	var glow_check := _settings_check(t_gfx, tr("Свечение (bloom)"), Settings.glow)
	glow_check.toggled.connect(func(on: bool):
		Settings.glow = on
		Settings.apply_and_save())
	var shadow_row := _row(t_gfx, tr("Качество теней:"))
	var shadow_opt := OptionButton.new()
	shadow_opt.add_item(tr("Низкое"), 0)
	shadow_opt.add_item(tr("Среднее"), 1)
	shadow_opt.add_item(tr("Высокое"), 2)
	shadow_opt.selected = Settings.shadow_quality
	shadow_opt.custom_minimum_size = Vector2(200, 40)
	shadow_row.add_child(shadow_opt)
	shadow_opt.item_selected.connect(func(i: int):
		Settings.shadow_quality = i
		Settings.apply_and_save())

	# --- Звук ---
	var t_snd := VBoxContainer.new()
	t_snd.name = tr("Звук")
	t_snd.add_theme_constant_override("separation", 10)
	tabs.add_child(t_snd)
	t_snd.add_child(_spacer(8))
	var vol_slider := _settings_slider(t_snd, tr("Звуки игры"), 0.0, 100.0, Settings.master_volume * 100.0, "%")
	vol_slider.value_changed.connect(func(v: float):
		Settings.master_volume = v / 100.0
		Settings.apply_and_save())
	vol_slider.drag_ended.connect(func(_c): Sfx.play("pickup", -6.0))
	var mus_slider := _settings_slider(t_snd, tr("Громкость музыки"), 0.0, 100.0, Settings.music_volume * 100.0, "%")
	mus_slider.value_changed.connect(func(v: float):
		Settings.music_volume = v / 100.0
		Settings.apply_and_save())
	var voice_check := _settings_check(t_snd, tr("Голосовой чат (рация, удерживать %s)") % key_name("voice"), Settings.voice_enabled)
	voice_check.toggled.connect(func(on: bool):
		Settings.voice_enabled = on
		Settings.apply_and_save())
	var vvol_slider := _settings_slider(t_snd, tr("Громкость голоса"), 0.0, 100.0, Settings.voice_volume * 100.0, "%")
	vvol_slider.value_changed.connect(func(v: float):
		Settings.voice_volume = v / 100.0
		Settings.apply_and_save())
	var duck_check := _settings_check(t_snd, tr("Приглушать игру, когда говорят в рацию"), Settings.voice_duck)
	duck_check.toggled.connect(func(on: bool):
		Settings.voice_duck = on
		Settings.apply_and_save())

	# --- микрофон ---
	var mic_row := _row(t_snd, tr("Микрофон:"))
	var mic_opt := OptionButton.new()
	mic_opt.add_item(tr("Системный по умолчанию"), 0)
	var devices := AudioServer.get_input_device_list()
	var dev_ids := [""]
	for d in devices:
		mic_opt.add_item(d, dev_ids.size())
		dev_ids.append(d)
	mic_opt.selected = maxi(0, dev_ids.find(Settings.mic_device))
	mic_opt.custom_minimum_size = Vector2(300, 40)
	mic_opt.fit_to_longest_item = false
	mic_row.add_child(mic_opt)
	mic_opt.item_selected.connect(func(i: int):
		Settings.mic_device = dev_ids[i]
		Settings.apply_and_save()
		Voice.restart_mic())

	var gain_slider := _settings_slider(t_snd, tr("Усиление микрофона"), 50.0, 400.0, Settings.mic_gain * 100.0, "%")
	gain_slider.value_changed.connect(func(v: float):
		Settings.mic_gain = v / 100.0
		Settings.apply_and_save())

	var mic_test_row := HBoxContainer.new()
	mic_test_row.add_theme_constant_override("separation", 10)
	t_snd.add_child(mic_test_row)
	var b_mic_test := Button.new()
	b_mic_test.text = tr("▶ Проверить микрофон")
	b_mic_test.custom_minimum_size = Vector2(260, 40)
	b_mic_test.add_theme_font_size_override("font_size", 15)
	mic_test_row.add_child(b_mic_test)
	var mic_meter := ColorRect.new()
	mic_meter.custom_minimum_size = Vector2(160, 14)
	mic_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_meter.color = Color(0.15, 0.18, 0.24)
	mic_test_row.add_child(mic_meter)
	var mic_fill := ColorRect.new()
	mic_fill.position = Vector2(1, 1)
	mic_fill.size = Vector2(0, 12)
	mic_fill.color = Color(0.4, 0.95, 0.45)
	mic_meter.add_child(mic_fill)
	var mic_status := _title_label("", 13, Color(0.55, 1.0, 0.55))
	t_snd.add_child(mic_status)
	var sync_test_ui := func():
		b_mic_test.text = tr("■ Остановить проверку") if Voice.test_active else tr("▶ Проверить микрофон")
		mic_status.text = tr("Идёт проверка: говори в микрофон — услышишь себя") if Voice.test_active else ""
	sync_test_ui.call()
	b_mic_test.pressed.connect(func():
		Voice.toggle_mic_test()
		sync_test_ui.call())
	var level_cb := func(level: float):
		mic_fill.size.x = 158.0 * clampf(level, 0.0, 1.0)
	Voice.mic_level.connect(level_cb)
	# ВАЖНО: отписываемся, когда полоску удалят (иначе спам «Lambda capture freed»)
	mic_meter.tree_exiting.connect(func(): Voice.mic_level.disconnect(level_cb))

	# --- Управление ---
	var t_ctl := VBoxContainer.new()
	t_ctl.name = tr("Управление")
	t_ctl.add_theme_constant_override("separation", 8)
	tabs.add_child(t_ctl)
	t_ctl.add_child(_spacer(6))
	var sens_slider := _settings_slider(t_ctl, tr("Чувствительность мыши"), 20.0, 300.0, Settings.mouse_sens * 100.0, "%")
	sens_slider.value_changed.connect(func(v: float):
		Settings.mouse_sens = v / 100.0
		Settings.apply_and_save())
	var invert_check := _settings_check(t_ctl, tr("Инвертировать мышь по вертикали"), Settings.invert_y)
	invert_check.toggled.connect(func(on: bool):
		Settings.invert_y = on
		Settings.apply_and_save())
	t_ctl.add_child(_title_label(tr("Клик по кнопке — затем нажми новую клавишу (Esc — отмена)"), 12, Color(0.65, 0.65, 0.65)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	t_ctl.add_child(scroll)
	var keys_box := VBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 4)
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(keys_box)
	for entry in REBIND_ACTIONS:
		var action: String = entry[0]
		var krow := _row(keys_box, tr(entry[1]) + ":")
		var btn := Button.new()
		btn.text = key_name(action)
		btn.custom_minimum_size = Vector2(140, 34)
		btn.add_theme_font_size_override("font_size", 14)
		krow.add_child(btn)
		btn.pressed.connect(func():
			_finish_rebind()
			_rebind_action = action
			_rebind_button = btn
			btn.text = "...")
	return tabs



func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _local_ips_text() -> String:
	var ips: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127."):
			ips.append(addr)
	if ips.is_empty():
		return ""
	return tr("Твои адреса (дай другу нужный):") + "\n" + ", ".join(ips)


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
	_sections.clear()
	_nav_buttons.clear()
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


func _settings_slider(box: VBoxContainer, title: String, minv: float, maxv: float, value: float, suffix: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = title + ":"
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.custom_minimum_size = Vector2(240, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = 1.0
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "%d%s" % [roundi(value), suffix]
	val_lbl.add_theme_font_size_override("font_size", 15)
	val_lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(val_lbl)
	slider.value_changed.connect(func(v: float): val_lbl.text = "%d%s" % [roundi(v), suffix])
	return slider


func _settings_check(box: VBoxContainer, title: String, value: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = title
	check.button_pressed = value
	check.add_theme_font_size_override("font_size", 17)
	box.add_child(check)
	return check


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
