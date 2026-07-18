class_name LootSystem
extends RefCounted
## Серверный лут и авторитетный инвентарь: сундуки, выдача/списание предметов,
## экипировка, дропы на земле, пикапы и применение расходников.

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


func place_chests(count: int) -> void:
	if game.is_pvp():
		return # в ПвП сундуков нет — только честная сталь
	var placed := 0
	# сперва тайники у тупичков дороги (C1): сундук ждёт в конце тропы,
	# рядом с монетами и отблеском — исследование коротких ответвлений окупается
	while not game.world_caches.is_empty() and placed < count:
		var cpos: Vector3 = game.world_caches.pop_front()
		placed += 1
		game.chest_seq += 1
		Net.bcast("rpc_chest_spawn", [game.chest_seq, cpos.x, cpos.z, randf_range(0, TAU)])
	for _try in 60:
		if placed >= count:
			break
		var x: float
		var z: float
		if not game.world_areas.is_empty():
			# оверворлд: сундуки внутри областей (есть смысл исследовать каждую)
			var area: Dictionary = game.world_areas[randi() % game.world_areas.size()]
			var aa := randf_range(0, TAU)
			var ar: float = area.radius * randf_range(0.3, 0.85)
			x = area.center.x + cos(aa) * ar
			z = area.center.z + sin(aa) * ar
		else:
			var a := randf_range(0, TAU)
			var r := randf_range(8.0, WorldGen.WORLD_RADIUS - 5.0)
			x = cos(a) * r
			z = sin(a) * r
		var ok := true
		for h in game.houses:
			if Vector2(h.x - x, h.z - z).length() < 5.0:
				ok = false
				break
		for c in game.chests.values():
			if Vector2(c.x - x, c.z - z).length() < 7.0:
				ok = false
				break
		if ok:
			for o in game.world_obstacles:
				if Vector2(o.x - x, o.z - z).length() < o.r + 1.3:
					ok = false
					break
		if ok:
			placed += 1
			game.chest_seq += 1
			Net.bcast("rpc_chest_spawn", [game.chest_seq, x, z, randf_range(0, TAU)])
	# сундуки — препятствия, появившиеся после первой запечки навсетки;
	# без перезапечки враги (сервер) шли бы напролом и «бились» о них.
	# Если самая первая запечка ещё не закончилась (сундуки при старте матча),
	# повторный вызов — ошибка; она и так подхватит уже добавленные сундуки.
	if placed > 0 and Net.is_server and game.nav_region != null and game.nav_ready:
		game.nav_region.bake_navigation_mesh(true)


func server_open_chest(opener: int, cid: int) -> void:
	var c: Dictionary = game.chests.get(cid, {})
	if c.is_empty() or c.opened or game.match_over:
		return
	var pn = game.player_nodes.get(opener)
	if pn == null or pn.global_position.distance_to(Vector3(c.x, 0, c.z)) > 3.0:
		return
	c.opened = true
	Net.bcast("rpc_chest_opened", [cid])
	if game.is_story():
		game.server_gold += randi_range(8, 14)
		Net.bcast("rpc_gold", [game.server_gold])
	# шанс экипировки: одна вещь падает НА ЗЕМЛЮ у сундука — кто первый поднял
	if randf() < 0.3:
		var edrop := Items.roll_drop(game.enemy_level(), Net.players.get(opener, {}).get("luck", 0), randi(), true)
		if not edrop.is_empty():
			server_spawn_item_drop(edrop, c.x + randf_range(-1.0, 1.0), c.z + randf_range(-1.0, 1.0))
	# лут: 2-3 предмета, В КООПЕРАТИВЕ ПОЛУЧАЮТ ВСЕ ИГРОКИ
	var total := 0
	for e in game.CHEST_LOOT:
		total += e[1]
	for i in randi_range(2, 3):
		var roll := randi() % total
		var type := "potion_hp"
		for e in game.CHEST_LOOT:
			roll -= e[1]
			if roll < 0:
				type = e[0]
				break
		if type == "crystal":
			var keys: Array = game.PICKUP_TYPES.keys()
			type = keys[randi() % keys.size()]
		for id in Net.players:
			if type == "heal":
				game.server_heal_player(id, 20)
			elif type == "shield":
				if game.server_hp.get(id, 0) > 0:
					game.server_shield[id] = game.SHIELD_POINTS
					Net.bcast("rpc_buff", [id, "shield", 999.0])
			elif game.PICKUP_TYPES.has(type):
				if game.server_hp.get(id, 0) > 0:
					Net.bcast("rpc_buff", [id, type, game.PICKUP_TYPES[type].dur])
			else:
				grant_item(id, type)


