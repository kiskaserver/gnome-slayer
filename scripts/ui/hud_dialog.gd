class_name HudDialog
extends RefCounted
## Диалоги с ретро-«озвучкой» (typewriter + бип) и катсцены
## (леттербокс, субтитры). Владеет своими виджетами.

var hud # Hud-владелец: виджеты добавляются его детьми, сигналы эмитятся его


func _init(hud_) -> void:
	hud = hud_


var dialog_panel: Panel
var dialog_speaker: Label
var dialog_text: Label
var letterbox_top: ColorRect
var letterbox_bottom: ColorRect
var subtitle_label: Label
var _letterbox_tween: Tween = null
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


## Леттербокс и субтитры. Зовётся из Hud._ready ровно в той точке порядка
## добавления детей, где виджеты жили раньше (z-порядок = порядок добавления).
func build_cutscene_widgets() -> void:
	# --- катсцена: чёрные полосы и субтитры (портал в конце главы) ---
	letterbox_top = ColorRect.new()
	letterbox_top.color = Color(0, 0, 0, 1.0)
	letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	letterbox_top.offset_bottom = 0.0
	letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(letterbox_top)

	letterbox_bottom = ColorRect.new()
	letterbox_bottom.color = Color(0, 0, 0, 1.0)
	letterbox_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	letterbox_bottom.offset_top = 0.0
	letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(letterbox_bottom)

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
	hud.add_child(subtitle_label)


func build_dialog_panel() -> void:
	# --- панель диалога ---
	dialog_panel = Panel.new()
	dialog_panel.theme = UiTheme.get_theme()
	dialog_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialog_panel.position = Vector2(-360, -230)
	dialog_panel.size = Vector2(720, 150)
	dialog_panel.visible = false
	hud.add_child(dialog_panel)
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
	_type_tween = hud.create_tween()
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
	hud.dialog_closed.emit(adv)


func is_dialog_open() -> bool:
	return dialog_panel.visible




## Катсцена конца главы: чёрные полосы наезжают сверху/снизу, а весь игровой
## интерфейс (полосы, счёт, бафы, квест-трекер, чат, хотбар...) скрывается
## целиком — на экране только полосы и субтитры, ничего не отвлекает.
func cutscene_start() -> void:
	if _letterbox_tween != null and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = hud.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_letterbox_tween.tween_property(letterbox_top, "offset_bottom", 90.0, 0.6)
	_letterbox_tween.tween_property(letterbox_bottom, "offset_top", -90.0, 0.6)
	hud.hp_back.get_parent().visible = false
	hud.xp_fill.get_parent().visible = false
	hud.kills_label.visible = false
	hud.wave_label.visible = false
	hud.hotbar.visible = false
	hud.score_box.visible = false
	hud.buffs_label.visible = false
	hud.quest_label.visible = false
	hud.level_label.visible = false
	hud.crosshair.visible = false
	hud.vignette.visible = false
	hud.chat_box.visible = false
	hud.sys_box.visible = false
	hud.talkers_label.visible = false
	hud.hint_label.visible = false
	hud.revive_bar.visible = false
	hud.chat_input.visible = false
	hud.center_label.text = ""    # чтобы «ты пал...» не висело поверх катсцены
	hud.banner_label.modulate.a = 0.0
	# незакрытый диалог закрываем ПРАВИЛЬНО — иначе теряется незавершённая сдача
	# квеста (dialog_closed → req_talk так и не отправится)
	if dialog_panel.visible:
		close_dialog()
	hud.stats_ui.stats_panel.visible = false


func cutscene_end() -> void:
	if _letterbox_tween != null and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = hud.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_letterbox_tween.tween_property(letterbox_top, "offset_bottom", 0.0, 0.5)
	_letterbox_tween.tween_property(letterbox_bottom, "offset_top", 0.0, 0.5)
	subtitle_label.modulate.a = 0.0
	if _type_tween != null and _type_tween.is_valid() and _type_target == subtitle_label:
		_type_tween.kill()
		_type_revealing = false
	hud.hp_back.get_parent().visible = true
	hud.xp_fill.get_parent().visible = true
	hud.kills_label.visible = true
	hud.wave_label.visible = true
	hud.hotbar.visible = true
	hud.score_box.visible = true
	hud.buffs_label.visible = true
	hud.quest_label.visible = true
	hud.level_label.visible = true
	hud.crosshair.visible = true
	hud.vignette.visible = true
	hud.chat_box.visible = true
	hud.sys_box.visible = true
	hud.talkers_label.visible = true
	hud.hint_label.visible = true


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
	var t := hud.create_tween()
	t.tween_property(subtitle_label, "modulate:a", 1.0, 0.3)
	t.tween_interval(maxf(0.0, total - 0.3))
	t.tween_property(subtitle_label, "modulate:a", 0.0, 0.4)
	return total + 0.4
