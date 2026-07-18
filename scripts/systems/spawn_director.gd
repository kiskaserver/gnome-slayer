class_name SpawnDirector
extends RefCounted
## Спавн врагов и волны: состав волн, спавн от домиков, «золотой» гном (элита),
## ПвП-подсев и таймеры возрождения.

## Небольшой шанс, что обычный спавн окажется редким "золотым" гномом —
## больше хп/урона, гарантированный жирный лут, своя ачивка за убийство.
const ELITE_CHANCE := 0.07

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


## Уровень врагов: по главе кампании или волне выживания.
func enemy_level() -> int:
	if game.is_story():
		return Net.campaign_chapter
	if game.is_pvp():
		return 2
	return 1 + floori(maxi(game.wave - 1, 0) / 2.0)


## Домики областей, рядом с которыми есть живые игроки (оверворлд): враги
## лезут из нор там, где отряд, а не по всей огромной карте.
func _active_houses() -> Array:
	if game.world_areas.is_empty():
		return game.houses
	var out: Array = []
	for house in game.houses:
		var aid: String = house.get("area", "")
		for area in game.world_areas:
			if area.id != aid:
				continue
			for id in game.player_nodes:
				if game.server_hp.get(id, 0) <= 0:
					continue
				var pp: Vector3 = game.player_nodes[id].global_position
				if Vector2(pp.x - area.center.x, pp.z - area.center.z).length() < area.radius + 18.0:
					out.append(house)
					break
			break
	return out if not out.is_empty() else game.houses


func server_spawn_gnome(type: String) -> void:
	game.gnome_seq += 1
	var px: float
	var pz: float
	var ex: float
	var ez: float
	if game.houses.is_empty():
		# ПвП-арена: спавн у края, выход к центру
		var sp: Vector3 = game.spawn_points[randi() % game.spawn_points.size()]
		px = sp.x + randf_range(-1.5, 1.5)
		pz = sp.z + randf_range(-1.5, 1.5)
		ex = px * 0.85
		ez = pz * 0.85
	else:
		var pool := _active_houses()
		var house: Dictionary = pool[randi() % pool.size()]
		px = house.x + house.dirx * 2.15
		pz = house.z + house.dirz * 2.15
		ex = house.x + house.dirx * 4.8 + randf_range(-1.2, 1.2)
		ez = house.z + house.dirz * 4.8 + randf_range(-1.2, 1.2)
	var is_elite: bool = not Gnome.TYPES[type].get("friendly", false) and not Gnome.TYPES[type].has("special") \
		and not game.is_pvp() and enemy_level() >= 2 and randf() < ELITE_CHANCE
	Net.bcast("rpc_gnome_spawn", [game.gnome_seq, type, px, pz, ex, ez, enemy_level(), is_elite])
	if is_elite:
		Net.bcast("rpc_banner", ["ЭЛИТНЫЙ ГНОМ ПОБЛИЗОСТИ!"])
	match type:
		"king", "frost_king":
			Net.bcast("rpc_banner", ["КОРОЛЬ ГНОМОВ!"])
		"skeleton_king":
			Net.bcast("rpc_banner", ["КОРОЛЬ-ЛИЧ!"])


## Спавн в произвольной точке (не у домика) — например подкрепление, которое
## босс поднимает из земли рядом с собой во время спецприёма, или элита с доски
## объявлений.
func server_spawn_gnome_at(type: String, pos: Vector3, lvl := 1, elite := false) -> void:
	game.gnome_seq += 1
	Net.bcast("rpc_gnome_spawn", [game.gnome_seq, type, pos.x, pos.z, pos.x, pos.z, lvl, elite])


func spread_slots(delta: float) -> void:
	var circlers: Array = []
	for g in game.gnomes.values():
		if g.alive and (g.state == "circle" or g.state == "retreat"):
			circlers.append(g)
	var min_gap := TAU / maxf(3.0, circlers.size())
	for i in circlers.size():
		for j in range(i + 1, circlers.size()):
			var a = circlers[i]
			var b = circlers[j]
			if a.target != b.target:
				continue
			var diff: float = angle_difference(b.slot_angle, a.slot_angle)
			if absf(diff) < min_gap:
				var push: float = (min_gap - absf(diff)) * delta * 1.5 * (1.0 if diff >= 0 else -1.0)
				a.slot_angle += push
				b.slot_angle -= push