## Выдать расходник игроку (сервер): авторитетный инвентарь + синк владельцу.
## Расходники стакаются по id; экипировка (оружие/тринкеты) идёт отдельными
## слотами через grant_equipment.
func grant_item(id: int, type: String) -> void:
	var inv: Array = game.server_inv.get(id, [])
	var stacked := false
	for slot in inv:
		if slot.get("kind", "") == "consumable" and slot.id == type:
			slot.count += 1
			stacked = true
			break
	if not stacked:
		if inv.size() >= game.INV_SIZE:
			Net.send_sys(id, "Инвентарь полон! %s пропал." % tr(game.ITEM_DEFS.get(type, {}).get("title", type)))
			return
		inv.append({"id": type, "kind": "consumable", "rarity": 0, "aseed": 0, "count": 1})
	game.server_inv[id] = inv
	Net.bcast("rpc_item_granted", [id, type])
	sync_inv(id)


## Выдать экипировку (сервер). false — инвентарь полон.
func grant_equipment(id: int, item: Dictionary) -> bool:
	var inv: Array = game.server_inv.get(id, [])
	if inv.size() >= game.INV_SIZE:
		return false
	inv.append(item)
	game.server_inv[id] = inv
	sync_inv(id)
	return true


## Списать один расходник по id; false — если его нет.
func consume_item(id: int, type: String) -> bool:
	var inv: Array = game.server_inv.get(id, [])
	for i in inv.size():
		if inv[i].get("kind", "") == "consumable" and inv[i].id == type:
			inv[i].count -= 1
			if inv[i].count <= 0:
				inv.remove_at(i)
			sync_inv(id)
			return true
	return false


## Синк авторитетного инвентаря/экипировки владельцу (и в Net.players — для сейва).
func sync_inv(id: int) -> void:
	var inv: Array = game.server_inv.get(id, [])
	var eq: Dictionary = game.server_equip.get(id, {"weapon": {}, "trinket": {}})
	if Net.players.has(id):
		Net.players[id]["inventory"] = inv.duplicate(true)
		Net.players[id]["equipment"] = eq.duplicate(true)
	if id == Net.my_id:
		game.on_inv_sync(inv, eq)
	else:
		Net.rpc_id(id, "rpc_inv_sync", inv, eq)


## Надеть предмет из инвентаря (сервер): слот по виду предмета, снятое — назад.
func server_equip_item(id: int, inv_idx: int) -> void:
	var inv: Array = game.server_inv.get(id, [])
	if inv_idx < 0 or inv_idx >= inv.size():
		return
	var item: Dictionary = inv[inv_idx]
	var slot := ""
	match item.get("kind", ""):
		"weapon": slot = "weapon"
		"trinket": slot = "trinket"
		_: return
	var eq: Dictionary = game.server_equip.get(id, {"weapon": {}, "trinket": {}})
	inv.remove_at(inv_idx)
	var prev: Dictionary = eq.get(slot, {})
	if not prev.is_empty():
		inv.append(prev)
	eq[slot] = item
	game.server_inv[id] = inv
	game.server_equip[id] = eq
	sync_inv(id)
	game._bcast_player_hp(id) # макс. здоровье могло измениться от аффиксов
	if slot == "weapon":
		Net.bcast("rpc_player_equip", [id, item.id])


## Снять предмет (сервер): слот -> инвентарь.
func server_unequip(id: int, slot: String) -> void:
	if not slot in ["weapon", "trinket"]:
		return
	var eq: Dictionary = game.server_equip.get(id, {"weapon": {}, "trinket": {}})
	var item: Dictionary = eq.get(slot, {})
	if item.is_empty():
		return
	var inv: Array = game.server_inv.get(id, [])
	if inv.size() >= game.INV_SIZE:
		Net.send_sys(id, "Инвентарь полон — снять некуда.")
		return
	inv.append(item)
	eq[slot] = {}
	game.server_inv[id] = inv
	game.server_equip[id] = eq
	sync_inv(id)
	game._bcast_player_hp(id)
	if slot == "weapon":
		Net.bcast("rpc_player_equip", [id, "sword1h"])


## Выбросить предмет из инвентаря (сервер) — просто исчезает (M4: продажа).
func server_drop_item(id: int, inv_idx: int) -> void:
	var inv: Array = game.server_inv.get(id, [])
	if inv_idx < 0 or inv_idx >= inv.size():
		return
	inv.remove_at(inv_idx)
	game.server_inv[id] = inv
	sync_inv(id)


