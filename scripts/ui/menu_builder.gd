class_name MenuBuilder
extends RefCounted
## Главное меню: боковая панель, разделы (играть/мультиплеер/достижения/
## настройки), карточки слотов сохранений. Общие UI-хелперы живут в Main.

var main # Main-владелец: menu_root/status_label и хелперы кнопок/строк

var _sections: Dictionary = {}
var _ach_progress_label: Label = null
var _ach_list: VBoxContainer = null
var _nav_buttons: Dictionary = {}
var _current_section := "play"
var _slot_cards: Array = []
var _restart_campaign_cb: CheckBox = null


func _init(main_) -> void:
	main = main_


## Сброс ссылок на узлы перед пересборкой меню (смена языка).
func reset() -> void:
	_sections.clear()
	_nav_buttons.clear()


## Совместимость со старым кодом страниц.
func show_page(page: String) -> void:
	show_section("play" if page in ["main", "play"] else ("mp" if page in ["mp", "host", "join"] else page))


func on_main_page() -> bool:
	return _current_section == "play"


func show_section(section: String) -> void:
	if section != "settings":
		Voice.stop_mic_test()
	if section == "achievements":
		refresh_achievements_panel()
	_current_section = section
	for key in _sections:
		_sections[key].visible = (key == section)
	for key in _nav_buttons:
		var btn: Button = _nav_buttons[key]
		btn.add_theme_color_override("font_color", UiTheme.ACCENT if key == section else Color(0.9, 0.9, 0.88))


func _h1(text: String) -> Label:
	return main._title_label(text, 38)


func _name_row(box: Container) -> void:
	var row: HBoxContainer = main._row(box, tr("Имя:"))
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
	var row: HBoxContainer = main._row(box, tr("Сложность:"), label_w)
	var opt := OptionButton.new()
	var ids := ["easy", "normal", "hard"]
	for i in ids.size():
		opt.add_item(tr(Quests.DIFFICULTIES[ids[i]].title), i)
	opt.selected = maxi(0, ids.find(Net.difficulty))
	opt.custom_minimum_size = Vector2(220, 40)
	row.add_child(opt)
	opt.item_selected.connect(func(i: int): Net.difficulty = ids[i])


func _biome_row(box: Container) -> void:
	var row: HBoxContainer = main._row(box, tr("Локация:"))
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
			refresh_slot_cards())
		b_del.pressed.connect(func():
			Save.delete_slot(slot_i)
			refresh_slot_cards())
		_slot_cards.append({"panel": card, "title": title, "info": info, "date": date, "del": b_del, "slot": slot_i})
	refresh_slot_cards()


func refresh_slot_cards() -> void:
	if main.menu_root == null or not main.menu_root.visible:
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
func build_menu() -> void:
	var menu_root := Control.new()
	main.menu_root = menu_root
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = UiTheme.get_theme()
	main.ui.add_child(menu_root)

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

	side_box.add_child(main._spacer(16))
	side_box.add_child(main._title_label(tr("ГНОМОБОЙ"), 42))
	var ver: Label = main._title_label(tr("Осколки Сердца Горы"), 13, Color(0.7, 0.72, 0.75))
	side_box.add_child(ver)
	var version_str: String = ProjectSettings.get_setting("application/config/version", "")
	if version_str != "":
		side_box.add_child(main._title_label("v%s" % version_str, 12, Color(0.5, 0.52, 0.56)))
	side_box.add_child(main._spacer(26))

	for entry in [["play", "ИГРАТЬ"], ["mp", "МУЛЬТИПЛЕЕР"], ["achievements", "ДОСТИЖЕНИЯ"], ["settings", "НАСТРОЙКИ"]]:
		var b := Button.new()
		b.text = tr(entry[1])
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 21)
		side_box.add_child(b)
		_nav_buttons[entry[0]] = b
		var sec: String = entry[0]
		b.pressed.connect(func(): show_section(sec))

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
		main.get_tree().quit())
	side_box.add_child(main._spacer(10))
	side_box.add_child(main._title_label(
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
	var status: Label = main._title_label("", 15, Color(1, 0.6, 0.5))
	main.status_label = status
	status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status.position = Vector2(-400, -14)
	status.size = Vector2(800, 24)
	menu_root.add_child(status)

	# меню пересобирается (смена языка и т.п.) — не подключаемся повторно
	if not Save.slots_changed.is_connected(refresh_slot_cards):
		Save.slots_changed.connect(refresh_slot_cards)
	show_section(_current_section)


# ===== ДОСТИЖЕНИЯ =====
func _build_achievements_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("ДОСТИЖЕНИЯ")))
	_ach_progress_label = main._title_label("", 15, Color(0.7, 0.9, 0.7))
	box.add_child(_ach_progress_label)
	box.add_child(main._spacer(6))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 8)
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ach_list)
	refresh_achievements_panel()
	return root


