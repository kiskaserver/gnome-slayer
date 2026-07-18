class_name TestHarness
extends Node
## Headless тест-харнес: --test / --test-story / --screenshot / --mphost / --mpjoin.
## Живёт ребёнком Main (наследует PROCESS_MODE_ALWAYS — тест паузы требует
## тикать при остановленном дереве) и тикается из Main._process.

var main: Node = null # Main: enter_game(), _show_section(), _open_settings()

var _test_mode := ""
var _test_timer := 0.0
var _test_log_timer := 0.0
var _test_input_checked := false
var _test_killed := false
var _test_chest := false
var _test_item_used := false
var _shot_stage := 0
var _test_gold_carry := 0
var _screenshot_path := ""
var _tod_override := -1.0
var _test_paused := false
var _pause_snapshot := {}
var _start_chapter := 1 # --chapter=N: сюжетный прогон с главы N (компоновка поздних глав)
var _test_stam_checked := false
var _test_parry_checked := false

var game: Game:
	get:
		return main.game


func handle_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test") or arg.begins_with("--mp") or arg.begins_with("--screenshot") or arg.begins_with("--shot"):
			Net.debug_log = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--biome="):
			Net.biome_choice = arg.get_slice("=", 1)
		elif arg.begins_with("--lang="):
			TranslationServer.set_locale(arg.get_slice("=", 1))
		elif arg == "--continue":
			Net.continue_campaign = true
		elif arg.begins_with("--difficulty="):
			Net.difficulty = arg.get_slice("=", 1)
		elif arg.begins_with("--tod="):
			_tod_override = float(arg.get_slice("=", 1))
		elif arg.begins_with("--chapter="):
			_start_chapter = clampi(int(arg.get_slice("=", 1)), 1, Quests.CHAPTERS.size())
	if Net.debug_log:
		# проверка переводов
		var prev_locale := TranslationServer.get_locale()
		TranslationServer.set_locale("en")
		print("[TEST] i18n en: %s | %s | %s" % [tr("ГНОМОБОЙ"), tr("Волна %d из %d") % [2, 7], tr("Зелье здоровья")])
		TranslationServer.set_locale("uk")
		print("[TEST] i18n uk: %s | %s | %s" % [tr("ГНОМОБОЙ"), tr("ЗДОРОВЬЕ"), tr("[%s] — открыть сундук") % "E"])
		TranslationServer.set_locale(prev_locale)
		_check_localization()
		_reset_test_saves()
	for arg in OS.get_cmdline_user_args():
		if arg == "--test":
			_test_mode = "single"
			Net.start_single("pve")
			main.enter_game()
		elif arg == "--test-tutorial":
			_test_mode = "tutorial"
			Net.start_single("story")
			main.enter_game()
		elif arg == "--test-story":
			_test_mode = "story"
			if _start_chapter > 1:
				# тестовые сейвы уже сброшены — пишем чистый слот с нужной главой
				Save.chapter = _start_chapter
				Save.write()
				Net.continue_campaign = true
			Net.start_single("story")
			main.enter_game()
		elif arg.begins_with("--screenshot="):
			_test_mode = "screenshot"
			_screenshot_path = arg.get_slice("=", 1)
			Net.start_single("story" if "--story" in OS.get_cmdline_user_args() else "pve")
			main.enter_game()
		elif arg.begins_with("--shot-menu="):
			_test_mode = "screenshot"
			_screenshot_path = arg.get_slice("=", 1)
			var sec := "mp"
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--section="):
					sec = a2.get_slice("=", 1)
			main._show_section(sec)
		elif arg.begins_with("--shot-settings="):
			_test_mode = "screenshot"
			_screenshot_path = arg.get_slice("=", 1)
			main._open_settings()
		elif arg.begins_with("--mphost"):
			_test_mode = "mphost"
			Net.my_name = "Хост"
			var mode_name := "pvp" if arg.ends_with("pvp") else ("story" if arg.ends_with("story") else "pve")
			var err := Net.start_host(7788, mode_name)
			print("[TEST] host start err=", err, " mode=", mode_name)
			main.enter_game()
		elif arg == "--mpjoin":
			_test_mode = "mpjoin"
			Net.my_name = "Клиент"
			var err := Net.start_client("127.0.0.1", 7788)
			print("[TEST] join start err=", err)


## Guard локализации: известные динамические строки (сырые id, короткие коды,
## имена предметов/аффиксов/рарностей) обязаны иметь перевод в uk и en.
## Ловит будущие пропуски автоматически: PASS=false, если tr(x) == x.
func _check_localization() -> void:
	var keys: Array = []
	for id in Items.CONSUMABLE_NAMES:
		keys.append(Items.CONSUMABLE_NAMES[id])
	for id in Items.WEAPONS:
		keys.append(Items.WEAPONS[id].name)
	for id in Items.TRINKETS:
		keys.append(Items.TRINKETS[id].name)
	for k in Items.AFFIX_POOL:
		keys.append(Items.AFFIX_POOL[k].title)
	for n in Items.RARITY_NAMES:
		keys.append(n)
	for id in Game.ITEM_DEFS:
		keys.append(Game.ITEM_DEFS[id].title)
		keys.append(Game.ITEM_DEFS[id].short)
	keys.append_array(["ЛКМ", "ПКМ", "СКМ", "Мышь %d", "Друг", "%s ПОБЕЖДАЕТ!", "гномы"])
	# Проверяем наличие ключа в каталоге локали, а не tr(x)==x: легитимно
	# одинаковые переводы ("Бомба" uk==ru) — не пропуск.
	var missing: Array = []
	for loc in ["uk", "en"]:
		var cat: Translation = TranslationServer.get_translation_object(loc)
		for k in keys:
			if cat == null or String(cat.get_message(k)).is_empty():
				missing.append("%s:%s" % [loc, k])
	print("[TEST] i18n guard: keys=%d missing=%d %s PASS=%s" % [
		keys.size() * 2, missing.size(), str(missing), str(missing.is_empty())])


## Герметичность прогонов: тестовые сейвы (test_*) переживают запуск и
## протаскивают экипировку/главу прошлого прогона в новый (например, арбалет,
## надетый в конце --test-story). Сносим их перед стартом; --continue
## намеренно продолжает прошлую кампанию — тогда не трогаем.
func _reset_test_saves() -> void:
	if Net.continue_campaign:
		return
	for i in range(1, Save.SLOTS + 1):
		if FileAccess.file_exists(Save.slot_path(i)):
			DirAccess.remove_absolute(Save.slot_path(i))
	if FileAccess.file_exists(Save.meta_path()):
		DirAccess.remove_absolute(Save.meta_path())
	Save.active_slot = 1
	Save.load_slot(Save.active_slot)


