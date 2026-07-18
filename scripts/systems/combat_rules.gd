class_name CombatRules
extends RefCounted
## Серверные правила боя: валидация урона, нокдаун/поднятие, Второе дыхание.

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


## Максимально правдоподобный урон одного удара для данного игрока — потолок,
## которым сервер обрезает присланное клиентом число (защита от читерского
## dmg: гигантский урон = ваншот, отрицательный = «лечение» цели через минус).
## Считаем по сильнейшему шагу серии с учётом всех множителей и запасом.
func max_melee_dmg(id: int) -> int:
	var pd: Dictionary = Net.players.get(id, {})
	# 42 — самый мощный удар (секира), 1.5 — ярость, 1.8 — крит, аффиксы экипировки
	var top := 42.0 * 1.5 * Quests.dmg_mult_for(pd) * 1.8 * Quests.crit_dmg_mult_for(pd) \
		* Items.equip_dmg_mult(game.server_equip.get(id, {}))
	return int(ceil(top)) + 4  # небольшой запас на округления


func server_handle_melee(sender: int, targets: Array, dmg: int, crit: bool) -> void:
	var sn = game.player_nodes.get(sender)
	if sn == null or game.server_hp.get(sender, 0) <= 0:
		return # мёртвый/павший игрок не бьёт
	# доверяем факту удара и списку целей (их сервер перепроверяет по дистанции),
	# но не доверяем числу урона — обрезаем в разумные серверные рамки
	dmg = clampi(dmg, 1, max_melee_dmg(sender))
	for t in targets:
		if not (t is Array) or t.size() < 2:
			continue
		if t[0] == "g":
			var g = game.gnomes.get(int(t[1]))
			if g != null and g.alive and not g.friendly and g.global_position.distance_to(sn.global_position) < 6.5:
				g.last_attacker = sender
				g.last_attacker_gid = 0 # игрок перебил зачёт: последним бил не наёмник
				g.server_take_damage(dmg, sn.global_position, crit)
		elif t[0] == "p" and game.is_pvp():
			var pid := int(t[1])
			var pn = game.player_nodes.get(pid)
			if pn != null and pn.global_position.distance_to(sn.global_position) < 6.5:
				server_damage_player(pid, dmg, sn.global_position, sender)


func server_damage_player(id: int, dmg: int, from_pos: Vector3, attacker: int = 0) -> void:
	var node = game.player_nodes.get(id)
	if node == null or game.server_hp.get(id, 0) <= 0 or game.match_over:
		return
	if game.in_safe_zone(node.global_position):
		return
	if node.iframes > 0:
		Net.bcast("rpc_player_hp", [id, game.server_hp[id], game.player_max_hp(id), "dodge", from_pos.x, from_pos.z])
		return
	var flag := "hit"
	if node.blocking:
		var to_enemy := atan2(from_pos.x - node.global_position.x, from_pos.z - node.global_position.z)
		if absf(angle_difference(to_enemy, node.facing)) < 1.4:
			dmg = maxi(1, roundi(dmg * 0.15))
			flag = "block"
	# барьер поглощает урон
	if game.server_shield.get(id, 0) > 0:
		var absorb: int = mini(game.server_shield[id], dmg)
		game.server_shield[id] -= absorb
		dmg -= absorb
		if game.server_shield[id] <= 0:
			game.server_shield.erase(id)
			Net.bcast("rpc_buff", [id, "shield_end", 0.0])
		if dmg <= 0:
			Net.bcast("rpc_player_hp", [id, game.server_hp[id], game.player_max_hp(id), "shield", from_pos.x, from_pos.z])
			return
	game.server_hp[id] = game.server_hp[id] - dmg
	Net.bcast("rpc_player_hp", [id, game.server_hp[id], game.player_max_hp(id), flag, from_pos.x, from_pos.z])
	if game.server_hp[id] <= 0:
		_server_player_defeated(id, attacker)
	elif not game._second_wind_used.get(id, false) and game.server_hp[id] <= game.player_max_hp(id) * game.SECOND_WIND_HP_FRAC:
		# первый раз на волоске от смерти за матч — короткий шанс выровняться
		game._second_wind_used[id] = true
		game.server_shield[id] = game.server_shield.get(id, 0) + 40
		Net.bcast("rpc_buff", [id, "shield", 999.0])
		Net.bcast("rpc_buff", [id, "rage", 10.0])
		Net.bcast("rpc_buff", [id, "speed", 10.0])
		Net.bcast("rpc_banner", ["ВТОРОЕ ДЫХАНИЕ!"])


