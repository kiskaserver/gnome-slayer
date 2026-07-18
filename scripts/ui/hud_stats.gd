class_name HudStats
extends RefCounted
## Панель персонажа (C): характеристики и дерево навыков.

var hud # Hud-владелец: виджеты добавляются его детьми, сигналы эмитятся его


func _init(hud_) -> void:
	hud = hud_


var stats_panel: Panel
var points_label: Label
var _stat_rows: Dictionary = {}
var _skill_rows: Dictionary = {}  # skill_id -> {"btn": Button, "line": ColorRect}

const STAT_DEFS := [
	["str", "Сила", "+6% урона"],
	["vit", "Живучесть", "+12 здоровья"],
	["agi", "Ловкость", "+4% скорости, быстрее кувырок"],
	["luck", "Удача", "+2% шанс крита"],
]


const COL_W := 170.0
const COL_X := [20.0, 195.0, 370.0, 545.0]

func build() -> void:
	stats_panel = Panel.new()
	stats_panel.theme = UiTheme.get_theme()
	stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	stats_panel.position = Vector2(-368, -260)
	stats_panel.size = Vector2(736, 520)
	stats_panel.visible = false
	hud.add_child(stats_panel)

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
		btn.pressed.connect(func(): hud.stat_alloc.emit(stat))
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
			sbtn.pressed.connect(func(): hud.skill_unlock.emit(skill_id))
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
