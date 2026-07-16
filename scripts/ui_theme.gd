class_name UiTheme
extends RefCounted
## Единая тема интерфейса: скруглённые панели, акцентное золото, ховеры.

const ACCENT := Color(1.0, 0.8, 0.38)
const BG_PANEL := Color(0.09, 0.11, 0.15, 0.96)
const BG_CARD := Color(0.12, 0.15, 0.2, 0.92)

static var _cached: Theme = null


static func _box(color: Color, radius := 10, border := Color.TRANSPARENT, border_w := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	if border_w > 0:
		b.border_color = border
		b.set_border_width_all(border_w)
	return b


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()

	# кнопки
	t.set_stylebox("normal", "Button", _box(Color(0.15, 0.18, 0.24, 0.95), 9))
	t.set_stylebox("hover", "Button", _box(Color(0.2, 0.24, 0.32, 0.98), 9, ACCENT, 1))
	t.set_stylebox("pressed", "Button", _box(Color(0.1, 0.12, 0.16, 0.98), 9, ACCENT, 2))
	t.set_stylebox("focus", "Button", _box(Color(0.2, 0.24, 0.32, 0.0), 9, ACCENT.darkened(0.2), 1))
	t.set_stylebox("disabled", "Button", _box(Color(0.12, 0.13, 0.16, 0.6), 9))
	t.set_color("font_color", "Button", Color(0.93, 0.93, 0.9))
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))

	# панели
	t.set_stylebox("panel", "Panel", _box(BG_PANEL, 14))
	t.set_stylebox("panel", "PanelContainer", _box(BG_PANEL, 14))

	# поля ввода
	t.set_stylebox("normal", "LineEdit", _box(Color(0.07, 0.09, 0.12, 0.95), 8))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.08, 0.1, 0.14, 0.98), 8, ACCENT, 1))
	t.set_color("font_color", "LineEdit", Color(0.95, 0.95, 0.92))
	t.set_color("caret_color", "LineEdit", ACCENT)

	# выпадающие списки
	t.set_stylebox("normal", "OptionButton", _box(Color(0.13, 0.16, 0.22, 0.95), 8))
	t.set_stylebox("hover", "OptionButton", _box(Color(0.18, 0.22, 0.3, 0.98), 8, ACCENT, 1))
	t.set_stylebox("pressed", "OptionButton", _box(Color(0.1, 0.12, 0.16, 0.98), 8))
	t.set_stylebox("focus", "OptionButton", _box(Color(0, 0, 0, 0), 8, ACCENT.darkened(0.3), 1))
	t.set_color("font_color", "OptionButton", Color(0.93, 0.93, 0.9))
	t.set_color("font_hover_color", "OptionButton", ACCENT)

	# чекбоксы
	t.set_color("font_color", "CheckBox", Color(0.93, 0.93, 0.9))
	t.set_color("font_hover_color", "CheckBox", ACCENT)

	# вкладки
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.16, 0.2, 0.27, 1.0), 8, ACCENT, 2))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.1, 0.12, 0.16, 0.85), 8))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.16, 0.19, 0.25, 0.95), 8))
	t.set_stylebox("panel", "TabContainer", _box(Color(0.1, 0.12, 0.17, 0.9), 10))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", Color(0.8, 0.8, 0.8))
	t.set_font_size("font_size", "TabContainer", 17)

	# ползунки
	var groove := _box(Color(0.07, 0.09, 0.12, 0.9), 4)
	groove.content_margin_top = 2
	groove.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", groove)
	var grabbed := _box(ACCENT, 6)
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT.darkened(0.15), 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 4))

	_cached = t
	return t
