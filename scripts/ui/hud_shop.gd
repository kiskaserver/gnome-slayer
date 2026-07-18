class_name HudShop
extends RefCounted
## Лавка торговца: покупка ассортимента и продажа трофеев.

var hud # Hud-владелец: виджеты добавляются его детьми, сигналы эмитятся его


func _init(hud_) -> void:
	hud = hud_


var shop_panel: Panel = null
var _shop_stock_box: VBoxContainer = null
var _shop_sell_box: VBoxContainer = null
var _shop_gold: Label = null
var _shop_stock_cache: Array = []


func _build_shop_panel() -> void:
	shop_panel = Panel.new()
	shop_panel.theme = UiTheme.get_theme()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.position = Vector2(-360, -260)
	shop_panel.size = Vector2(720, 520)
	shop_panel.visible = false
	hud.add_child(shop_panel)

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
			Items.RARITY_COLORS[rarity], func(): hud.shop_buy.emit(idx)))
	for i in inv.size():
		var item2: Dictionary = inv[i]
		var rarity2: int = clampi(int(item2.get("rarity", 0)), 0, 3)
		var cnt: int = int(item2.get("count", 1))
		var txt: String = tr(Items.def_name(item2)) + (" x%d" % cnt if cnt > 1 else "")
		var idx2 := i
		_shop_sell_box.add_child(_shop_row(txt, tr("+%d з.") % Items.sell_price(item2),
			Items.RARITY_COLORS[rarity2], func(): hud.shop_sell.emit(idx2)))


func close_shop() -> void:
	if shop_panel != null:
		shop_panel.visible = false
	hud.shop_closed.emit()


func is_shop_open() -> bool:
	return shop_panel != null and shop_panel.visible
