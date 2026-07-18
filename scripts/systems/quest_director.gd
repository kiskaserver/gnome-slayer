class_name QuestDirector
extends RefCounted
## Сюжетный FSM (сервер): этапы q_main/q_side, квест-объекты, найм мага,
## портал конца главы, тик сюжета (шипы данжа, вход в подземелье, трикл).

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


func server_story_begin() -> void:
	if not game._carry_restored:
		# свежая глава; после возврата из подземелья квест уже восстановлен
		game.q_main = 0
		game.q_kills = 0
		game.q_side = -1
		game.q_side_n = 0
		game.boss_gid = 0
	bcast_quest()
	game.max_attackers = maxi(1, 2 + maxi(0, Net.players.size() - 1) + int(game.diff().tokens))
	var roles: Dictionary = game.BIOME_ENEMIES.get(Net.biome, game.BIOME_ENEMIES["meadow"])
	var pop: int = game.diff().story_pop
	for i in pop:
		var types := [roles.melee, roles.melee, roles.fast, roles.caster]
		game.server_spawn_gnome(types[i % types.size()])
	# вернулись из подземелья с недобитым сайд-квестом на сбор — доложить объекты
	if game._carry_restored and game.q_side == 1:
		_respawn_side_qnodes()


## Осколок и подземелье: стартовая населённость данжа + босс в дальнем зале.
func server_dungeon_begin() -> void:
	bcast_quest()
	game.max_attackers = maxi(1, 2 + maxi(0, Net.players.size() - 1) + int(game.diff().tokens))
	var roles: Dictionary = game.BIOME_ENEMIES.get("night", {})  # в склепе всегда нежить
	# сундуки по комнатам
	for spot in game.dungeon_chest_spots:
		game.chest_seq += 1
		Net.bcast("rpc_chest_spawn", [game.chest_seq, spot.x, spot.z, randf_range(0, TAU)])
	# охрана комнат
	var pop: int = maxi(5, game.diff().story_pop - 2)
	var types := [roles.melee, roles.melee, roles.fast, roles.caster]
	for i in pop:
		var a := randf_range(0, TAU)
		var r := randf_range(2.0, 5.0)
		var base: Vector3 = game.boss_spot if i % 3 == 0 else game.spawn_points[0]
		# раскидываем по комнатам: треть у босса, остальные от входа вглубь
		game.server_spawn_gnome_at(types[i % types.size()], base + Vector3(cos(a) * r, 0, sin(a) * r), game.enemy_level())
	# босс ждёт в дальнем зале
	if game.q_main == 2:
		game.boss_gid = game.gnome_seq + 1
		game.server_spawn_gnome_at(roles.boss, game.boss_spot, game.enemy_level())
		Net.bcast("rpc_banner", ["ХРАНИТЕЛЬ ОСКОЛКА ЗДЕСЬ"])


## Доспавнить недостающие объекты сайд-квеста после возврата из подземелья.
func _respawn_side_qnodes() -> void:
	var side: Dictionary = game.chapter_cfg().side
	if side.get("type", "") != "collect":
		return # kill-квесты объектов не имеют
	var need: int = int(side.get("count", 0)) - game.q_side_n
	for i in maxi(0, need):
		_spawn_qnode(side.get("kind", "mushroom"))


func story_kill_target() -> int:
	return maxi(3, roundi(game.chapter_cfg().kill_count * game.diff().count))


func bcast_quest() -> void:
	Net.bcast("rpc_quest", [game.q_main, game.q_kills, game.q_side, game.q_side_n])


func server_talk(sender: int, which: String) -> void:
	if not game.is_story() or game.match_over:
		return
	var cfg: Dictionary = game.chapter_cfg()
	if which == "main":
		if game.q_main == 0:
			game.q_main = 1
			bcast_quest()
		elif game.q_main == 4:
			server_open_portal()
	elif which == "hire":
		_try_hire(sender)
	elif which == "side":
		if game.q_side == -1:
			game.q_side = 1
			bcast_quest()
			if cfg.side.type == "collect":
				for i in cfg.side.count:
					_spawn_qnode(cfg.side.kind)
		elif game.q_side == 2:
			# сдача: награда и отметка в кампании
			game.q_side = 3
			Net.sides_mask |= 1 << (Net.campaign_chapter - 1)
			if Net.mode != Net.Mode.CLIENT:
				Save.sides_mask = Net.sides_mask
				Save.write()
			game.server_grant_xp_all(Quests.XP_SIDE_REWARD)
			for id in Net.players:
				game._server_grant_item(id, "bomb")
			Net.bcast("rpc_banner", ["ЗАДАНИЕ ВЫПОЛНЕНО"])
			bcast_quest()