func wave_composition(w: int) -> Array:
	var roles: Dictionary = game.BIOME_ENEMIES.get(Net.biome, game.BIOME_ENEMIES["meadow"])
	var k: float = game.diff().count
	var list: Array = []
	for i in maxi(1, roundi((1 + ceili(w * 0.7)) * k)):
		list.append(roles.melee)
	for i in roundi(maxi(0, w - 1) * k):
		list.append(roles.fast)
	for i in roundi(floori(w / 2.0) * k):
		list.append(roles.caster)
	# рой миньонов многочисленнее обычных «быстрых»
	if roles.fast == "skeleton_minion":
		for i in mini(w, 5):
			list.append(roles.fast)
	list.shuffle()
	list = list.slice(0, 18)
	if w % game.FINAL_WAVE == 0:
		list.append(roles.boss)
	return list


func start_wave(w: int) -> void:
	game.wave = w
	game.spawn_queue = wave_composition(w)
	game.spawn_timer = 0.5
	game.wave_cleared = false
	game.max_attackers = maxi(1, 2 + floori(w / 3.0) + maxi(0, Net.players.size() - 1) + int(game.diff().tokens))
	for id in game.server_hp:
		if game.server_hp[id] <= 0:
			# павшие встают с новой волной, но лишь с половиной здоровья
			game.server_hp[id] = game.player_max_hp(id) / 2
			var pos := game._player_spawn_pos() as Vector2
			Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
			Net.bcast("rpc_player_hp", [id, game.server_hp[id], game.player_max_hp(id), "heal", pos.x, pos.y])
	game.revive_progress.clear()
	# каждые 2 волны — новый сундук
	game.chest_wave_counter += 1
	if game.chest_wave_counter >= 2:
		game.chest_wave_counter = 0
		game._server_place_chests(1)
	Net.bcast("rpc_wave", [w, game.endless, false])


func update_waves_pve(delta: float) -> void:
	if not game.spawn_queue.is_empty():
		game.spawn_timer -= delta
		if game.spawn_timer <= 0:
			game.spawn_timer = randf_range(0.5, 1.0)
			server_spawn_gnome(game.spawn_queue.pop_front())
		return
	if game.wave == 0:
		return
	var alive := 0
	for g in game.gnomes.values():
		if g.alive:
			alive += 1
	if alive > 0:
		game.wave_down = 0.0
		return
	if not game.wave_cleared:
		game.wave_cleared = true
		game.wave_down = 0.0
		if not game.endless and game.wave >= game.FINAL_WAVE:
			game._server_game_over(true, "ПОБЕДА! Племя гномов разбито!")
			return
		Net.bcast("rpc_banner", ["ВОЛНА ЗАЧИЩЕНА"])
		for id in game.server_hp:
			game.server_heal_player(id, 15)
	game.wave_down += delta
	if game.wave_down > 3.0:
		start_wave(game.wave + 1)


func update_pvp(delta: float) -> void:
	game.pvp_trickle -= delta
	if game.pvp_trickle <= 0:
		game.pvp_trickle = 12.0
		var alive := 0
		for g in game.gnomes.values():
			if g.alive:
				alive += 1
		if alive < 4:
			var roles: Dictionary = game.BIOME_ENEMIES.get(Net.biome, game.BIOME_ENEMIES["meadow"])
			var types := [roles.melee, roles.fast, roles.caster]
			for i in 2:
				server_spawn_gnome(types[randi() % 3])
	for id in game.respawn_timers.keys():
		game.respawn_timers[id] -= delta
		if game.respawn_timers[id] <= 0:
			game.respawn_timers.erase(id)
			if game.server_hp.has(id):
				game.server_hp[id] = game.player_max_hp(id)
				var pos := game._player_spawn_pos() as Vector2
				Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