func refresh_achievements_panel() -> void:
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

	var mrow: HBoxContainer = main._row(box, tr("Режим:"))
	var smode_opt := OptionButton.new()
	smode_opt.add_item(tr("Сюжет — Осколки Сердца Горы"), 0)
	smode_opt.add_item(tr("Волны — выживание"), 1)
	smode_opt.custom_minimum_size = Vector2(340, 40)
	mrow.add_child(smode_opt)

	box.add_child(main._spacer(4))
	_slots_block(box)

	_restart_campaign_cb = CheckBox.new()
	_restart_campaign_cb.text = tr("Начать кампанию заново (герой сохранится)")
	_restart_campaign_cb.add_theme_font_size_override("font_size", 14)
	box.add_child(_restart_campaign_cb)
	_restart_campaign_cb.visible = Save.has_campaign()

	# повторное обучение — по желанию (D2: «и за кнопкой в меню»)
	var tut_cb := CheckBox.new()
	tut_cb.text = tr("Показать обучение снова")
	tut_cb.add_theme_font_size_override("font_size", 14)
	box.add_child(tut_cb)
	tut_cb.visible = Save.tutorial_done

	_difficulty_row(box)
	_biome_row(box)
	box.add_child(main._title_label(tr("(в сюжете локации идут по главам)"), 12, Color(0.6, 0.62, 0.66)))

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(stretch)
	var b_go: Button = main._styled_button(tr("В БОЙ"))
	b_go.custom_minimum_size = Vector2(0, 56)
	box.add_child(b_go)
	b_go.pressed.connect(func():
		var story: bool = smode_opt.selected == 0
		if story and _restart_campaign_cb.button_pressed:
			Save.reset_campaign()
		if story and tut_cb.button_pressed:
			Save.tutorial_done = false # только в памяти: завершение снова запишет флаг
		Net.continue_campaign = Save.has_campaign()
		Net.start_single("story" if story else "pve")
		main.enter_game())
	return root