func _spawn_qnode(kind: String, at := Vector3.INF) -> void:
	game.qnode_seq += 1
	var pos := at
	if pos == Vector3.INF:
		for _try in 60:
			if not game.world_areas.is_empty():
				# оверворлд: квест-объекты внутри областей вдоль пути (не в глухом лесу)
				var area: Dictionary = game.world_areas[randi() % game.world_areas.size()]
				var aa := randf_range(0, TAU)
				var ar: float = area.radius * randf_range(0.3, 0.8)
				pos = Vector3(area.center.x + cos(aa) * ar, 0, area.center.z + sin(aa) * ar)
			else:
				var a := randf_range(0, TAU)
				var r := randf_range(10.0, WorldGen.WORLD_RADIUS - 5.0)
				pos = Vector3(cos(a) * r, 0, sin(a) * r)
			if pos.distance_to(game.CAMP_POS) > game.SAFE_RADIUS + 2.0 and clear_of_houses(pos):
				break
	Net.bcast("rpc_qnode", [game.qnode_seq, kind, pos.x, pos.z])


## Найм вольного мага (сервер): проверка золота и лимита, спавн у лагеря.
func _try_hire(sender: int) -> void:
	if not game.is_story() or game.match_over:
		return
	var allies := 0
	for g in game.gnomes.values():
		if g.friendly and g.alive:
			allies += 1
	if allies >= Net.players.size() + 1:
		Net.send_sys(sender, "У Фырка кончились свободные ученики.")
		return
	if game.server_gold < game.HIRE_COST:
		Net.send_sys(sender, "Не хватает золота — маг работает по предоплате.")
		return
	game.server_gold -= game.HIRE_COST
	Net.bcast("rpc_gold", [game.server_gold])
	var pn = game.player_nodes.get(sender)
	var dir := Vector3(0, 0, 1)
	if pn != null:
		dir = pn.global_position - game.CAMP_POS
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, 1)
	var px: float = game.CAMP_POS.x + dir.x * (game.SAFE_RADIUS + 0.6)
	var pz: float = game.CAMP_POS.z + dir.z * (game.SAFE_RADIUS + 0.6)
	game.gnome_seq += 1
	Net.bcast("rpc_gnome_spawn", [game.gnome_seq, "ally_mage", px, pz,
		px + dir.x * 1.5, pz + dir.z * 1.5, game.enemy_level()])
	if game.gnomes.has(game.gnome_seq):
		game.gnomes[game.gnome_seq].owner_id = sender
	Net.bcast("rpc_sys", ["Вольный маг нанят! Он пойдёт за нанимателем."])


## Точка не внутри домика и не в дереве/камне/точке интереса — иначе не достать
## (или сундук окажется в текстуре объекта).
func clear_of_houses(pos: Vector3) -> bool:
	for house in game.houses:
		if Vector2(house.x - pos.x, house.z - pos.z).length() < 4.5:
			return false
	for o in game.world_obstacles:
		if Vector2(o.x - pos.x, o.z - pos.z).length() < o.r + 1.2:
			return false
	return true


func server_qnode_take(sender: int, id: int) -> void:
	if not game.is_story() or game.match_over:
		return
	var qn: Dictionary = game.qnodes.get(id, {})
	if qn.is_empty() or qn.taken:
		return
	var pn = game.player_nodes.get(sender)
	if pn == null or pn.global_position.distance_to(qn.node.global_position) > 3.0:
		return
	match qn.kind:
		"shard":
			if game.q_main == 3:
				game.q_main = 4
				Net.bcast("rpc_qnode_taken", [id])
				Net.bcast("rpc_banner", ["ОСКОЛОК СЕРДЦА У ТЕБЯ!"])
				bcast_quest()
		"mushroom":
			if game.q_side == 1:
				game.q_side_n += 1
				Net.bcast("rpc_qnode_taken", [id])
				_check_side_done()
				bcast_quest()
		"bonfire":
			if game.q_side == 1:
				game.q_side_n += 1
				Net.bcast("rpc_qnode_lit", [id])
				_check_side_done()
				bcast_quest()


func _check_side_done() -> void:
	var cfg: Dictionary = game.chapter_cfg()
	if game.q_side == 1 and game.q_side_n >= cfg.side.count:
		game.q_side = 2
		Net.bcast("rpc_banner", ["ВОЗВРАЩАЙСЯ В ЛАГЕРЬ"])


func on_gnome_died(g) -> void:
	var cfg: Dictionary = game.chapter_cfg()
	var roles: Dictionary = game.BIOME_ENEMIES.get(Net.biome, game.BIOME_ENEMIES["meadow"])
	if game.q_main == 1 and g.gid != game.boss_gid:
		game.q_kills += 1
		if game.q_kills >= story_kill_target():
			# дорога расчищена — хранитель осколка ждёт в склепе на дальнем краю
			game.q_main = 2
			Net.bcast("rpc_banner", ["ХРАНИТЕЛЬ ОСКОЛКА — В СКЛЕПЕ НА КРАЮ ЛЕСА"])
		bcast_quest()
	elif game.q_main == 2 and g.gid == game.boss_gid:
		game.q_main = 3
		_spawn_qnode("shard", g.global_position)
		bcast_quest()
	if game.q_side == 1 and cfg.side.type == "kill_fast" and g.type == roles.fast:
		game.q_side_n += 1
		_check_side_done()
		bcast_quest()