## Дроп экипировки на землю (сервер): лежит, ждёт, кто первым подберёт.
func server_spawn_item_drop(item: Dictionary, x: float, z: float) -> void:
	if item.is_empty():
		return
	game.drop_seq += 1
	Net.bcast("rpc_item_drop", [game.drop_seq, item, x, z])


func server_use_item(id: int, type: String, dx: float, dz: float) -> void:
	var node = game.player_nodes.get(id)
	if node == null or game.server_hp.get(id, 0) <= 0:
		return
	# предмет применяется, только если он реально есть в серверном инвентаре —
	# защита от бесконечного использования модифицированным клиентом
	if not consume_item(id, type):
		return
	match type:
		"potion_hp":
			game.server_heal_player(id, 40)
		"gold_feast":
			# пир для всего отряда: живых лечит до отвала, павших поднимает
			for pid in Net.players:
				if game.server_hp.get(pid, 0) > 0:
					game.server_heal_player(pid, 999)
				elif not game.is_pvp() and game.player_nodes.has(pid):
					game.revive_progress.erase(pid)
					game.downed_timers.erase(pid)
					game.server_hp[pid] = game.player_max_hp(pid) / 2
					Net.bcast("rpc_player_revived", [pid, game.server_hp[pid]])
		"potion_rage":
			Net.bcast("rpc_buff", [id, "rage", game.PICKUP_TYPES["rage"].dur])
		"potion_speed":
			Net.bcast("rpc_buff", [id, "speed", game.PICKUP_TYPES["speed"].dur])
		"bomb":
			game.bomb_seq += 1
			var from: Vector3 = node.global_position + Vector3(0, 1.3, 0)
			var vel := Vector3(dx, 0, dz).normalized() * 9.0 + Vector3(0, 5.0, 0)
			Net.bcast("rpc_bomb", [game.bomb_seq, from, vel])


## Тик пикапов: у всех — левитация/вращение, на сервере — подбор и потухание.
func update_pickups(delta: float) -> void:
	for pid in game.pickups.keys():
		var pk: Dictionary = game.pickups[pid]
		pk.life += delta
		pk.node.position.y = 0.15 + sin(pk.life * 3.0) * 0.12
		pk.node.rotation.y += delta * 2.0
		if not Net.is_server:
			continue
		if pk.life < 1.0:
			continue # дать заметить, а не съедать в кадр появления
		var taken_by := 0
		for id in game.player_nodes:
			if game.server_hp.get(id, 0) <= 0:
				continue
			if pk.type == "heal" and game.server_hp.get(id, 0) >= game.player_max_hp(id):
				continue # гриб при полном здоровье не тратится
			if pk.node.global_position.distance_to(game.player_nodes[id].global_position) < 1.4:
				taken_by = id
				break
		if taken_by != 0:
			match pk.type:
				"heal":
					game.server_heal_player(taken_by, 20)
				"shield":
					game.server_shield[taken_by] = game.SHIELD_POINTS
					Net.bcast("rpc_buff", [taken_by, "shield", 999.0])
				"potion_hp", "potion_rage", "potion_speed", "bomb", "gold_feast":
					grant_item(taken_by, pk.type)
				_:
					Net.bcast("rpc_buff", [taken_by, pk.type, game.PICKUP_TYPES[pk.type].dur])
			game.pickups.erase(pid)
			pk.node.queue_free()
			Net.bcast("rpc_pickup_taken", [pid])
		elif pk.life > 30.0:
			game.pickups.erase(pid)
			pk.node.queue_free()
			Net.bcast("rpc_pickup_taken", [pid])


## Тик дропов экипировки: вращение у всех, на сервере — подбор и истечение.
func update_item_drops(delta: float) -> void:
	for did in game.item_drops.keys():
		var d: Dictionary = game.item_drops[did]
		d.life += delta
		if is_instance_valid(d.node):
			d.node.rotation.y += delta * 1.5
		if not Net.is_server:
			continue
		if d.life < 0.8:
			continue
		for id in game.player_nodes:
			if game.server_hp.get(id, 0) <= 0:
				continue
			if d.node.global_position.distance_to(game.player_nodes[id].global_position) < 1.6:
				if grant_equipment(id, d.item):
					Net.bcast("rpc_item_drop_taken", [did, id])
				break
		if d.life > 60.0 and game.item_drops.has(did):
			Net.bcast("rpc_item_drop_taken", [did, 0])
