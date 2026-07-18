class_name SettingsUi
extends RefCounted
## Вкладки настроек (общие/графика/звук/управление): используются и в разделе
## меню, и в оверлее паузы. Ребинд клавиш обрабатывает Main (_input).

var main # Main-владелец: key_name(), ребинд-состояние, _rebuild_ui()


func _init(main_) -> void:
	main = main_


## Вкладки настроек: используются и в меню, и в оверлее паузы.
func build_content() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 430)

	# --- Общие ---
	var t_common := VBoxContainer.new()
	t_common.name = tr("Общие")
	t_common.add_theme_constant_override("separation", 10)
	tabs.add_child(t_common)
	t_common.add_child(main._spacer(8))
	var lang_row: HBoxContainer = main._row(t_common, tr("Язык:"))
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
		main._rebuild_ui())
	t_common.add_child(main._spacer(10))
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
	t_gfx.add_child(main._spacer(8))
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
	var msaa_row: HBoxContainer = main._row(t_gfx, tr("Сглаживание (MSAA):"))
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
	var shadow_row: HBoxContainer = main._row(t_gfx, tr("Качество теней:"))
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
	t_snd.add_child(main._spacer(8))
	var vol_slider := _settings_slider(t_snd, tr("Звуки игры"), 0.0, 100.0, Settings.master_volume * 100.0, "%")
	vol_slider.value_changed.connect(func(v: float):
		Settings.master_volume = v / 100.0
		Settings.apply_and_save())
	vol_slider.drag_ended.connect(func(_c): Sfx.play("pickup", -6.0))
	var mus_slider := _settings_slider(t_snd, tr("Громкость музыки"), 0.0, 100.0, Settings.music_volume * 100.0, "%")
	mus_slider.value_changed.connect(func(v: float):
		Settings.music_volume = v / 100.0
		Settings.apply_and_save())
	var voice_check := _settings_check(t_snd, tr("Голосовой чат (рация, удерживать %s)") % main.key_name("voice"), Settings.voice_enabled)
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
	var mic_row: HBoxContainer = main._row(t_snd, tr("Микрофон:"))
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
	var mic_status: Label = main._title_label("", 13, Color(0.55, 1.0, 0.55))
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
	t_ctl.add_child(main._spacer(6))
	var sens_slider := _settings_slider(t_ctl, tr("Чувствительность мыши"), 20.0, 300.0, Settings.mouse_sens * 100.0, "%")
	sens_slider.value_changed.connect(func(v: float):
		Settings.mouse_sens = v / 100.0
		Settings.apply_and_save())
	var invert_check := _settings_check(t_ctl, tr("Инвертировать мышь по вертикали"), Settings.invert_y)
	invert_check.toggled.connect(func(on: bool):
		Settings.invert_y = on
		Settings.apply_and_save())
	t_ctl.add_child(main._title_label(tr("Клик по кнопке — затем нажми новую клавишу (Esc — отмена)"), 12, Color(0.65, 0.65, 0.65)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	t_ctl.add_child(scroll)
	var keys_box := VBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 4)
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(keys_box)
	for entry in main.REBIND_ACTIONS:
		var action: String = entry[0]
		var krow: HBoxContainer = main._row(keys_box, tr(entry[1]) + ":")
		var btn := Button.new()
		btn.text = main.key_name(action)
		btn.custom_minimum_size = Vector2(140, 34)
		btn.add_theme_font_size_override("font_size", 14)
		krow.add_child(btn)
		btn.pressed.connect(func():
			main._finish_rebind()
			main._rebind_action = action
			main._rebind_button = btn
			btn.text = "...")
	return tabs


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
