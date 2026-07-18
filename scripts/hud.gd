class_name Hud
extends CanvasLayer
## Игровой интерфейс: здоровье, счёт, баннеры, виньетка, табло игроков.

var hp_fill: ColorRect
var hp_back: ColorRect
var stam_back: ColorRect
var stam_fill: ColorRect
var tut_label: Label
var kills_label: Label
var wave_label: Label
var banner_label: Label
var combo_label: Label
var vignette: ColorRect
var crosshair: ColorRect
var score_box: VBoxContainer
var center_label: Label

var buffs_label: Label
var chat_box: VBoxContainer
var sys_box: VBoxContainer
var chat_input: LineEdit
var talkers_label: Label
var hotbar: HBoxContainer
var hint_label: Label
var revive_bar: ColorRect
var revive_fill: ColorRect
var _hp_tween: Tween = null
var _revive_tween: Tween = null
var _hotbar_slots: Array = []
var xp_fill: ColorRect
var level_label: Label
var quest_label: Label

# Панели вынесены в компоненты (scripts/ui/*): статы, инвентарь, лавка,
# диалоги/катсцены. Hud держит ядро (полосы, чат, хотбар, баннеры) и делегаты.
var stats_ui: HudStats
var inv_ui: HudInventory
var shop_ui: HudShop
var dialog_ui: HudDialog

signal dialog_closed(advance: String)
signal stat_alloc(stat: String)
signal skill_unlock(skill_id: String)
signal inv_equip(inv_idx: int)
signal inv_unequip(slot: String)
signal inv_drop(inv_idx: int)
signal shop_buy(stock_idx: int)
signal shop_sell(inv_idx: int)
signal shop_closed

var _stats_points_hint: Label

var _banner_tween: Tween
var _combo_tween: Tween
var _talkers: Dictionary = {} # имя -> ttl

signal chat_submitted(text: String)
signal chat_closed


