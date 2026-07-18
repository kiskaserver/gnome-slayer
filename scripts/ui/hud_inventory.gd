class_name HudInventory
extends RefCounted
## Инвентарь и экипировка (I): сетка 20 ячеек, слоты оружия/тринкета.

var hud # Hud-владелец: виджеты добавляются его детьми, сигналы эмитятся его


func _init(hud_) -> void:
	hud = hud_


var inv_panel: Panel = null
var _inv_grid: GridContainer = null
var _inv_equip_box: VBoxContainer = null
var _inv_tip: Label = null


func _build_inv_panel() -> void:
	inv_panel = Panel.new()
	inv_panel.theme = UiTheme.get_theme()
	inv_panel.set_anchors_preset(Control.PRESET_CENTER)
	inv_panel.position = Vector2(-330, -250)
	inv_panel.size = Vector2(660, 500)
	inv_panel.visible = false
	hud.add_child(inv_panel)

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
			btn.pressed.connect(func(): hud.inv_unequip.emit(s))
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
		btn.pressed.connect(func(): hud.inv_equip.emit(idx))
		btn.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				hud.inv_drop.emit(idx))


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
