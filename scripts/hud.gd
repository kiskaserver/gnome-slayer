class_name Hud
extends CanvasLayer
## Игровой интерфейс: здоровье, счёт, баннеры, виньетка, табло игроков.

var hp_fill: ColorRect
var hp_back: ColorRect
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
var dialog_panel: Panel
var letterbox_top: ColorRect
var letterbox_bottom: ColorRect
var subtitle_label: Label
var _letterbox_tween: Tween = null
var dialog_speaker: Label
var dialog_text: Label
var _dialog_pages: Array = []
var _dialog_page := 0
var _dialog_advance := ""

# --- "озвучка" репликами: буквы проступают постепенно под перестук-бип,
# как в старых играх, вместо мгновенного текста или ИИ-голоса ---
var _type_tween: Tween = null
var _type_target: Label = null
var _type_full := ""
var _type_last_count := 0
var _type_revealing := false

signal dialog_closed(advance: String)
signal stat_alloc(stat: String)
signal skill_unlock(skill_id: String)
signal inv_equip(inv_idx: int)
signal inv_unequip(slot: String)
signal inv_drop(inv_idx: int)
signal shop_buy(stock_idx: int)
signal shop_sell(inv_idx: int)
signal shop_closed

var stats_panel: Panel
var points_label: Label
var _stat_rows: Dictionary = {}
var _stats_points_hint: Label
var _skill_rows: Dictionary = {}  # skill_id -> {"btn": Button, "line": ColorRect}

var inv_panel: Panel = null
var _inv_grid: GridContainer = null
var _inv_equip_box: VBoxContainer = null
var _inv_tip: Label = null

var shop_panel: Panel = null
var _shop_stock_box: VBoxContainer = null
var _shop_sell_box: VBoxContainer = null
var _shop_gold: Label = null
var _shop_stock_cache: Array = []

var _banner_tween: Tween
var _combo_tween: Tween
var _talkers: Dictionary = {} # имя -> ttl

signal chat_submitted(text: String)
signal chat_closed


func _ready() -> void:
	layer = 10
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

	# --- катсцена: чёрные полосы и субтитры (портал в конце главы) ---
	letterbox_top = ColorRect.new()
	letterbox_top.color = Color(0, 0, 0, 1.0)
	letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	letterbox_top.offset_bottom = 0.0
	letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(letterbox_top)

	letterbox_bottom = ColorRect.new()
	letterbox_bottom.color = Color(0, 0, 0, 1.0)
	letterbox_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	letterbox_bottom.offset_top = 0.0
	letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(letterbox_bottom)

	subtitle_label = Label.new()
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_label.position = Vector2(-450, -140)
	subtitle_label.size = Vector2(900, 90)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_size_override("font_size", 26)
	subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	subtitle_label.add_theme_constant_override("outline_size", 8)
	subtitle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	subtitle_label.modulate.a = 0.0
	add_child(subtitle_label)

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

	# --- панель диалога ---
	dialog_panel = Panel.new()
	dialog_panel.theme = UiTheme.get_theme()
	dialog_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialog_panel.position = Vector2(-360, -230)
	dialog_panel.size = Vector2(720, 150)
	dialog_panel.visible = false
	add_child(dialog_panel)
	dialog_speaker = Label.new()
	dialog_speaker.position = Vector2(18, 10)
	dialog_speaker.add_theme_font_size_override("font_size", 18)
	dialog_speaker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	dialog_panel.add_child(dialog_speaker)
	dialog_text = Label.new()
	dialog_text.position = Vector2(18, 42)
	dialog_text.size = Vector2(684, 70)
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.add_theme_font_size_override("font_size", 17)
	dialog_panel.add_child(dialog_text)
	var dialog_hint := Label.new()
	dialog_hint.position = Vector2(18, 118)
	dialog_hint.add_theme_font_size_override("font_size", 13)
	dialog_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dialog_hint.text = tr("[E / ЛКМ] — далее")
	dialog_panel.add_child(dialog_hint)

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
	_build_stats_panel()