func _ready() -> void:
	layer = 10
	stats_ui = HudStats.new(self)
	inv_ui = HudInventory.new(self)
	shop_ui = HudShop.new(self)
	dialog_ui = HudDialog.new(self)
	# единая тема для панельных элементов HUD
	var thm := UiTheme.get_theme()
	for c in []:
		pass

	# --- полоса здоровья ---
	var hp_wrap := Control.new()
	hp_wrap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_wrap.position = Vector2(24, -70)
	add_child(hp_wrap)

	var hp_title := Label.new()
	hp_title.text = tr("ЗДОРОВЬЕ")
	hp_title.add_theme_font_size_override("font_size", 13)
	hp_title.add_theme_color_override("font_color", Color(0.91, 0.89, 0.84))
	hp_wrap.add_child(hp_title)

	hp_back = ColorRect.new()
	hp_back.color = Color(0.06, 0.05, 0.05, 0.75)
	hp_back.position = Vector2(0, 22)
	hp_back.size = Vector2(320, 18)
	hp_wrap.add_child(hp_back)

	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.8, 0.25, 0.2)
	hp_fill.position = Vector2(2, 2)
	hp_fill.size = Vector2(316, 14)
	hp_back.add_child(hp_fill)

	# --- стамина (D1): тонкая полоса под здоровьем — бег и перекид тратят её ---
	stam_back = ColorRect.new()
	stam_back.color = Color(0.06, 0.05, 0.05, 0.7)
	stam_back.position = Vector2(0, 43)
	stam_back.size = Vector2(320, 10)
	hp_wrap.add_child(stam_back)
	stam_fill = ColorRect.new()
	stam_fill.color = Color(0.95, 0.85, 0.35)
	stam_fill.position = Vector2(1, 1)
	stam_fill.size = Vector2(318, 8)
	stam_back.add_child(stam_fill)

	# --- строка обучения: верх по центру, золотая, видна и в бою ---
	tut_label = Label.new()
	tut_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tut_label.position = Vector2(-460, 66)
	tut_label.size = Vector2(920, 28)
	tut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tut_label.add_theme_font_size_override("font_size", 17)
	tut_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	tut_label.add_theme_constant_override("outline_size", 8)
	tut_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	tut_label.text = ""
	add_child(tut_label)

	# --- счёт справа сверху ---
	kills_label = Label.new()
	kills_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kills_label.position = Vector2(-320, 16)
	kills_label.size = Vector2(300, 34)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_label.text = tr("Гномов убито: %d") % 0
	kills_label.add_theme_font_size_override("font_size", 26)
	add_child(kills_label)

	wave_label = Label.new()
	wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_label.position = Vector2(-320, 52)
	wave_label.size = Vector2(300, 24)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.text = ""
	wave_label.add_theme_font_size_override("font_size", 15)
	wave_label.modulate.a = 0.85
	add_child(wave_label)

	# --- табло игроков (мультиплеер) ---
	score_box = VBoxContainer.new()
	score_box.position = Vector2(24, 20)
	add_child(score_box)

	# --- баннер волны ---
	banner_label = Label.new()
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.position = Vector2(-400, 160)
	banner_label.size = Vector2(800, 80)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 52)
	banner_label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.78))
	banner_label.add_theme_constant_override("outline_size", 10)
	banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner_label.modulate.a = 0.0
	add_child(banner_label)

	# --- центральное сообщение (смерть/возрождение) ---
	center_label = Label.new()
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.position = Vector2(-400, -20)
	center_label.size = Vector2(800, 60)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 28)
	center_label.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	center_label.add_theme_constant_override("outline_size", 8)
	center_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	center_label.text = ""
	add_child(center_label)

	dialog_ui.build_cutscene_widgets()

	# --- комбо ---
	combo_label = Label.new()
	combo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	combo_label.position = Vector2(-200, -120)
	combo_label.size = Vector2(400, 40)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 24)
	combo_label.add_theme_color_override("font_color", Color(1, 0.84, 0.42))
	combo_label.add_theme_constant_override("outline_size", 8)
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	combo_label.modulate.a = 0.0
	add_child(combo_label)

	# --- виньетка урона ---
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.7, 0.05, 0.05, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	# --- прицел ---
	crosshair = ColorRect.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-3, -3)
	crosshair.size = Vector2(6, 6)
	crosshair.color = Color(1, 1, 1, 0.65)
	add_child(crosshair)

	# --- бафы над полосой здоровья ---
	buffs_label = Label.new()
	buffs_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	buffs_label.position = Vector2(24, -98)
	buffs_label.add_theme_font_size_override("font_size", 15)
	buffs_label.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	buffs_label.add_theme_constant_override("outline_size", 6)
	buffs_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(buffs_label)

	# --- системная лента слева (лут, квесты) ---
	sys_box = VBoxContainer.new()
	sys_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	sys_box.position = Vector2(24, -320)
	sys_box.add_theme_constant_override("separation", 2)
	add_child(sys_box)

	# --- чат игроков справа ---
	chat_box = VBoxContainer.new()
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chat_box.position = Vector2(-464, -320)
	chat_box.custom_minimum_size = Vector2(440, 0)
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_box.add_theme_constant_override("separation", 2)
	add_child(chat_box)

	chat_input = LineEdit.new()
	chat_input.theme = UiTheme.get_theme()
	chat_input.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chat_input.position = Vector2(-384, -140)
	chat_input.custom_minimum_size = Vector2(360, 34)
	chat_input.max_length = 120
	chat_input.placeholder_text = tr("Сообщение...")
	chat_input.visible = false
	add_child(chat_input)
	chat_input.text_submitted.connect(func(t: String):
		chat_submitted.emit(t)
		close_chat())
	chat_input.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
			close_chat())

	# --- опыт и уровень (над полосой здоровья) ---
	var xp_back := ColorRect.new()
	xp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	xp_back.position = Vector2(24, -78)
	xp_back.size = Vector2(320, 5)
	xp_back.color = Color(0.06, 0.05, 0.05, 0.75)
	add_child(xp_back)
	xp_fill = ColorRect.new()
	xp_fill.position = Vector2(1, 1)
	xp_fill.size = Vector2(0, 3)
	xp_fill.color = Color(1.0, 0.85, 0.35)
	xp_back.add_child(xp_fill)
	level_label = Label.new()
	level_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	level_label.position = Vector2(350, -86)
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	level_label.add_theme_constant_override("outline_size", 6)
	level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(level_label)

	# --- трекер квестов (сюжет) ---
	quest_label = Label.new()
	quest_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	quest_label.position = Vector2(24, 160)
	quest_label.add_theme_font_size_override("font_size", 15)
	quest_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	quest_label.add_theme_constant_override("outline_size", 7)
	quest_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(quest_label)

	dialog_ui.build_dialog_panel()

	# --- полоса прогресса поднятия ---
	revive_bar = ColorRect.new()
	revive_bar.set_anchors_preset(Control.PRESET_CENTER)
	revive_bar.position = Vector2(-160, 46)
	revive_bar.size = Vector2(320, 14)
	revive_bar.color = Color(0.06, 0.05, 0.05, 0.8)
	revive_bar.visible = false
	add_child(revive_bar)
	revive_fill = ColorRect.new()
	revive_fill.position = Vector2(2, 2)
	revive_fill.size = Vector2(0, 10)
	revive_fill.color = Color(0.45, 0.95, 0.5)
	revive_bar.add_child(revive_fill)

	# --- подсказка взаимодействия (над хотбаром) ---
	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-300, -96)
	hint_label.size = Vector2(600, 26)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 17)
	hint_label.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	hint_label.add_theme_constant_override("outline_size", 7)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(hint_label)

	# --- хотбар (инвентарь 1-5) ---
	hotbar = HBoxContainer.new()
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.position = Vector2(-140, -60)
	hotbar.add_theme_constant_override("separation", 8)
	add_child(hotbar)
	for i in 5:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(48, 48)
		slot.self_modulate = Color(1, 1, 1, 0.55)
		hotbar.add_child(slot)
		var key := Label.new()
		key.text = str(i + 1)
		key.position = Vector2(4, 0)
		key.add_theme_font_size_override("font_size", 11)
		key.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		slot.add_child(key)
		var icon := ColorRect.new()
		icon.position = Vector2(12, 14)
		icon.size = Vector2(24, 24)
		icon.visible = false
		slot.add_child(icon)
		var short := Label.new()
		short.name = "short"
		short.position = Vector2(12, 16)
		short.size = Vector2(24, 20)
		short.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		short.add_theme_font_size_override("font_size", 11)
		short.add_theme_constant_override("outline_size", 4)
		short.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		slot.add_child(short)
		var count := Label.new()
		count.name = "count"
		count.position = Vector2(28, 28)
		count.add_theme_font_size_override("font_size", 13)
		count.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
		count.add_theme_constant_override("outline_size", 5)
		count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		slot.add_child(count)
		_hotbar_slots.append({"panel": slot, "icon": icon, "short": short, "count": count})

	# --- кто говорит (рация) ---
	talkers_label = Label.new()
	talkers_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	talkers_label.position = Vector2(-300, 90)
	talkers_label.size = Vector2(600, 26)
	talkers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	talkers_label.add_theme_font_size_override("font_size", 15)
	talkers_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	talkers_label.add_theme_constant_override("outline_size", 6)
	talkers_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(talkers_label)

	_stats_points_hint = Label.new()
	_stats_points_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stats_points_hint.position = Vector2(24, -122)
	_stats_points_hint.add_theme_font_size_override("font_size", 14)
	_stats_points_hint.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_stats_points_hint.add_theme_constant_override("outline_size", 6)
	_stats_points_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(_stats_points_hint)

	# КРИТИЧНО: HUD не должен перехватывать мышь. В режиме захвата курсора
	# все события мыши приходят в центр экрана — прямо в прицел; Control с
	# фильтром STOP (по умолчанию у ColorRect) съедает их, ломая камеру и ЛКМ.
	_ignore_mouse_recursive(self)
	stats_ui.build()