## Проверки генерации оверворлда (C3): компоновка, пересечения коллайдеров,
## связность по навсетке и плотность областей. Ждёт запечки навигации.
func _check_overworld_layout() -> void:
	print("[TEST] overworld: areas=%d road=%d entrance=%s PASS=%s" % [
		game.world_areas.size(), game.world_road.size(),
		str(game.dungeon_entrance != Vector3.INF),
		str(game.world_areas.size() >= 5 and game.world_road.size() >= 3 and game.dungeon_entrance != Vector3.INF)])
	# крупные объекты (здания/дома/POI/крипта, r>=2) не должны пересекаться
	# коллайдерами — это ловит «здание в здании»
	var big: Array = []
	for o in game.world_obstacles:
		if float(o.get("r", 0.0)) >= 2.0:
			big.append(o)
	var overlaps := 0
	for a in big.size():
		for b2 in range(a + 1, big.size()):
			var oa: Dictionary = big[a]
			var ob: Dictionary = big[b2]
			var d2: float = Vector2(oa.x - ob.x, oa.z - ob.z).length()
			if d2 < oa.r + ob.r - 0.3: # пересечение коллайдеров
				overlaps += 1
	print("[TEST] overworld: %d big props, %d collider overlaps PASS=%s" % [
		big.size(), overlaps, str(overlaps == 0)])
	# связность — от лагеря по навсетке достижимы центры всех областей и вход
	# в подземелье (иначе застройка перегородила путь). Запечка асинхронная.
	var nav_wait := 0.0
	while not game.nav_ready and nav_wait < 8.0:
		await get_tree().create_timer(0.5).timeout
		nav_wait += 0.5
	await get_tree().physics_frame # серверу навигации нужен синк после запечки
	await get_tree().physics_frame
	# исходная точка — первый вейпоинт дороги за сейф-зоной: гарантированно
	# основная плоскость навсетки, а не островок на крыше пропа
	var map_rid: RID = game.get_world_3d().navigation_map
	var road_p: Vector3 = game.world_road[1] if game.world_road.size() > 1 else Vector3.ZERO
	var from_p: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, road_p)
	var unreachable: Array = []
	for area in game.world_areas:
		if area.kind == "camp":
			continue # лагерь вырезан из навсетки сейф-зоной — старт и так тут
		var to_p: Vector3 = area.center
		var path := NavigationServer3D.map_get_path(map_rid, from_p, to_p, true)
		if path.is_empty() or Vector2(path[path.size() - 1].x - to_p.x, path[path.size() - 1].z - to_p.z).length() > 7.0:
			unreachable.append(area.id)
	var dpath := NavigationServer3D.map_get_path(map_rid, from_p, game.dungeon_entrance, true)
	var d_ok: bool = not dpath.is_empty() and Vector2(dpath[dpath.size() - 1].x - game.dungeon_entrance.x,
		dpath[dpath.size() - 1].z - game.dungeon_entrance.z).length() < 7.0
	print("[TEST] overworld: connectivity unreachable=%s entrance_path=%s PASS=%s" % [
		str(unreachable), str(d_ok), str(unreachable.is_empty() and d_ok)])
	# плотность — в каждой области (кроме лагеря) есть чем заняться:
	# домики-спавнеры, точки интереса, сундуки
	var sparse: Array = []
	for area in game.world_areas:
		if area.kind == "camp":
			continue
		var n_int := 0
		for h in game.houses:
			if h.get("area", "") == area.id:
				n_int += 1
		for poi in game.world_pois:
			if Vector2(poi.x - area.center.x, poi.z - area.center.z).length() < area.radius:
				n_int += 1
		for c2 in game.chests.values():
			if Vector2(c2.x - area.center.x, c2.z - area.center.z).length() < area.radius:
				n_int += 1
		# вход в подземелье — главный интерактив своей области (подход к склепу)
		if game.dungeon_entrance != Vector3.INF \
				and Vector2(game.dungeon_entrance.x - area.center.x, game.dungeon_entrance.z - area.center.z).length() < area.radius + 8.0:
			n_int += 1
		if n_int < 2:
			sparse.append("%s:%d" % [area.id, n_int])
	print("[TEST] overworld: density sparse=%s PASS=%s" % [str(sparse), str(sparse.is_empty())])