## Портал открывается вместо мгновенного телепорта: рассказ закончен на месте,
## а переход в следующую главу — осознанный шаг игрока, а не смена экрана.
func server_open_portal() -> void:
	if game.portal_open:
		return
	game.portal_open = true
	game.portal_pos = game.CAMP_POS + Vector3(0, 0, game.SAFE_RADIUS + 3.0) # запасной вариант, если не найдём место почище
	for _try in 20:
		var away := Vector2(0, 1).rotated(randf_range(0, TAU))
		var cand: Vector3 = game.CAMP_POS + Vector3(away.x, 0, away.y) * (game.SAFE_RADIUS + 3.0)
		if clear_of_houses(cand):
			game.portal_pos = cand
			break
	Net.bcast("rpc_portal_spawn", [game.portal_pos.x, game.portal_pos.z])
	game.q_main = 5
	bcast_quest()


func server_chapter_complete() -> void:
	game.server_grant_xp_all(Quests.XP_CHAPTER_REWARD)
	game.match_over = true
	# катсцена портала — рассказ подводит итог главы, пока экран занят полосами и субтитрами
	var outro: Array = Quests.CHAPTER_OUTRO[Net.campaign_chapter - 1] if Net.campaign_chapter - 1 < Quests.CHAPTER_OUTRO.size() else []
	Net.bcast("rpc_cutscene", [outro, game.portal_pos.x, game.portal_pos.y, game.portal_pos.z])
	if Net.campaign_chapter >= Quests.CHAPTERS.size():
		# концовка зависит от выполненных сайд-квестов за кампанию
		var done := 0
		for i in Quests.CHAPTERS.size():
			if Net.sides_mask & (1 << i):
				done += 1
		var ending := "bitter"
		if done >= Quests.CHAPTERS.size():
			ending = "gold"
		elif done >= 3:
			ending = "light"
		Save.reset_campaign()
		Save.store_hero(Net.players.get(1, {}))
		game.restart_timer = -1.0 # финал кампании — без авторестарта
		game.delay(4.8, func():
			game._server_game_over(true, "ENDING:%s:%d" % [ending, done]))
		return
	var next := Net.campaign_chapter + 1
	if Net.mode != Net.Mode.CLIENT:
		Save.chapter = next
		Save.store_hero(Net.players.get(1, {}))
	var nbiome: String = Quests.CHAPTER_BIOMES[next - 1]
	var nseed := randi()
	game.delay(4.8, func():
		Net.bcast("rpc_chapter", [next, nbiome, nseed]))


func update_story(delta: float) -> void:
	if game.portal_open:
		for id in game.player_nodes:
			var p = game.player_nodes[id]
			if game.server_hp.get(id, 0) > 0 and p.global_position.distance_to(game.portal_pos) < 2.2:
				game.portal_open = false
				if game.portal_mode == "dungeon_exit":
					game._server_exit_dungeon()
				else:
					server_chapter_complete()
				break
		return # ждём, пока игрок сам шагнёт в портал

	# --- подземелье: шипы, выход после осколка; трикл врагов не нужен ---
	if game.is_dungeon():
		game._trap_tick -= delta
		if game._trap_tick <= 0:
			game._trap_tick = 0.8
			for id in game.player_nodes:
				if game.server_hp.get(id, 0) <= 0:
					continue
				var pp: Vector3 = game.player_nodes[id].global_position
				for t in game.dungeon_traps:
					if Vector2(pp.x - t.x, pp.z - t.z).length() < t.r:
						game.server_damage_player(id, 6, Vector3(t.x, 0, t.z))
						break
		if game.q_main == 4 and not game.portal_open and game.portal_node == null:
			# осколок взят — открываем портал наружу в зале босса
			game.portal_mode = "dungeon_exit"
			game.portal_open = true
			game.portal_pos = game.boss_spot
			Net.bcast("rpc_portal_spawn", [game.portal_pos.x, game.portal_pos.z])
			Net.bcast("rpc_banner", ["ПУТЬ НАРУЖУ ОТКРЫТ"])
		return

	# --- оверворлд: вход в подземелье, когда пришло время (этап 2) ---
	if game.q_main == 2 and game.dungeon_entrance != Vector3.INF:
		var near := 0
		var alive_n := 0
		for id in game.player_nodes:
			if game.server_hp.get(id, 0) <= 0:
				continue
			alive_n += 1
			if game.player_nodes[id].global_position.distance_to(game.dungeon_entrance) < 6.0:
				near += 1
		if alive_n > 0 and near == alive_n:
			game._server_enter_dungeon()
			return

	game.story_trickle -= delta
	if game.story_trickle <= 0:
		game.story_trickle = 12.0
		var alive := 0
		for g in game.gnomes.values():
			if g.alive and g.gid != game.boss_gid and not g.friendly:
				alive += 1
		if alive < game.diff().story_pop:
			var roles: Dictionary = game.BIOME_ENEMIES.get(Net.biome, game.BIOME_ENEMIES["meadow"])
			var types := [roles.melee, roles.fast, roles.caster]
			# пока активен сайд-квест на шустрых — они должны попадаться
			if game.q_side == 1 and game.chapter_cfg().side.type == "kill_fast":
				types = [roles.fast, roles.fast, roles.melee]
			for i in 2:
				game.server_spawn_gnome(types[randi() % 3])