# ---------------------------------------------------------------------------
# Делегаты панелей — реализация в scripts/ui/* (внешний API не менялся)
# ---------------------------------------------------------------------------
func toggle_stats(p: Dictionary) -> bool:
	return stats_ui.toggle_stats(p)


func refresh_stats(p: Dictionary) -> void:
	stats_ui.refresh_stats(p)


func is_stats_open() -> bool:
	return stats_ui.is_stats_open()


func toggle_inventory(inv: Array, equip: Dictionary) -> bool:
	return inv_ui.toggle_inventory(inv, equip)


func refresh_inventory(inv: Array, equip: Dictionary) -> void:
	inv_ui.refresh_inventory(inv, equip)


func is_inventory_open() -> bool:
	return inv_ui.is_inventory_open()


func open_shop(stock: Array, inv: Array, gold_now: int) -> void:
	shop_ui.open_shop(stock, inv, gold_now)


func refresh_shop(inv: Array, gold_now: int) -> void:
	shop_ui.refresh_shop(inv, gold_now)


func close_shop() -> void:
	shop_ui.close_shop()


func is_shop_open() -> bool:
	return shop_ui.is_shop_open()


func show_dialog(pages: Array, advance: String) -> void:
	dialog_ui.show_dialog(pages, advance)


func dialog_next() -> void:
	dialog_ui.dialog_next()