const STAT_DEFS := [
	["str", "Сила", "+6% урона"],
	["vit", "Живучесть", "+12 здоровья"],
	["agi", "Ловкость", "+4% скорости, быстрее кувырок"],
	["luck", "Удача", "+2% шанс крита"],
]


const COL_W := 170.0
const COL_X := [20.0, 195.0, 370.0, 545.0]

func _build_stats_panel() -> void:
	stats_panel = Panel.new()
	stats_panel.theme = UiTheme.get_theme()
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.position = Vector2(-368, -260)
	stats_panel.size = Vector2(736, 520)
	stats_panel.visible = false
	add_child(stats_panel)

	var title := Label.new()
	title.text = tr("ПЕРСОНАЖ")
	title.position = Vector2(0, 14)
	title.size = Vector2(736, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.91, 0.78))
	stats_panel.add_child(title)

	points_label = Label.new()
	points_label.position = Vector2(0, 50)
	points_label.size = Vector2(736, 24)
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_label.add_theme_font_size_override("font_size", 17)
	points_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	stats_panel.add_child(points_label)

	# --- дерево навыков: 4 колонки (str/vit/agi/luck), сверху корень-характеристика,
	# ниже — тир 1 и тир 2, ветвящиеся друг из друга. Тонкая линия — связь узлов.
	var root_y := 92.0
	for i in STAT_DEFS.size():
		var def: Array = STAT_DEFS[i]
		var stat: String = def[0]
		var cx: float = COL_X[i]

		var name_l := Label.new()
		name_l.text = tr(def[1])
		name_l.position = Vector2(cx, root_y)
		name_l.size = Vector2(COL_W - 50, 26)
		name_l.add_theme_font_size_override("font_size", 18)
		stats_panel.add_child(name_l)
		var val_l := Label.new()
		val_l.position = Vector2(cx, root_y + 24)
		val_l.size = Vector2(COL_W - 50, 20)
		val_l.add_theme_font_size_override("font_size", 15)
		val_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		stats_panel.add_child(val_l)
		var desc_l := Label.new()
		desc_l.text = tr(def[2])
		desc_l.position = Vector2(cx, root_y + 46)
		desc_l.size = Vector2(COL_W, 32)
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		stats_panel.add_child(desc_l)
		var btn := Button.new()
		btn.text = "+"
		btn.position = Vector2(cx + COL_W - 44, root_y)
		btn.size = Vector2(40, 36)
		btn.add_theme_font_size_override("font_size", 20)
		stats_panel.add_child(btn)
		btn.pressed.connect(func(): stat_alloc.emit(stat))
		_stat_rows[stat] = {"val": val_l, "btn": btn}

		# тир 1 и тир 2 того же дерева, найденные по branch/tier в общем списке
		var tier_y := root_y + 92.0
		for tier in [1, 2]:
			var skill_id := ""
			for sid in Skills.TREE:
				var sdef: Dictionary = Skills.TREE[sid]
				if sdef.branch == stat and sdef.tier == tier:
					skill_id = sid
					break
			if skill_id == "":
				continue
			var sdef: Dictionary = Skills.TREE[skill_id]

			var line := ColorRect.new()
			line.color = Color(0.5, 0.45, 0.3, 0.6)
			line.position = Vector2(cx + COL_W * 0.5 - 1, tier_y - 26)
			line.size = Vector2(2, 26)
			stats_panel.add_child(line)

			var sbtn := Button.new()
			sbtn.position = Vector2(cx, tier_y)
			sbtn.size = Vector2(COL_W, 56)
			sbtn.text = tr(sdef.name) + "\n" + tr(sdef.desc)
			sbtn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sbtn.add_theme_font_size_override("font_size", 12)
			stats_panel.add_child(sbtn)
			sbtn.pressed.connect(func(): skill_unlock.emit(skill_id))
			_skill_rows[skill_id] = {"btn": sbtn}
			tier_y += 76.0

	var hint := Label.new()
	hint.text = tr("[C / Esc] — закрыть")
	hint.position = Vector2(0, 488)
	hint.size = Vector2(736, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stats_panel.add_child(hint)


func refresh_stats(p: Dictionary) -> void:
	var pts: int = p.get("points", 0)
	points_label.text = tr("Свободных очков: %d") % pts
	for stat in _stat_rows:
		_stat_rows[stat].val.text = str(p.get(stat, 0))
		_stat_rows[stat].btn.disabled = pts <= 0
	for skill_id in _skill_rows:
		var btn: Button = _skill_rows[skill_id].btn
		if Skills.has(p, skill_id):
			btn.disabled = true
			btn.modulate = Color(0.55, 1.0, 0.65)
		elif Skills.can_unlock(p, skill_id) and pts > 0:
			btn.disabled = false
			btn.modulate = Color(1, 1, 1)
		else:
			btn.disabled = true
			btn.modulate = Color(0.6, 0.6, 0.6)


func toggle_stats(p: Dictionary) -> bool:
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		refresh_stats(p)
	return stats_panel.visible


func is_stats_open() -> bool:
	return stats_panel.visible


# ---------------------------------------------------------------------------
# Инвентарь и экипировка (клавиша I)
# ---------------------------------------------------------------------------
func _build_inv_panel() -> void:
	inv_panel = Panel.new()
	inv_panel.theme = UiTheme.get_theme()
	inv_panel.set_anchors_preset(Control.PRESET_CENTER)
	inv_panel.position = Vector2(-330, -250)
	inv_panel.size = Vector2(660, 500)
	inv_panel.visible = false
	add_child(inv_panel)

	var title := Label.new()
	title.text = tr("ИНВЕНТАРЬ")
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	inv_panel.add_child(title)

	# слоты экипировки слева
	_inv_equip_box = VBoxContainer.new()
	_inv_equip_box.position = Vector2(20, 60)
	_inv_equip_box.add_theme_constant_override("separation", 10)
	inv_panel.add_child(_inv_equip_box)

	# сетка предметов справа
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 5
	_inv_grid.position = Vector2(210, 60)
	_inv_grid.add_theme_constant_override("h_separation", 8)
	_inv_grid.add_theme_constant_override("v_separation", 8)
	inv_panel.add_child(_inv_grid)

	# тултип-строка внизу
	_inv_tip = Label.new()
	_inv_tip.position = Vector2(20, 440)
	_inv_tip.size = Vector2(620, 50)
	_inv_tip.add_theme_font_size_override("font_size", 14)
	_inv_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_tip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	inv_panel.add_child(_inv_tip)

	var hint := Label.new()
	hint.text = tr("ЛКМ — надеть/использовать · ПКМ — выбросить")
	hint.position = Vector2(20, 415)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	inv_panel.add_child(hint)


func _item_tip_text(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var rarity: int = clampi(int(item.get("rarity", 0)), 0, 3)
	var s: String = tr(Items.def_name(item)) + " — " + tr(Items.RARITY_NAMES[rarity])
	var af := Items.affix_text(item)
	if af != "":
		s += "  ·  " + af
	if item.get("kind", "") == "weapon":
		var cls: Dictionary = Items.WEAPONS.get(item.id, {})
		if not cls.is_empty():
			s += "  ·  " + tr("удар: %d/%d/%d") % [cls.combo[0].dmg, cls.combo[1].dmg, cls.combo[2].dmg]
	return s


func _inv_slot_button(item: Dictionary, label_when_empty: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 64)
	btn.clip_text = true
	if item.is_empty():
		btn.text = label_when_empty
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		btn.add_theme_font_size_override("font_size", 12)
	else:
		var rarity: int = clampi(int(item.get("rarity", 0)), 0, 3)
		var cnt: int = int(item.get("count", 1))
		btn.text = tr(Items.def_name(item)) + (" x%d" % cnt if cnt > 1 else "")
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Items.RARITY_COLORS[rarity])
		btn.mouse_entered.connect(func(): _inv_tip.text = _item_tip_text(item))
	return btn


func refresh_inventory(inv: Array, equip: Dictionary) -> void:
	if inv_panel == null:
		return
	for c in _inv_grid.get_children():
		c.queue_free()
	for c in _inv_equip_box.get_children():
		c.queue_free()
	# экипировка
	for slot in ["weapon", "trinket"]:
		var cap := Label.new()
		cap.text = tr("Оружие:") if slot == "weapon" else tr("Тринкет:")
		cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
		_inv_equip_box.add_child(cap)
		var item: Dictionary = equip.get(slot, {})
		var btn := _inv_slot_button(item, tr("пусто"))
		btn.custom_minimum_size = Vector2(170, 56)
		_inv_equip_box.add_child(btn)
		if not item.is_empty():
			var s: String = slot
			btn.pressed.connect(func(): inv_unequip.emit(s))
	# сетка (20 ячеек)
	for i in 20:
		var item: Dictionary = inv[i] if i < inv.size() else {}
		var btn := _inv_slot_button(item, "")
		_inv_grid.add_child(btn)
		if item.is_empty():
			btn.disabled = true
			btn.self_modulate = Color(1, 1, 1, 0.4)
			continue
		var idx := i
		btn.pressed.connect(func(): inv_equip.emit(idx))
		btn.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				inv_drop.emit(idx))