# ===== МУЛЬТИПЛЕЕР =====
func _build_mp_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("МУЛЬТИПЛЕЕР")))
	box.add_child(main._title_label(tr("Кроссплей Windows и Linux. Порты или Radmin VPN."), 13, Color(0.7, 0.8, 0.7)))
	_name_row(box)
	box.add_child(main._spacer(4))

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
	hbox.add_child(main._title_label(tr("СОЗДАТЬ СЕРВЕР"), 22))
	var hm: HBoxContainer = main._row(hbox, tr("Режим:"), 90)
	var mode_opt := OptionButton.new()
	mode_opt.add_item(tr("Сюжет — кооператив"), 0)
	mode_opt.add_item(tr("ПвЕ — вместе против волн"), 1)
	mode_opt.add_item(tr("ПвП — арена с руинами, до 10 убийств"), 2)
	mode_opt.custom_minimum_size = Vector2(240, 40)
	mode_opt.fit_to_longest_item = false
	hm.add_child(mode_opt)
	# тип сессии для приглашений через Discord
	var hs: HBoxContainer = main._row(hbox, tr("Сессия:"), 90)
	var sess_opt := OptionButton.new()
	sess_opt.add_item(tr("Открытая — друзья могут зайти из Discord"), 0)
	sess_opt.add_item(tr("Приватная — только по прямому IP"), 1)
	sess_opt.custom_minimum_size = Vector2(240, 40)
	sess_opt.fit_to_longest_item = false
	hs.add_child(sess_opt)
	_difficulty_row(hbox, 90)
	var hp_row: HBoxContainer = main._row(hbox, tr("Порт:"), 90)
	var hport_edit := LineEdit.new()
	hport_edit.text = str(Net.DEFAULT_PORT)
	hport_edit.custom_minimum_size = Vector2(120, 40)
	hp_row.add_child(hport_edit)
	var slot_lbl: Label = main._title_label("", 13, Color(0.75, 0.85, 0.75))
	hbox.add_child(slot_lbl)
	var refresh_slot := func():
		var info: Dictionary = Save.slot_info(Save.active_slot)
		var suffix: String = (" · " + tr("Глава %d") % info.chapter) if not info.is_empty() else ""
		slot_lbl.text = tr("Сохранение: слот %d") % Save.active_slot + suffix
	refresh_slot.call()
	Save.slots_changed.connect(refresh_slot)
	slot_lbl.tree_exiting.connect(func(): Save.slots_changed.disconnect(refresh_slot))
	var ips_lbl: Label = main._title_label(_local_ips_text(), 12, Color(0.7, 0.8, 0.7))
	ips_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(ips_lbl)
	var hstretch := Control.new()
	hstretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(hstretch)
	var b_host_go: Button = main._styled_button(tr("ЗАПУСТИТЬ СЕРВЕР"))
	hbox.add_child(b_host_go)
	b_host_go.pressed.connect(func():
		var port := int(hport_edit.text)
		if port < 1024 or port > 65535:
			main._set_status(tr("Некорректный порт."))
			return
		var mode_name: String = ["story", "pve", "pvp"][mode_opt.selected]
		Net.continue_campaign = Save.has_campaign()
		var err := Net.start_host(port, mode_name, sess_opt.selected == 1)
		if err != OK:
			main._set_status(tr("Не удалось открыть порт %d (занят?).") % port)
			return
		main.enter_game())

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
	jbox.add_child(main._title_label(tr("ПРИСОЕДИНИТЬСЯ"), 22))
	var jip_row: HBoxContainer = main._row(jbox, tr("IP сервера:"), 110)
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(180, 40)
	jip_row.add_child(ip_edit)
	var jp_row: HBoxContainer = main._row(jbox, tr("Порт:"), 110)
	var jport_edit := LineEdit.new()
	jport_edit.text = str(Net.DEFAULT_PORT)
	jport_edit.custom_minimum_size = Vector2(120, 40)
	jp_row.add_child(jport_edit)
	var jhint: Label = main._title_label(tr("Интернет: IP хоста (нужен проброс порта)
Radmin VPN / Hamachi / LAN: IP из сети VPN (26.x.x.x и т.п.)"), 12, Color(0.7, 0.8, 0.7))
	jhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jbox.add_child(jhint)
	var jhero: Label = main._title_label(tr("Твой герой придёт из активного слота сохранения."), 12, Color(0.75, 0.85, 0.75))
	jhero.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jbox.add_child(jhero)
	var jstretch := Control.new()
	jstretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jbox.add_child(jstretch)
	var b_join_go: Button = main._styled_button(tr("ПОДКЛЮЧИТЬСЯ"))
	jbox.add_child(b_join_go)
	b_join_go.pressed.connect(func():
		var err := Net.start_client(ip_edit.text.strip_edges(), int(jport_edit.text))
		if err != OK:
			main._set_status(tr("Некорректный адрес."))
			return
		main._set_status(tr("Подключение к %s...") % ip_edit.text))
	return root


# ===== НАСТРОЙКИ (раздел меню) =====
func _build_settings_section(content: Control) -> Control:
	var box := _section_root(content)
	var root: Control = box.get_parent().get_parent()
	box.add_child(_h1(tr("НАСТРОЙКИ")))
	var tabs: TabContainer = main._build_settings_content()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	return root


func _local_ips_text() -> String:
	var ips: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.contains(".") and not addr.begins_with("127."):
			ips.append(addr)
	if ips.is_empty():
		return ""
	return tr("Твои адреса (дай другу нужный):") + "\n" + ", ".join(ips)