func close_dialog() -> void:
	dialog_ui.close_dialog()


func is_dialog_open() -> bool:
	return dialog_ui.is_dialog_open()


func cutscene_start() -> void:
	dialog_ui.cutscene_start()


func cutscene_end() -> void:
	dialog_ui.cutscene_end()


func cutscene_line(text: String) -> float:
	return dialog_ui.cutscene_line(text)


func set_stat_points(pts: int) -> void:
	_stats_points_hint.text = (tr("Очки характеристик: %d — нажми C") % pts) if pts > 0 else ""
	if is_stats_open():
		refresh_stats(Net.players.get(Net.my_id, {}))


func _process(delta: float) -> void:
	if _talkers.is_empty():
		if talkers_label.text != "":
			talkers_label.text = ""
		return
	var names: Array = []
	for n in _talkers.keys():
		_talkers[n] -= delta
		if _talkers[n] <= 0:
			_talkers.erase(n)
		else:
			names.append(n)
	talkers_label.text = ("🎙 " + ", ".join(names)) if not names.is_empty() else ""


func show_talker(name_: String) -> void:
	_talkers[name_] = 0.35


var _buffs_cache := ""


func set_buffs(buffs: Dictionary) -> void:
	var parts: Array = []
	var titles := {"rage": tr("Ярость"), "speed": tr("Скорость"), "shield": tr("Барьер"), "greatsword": tr("Великий меч")}
	for type in buffs:
		var left: float = buffs[type]
		if left >= 900.0:
			parts.append(titles.get(type, type))
		else:
			parts.append("%s %dс" % [titles.get(type, type), ceili(left)])
	var text := " · ".join(parts)
	if text != _buffs_cache:
		_buffs_cache = text
		buffs_label.text = text


func set_xp(level: int, xp: int, xp_next: int) -> void:
	level_label.text = tr("Ур. %d") % level
	xp_fill.size.x = 318.0 * clampf(float(xp) / xp_next, 0.0, 1.0)


func set_quest_lines(lines: Array) -> void:
	quest_label.text = "\n".join(lines)



func set_revive_progress(k: float) -> void:
	revive_bar.visible = k > 0.001
	if k <= 0.001:
		if _revive_tween != null and _revive_tween.is_valid():
			_revive_tween.kill()
		revive_fill.size.x = 0.0
		return
	if _revive_tween != null and _revive_tween.is_valid():
		_revive_tween.kill()
	# сервер шлёт прогресс редкими тиками — сглаживаем твином, иначе полоска дёргается ступеньками
	_revive_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	_revive_tween.tween_property(revive_fill, "size:x", 316.0 * clampf(k, 0.0, 1.0), 0.18)


func set_hint(text: String) -> void:
	if hint_label.text != text:
		hint_label.text = text