func toggle_inventory(inv: Array, equip: Dictionary) -> bool:
	if inv_panel == null:
		_build_inv_panel()
	inv_panel.visible = not inv_panel.visible
	if inv_panel.visible:
		_inv_tip.text = ""
		refresh_inventory(inv, equip)
	return inv_panel.visible


func is_inventory_open() -> bool:
	return inv_panel != null and inv_panel.visible


# ---------------------------------------------------------------------------
# Лавка торговца
# ---------------------------------------------------------------------------
func _build_shop_panel() -> void:
	shop_panel = Panel.new()
	shop_panel.theme = UiTheme.get_theme()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.position = Vector2(-360, -260)
	shop_panel.size = Vector2(720, 520)
	shop_panel.visible = false
	add_child(shop_panel)

	var title := Label.new()
	title.text = tr("ЛАВКА КРАМСА")
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	shop_panel.add_child(title)

	_shop_gold = Label.new()
	_shop_gold.position = Vector2(520, 16)
	_shop_gold.add_theme_font_size_override("font_size", 18)
	_shop_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	shop_panel.add_child(_shop_gold)

	var cap_buy := Label.new()
	cap_buy.text = tr("Товары:")
	cap_buy.position = Vector2(20, 52)
	cap_buy.add_theme_font_size_override("font_size", 15)
	shop_panel.add_child(cap_buy)
	var scroll_b := ScrollContainer.new()
	scroll_b.position = Vector2(20, 78)
	scroll_b.size = Vector2(330, 400)
	shop_panel.add_child(scroll_b)
	_shop_stock_box = VBoxContainer.new()
	_shop_stock_box.add_theme_constant_override("separation", 6)
	_shop_stock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_b.add_child(_shop_stock_box)

	var cap_sell := Label.new()
	cap_sell.text = tr("Твои трофеи (продажа):")
	cap_sell.position = Vector2(370, 52)
	cap_sell.add_theme_font_size_override("font_size", 15)
	shop_panel.add_child(cap_sell)
	var scroll_s := ScrollContainer.new()
	scroll_s.position = Vector2(370, 78)
	scroll_s.size = Vector2(330, 400)
	shop_panel.add_child(scroll_s)
	_shop_sell_box = VBoxContainer.new()
	_shop_sell_box.add_theme_constant_override("separation", 6)
	_shop_sell_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_s.add_child(_shop_sell_box)