func _server_player_defeated(id: int, attacker: int) -> void:
	game.server_hp[id] = 0
	if game.is_pvp():
		Net.players[id].deaths += 1
		var ktext := "гномы"
		if attacker > 0 and Net.players.has(attacker):
			Net.players[attacker].kills += 1
			ktext = Net.players[attacker].name
		Net.bcast("rpc_player_died", [id, ktext])
		Net.bcast("rpc_scores", [Net.players])
		game.respawn_timers[id] = 4.0
		if attacker > 0 and Net.players[attacker].kills >= game.PVP_TARGET:
			# имя подставляет клиент ПОСЛЕ tr() — иначе строка не совпадает с ключом
			game._server_game_over(true, "PVPWIN:%s" % Net.players[attacker].name)
		return

	# ПвЕ: в мультиплеере — нокдаун, в одиночке — смерть
	if Net.players.size() > 1:
		Net.bcast("rpc_player_downed", [id])
	else:
		Net.bcast("rpc_player_died", [id, "гномы"])
	var any_alive := false
	for pid in game.server_hp:
		if game.server_hp[pid] > 0:
			any_alive = true
			break
	if not any_alive:
		game._server_game_over(false, "ОТРЯД ПАЛ В БОЮ")


## Тик поднятия (клиент шлёт, пока держит E рядом с павшим).
func server_revive_tick(reviver: int, target: int) -> void:
	if game.is_pvp() or game.match_over:
		return
	var rn = game.player_nodes.get(reviver)
	var tn = game.player_nodes.get(target)
	if rn == null or tn == null or game.server_hp.get(reviver, 0) <= 0 or game.server_hp.get(target, 1) > 0:
		return
	if rn.global_position.distance_to(tn.global_position) > 4.2:
		return
	var e: Dictionary = game.revive_progress.get(target, {"k": 0.0, "idle": 0.0, "by": reviver, "t": 0.0})
	# прогресс привязан ко времени, а не к числу RPC: спам пакетами не ускоряет
	# подъём (клиент честно шлёт тик раз в ~0.15 с)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(e.get("t", 0.0)) >= 0.12:
		e.k += 0.16 * Skills.revive_speed_mult(Net.players.get(reviver, {}))
		e.t = now
	e.idle = 0.0
	e.by = reviver
	game.revive_progress[target] = e
	if e.k >= game.REVIVE_TIME:
		game.revive_progress.erase(target)
		game.downed_timers.erase(target)
		game.server_hp[target] = game.player_max_hp(target) / 2
		Net.bcast("rpc_player_revived", [target, game.server_hp[target]])
	else:
		Net.bcast("rpc_revive_progress", [target, reviver, e.k / game.REVIVE_TIME])


func server_heal_player(id: int, amount: int) -> void:
	if game.server_hp.get(id, 0) <= 0:
		return
	game.server_hp[id] = mini(game.player_max_hp(id), game.server_hp[id] + amount)
	var node = game.player_nodes.get(id)
	var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
	Net.bcast("rpc_player_hp", [id, game.server_hp[id], game.player_max_hp(id), "heal", pos.x, pos.z])


func update_revives(delta: float) -> void:
	# автоподъём: если павшего так и не подняли — встаёт сам у точки спавна
	if not game.is_pvp() and Net.players.size() > 1:
		for id in game.server_hp:
			if game.server_hp[id] <= 0 and game.player_nodes.has(id):
				game.downed_timers[id] = game.downed_timers.get(id, 0.0) + delta
				if game.downed_timers[id] >= game.BLEEDOUT_TIME:
					game.downed_timers.erase(id)
					game.revive_progress.erase(id)
					game.server_hp[id] = game.player_max_hp(id) / 2
					var pos := game._player_spawn_pos() as Vector2
					Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
			else:
				game.downed_timers.erase(id)
	for id in game.revive_progress.keys():
		var e: Dictionary = game.revive_progress[id]
		e.idle += delta
		if e.idle > 0.6: # бросили поднимать
			game.revive_progress.erase(id)
			Net.bcast("rpc_revive_progress", [id, e.by, 0.0])