## Обновляет хотбар: inv — массив {type, count}.
func set_inventory(inv: Array) -> void:
	for i in _hotbar_slots.size():
		var s: Dictionary = _hotbar_slots[i]
		if i < inv.size():
			var def: Dictionary = Game.ITEM_DEFS.get(inv[i].type, {})
			s.icon.visible = true
			s.icon.color = def.get("color", Color.GRAY)
			s.short.text = tr(def.get("short", "?"))
			s.count.text = "x%d" % inv[i].count if inv[i].count > 1 else ""
			s.panel.self_modulate = Color(1, 1, 1, 0.9)
		else:
			s.icon.visible = false
			s.short.text = ""
			s.count.text = ""
			s.panel.self_modulate = Color(1, 1, 1, 0.45)


func add_chat(pname: String, text: String, system := false) -> void:
	var box := sys_box if system else chat_box
	var l := Label.new()
	l.text = ("%s: %s" % [pname, text]) if pname != "" else text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.5) if system else Color(0.95, 0.95, 0.95))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not system:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	while box.get_child_count() > 7:
		box.get_child(0).free()
	# твин на самой метке — при досрочном удалении строки он гаснет вместе с ней,
	# а не сыплет ошибками «tween target freed» в оживлённом чате
	var t := l.create_tween()
	t.tween_interval(9.0)
	t.tween_property(l, "modulate:a", 0.0, 1.5)
	t.tween_callback(l.queue_free)


func open_chat() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()


func close_chat() -> void:
	chat_input.visible = false
	chat_input.release_focus()
	chat_closed.emit()


func is_chat_open() -> bool:
	return chat_input.visible


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse_recursive(c)


## Строка текущего шага обучения; пустая — скрыта.
func set_tutorial(text: String) -> void:
	tut_label.text = text


## Полоса стамины: k в [0..1]; при истощении подсвечивается тревожным.
func set_stamina(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	stam_fill.size.x = 318.0 * k
	stam_fill.color = Color(0.95, 0.85, 0.35) if k > 0.25 else Color(1.0, 0.5, 0.2)


func set_hp(hp: int, max_hp: int) -> void:
	var k := clampf(float(hp) / max_hp, 0, 1)
	hp_fill.color = Color(0.85, 0.2, 0.16) if k >= 0.3 else Color(1.0, 0.25, 0.15)
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(hp_fill, "size:x", 316.0 * k, 0.2)


func set_kills(n: int) -> void:
	kills_label.text = tr("Гномов убито: %d") % n


func set_pvp_kills(n: int) -> void:
	kills_label.text = tr("Убийств: %d") % n


func set_wave(text: String) -> void:
	wave_label.text = text


func banner(text: String, hold := 1.8) -> void:
	banner_label.text = text
	if _banner_tween != null:
		_banner_tween.kill()
	banner_label.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_label, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.5)


func center_msg(text: String) -> void:
	center_label.text = text


func combo_flash(step: int) -> void:
	combo_label.text = tr("КРУШИТЕЛЬНЫЙ УДАР!") if step >= 3 else "x%d" % step
	if _combo_tween != null:
		_combo_tween.kill()
	combo_label.modulate.a = 1.0
	_combo_tween = create_tween()
	_combo_tween.tween_interval(0.5)
	_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.25)


func hurt_flash() -> void:
	vignette.color.a = 0.35
	var t := create_tween()
	t.tween_property(vignette, "color:a", 0.0, 0.4)


var _scores_sig := ""


func set_scores(players: Dictionary, pvp: bool, my_id: int) -> void:
	# не пересобирать табло, если ничего не изменилось (вызывается на каждый килл)
	var sig := str(players) + str(pvp)
	if sig == _scores_sig:
		return
	_scores_sig = sig
	for c in score_box.get_children():
		c.queue_free()
	if players.size() <= 1 and not pvp:
		return
	var ids := players.keys()
	ids.sort_custom(func(a, b): return players[a].kills > players[b].kills)
	for id in ids:
		var p: Dictionary = players[id]
		var l := Label.new()
		var marker := "► " if id == my_id else "   "
		if pvp:
			l.text = "%s%s — %d / %d" % [marker, p.name, p.kills, p.deaths]
		else:
			l.text = "%s%s — %d" % [marker, p.name, p.kills]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(1, 0.95, 0.75) if id == my_id else Color(0.9, 0.9, 0.9, 0.85))
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		score_box.add_child(l)