func _shop_row(text: String, price_text: String, color: Color, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(200, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = price_text
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(96, 34)
	btn.pressed.connect(cb)
	row.add_child(btn)
	return row


func open_shop(stock: Array, inv: Array, gold_now: int) -> void:
	if shop_panel == null:
		_build_shop_panel()
	_shop_stock_cache = stock
	shop_panel.visible = true
	refresh_shop(inv, gold_now)


func refresh_shop(inv: Array, gold_now: int) -> void:
	if shop_panel == null or not shop_panel.visible:
		return
	_shop_gold.text = tr("Золото: %d") % gold_now
	for c in _shop_stock_box.get_children():
		c.queue_free()
	for c in _shop_sell_box.get_children():
		c.queue_free()
	for i in _shop_stock_cache.size():
		var entry: Dictionary = _shop_stock_cache[i]
		var item: Dictionary = entry.item
		var rarity: int = clampi(int(item.get("rarity", 0)), 0, 3)
		var name_txt: String = tr(Items.def_name(item))
		if item.kind != "consumable":
			name_txt += " (%s)" % tr(Items.RARITY_NAMES[rarity])
			var af := Items.affix_text(item)
			if af != "":
				name_txt += "\n" + af
		var idx := i
		_shop_stock_box.add_child(_shop_row(name_txt, tr("%d з.") % entry.price,
			Items.RARITY_COLORS[rarity], func(): shop_buy.emit(idx)))
	for i in inv.size():
		var item2: Dictionary = inv[i]
		var rarity2: int = clampi(int(item2.get("rarity", 0)), 0, 3)
		var cnt: int = int(item2.get("count", 1))
		var txt: String = tr(Items.def_name(item2)) + (" x%d" % cnt if cnt > 1 else "")
		var idx2 := i
		_shop_sell_box.add_child(_shop_row(txt, tr("+%d з.") % Items.sell_price(item2),
			Items.RARITY_COLORS[rarity2], func(): shop_sell.emit(idx2)))


func close_shop() -> void:
	if shop_panel != null:
		shop_panel.visible = false
	shop_closed.emit()


func is_shop_open() -> bool:
	return shop_panel != null and shop_panel.visible


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


func show_dialog(pages: Array, advance: String) -> void:
	_dialog_pages = pages
	_dialog_page = 0
	_dialog_advance = advance
	dialog_panel.visible = true
	_show_dialog_page()


func _show_dialog_page() -> void:
	var page: Array = _dialog_pages[_dialog_page]
	dialog_speaker.text = tr(page[0])
	_typewriter(dialog_text, tr(page[1]), 30.0)


func dialog_next() -> void:
	if _type_revealing:
		_type_skip()
		return
	_dialog_page += 1
	if _dialog_page >= _dialog_pages.size():
		close_dialog()
	else:
		_show_dialog_page()


## Постепенно проявляет text в label, играя короткий "бип" на части букв —
## ретро-озвучка речи без синтеза голоса и без готовых голосовых файлов.
## Возвращает длительность проявления в секундах.
func _typewriter(label: Label, text: String, cps: float) -> float:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_target = label
	_type_full = text
	_type_last_count = 0
	_type_revealing = true
	label.text = ""
	if text.is_empty():
		_type_revealing = false
		return 0.0
	var dur: float = maxf(text.length() / cps, 0.05)
	_type_tween = create_tween()
	_type_tween.tween_method(_type_reveal, 0.0, float(text.length()), dur)
	_type_tween.tween_callback(func(): _type_revealing = false)
	return dur


func _type_reveal(n: float) -> void:
	if _type_target == null:
		return
	var count := int(n)
	if count == _type_last_count:
		return
	_type_target.text = _type_full.substr(0, count)
	for i in range(_type_last_count, count):
		if i % 2 == 0:
			var ch := _type_full.unicode_at(i)
			if ch != 32 and ch != 10 and ch != 9:
				Sfx.play("blip", -9.0, randf_range(0.8, 1.3))
				break
	_type_last_count = count


func _type_skip() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	if _type_target != null:
		_type_target.text = _type_full
	_type_revealing = false


func close_dialog() -> void:
	dialog_panel.visible = false
	var adv := _dialog_advance
	_dialog_advance = ""
	dialog_closed.emit(adv)


func is_dialog_open() -> bool:
	return dialog_panel.visible


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
			s.short.text = def.get("short", "?")
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


## Катсцена конца главы: чёрные полосы наезжают сверху/снизу, а весь игровой
## интерфейс (полосы, счёт, бафы, квест-трекер, чат, хотбар...) скрывается
## целиком — на экране только полосы и субтитры, ничего не отвлекает.
func cutscene_start() -> void:
	if _letterbox_tween != null and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_letterbox_tween.tween_property(letterbox_top, "offset_bottom", 90.0, 0.6)
	_letterbox_tween.tween_property(letterbox_bottom, "offset_top", -90.0, 0.6)
	hp_back.get_parent().visible = false
	xp_fill.get_parent().visible = false
	kills_label.visible = false
	wave_label.visible = false
	hotbar.visible = false
	score_box.visible = false
	buffs_label.visible = false
	quest_label.visible = false
	level_label.visible = false
	crosshair.visible = false
	vignette.visible = false
	chat_box.visible = false
	sys_box.visible = false
	talkers_label.visible = false
	hint_label.visible = false
	revive_bar.visible = false
	chat_input.visible = false
	center_label.text = ""    # чтобы «ты пал...» не висело поверх катсцены
	banner_label.modulate.a = 0.0
	# незакрытый диалог закрываем ПРАВИЛЬНО — иначе теряется незавершённая сдача
	# квеста (dialog_closed → req_talk так и не отправится)
	if dialog_panel.visible:
		close_dialog()
	stats_panel.visible = false


func cutscene_end() -> void:
	if _letterbox_tween != null and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_letterbox_tween.tween_property(letterbox_top, "offset_bottom", 0.0, 0.5)
	_letterbox_tween.tween_property(letterbox_bottom, "offset_top", 0.0, 0.5)
	subtitle_label.modulate.a = 0.0
	if _type_tween != null and _type_tween.is_valid() and _type_target == subtitle_label:
		_type_tween.kill()
		_type_revealing = false
	hp_back.get_parent().visible = true
	xp_fill.get_parent().visible = true
	kills_label.visible = true
	wave_label.visible = true
	hotbar.visible = true
	score_box.visible = true
	buffs_label.visible = true
	quest_label.visible = true
	level_label.visible = true
	crosshair.visible = true
	vignette.visible = true
	chat_box.visible = true
	sys_box.visible = true
	talkers_label.visible = true
	hint_label.visible = true


const SUBTITLE_REVEAL_CPS := 24.0  # скорость проступания букв — неспешно, "по-старому"
const SUBTITLE_MIN_TIME := 3.0  # минимум на экране, даже для короткой строки
const SUBTITLE_READ_CPS := 13.0  # темп дочитывания уже полностью проявленного текста


## Показывает строку субтитров с плавным появлением/исчезновением; текст
## проступает по буквам под тот же ретро-бип, что и в диалогах. Время на
## экране считается от длины строки, чтобы длинную реплику успевали дочитать —
## возвращает, сколько секунд катсцена должна подождать перед следующей строкой.
func cutscene_line(text: String) -> float:
	var reveal_dur := _typewriter(subtitle_label, text, SUBTITLE_REVEAL_CPS)
	var total: float = maxf(SUBTITLE_MIN_TIME, text.length() / SUBTITLE_READ_CPS)
	total = maxf(total, reveal_dur + 0.8)
	var t := create_tween()
	t.tween_property(subtitle_label, "modulate:a", 1.0, 0.3)
	t.tween_interval(maxf(0.0, total - 0.3))
	t.tween_property(subtitle_label, "modulate:a", 0.0, 0.4)
	return total + 0.4


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