func tick(delta: float) -> void:
	if _test_mode == "":
		return
	_test_timer += delta
	_test_log_timer += delta

	# регрессионный тест ввода: HUD не должен съедать мышь
	if _test_mode == "single" and not _test_input_checked and _test_timer > 4.0 and game != null:
		_test_input_checked = true
		var me: PlayerChar = game.player_nodes.get(Net.my_id)
		if me != null:
			var yaw_before: float = me.cam_yaw.rotation.y
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(200, 0)
			motion.position = get_viewport().get_visible_rect().size / 2
			Input.parse_input_event(motion)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = motion.position
			Input.parse_input_event(click)
			get_tree().create_timer(0.5).timeout.connect(func():
				var yaw_moved: bool = absf(me.cam_yaw.rotation.y - yaw_before) > 0.01
				var attacked: bool = me.state == "attack" or me.combo_step > 0
				print("[TEST] input-check: camera=%s attack=%s (state=%s)" % [
					"PASS" if yaw_moved else "FAIL",
					"PASS" if attacked else "FAIL", me.state])
				# отпустить синтетический клик — иначе герой вечно копит замах
				var rel := InputEventMouseButton.new()
				rel.button_index = MOUSE_BUTTON_LEFT
				rel.pressed = false
				rel.position = click.position
				Input.parse_input_event(rel))

	if _tod_override >= 0 and game != null and game.daynight != null:
		game.daynight.time = _tod_override
		game.daynight._apply()

	if _test_mode == "screenshot" and "--stats" in OS.get_cmdline_user_args() \
			and _shot_stage == 0 and _test_timer > 0.5 and game != null:
		_shot_stage = 99
		Net.players[1].points = 3
		game.hud.toggle_stats(Net.players[1])

	# отладочный ракурс для проверки новых 3д-моделей: --poi=ruins|crypt|battlefield|...|portal
	if _test_mode == "screenshot" and game != null and game.is_story() and _shot_stage == 0 and _test_timer > 0.3:
		var poi_arg := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--poi="):
				poi_arg = a.get_slice("=", 1)
		if poi_arg != "":
			_shot_stage = 50
			var me5: PlayerChar = game.player_nodes.get(Net.my_id)
			if poi_arg == "portal":
				game._server_open_portal()
				me5.global_position = game.portal_pos + Vector3(0, 0.2, 4.0)
				me5.cam_yaw.rotation.y = PI
			else:
				for i in game.world_pois.size():
					var poi: Dictionary = game.world_pois[i]
					if poi.kind == poi_arg:
						me5.global_position = Vector3(poi.x, 0, poi.z) + Vector3(0, 0.2, 4.5)
						me5.cam_yaw.rotation.y = PI
						break
			print("[TEST] poi shot kinds available: %s" % str(game.world_pois.map(func(p): return p.kind)))

	if _test_mode == "screenshot":
		# сценка для скриншота: пара гномов гибнет в кадре (регдоллы)
		if _shot_stage == 0 and _test_timer > 0.8 and game != null and not game.is_story():
			_shot_stage = 1
			var roles: Dictionary = Game.BIOME_ENEMIES.get(Net.biome, Game.BIOME_ENEMIES["meadow"])
			game.server_spawn_gnome(roles.melee)
			game.server_spawn_gnome(roles.caster)
		elif _shot_stage == 1 and _test_timer > 1.9:
			_shot_stage = 2
			var me: PlayerChar = game.player_nodes.get(Net.my_id)
			# предметы в кадр: кристалл, меч, бочонок
			game.on_pickup_spawn(9001, "rage", me.global_position.x - 3.0, me.global_position.z - 2.0)
			game.on_pickup_spawn(9002, "greatsword", me.global_position.x + 3.0, me.global_position.z - 2.5)
			game.on_pickup_spawn(9003, "bomb", me.global_position.x, me.global_position.z - 1.5)
			var off := -2.0
			for g in game.gnomes.values():
				if g.alive:
					g.global_position = me.global_position + Vector3(off, 0, -4.0)
					g.facing = 0.0
					off += 4.0
		if _test_timer > 2.5:
			_test_mode = ""
			if "--nohud" in OS.get_cmdline_user_args() and game != null:
				game.hud.visible = false
				await get_tree().process_frame
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(_screenshot_path)
			print("[TEST] screenshot saved -> ", _screenshot_path)
			get_tree().quit()
		return

	if _test_log_timer >= 3.0:
		_test_log_timer = 0.0
		if game != null:
			var parts: Array = []
			for gid in game.gnomes:
				var g = game.gnomes[gid]
				parts.append("%s:%s:%s" % [g.type, g.state, str(g.global_position.snapped(Vector3.ONE * 0.1))])
			var hp_text := ""
			for id in game.player_nodes:
				hp_text += "P%d(hp=%d,st=%s) " % [id, game.server_hp.get(id, -1) if Net.is_server else game.player_nodes[id].hp, game.player_nodes[id].state]
			var inv_text := ""
			for slot in game.inventory:
				inv_text += "%s x%d " % [slot.get("id", slot.get("type", "?")), slot.get("count", 1)]
			print("[TEST] t=%.0f %s wave=%d biome=%s pickups=%d chests=%d inv=[%s] nav=%s gnomes=[%s]" % [
				_test_timer, hp_text, game.wave, Net.biome, game.pickups.size(), game.chests.size(), inv_text.strip_edges(), game.nav_ready, ", ".join(parts)])
		else:
			print("[TEST] t=%.0f (game=null)" % _test_timer)

	# проверка смертей: убить всех гномов, убедиться что трупы и хилки работают
	if _test_mode == "single" and not _test_killed and _test_timer > 19.0 and game != null and Net.is_server:
		_test_killed = true
		var me: PlayerChar = game.player_nodes.get(Net.my_id)
		var killed := 0
		for g in game.gnomes.values():
			if g.alive:
				g.last_attacker = 1
				g.server_take_damage(999, me.global_position, true)
				killed += 1
		print("[TEST] kill-all: killed=%d corpses=%d" % [killed,
			game.gnomes.values().filter(func(g): return g.corpse != null).size()])

	# сюжетный тест: полный цикл главы через серверные вызовы
	if _test_mode == "story" and game != null and Net.is_server and _start_chapter > 1:
		# --chapter=N: скриптованный сюжет рассчитан на главу 1 — тут проверяем
		# только генерацию мира поздней главы (компоновка, связность, плотность)
		if _shot_stage == 0 and _test_timer > 5.0:
			_shot_stage = 99
			await _check_overworld_layout()
			# и подземелье этой главы: тема по биому, структура M5 на месте
			game.zones.server_enter_dungeon()
		elif _shot_stage == 99 and _test_timer > 10.0 and Net.zone == "dungeon":
			_shot_stage = 100
			var mb = game.gnomes.get(game.miniboss_gid)
			print("[TEST] dungeon-layout: theme=%s chests=%d secret=%s door=%s miniboss=%s rewards=%d traps=%d PASS=%s" % [
				game.dungeon_theme, game.dungeon_chest_spots.size(),
				str(not game.dungeon_secret.is_empty()), str(not game.dungeon_door.is_empty()),
				str(mb != null and mb.elite), game.dungeon_reward_spots.size(), game.dungeon_traps.size(),
				str(game.dungeon_theme in ["crypt", "cave", "catacombs"]
					and not game.dungeon_secret.is_empty() and not game.dungeon_door.is_empty()
					and mb != null and mb.elite and game.dungeon_reward_spots.size() == 2
					and game.dungeon_chest_spots.size() >= 1)])
			print("[TEST] done, quitting. mode=story chapter=%d" % _start_chapter)
			get_tree().quit()
		elif _test_timer > 40.0:
			get_tree().quit() # страховка, если проверка не завершилась
		return

	if _test_mode == "story" and game != null and Net.is_server:
		var me3: PlayerChar = game.player_nodes.get(Net.my_id)
		if _shot_stage == 0 and _test_timer > 2.0:
			_shot_stage = 1
			print("[TEST] story: ch=%d npcs=%d q_main=%d chests=%d" % [Net.campaign_chapter, game.npcs.size(), game.q_main, game.chests.size()])
			game.server_talk(1, "main")
			game.server_talk(1, "side")
			print("[TEST] story: after talk q_main=%d q_side=%d qnodes=%d" % [game.q_main, game.q_side, game.qnodes.size()])
		elif _shot_stage == 1 and _test_timer > 4.0:
			_shot_stage = 2
			# сайд-квест: подойти к каждому квест-объекту и взять его
			for id in game.qnodes.keys():
				if game.qnodes[id].kind != "shard":
					me3.global_position = game.qnodes[id].node.global_position + Vector3(0.5, 0, 0)
					game.server_qnode_take(1, id)
			print("[TEST] story: side collect q_side=%d n=%d PASS=%s" % [
				game.q_side, game.q_side_n, str(game.q_side == 2)])
			# сдача у НПС
			game.server_talk(1, "side")
			print("[TEST] story: side turn-in q_side=%d PASS=%s" % [
				game.q_side, str(game.q_side == 3)])
			# сейф-зона: в лагере урон не проходит
			me3.global_position = Game.CAMP_POS + Vector3(1, 0, 1)
			var hp_before: int = game.server_hp[1]
			game.server_damage_player(1, 50, Vector3.ZERO)
			print("[TEST] story: safe-zone hp %d->%d PASS=%s" % [
				hp_before, game.server_hp[1], str(game.server_hp[1] == hp_before)])
			# найм вольного мага
			game.server_gold = 100
			game.server_talk(1, "hire")
			var allies := 0
			for g2 in game.gnomes.values():
				if g2.friendly and g2.alive:
					allies += 1
			print("[TEST] story: hire allies=%d gold=%d PASS=%s" % [
				allies, game.server_gold, str(allies == 1 and game.server_gold == 70)])
			var killed := 0
			for g in game.gnomes.values():
				if g.alive and killed < game.chapter_cfg().kill_count:
					g.last_attacker = 1
					g.server_take_damage(9999, me3.global_position, false)
					killed += 1
			print("[TEST] story: killed=%d q_main=%d boss_gid=%d" % [killed, game.q_main, game.boss_gid])
		elif _shot_stage == 2 and _test_timer > 6.0:
			_shot_stage = 3
			# дорога зачищена — этап 2: идти к склепу; телепортируемся ко входу
			print("[TEST] dungeon: pre-enter q_main=%d gold=%d entrance=%s PASS=%s" % [
				game.q_main, game.server_gold, str(game.dungeon_entrance),
				str(game.q_main == 2 and game.dungeon_entrance != Vector3.INF)])
			_test_gold_carry = game.server_gold
			me3.global_position = game.dungeon_entrance
		elif _shot_stage == 3 and _test_timer > 8.5:
			_shot_stage = 4
			# уже должны быть в подземелье: зона, перенос квеста/золота, босс на месте
			var boss = game.gnomes.get(game.boss_gid)
			print("[TEST] dungeon: inside zone=%s q_main=%d gold=%d boss=%s rooms=%s PASS=%s" % [
				Net.zone, game.q_main, game.server_gold, str(boss != null),
				str(game.boss_spot != Vector3.INF),
				str(Net.zone == "dungeon" and game.q_main == 2 and game.server_gold == _test_gold_carry \
					and boss != null and game.boss_spot != Vector3.INF)])
			# 5.0: хранитель произнёс тезис — доктрина ждёт ответа; Слово
			# заставляет его сомневаться (−15% здоровья)
			var boss50 = game.gnomes.get(game.boss_gid)
			var bhp0: int = boss50.max_hp if boss50 != null else -1
			print("[TEST] doctrine: prompt=%s PASS=%s" % [str(game.doctrine_open), str(game.doctrine_open)])
			game.server_doctrine(1, false) # отвечаем Словом
			var bhp1: int = boss50.max_hp if boss50 != null else -1
			print("[TEST] doctrine: word chosen boss hp %d->%d counters s=%d w=%d PASS=%s" % [
				bhp0, bhp1, Net.doctrine_steel, Net.doctrine_word,
				str(boss50 != null and bhp1 == roundi(bhp0 * 0.85) and Net.doctrine_word == 1
					and not game.doctrine_open)])
			# M5: тема, секретная кладка, решётка со стражем ключа, ниша наград
			var mb = game.gnomes.get(game.miniboss_gid)
			print("[TEST] dungeon-m5: theme=%s secret=%s door=%s miniboss=%s rewards=%d PASS=%s" % [
				game.dungeon_theme, str(not game.dungeon_secret.is_empty()),
				str(not game.dungeon_door.is_empty() and not game.dungeon_door.get("opened", false)),
				str(mb != null and mb.elite), game.dungeon_reward_spots.size(),
				str(game.dungeon_theme != "" and not game.dungeon_secret.is_empty()
					and not game.dungeon_door.is_empty() and mb != null and mb.elite
					and game.dungeon_reward_spots.size() == 2)])
			# секретная кладка: подойти и расшатать
			if not game.dungeon_secret.is_empty():
				me3.global_position = Vector3(game.dungeon_secret.x + 1.2, 0, game.dungeon_secret.z)
				game.server_open_secret(1)
				print("[TEST] dungeon-m5: secret opened=%s PASS=%s" % [
					str(game.dungeon_secret.get("opened", false)), str(game.dungeon_secret.get("opened", false))])
			# ключ у стража: его смерть поднимает решётку
			if mb != null and mb.alive:
				mb.last_attacker = 1
				mb.server_take_damage(99999, mb.global_position + Vector3(1, 0, 0), false)
			print("[TEST] dungeon-m5: door after key opened=%s PASS=%s" % [
				str(game.dungeon_door.get("opened", false)), str(game.dungeon_door.get("opened", false))])
			if boss != null and boss.alive:
				boss.last_attacker = 1
				boss.server_take_damage(99999, boss.global_position + Vector3(1, 0, 0), false)
			print("[TEST] dungeon: boss killed, q_main=%d PASS=%s" % [game.q_main, str(game.q_main == 3)])
		elif _shot_stage == 4 and _test_timer > 10.0:
			_shot_stage = 41
			# M5: пара трофеев в нише — телепорт к первому (второй должен рассыпаться)
			print("[TEST] dungeon-m5: reward pair=%d PASS=%s" % [
				game.reward_pair.size(), str(game.reward_pair.size() == 2)])
			if game.reward_pair.size() == 2:
				var d0: Dictionary = game.item_drops.get(game.reward_pair[0], {})
				if not d0.is_empty() and is_instance_valid(d0.node):
					me3.global_position = d0.node.global_position + Vector3(0.4, 0, 0)
		elif _shot_stage == 41 and _test_timer > 11.4:
			_shot_stage = 5
			print("[TEST] dungeon-m5: reward choice pair_left=%d drops_left=%d PASS=%s" % [
				game.reward_pair.size(), game.item_drops.size(), str(game.reward_pair.is_empty())])
			var me4: PlayerChar = game.player_nodes.get(Net.my_id)
			for id in game.qnodes.keys():
				if game.qnodes[id].kind == "shard":
					me4.global_position = game.qnodes[id].node.global_position + Vector3(1, 0, 0)
					game.server_qnode_take(1, id)
			print("[TEST] dungeon: shard taken, q_main=%d PASS=%s" % [game.q_main, str(game.q_main == 4)])
		elif _shot_stage == 5 and _test_timer > 12.6:
			_shot_stage = 6
			# осколок лежит в зале босса, портал наружу открывается там же —
			# игрок мог выйти мгновенно (портал под ногами). Оба исхода валидны.
			if Net.zone == "overworld":
				print("[TEST] dungeon: exit portal PASS=true (instant exit — portal opened underfoot)")
			else:
				print("[TEST] dungeon: exit portal open=%s mode=%s PASS=%s" % [
					str(game.portal_open), game.portal_mode,
					str(game.portal_open and game.portal_mode == "dungeon_exit")])
				me3.global_position = game.portal_pos
		elif _shot_stage == 6 and _test_timer > 14.0:
			_shot_stage = 7
			# вернулись на поверхность: зона, квест и золото пережили оба перехода
			print("[TEST] dungeon: back zone=%s q_main=%d gold>=carry=%s PASS=%s" % [
				Net.zone, game.q_main, str(game.server_gold >= _test_gold_carry),
				str(Net.zone == "overworld" and game.q_main == 4 and game.server_gold >= _test_gold_carry)])
			game.server_talk(1, "main")
			# глава завершается порталом — в него нужно физически войти
			var me5: PlayerChar = game.player_nodes.get(Net.my_id)
			me5.global_position = game.portal_pos
			print("[TEST] story: portal open=%s pos=%s q_main=%d" % [game.portal_open, game.portal_pos, game.q_main])
		elif _shot_stage == 7 and _test_timer > 20.5:
			_shot_stage = 8
			var me_lvl: int = Net.players[1].level
			# ожидания относительны стартовой главы: прогон может начинаться
			# с --chapter=N (проверка компоновки поздних глав)
			var want_ch: int = _start_chapter + 1
			var want_biome: String = Quests.CHAPTER_BIOMES[clampi(want_ch - 1, 0, Quests.CHAPTER_BIOMES.size() - 1)]
			print("[TEST] story: now ch=%d biome=%s level=%d xp=%d npcs=%d PASS=%s" % [
				Net.campaign_chapter, Net.biome, me_lvl, Net.players[1].xp,
				game.npcs.size(), str(Net.campaign_chapter == want_ch and Net.biome == want_biome and me_lvl > 1)])
			# сейв: глава записана на диск
			print("[TEST] save: chapter=%d sides_mask=%d hero_level=%d PASS=%s" % [
				Save.chapter, Save.sides_mask, Save.hero.level,
				str(Save.chapter == want_ch and Save.hero.level == me_lvl)])
			# характеристики: тратим очки (сравниваем с началом — тестовый сейв персистится)
			var pts_before: int = Net.players[1].points
			var str_before: int = Net.players[1].str
			var vit_before: int = Net.players[1].vit
			game.server_alloc_stat(1, "str")
			game.server_alloc_stat(1, "vit")
			var pd: Dictionary = Net.players[1]
			print("[TEST] stats: points %d->%d str=%d vit=%d maxhp=%d PASS=%s" % [
				pts_before, pd.points, pd.str, pd.vit, game.player_max_hp(1),
				str(pd.str == str_before + 1 and pd.vit == vit_before + 1
					and pd.points == pts_before - 2 and game.player_max_hp(1) > 100)])
			# уровни врагов второй главы
			var lvls: Array = []
			for g in game.gnomes.values():
				lvls.append(g.level)
			print("[TEST] enemy levels ch2: %s PASS=%s" % [str(lvls), str(not lvls.is_empty() and lvls.min() >= 2)])

			# точки интереса: лор-детали + костёр/колодец/доска объявлений
			var poi_kinds_seen: Array = []
			for i in game.world_pois.size():
				var poi: Dictionary = game.world_pois[i]
				poi_kinds_seen.append(poi.kind)
				me3.global_position = Vector3(poi.x, 0, poi.z)
				match poi.kind:
					"ruins", "standing_stones", "crypt", "battlefield":
						game.start_lore(i)
					"shrine":
						game.server_shrine_bless(1, i)
					"campfire":
						game.server_campfire_rest(1, i)
					"well":
						game.server_well_drink(1, i)
					"bounty_board":
						game.server_bounty_read(1, i)
			print("[TEST] story: poi kinds=%s PASS=%s" % [str(poi_kinds_seen), str(not poi_kinds_seen.is_empty())])

			# оверворлд: компоновка/связность/плотность + чекпоинт и поводок ниже
			await _check_overworld_layout()
			var cp_ok := game.team_checkpoint != Vector2.INF
			print("[TEST] overworld: checkpoint set=%s (campfire rest)" % str(cp_ok))
			# поводок: у врага с домом далёкая цель игнорируется
			var leashed = null
			for g4 in game.gnomes.values():
				if g4.alive and not g4.friendly and g4.home_pos != Vector3.INF:
					leashed = g4
					break
			if leashed != null:
				me3.global_position = leashed.home_pos + Vector3(Gnome.HOME_LEASH + 25.0, 0, 0)
				leashed.target = null
				leashed.retarget_timer = 0.0
				leashed._pick_target(0.1)
				var lp = leashed.target
				print("[TEST] overworld: leash ignores far player PASS=%s" % str(lp == null or lp is Gnome))
			else:
				print("[TEST] overworld: leash SKIP (no leashed enemy alive)")

			# элитный гном: спавн, оглушение, добивающий удар (финишер)
			var roles2: Dictionary = Game.BIOME_ENEMIES.get(Net.biome, Game.BIOME_ENEMIES["meadow"])
			game.server_spawn_gnome_at(roles2.melee, me3.global_position + Vector3(3, 0, 0), 1, true)
			await get_tree().process_frame
			await get_tree().process_frame
			var elite_g = null
			for g in game.gnomes.values():
				if g.elite and g.alive:
					elite_g = g
					break
			if elite_g != null:
				var elite_max_hp: int = elite_g.max_hp
				elite_g.state = "stagger"
				elite_g.last_attacker = 1
				elite_g.server_take_damage(9999, me3.global_position, false)
				print("[TEST] story: elite max_hp=%d elite_flag=%s dead=%s PASS=%s" % [
					elite_max_hp, elite_g.elite, not elite_g.alive, str(elite_g.elite and not elite_g.alive)])
			else:
				print("[TEST] story: elite gnome spawn FAIL (not found)")
			# бочки (D1): взрыв ранит гнома рядом; сама бочка исчезает
			if not game.barrels.is_empty():
				var bid0: int = game.barrels.keys()[0]
				var b0: Dictionary = game.barrels[bid0]
				game.server_spawn_gnome_at(roles2.melee, Vector3(b0.x + 1.6, 0, b0.z), 1)
				var vgid: int = game.gnome_seq
				await get_tree().process_frame
				await get_tree().process_frame
				var victim = game.gnomes.get(vgid)
				var vhp0: int = victim.hp if victim != null else -1
				game.server_explode_barrel(bid0, 1)
				var vhp1: int = victim.hp if victim != null else -1
				print("[TEST] barrels: count=%d exploded=%s victim hp %d->%d PASS=%s" % [
					game.barrels.size(), str(not b0.alive), vhp0, vhp1,
					str(not b0.alive and victim != null and (vhp1 < vhp0 or not victim.alive))])
			else:
				print("[TEST] barrels: count=0 PASS=false")
			print("[TEST] achievements: unlocked=%d lore=%d/%d" % [
				Achievements.count_unlocked(), Achievements.lore_progress().x, Achievements.lore_progress().y])

			# --- экипировка: выдать, надеть, проверить статы и персист ---
			var dmg_cap_before: int = game._max_melee_dmg(1)
			var hp_before2: int = game.player_max_hp(1)
			game._server_grant_equipment(1, {"id": "axe2h", "kind": "weapon", "rarity": 2, "aseed": 12345, "count": 1})
			game._server_grant_equipment(1, {"id": "amulet_oak", "kind": "trinket", "rarity": 1, "aseed": 777, "count": 1})
			var inv1: Array = game.server_inv[1]
			game.server_equip_item(1, inv1.size() - 2) # секира
			inv1 = game.server_inv[1]
			game.server_equip_item(1, inv1.size() - 1) # амулет (сместился на конец)
			var eqd: Dictionary = game.server_equip[1]
			var dmg_cap_after: int = game._max_melee_dmg(1)
			var hp_after2: int = game.player_max_hp(1)
			print("[TEST] items: equip weapon=%s trinket=%s PASS=%s" % [
				eqd.weapon.get("id", "?"), eqd.trinket.get("id", "?"),
				str(eqd.weapon.get("id", "") == "axe2h" and eqd.trinket.get("id", "") == "amulet_oak")])
			# кап урона растёт, только если среди аффиксов выпал «Урон» (детерминировано от сида);
			# +hp гарантирован — у амулета профильный аффикс всегда здоровье
			var afw := Items.affixes({"id": "axe2h", "rarity": 2, "aseed": 12345})
			var cap_ok: bool = (dmg_cap_after > dmg_cap_before) == afw.has("dmg")
			print("[TEST] items: dmg cap %d->%d (dmg affix=%s) hp %d->%d PASS=%s" % [
				dmg_cap_before, dmg_cap_after, str(afw.has("dmg")), hp_before2, hp_after2,
				str(cap_ok and hp_after2 > hp_before2)])
			# детерминизм аффиксов: одинаковая тройка -> одинаковые статы
			var af1 := Items.affixes({"id": "axe2h", "rarity": 2, "aseed": 12345})
			var af2 := Items.affixes({"id": "axe2h", "rarity": 2, "aseed": 12345})
			var af3 := Items.affixes({"id": "axe2h", "rarity": 2, "aseed": 54321})
			print("[TEST] items: affix determinism PASS=%s (diff seed differs=%s)" % [
				str(af1 == af2), str(af1 != af3)])
			# персист: инвентарь/экипировка уезжают в сейв героя
			Save.store_hero(Net.players[1])
			print("[TEST] items: save inv=%d equip_w=%s PASS=%s" % [
				Save.hero_inventory.size(), Save.hero_equipment.weapon.get("id", "?"),
				str(Save.hero_equipment.weapon.get("id", "") == "axe2h")])

			# --- лавка: детерминизм ассортимента, покупка, продажа ---
			var stock1 := Items.shop_stock(Net.world_seed, Net.campaign_chapter)
			var stock2 := Items.shop_stock(Net.world_seed, Net.campaign_chapter)
			game.server_gold = 500
			var inv_n_before: int = game.server_inv[1].size()
			game.server_buy(1, 0) # первый расходник
			var bought: bool = game.server_gold < 500
			var gold_after_buy: int = game.server_gold
			game.server_sell(1, game.server_inv[1].size() - 1)
			print("[TEST] shop: stock=%d determ=%s buy(gold %d->%d inv %d->%d) sell(gold %d) PASS=%s" % [
				stock1.size(), str(stock1 == stock2), 500, gold_after_buy,
				inv_n_before, game.server_inv[1].size(), game.server_gold,
				str(stock1.size() >= 5 and stock1 == stock2 and bought and game.server_gold > gold_after_buy)])

			# --- арбалет: экипировать, хитскан-выстрел по гному строго по лучу ---
			game._server_grant_equipment(1, {"id": "crossbow", "kind": "weapon", "rarity": 0, "aseed": 1, "count": 1})
			game.server_equip_item(1, game.server_inv[1].size() - 1)
			var me6: PlayerChar = game.player_nodes.get(Net.my_id)
			# чистое поле: убираем прочих врагов, ставим одну мишень строго на восток
			for g6 in game.gnomes.values():
				if g6.alive and not g6.friendly:
					g6.alive = false
					g6.hp = 0
			me6.global_position = Vector3(0, 0.1, 0)
			game.server_spawn_gnome_at("berserker", Vector3(6, 0, 0), 1)
			var seq6: int = game.gnome_seq
			await get_tree().process_frame
			await get_tree().process_frame
			var targ = game.gnomes.get(seq6)
			if targ != null:
				me6.global_position = Vector3(0, 0.1, 0)
				targ.global_position = Vector3(6, 0.1, 0) # гарантируем позицию (не всплытие из норы)
				targ.alive = true
				var hp_t0: int = targ.hp
				game._shot_cd.erase(1)
				game.server_shoot(1, 1.0, 0.0) # луч ровно на восток
				var shot_hit: bool = targ.hp < hp_t0 or not targ.alive
				print("[TEST] crossbow: equipped=%s hitscan hp %d->%d PASS=%s" % [
					str(game.server_equip[1].weapon.get("id", "") == "crossbow"),
					hp_t0, targ.hp, str(shot_hit)])
			else:
				print("[TEST] crossbow: target spawn FAIL")
			get_tree().quit()

	# обучение (D2): скриптованное прохождение всех шагов + флаг на диске
	if _test_mode == "tutorial" and game != null:
		var tut = game.tutorial
		if _shot_stage == 0 and _test_timer > 2.0:
			_shot_stage = 1
			print("[TEST] tutorial: created=%s step=%s" % [
				str(tut != null and tut.active), tut.STEPS[tut.step] if tut != null else "-"])
			if tut == null:
				get_tree().quit()
				return
			tut.notify("move", 5.0)
			tut.notify("camera", 1.5)
		elif _shot_stage == 1 and _test_timer > 2.6:
			_shot_stage = 2
			print("[TEST] tutorial: move done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "sprint")])
			tut.notify("sprint", 1.5)
		elif _shot_stage == 2 and _test_timer > 3.2:
			_shot_stage = 3
			print("[TEST] tutorial: sprint done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "attack")])
			var me_t: PlayerChar = game.player_nodes.get(Net.my_id)
			for i in 3: # три настоящих замаха (notify дёргает start_attack)
				me_t.state = "idle"
				me_t.combat.start_attack()
			me_t.state = "idle"
		elif _shot_stage == 3 and _test_timer > 3.8:
			_shot_stage = 4
			print("[TEST] tutorial: attack done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "defense")])
			tut.notify("block", 1.0)
			var me_t2: PlayerChar = game.player_nodes.get(Net.my_id)
			me_t2.state = "idle"
			me_t2.dodge_cooldown = 0.0
			me_t2.stamina = me_t2.STAM_MAX
			me_t2.combat.try_dodge() # notify("dodge") внутри
			me_t2.state = "idle"
		elif _shot_stage == 4 and _test_timer > 4.4:
			_shot_stage = 5
			print("[TEST] tutorial: defense done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "chest")])
			var me_t3: PlayerChar = game.player_nodes.get(Net.my_id)
			for cid in game.chests:
				var ch: Dictionary = game.chests[cid]
				me_t3.global_position = Vector3(ch.x + 1.0, 0, ch.z)
				game.server_open_chest(1, cid) # on_chest_opened дёрнет notify
				break
		elif _shot_stage == 5 and _test_timer > 5.0:
			_shot_stage = 6
			print("[TEST] tutorial: chest done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "inventory")])
			game.hud.toggle_inventory(game.inventory, game.my_equip)
		elif _shot_stage == 6 and _test_timer > 5.6:
			_shot_stage = 7
			print("[TEST] tutorial: inventory done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "stats")])
			game.hud.toggle_inventory([], {}) # закрыть
			game.hud.toggle_stats(Net.players[1])
		elif _shot_stage == 7 and _test_timer > 6.2:
			_shot_stage = 8
			print("[TEST] tutorial: stats done -> %s PASS=%s" % [tut.STEPS[tut.step], str(tut.STEPS[tut.step] == "item")])
			game.hud.toggle_stats({}) # закрыть
			game._server_grant_item(1, "potion_hp")
			game.use_item_slot(0)
		elif _shot_stage == 8 and _test_timer > 6.8:
			_shot_stage = 9
			print("[TEST] tutorial: item done -> %s waypoint=%s PASS=%s" % [
				tut.STEPS[tut.step], str(game.waypoint_node != null),
				str(tut.STEPS[tut.step] == "talk" and game.waypoint_node != null)])
			game.start_dialog(0) # финал: разговор со старейшиной
		elif _shot_stage == 9 and _test_timer > 7.4:
			_shot_stage = 10
			var meta := ConfigFile.new()
			meta.load(Save.meta_path())
			var on_disk: bool = bool(meta.get_value("meta", "tutorial_done", false))
			print("[TEST] tutorial: finished active=%s flag=%s disk=%s waypoint_cleared=%s PASS=%s" % [
				str(tut.active), str(Save.tutorial_done), str(on_disk), str(game.waypoint_node == null),
				str(not tut.active and Save.tutorial_done and on_disk and game.waypoint_node == null)])
			print("[TEST] done, quitting. mode=tutorial")
			get_tree().quit()
		return

	# стамина (D1): перекид тратит; пустая — блокирует перекид; покой восстанавливает
	if _test_mode == "single" and not _test_stam_checked and _test_timer > 19.0 and game != null:
		_test_stam_checked = true
		var me_s: PlayerChar = game.player_nodes.get(Net.my_id)
		if me_s != null and me_s.state in ["idle", "block"]:
			var s0: float = me_s.stamina
			me_s.dodge_cooldown = 0.0
			me_s.try_dodge()
			var drained: bool = me_s.stamina < s0
			me_s.state = "idle"
			me_s.dodge_cooldown = 0.0
			me_s.stamina = 0.0
			me_s.try_dodge()
			var blocked: bool = me_s.state != "dodge"
			me_s.stam_regen_delay = 0.0
			get_tree().create_timer(1.0).timeout.connect(func():
				print("[TEST] stamina: drain=%s blocked_at_zero=%s regen=%.0f PASS=%s" % [
					str(drained), str(blocked), me_s.stamina,
					str(drained and blocked and me_s.stamina > 5.0)]))
		else:
			print("[TEST] stamina: SKIP (player busy: %s)" % (me_s.state if me_s != null else "null"))

	# парирование + тяжёлый удар (D1)
	if _test_mode == "single" and not _test_parry_checked and _test_timer > 21.0 and game != null:
		_test_parry_checked = true
		var me_p: PlayerChar = game.player_nodes.get(Net.my_id)
		if me_p != null:
			# свежий блок в сторону удара -> парирование без урона
			var apos: Vector3 = me_p.global_position + Vector3(sin(me_p.facing), 0, cos(me_p.facing)) * 2.0
			me_p.blocking = true
			me_p.block_started_ms = Time.get_ticks_msec()
			var hp0: int = game.server_hp[1]
			var res1: String = str(game.server_damage_player(1, 20, apos))
			# устаревший блок -> обычное блокирование с уроном 15%
			me_p.blocking = true
			me_p.block_started_ms = Time.get_ticks_msec() - 600
			var res2: String = str(game.server_damage_player(1, 20, apos))
			var hp2: int = game.server_hp[1]
			me_p.blocking = false
			print("[TEST] parry: fresh=%s stale=%s hp %d->%d PASS=%s" % [
				res1, res2, hp0, hp2,
				str(res1 == "parry" and res2 == "block" and hp2 == hp0 - maxi(1, roundi(20 * 0.15)))])
			# тяжёлый удар: замах из зарядки тратит стамину и бьёт сильнее комбо
			me_p.state = "idle"
			me_p.stamina = me_p.STAM_MAX
			me_p.combat.release_heavy()
			var base_dmg: int = me_p.active_combo()[me_p.active_combo().size() - 1].dmg
			print("[TEST] heavy: state=%s dmg=%d>base=%d stamina=%.0f PASS=%s" % [
				me_p.state, me_p.heavy_step.get("dmg", 0), base_dmg, me_p.stamina,
				str(me_p.state == "attack" and me_p.heavy_step.get("dmg", 0) > base_dmg
					and me_p.stamina <= me_p.STAM_MAX - me_p.STAM_HEAVY + 0.1)])

	# тест паузы: в одиночке мир должен замирать
	if _test_mode == "single" and not _test_paused and _test_timer > 7.0 and game != null:
		_test_paused = true
		get_tree().paused = true
		_pause_snapshot = {}
		for gid in game.gnomes:
			_pause_snapshot[gid] = game.gnomes[gid].global_position
		_pause_snapshot["daytime"] = game.daynight.time
	elif _test_paused and _pause_snapshot.size() > 0 and _test_timer > 9.5 and game != null:
		var frozen := true
		for gid in _pause_snapshot:
			if gid is int and game.gnomes.has(gid):
				if game.gnomes[gid].global_position.distance_to(_pause_snapshot[gid]) > 0.05:
					frozen = false
		if absf(game.daynight.time - _pause_snapshot["daytime"]) > 0.001:
			frozen = false
		print("[TEST] pause-check: %s" % ("PASS" if frozen else "FAIL"))
		_pause_snapshot = {}
		get_tree().paused = false

	# тест сундука: телепорт к сундуку, открыть, собрать лут, применить предмет
	if _test_mode == "single" and not _test_chest and _test_timer > 12.0 and game != null and not game.chests.is_empty():
		_test_chest = true
		var me2: PlayerChar = game.player_nodes.get(Net.my_id)
		var cid: int = game.chests.keys()[0]
		var c: Dictionary = game.chests[cid]
		me2.global_position = Vector3(c.x + 1.0, 0.1, c.z)
		Net.req_open_chest(cid)
		print("[TEST] chest open requested cid=%d opened=%s" % [cid, game.chests[cid].opened])
	if _test_mode == "single" and _test_chest and not _test_item_used and _test_timer > 16.0 and game != null:
		_test_item_used = true
		if game.inventory.size() > 0:
			var itype: String = game.inventory[0].get("id", "?")
			game.use_item_slot(0)
			print("[TEST] used item: %s, inv slots left=%d" % [itype, game.inventory.size()])
		else:
			print("[TEST] used item: NONE (inventory empty)")

	# тест: КЛИЕНТ поднимает павшего ХОСТА (обратное направление)
	if _test_mode == "mpjoin" and game != null and "--revive2" in OS.get_cmdline_user_args():
		var host_node = game.player_nodes.get(1)
		if _test_timer > 12.0 and _test_timer < 20.0 and host_node != null and host_node.state == "downed":
			var me4: PlayerChar = game.player_nodes.get(Net.my_id)
			if _shot_stage < 90:
				_shot_stage = 90
				print("[TEST] client-reviver: host downed, starting")
			me4.global_position = host_node.global_position + Vector3(1, 0, 0)
			if fmod(_test_timer, 0.2) < 0.05:
				Net.req_revive(1)
		elif _test_timer > 20.0 and _shot_stage == 90:
			_shot_stage = 91
			print("[TEST] client-reviver result: host state=%s hp=%d" % [host_node.state, host_node.hp])

	if _test_mode == "mphost" and "--revive2" in OS.get_cmdline_user_args() and game != null and Net.players.size() > 1:
		if _test_timer > 10.0 and _shot_stage == 0:
			_shot_stage = 1
			game.server_damage_player(1, 9999, Vector3.ZERO)
			print("[TEST] host self-downed, state=%s" % game.player_nodes[1].state)
		elif _test_timer > 22.0 and _shot_stage == 1:
			_shot_stage = 2
			print("[TEST] host after client revive: hp=%d state=%s PASS=%s" % [
				game.server_hp.get(1, -1), game.player_nodes[1].state,
				str(game.server_hp.get(1, 0) > 0)])

	# тест: хост пал, волна зачищена -> хост возрождается на новой волне с 50% HP
	if _test_mode == "mphost" and "--waverespawn" in OS.get_cmdline_user_args() and game != null and Net.players.size() > 1:
		if _test_timer > 9.0 and _shot_stage == 0:
			_shot_stage = 1
			game.server_damage_player(1, 9999, Vector3.ZERO)
			print("[TEST] wave-respawn: host downed=%s wave=%d" % [game.player_nodes[1].state, game.wave])
		elif _shot_stage >= 1 and _shot_stage < 50 and _test_timer > 11.0:
			_shot_stage += 1
			for g in game.gnomes.values():
				if g.alive:
					g.last_attacker = 0
					g.server_take_damage(9999, Vector3.ZERO, false)
			if game.wave >= 2 and game.server_hp.get(1, 0) > 0:
				print("[TEST] wave-respawn: wave=%d host hp=%d/%d state=%s PASS=%s" % [
					game.wave, game.server_hp[1], game.player_max_hp(1), game.player_nodes[1].state,
					str(game.server_hp[1] * 2 <= game.player_max_hp(1) + 1 and game.player_nodes[1].state != "downed")])
				_shot_stage = 50

	# сетевой тест: клиент шлёт чат и голос
	if _test_mode == "mpjoin" and game != null:
		if _test_timer > 8.0 and _shot_stage == 0:
			_shot_stage = 1
			Net.send_chat("тестовое сообщение")
			print("[TEST] chat sent")
		elif _test_timer > 10.0 and _shot_stage == 1:
			_shot_stage = 2
			var fake := PackedByteArray()
			fake.resize(300)
			Net.send_voice(fake)
			print("[TEST] voice sent")

	# сетевой тест: хост валит клиента в нокдаун и поднимает
	if _test_mode == "mphost" and game != null and Net.players.size() > 1:
		var cid := 0
		for id in game.player_nodes:
			if id != 1:
				cid = id
		if cid != 0:
			if _test_timer > 12.0 and _shot_stage == 0:
				_shot_stage = 1
				game.server_damage_player(cid, 999, game.player_nodes[1].global_position)
				print("[TEST] downed client %d, state=%s" % [cid, game.player_nodes[cid].state])
			elif _test_timer > 13.5 and _test_timer < 14.0 and _shot_stage >= 1 and _shot_stage < 8:
				# фаза 1: начали поднимать (несколько тиков)
				_shot_stage += 1
				game.player_nodes[1].global_position = game.player_nodes[cid].global_position + Vector3(1, 0, 0)
				game.server_revive_tick(1, cid)
			elif _test_timer > 14.0 and _test_timer < 15.6 and _shot_stage < 20:
				# фаза 2: ПРЕРВАЛИ (не тикаем > 0.6 c — сервер должен сбросить прогресс)
				if _shot_stage != 15:
					_shot_stage = 15
					print("[TEST] revive interrupted at progress=%s" % str(game.revive_progress))
			elif _test_timer > 15.6 and _shot_stage >= 15 and _shot_stage < 60:
				# фаза 3: возобновили — должен подняться
				_shot_stage += 1
				game.player_nodes[1].global_position = game.player_nodes[cid].global_position + Vector3(1, 0, 0)
				game.server_revive_tick(1, cid)
				if game.server_hp.get(cid, 0) > 0 and _shot_stage < 59:
					print("[TEST] revived AFTER interruption %d hp=%d state=%s PASS=true" % [cid, game.server_hp[cid], game.player_nodes[cid].state])
					_shot_stage = 60
			elif _test_timer > 22.0 and _shot_stage >= 15 and _shot_stage < 60:
				print("[TEST] revive after interruption FAILED: progress=%s hp=%d" % [str(game.revive_progress), game.server_hp.get(cid, 0)])
				_shot_stage = 60

	# сюжет: вайп отряда -> глава перезапускается сама
	if _test_mode == "mphost" and Net.game_mode == "story" and game != null and Net.players.size() > 1:
		if _test_timer > 16.0 and _shot_stage < 70:
			_shot_stage = 70
			for id in Net.players.keys():
				game.server_damage_player(id, 9999, Vector3.ZERO)
			print("[TEST] wipe: all players downed/dead, match_over=%s" % game.match_over)
		elif _shot_stage == 70 and _test_timer > 26.0:
			_shot_stage = 71
			var alive := 0
			for id in game.server_hp:
				if game.server_hp[id] > 0:
					alive += 1
			print("[TEST] wipe-restart: q_main=%d alive=%d gnomes=%d PASS=%s" % [
				game.q_main, alive, game.gnomes.size(),
				str(alive == Net.players.size() and game.q_main == 0 and not game.match_over)])

	var limit := 34.0 if (_test_mode == "mphost" and Net.game_mode == "story") else (30.0 if _test_mode == "single" else 25.0)
	if _test_timer > limit:
		print("[TEST] done, quitting. mode=", _test_mode)
		get_tree().quit()
