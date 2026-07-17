class_name Game
extends Node3D
## Игровой контроллер: мир, волны, спавн из домиков, предметы, нокдаун/поднятие,
## эффекты, серверные правила, чат/голос.

const FINAL_WAVE := 7
const PVP_TARGET := 10
const MAX_HP := 100
const BATCH_INTERVAL := 1.0 / 15.0
const REVIVE_TIME := 3.0

const PLAYER_COLORS := [
	Color.WHITE, Color(0.65, 0.75, 1.0), Color(0.7, 1.0, 0.7), Color(1.0, 0.75, 0.8),
	Color(0.7, 1.0, 1.0), Color(1.0, 0.95, 0.6), Color(1.0, 0.7, 0.5), Color(0.85, 0.7, 1.0),
]

# Предметы-бафы (кристаллы, действуют сразу). heal — гриб, отдельно.
const PICKUP_TYPES := {
	"rage": {"color": Color(1.0, 0.3, 0.2), "dur": 15.0, "title": "Ярость"},
	"speed": {"color": Color(0.3, 1.0, 0.45), "dur": 15.0, "title": "Скорость"},
	"shield": {"color": Color(0.4, 0.75, 1.0), "dur": 999.0, "title": "Барьер"},
	"greatsword": {"color": Color(1.0, 0.85, 0.3), "dur": 25.0, "title": "Великий меч"},
}
const SHIELD_POINTS := 30

# Предметы инвентаря (хотбар 1-5)
const ITEM_DEFS := {
	"potion_hp": {"title": "Зелье здоровья", "short": "ЗД", "color": Color(0.9, 0.25, 0.3), "mesh": "bottle_A_green", "tint": Color(1.3, 0.6, 0.6)},
	"potion_rage": {"title": "Зелье ярости", "short": "ЯР", "color": Color(1.0, 0.45, 0.15), "mesh": "bottle_C_brown", "tint": Color(1.3, 0.8, 0.6)},
	"potion_speed": {"title": "Зелье скорости", "short": "СК", "color": Color(0.3, 0.9, 0.5), "mesh": "bottle_B_green", "tint": Color.WHITE},
	"bomb": {"title": "Бомба", "short": "БМ", "color": Color(0.55, 0.4, 0.25), "mesh": "keg", "tint": Color.WHITE, "mscale": 0.5},
	"gold_feast": {"title": "Золотой пир", "short": "ПИР", "color": Color(1.0, 0.85, 0.3), "mesh": "coin_stack_small", "tint": Color.WHITE},
}
const HOTBAR_SIZE := 5

# Уникальные противники локаций: роли -> тип врага
const BIOME_ENEMIES := {
	"meadow": {"melee": "berserker", "fast": "scout", "caster": "shaman", "boss": "king"},
	"winter": {"melee": "frost_berserker", "fast": "scout", "caster": "frost_shaman", "boss": "frost_king"},
	"autumn": {"melee": "berserker", "fast": "skeleton_rogue", "caster": "shaman", "boss": "king"},
	"night": {"melee": "skeleton_warrior", "fast": "skeleton_minion", "caster": "skeleton_mage", "boss": "skeleton_king"},
}

# Лут сундуков: [тип, вес]
const CHEST_LOOT := [
	["potion_hp", 28], ["bomb", 20], ["potion_rage", 12], ["potion_speed", 12],
	["crystal", 14], ["heal", 8], ["gold_feast", 6],
]

var models: Dictionary = {}
var spawn_points: Array = []
var houses: Array = []
var world_obstacles: Array = []
var world_pois: Array = []
var world_areas: Array = []          # оверворлд: [{id, kind, center, radius}]
var world_road: Array = []           # вейпоинты главной дороги
var dungeon_entrance := Vector3.INF  # точка входа в подземелье
var team_checkpoint := Vector2.INF   # чекпоинт отряда (костёр у дороги)
var boss_spot := Vector3.INF         # зал босса (в подземелье)
var dungeon_traps: Array = []        # шипы: [{x,z,r}]
var dungeon_chest_spots: Array = []  # места сундуков в комнатах
var spawn_override := Vector2.INF    # разовая точка спавна после смены зоны
var _entrance_hint := Vector2.INF    # где вход в склеп (пронесено сквозь данж)
var _carry_restored := false         # состояние восстановлено из Net.carry
var _trap_tick := 0.0
var portal_mode := "chapter"         # chapter | dungeon_exit
var _shrine_cd: Dictionary = {}  # индекс точки интереса -> время, когда снова можно благословить
const SECOND_WIND_HP_FRAC := 0.25
var _second_wind_used: Dictionary = {}  # id игрока -> уже сработало в этом матче
var nav_region: NavigationRegion3D = null
var nav_ready := false
var daynight: DayNight = null
var _time_sync := 5.0

# --- сюжетный режим ---
var npcs: Array = []            # [main_npc, side_npc]
var qnodes: Dictionary = {}     # id -> {node, kind, taken}
var qnode_seq := 0
var q_main := 0                 # этап основного квеста
var q_kills := 0
var q_side := -1                # -1 не взят, 1 в работе, 2 выполнен
var q_side_n := 0
var boss_gid := 0
var server_gold := 0  # золото отряда (сюжет): падает с гномов и из сундуков
var gold := 0         # клиентская копия для HUD
var story_trickle := 8.0
var _known_levels: Dictionary = {}
var _hero_dirty := false
var _hero_save_timer := 30.0
var _reviver_msg_shown := false # у меня на экране «Поднимаешь...» — надо будет стереть
var hud: Hud = null
var main: Node = null
var ui_blocked := false

var player_nodes: Dictionary = {} # peer_id -> PlayerChar
var gnomes: Dictionary = {}       # gid -> Gnome
var pickups: Dictionary = {}      # pid -> {node, life, type}
var fireballs: Dictionary = {}    # fid -> {node, dir, life}
var chests: Dictionary = {}       # cid -> {node, lid, opened, x, z}
var bombs: Dictionary = {}        # bid -> {node, vel, life}

# инвентарь локального игрока: массив {type, count} (макс. HOTBAR_SIZE слотов)
var inventory: Array = []

# --- серверное состояние ---
var server_hp: Dictionary = {}
var server_shield: Dictionary = {}
var server_inv: Dictionary = {}  # id -> Array{type,count}: авторитетное зеркало инвентарей
var players_meta: Dictionary = {}
var attackers: Dictionary = {}
var max_attackers := 2
var wave := 0
var wave_text := ""
var endless := false
var match_over := false
var spawn_queue: Array = []
var spawn_timer := 0.0
var wave_down := 0.0
var wave_cleared := false
var pvp_trickle := 6.0
var respawn_timers: Dictionary = {}
var revive_progress: Dictionary = {} # target_id -> {"k": float, "idle": float, "by": int}
var gnome_seq := 0
var fb_seq := 0
var pk_seq := 0
var chest_seq := 0
var bomb_seq := 0
var chest_wave_counter := 0
var batch_timer := 0.0
var _batch_full_timer := 0.0
var restart_timer := -1.0

var _rng := RandomNumberGenerator.new()

const FX_POOL_SIZE := 20
var _fx_pool: Array = []
var _fx_idx := 0
var _fx_numbers_active := 0

static var _model_cache: Dictionary = {}


## Отложенный вызов, умирающий вместе с миром (SceneTreeTimer с лямбдой
## переживал смену главы и спамил «Lambda capture freed»).
func delay(sec: float, cb: Callable) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(0.01, sec)
	add_child(t)
	t.timeout.connect(func():
		cb.call()
		t.queue_free())
	t.start()


func is_pvp() -> bool:
	return Net.game_mode == "pvp"


func is_story() -> bool:
	return Net.game_mode == "story"


func is_dungeon() -> bool:
	return is_story() and Net.zone == "dungeon"


## Упаковать переносимое состояние перед сменой зоны (сервер).
func _fill_carry(extra: Dictionary = {}) -> void:
	Net.carry = {
		"gold": server_gold,
		"q_main": q_main, "q_kills": q_kills,
		"q_side": q_side, "q_side_n": q_side_n,
		"checkpoint_x": team_checkpoint.x, "checkpoint_y": team_checkpoint.y,
		"second_wind": _second_wind_used.duplicate(),
	}
	for k in extra:
		Net.carry[k] = extra[k]


## Распаковать состояние после смены зоны (сервер, до спавна игроков).
func _restore_carry() -> void:
	if Net.carry.is_empty():
		return
	_carry_restored = true
	server_gold = int(Net.carry.get("gold", 0))
	q_main = int(Net.carry.get("q_main", 0))
	q_kills = int(Net.carry.get("q_kills", 0))
	q_side = int(Net.carry.get("q_side", -1))
	q_side_n = int(Net.carry.get("q_side_n", 0))
	team_checkpoint = Vector2(Net.carry.get("checkpoint_x", Vector2.INF.x), Net.carry.get("checkpoint_y", Vector2.INF.y))
	_second_wind_used = Net.carry.get("second_wind", {})
	if Net.carry.has("return_x"):
		spawn_override = Vector2(Net.carry.get("return_x"), Net.carry.get("return_z"))
	if Net.carry.has("entrance_x"):
		_entrance_hint = Vector2(Net.carry.get("entrance_x"), Net.carry.get("entrance_z"))
	Net.carry = {}
	delay(0.5, func():
		Net.bcast("rpc_gold", [server_gold])
		_bcast_quest())


func diff() -> Dictionary:
	return Quests.DIFFICULTIES.get(Net.difficulty, Quests.DIFFICULTIES["normal"])


func _ready() -> void:
	if _model_cache.is_empty():
		for m in ["Knight", "Barbarian", "Mage", "Rogue_Hooded",
				"Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Minion", "Skeleton_Rogue",
				"chest_gold", "chest", "Rogue", "keg", "bottle_A_green", "bottle_B_green", "bottle_C_brown", "coin_stack_small"]:
			_model_cache[m] = load("res://models/%s.glb" % m)
		for w in ["Skeleton_Blade", "Skeleton_Axe", "Skeleton_Staff", "Skeleton_Shield_Small_A"]:
			_model_cache[w] = load("res://models/skeleton_weapons/%s.gltf" % w)
		_model_cache["sword_2handed"] = load("res://models/adventurer_items/sword_2handed.gltf")
	models = _model_cache

	# сюжет живёт в большом мире-путешествии (или в подземелье), волны/ПвП — на арене
	var data: Dictionary
	if is_dungeon():
		data = WorldDungeon.build(self, Net.zone_seed)
	elif is_story():
		data = WorldGen.build_overworld(self, Net.world_seed, Net.biome)
	else:
		data = WorldGen.build(self, Net.world_seed, Net.biome, is_pvp())
	spawn_points = data.spawn_points
	houses = data.houses
	world_obstacles = data.obstacles
	world_pois = data.get("pois", [])
	world_areas = data.get("areas", [])
	world_road = data.get("road", [])
	dungeon_entrance = data.get("dungeon_entrance", Vector3.INF)
	boss_spot = data.get("boss_spot", Vector3.INF)
	dungeon_traps = data.get("traps", [])
	dungeon_chest_spots = data.get("chest_spots", [])
	nav_region = data.nav_region
	if is_story() and not is_dungeon():
		# вырезаем сейф-зону лагеря из навсетки: маршруты врагов
		# огибают лагерь, а не утыкаются в его границу
		var hole := NavigationObstacle3D.new()
		hole.affect_navigation_mesh = true
		hole.carve_navigation_mesh = true
		var pts := PackedVector3Array()
		for i in 12:
			var a := TAU * float(i) / 12.0
			pts.append(Vector3(sin(a) * SAFE_RADIUS, 0, cos(a) * SAFE_RADIUS))
		hole.vertices = pts
		add_child(hole)
		hole.global_position = CAMP_POS
	nav_region.bake_finished.connect(func(): nav_ready = true)
	nav_region.bake_navigation_mesh(true)

	if not is_dungeon():
		# в подземелье нет неба и цикла суток — только факелы и мрак
		daynight = DayNight.new()
		add_child(daynight)
		var start_t: float = chapter_cfg().get("start_time", data.biome.start_time) if is_story() else data.biome.start_time
		daynight.setup(data, data.biome, start_t)

	_init_fx_pool()
	_prewarm_pipelines()

	hud = Hud.new()
	add_child(hud)
	Net.game = self
	Settings.changed.connect(_apply_gfx_settings)
	_apply_gfx_settings()

	if is_story() and not is_dungeon():
		_build_camp()

	if Net.is_server:
		# состояние, пронесённое сквозь смену зоны (золото, квест, чекпоинт)
		_restore_carry()
		for id in Net.players:
			server_on_player_joined(id)
		# разовая точка входа отработала — дальше обычные правила респавна
		delay(3.0, func(): spawn_override = Vector2.INF)
		if is_dungeon():
			_server_dungeon_begin()
		else:
			# в большом мире-путешествии сундуков больше — по одному на область
			_server_place_chests(6 if is_story() else 3)
			if is_pvp():
				Net.bcast("rpc_wave", [0, false, true])
			elif is_story():
				_server_story_begin()
			else:
				delay(2.0, func():
					if not match_over:
						_start_wave(1))


func _apply_gfx_settings() -> void:
	if daynight != null and daynight.env != null:
		if daynight.env.ssao_enabled != Settings.ssao:
			daynight.env.ssao_enabled = Settings.ssao
		if daynight.env.glow_enabled != Settings.glow:
			daynight.env.glow_enabled = Settings.glow


func weapon_scene(weapon_name: String) -> PackedScene:
	return models.get(weapon_name)


# ---------------------------------------------------------------------------
# Игроки
# ---------------------------------------------------------------------------
func server_on_player_joined(id: int) -> void:
	var color: Color = PLAYER_COLORS[players_meta.size() % PLAYER_COLORS.size()]
	var pos := _player_spawn_pos()
	server_hp[id] = player_max_hp(id)
	players_meta[id] = {"color": color}
	var pname: String = Net.players[id].name

	if id != 1:
		# новому клиенту — текущее состояние мира
		for oid in player_nodes:
			var meta: Dictionary = players_meta.get(oid, {"color": Color.WHITE})
			var n = player_nodes[oid]
			Net.rpc_id(id, "rpc_spawn_player", oid, n.player_name, n.global_position.x, n.global_position.z, meta.color)
		for oid in player_nodes:
			if server_hp.get(oid, 0) <= 0 and not is_pvp():
				Net.rpc_id(id, "rpc_player_downed", oid)
		for gid in gnomes:
			var g = gnomes[gid]
			Net.rpc_id(id, "rpc_gnome_spawn", gid, g.type, g.global_position.x, g.global_position.z, 0.0, 0.0, g.level)
		Net.rpc_id(id, "rpc_wave", wave, endless, is_pvp())
		for pid in pickups:
			var pk = pickups[pid]
			Net.rpc_id(id, "rpc_pickup_spawn", pid, pk.type, pk.node.global_position.x, pk.node.global_position.z)
		for cid in chests:
			var c = chests[cid]
			Net.rpc_id(id, "rpc_chest_spawn", cid, c.x, c.z, c.node.rotation.y)
			if c.opened:
				Net.rpc_id(id, "rpc_chest_opened", cid)
		if daynight != null:
			Net.rpc_id(id, "rpc_daytime", daynight.time)
		if is_story():
			Net.rpc_id(id, "rpc_quest", q_main, q_kills, q_side, q_side_n)
			Net.rpc_id(id, "rpc_gold", server_gold)
			for qid in qnodes:
				var qn = qnodes[qid]
				if not qn.taken:
					Net.rpc_id(id, "rpc_qnode", qid, qn.kind, qn.node.global_position.x, qn.node.global_position.z)

	Net.bcast("rpc_spawn_player", [id, pname, pos.x, pos.y, color])


func _player_spawn_pos() -> Vector2:
	if is_story():
		# разовая точка после смены зоны (выход из склепа у крипты)
		if spawn_override != Vector2.INF:
			return spawn_override + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		# в подземелье отряд появляется во входном зале
		if is_dungeon() and not spawn_points.is_empty():
			var ep: Vector3 = spawn_points[0]
			return Vector2(ep.x + randf_range(-2.0, 2.0), ep.z + randf_range(-2.0, 2.0))
		# чекпоинт (костёр у дороги) — точка возрождения отряда, если тронут
		if team_checkpoint != Vector2.INF:
			return team_checkpoint + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		return Vector2(CAMP_POS.x + randf_range(-2.5, 2.5), CAMP_POS.z + randf_range(1.0, 4.0))
	if is_pvp():
		var a := randf_range(0, TAU)
		var r := randf_range(6.0, 16.0)
		return Vector2(cos(a) * r, sin(a) * r)
	return Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))


func on_spawn_player(id: int, pname: String, x: float, z: float, color: Color) -> void:
	if player_nodes.has(id):
		return
	var p := PlayerChar.new()
	add_child(p)
	p.setup(self, id, pname, color)
	p.global_position = Vector3(x, 0.1, z)
	player_nodes[id] = p
	fx_burst(Vector3(x, 1.0, z), Color(1.0, 0.9, 0.5), 12)
	if id == Net.my_id:
		hud.set_hp(MAX_HP, MAX_HP)


func on_despawn_player(id: int) -> void:
	if player_nodes.has(id):
		player_nodes[id].queue_free()
		player_nodes.erase(id)
	server_hp.erase(id)
	server_shield.erase(id)
	server_inv.erase(id)
	players_meta.erase(id)
	respawn_timers.erase(id)
	revive_progress.erase(id)
	downed_timers.erase(id)
	_second_wind_used.erase(id)


func on_player_state(sender: int, pkt: PackedFloat32Array) -> void:
	var node = player_nodes.get(sender)
	if node != null and not node.is_local:
		node.apply_net_state(pkt)


func get_player_noise(node) -> float:
	if node.is_local:
		return node.noise_radius
	var a: String = node.current_anim
	if a.contains("Attack"):
		return 22.0
	if a == "Running_A":
		return 14.0
	if a.begins_with("Walking"):
		return 7.0
	return 3.0


## Ближайший павший союзник (для поднятия).
func find_downed_near(pos: Vector3, radius: float, exclude_id: int) -> int:
	for id in player_nodes:
		if id == exclude_id:
			continue
		var p = player_nodes[id]
		if p.state == "downed" and p.global_position.distance_to(pos) < radius:
			return id
	return 0


# ---------------------------------------------------------------------------
# Урон и нокдаун (сервер)
# ---------------------------------------------------------------------------
## Максимально правдоподобный урон одного удара для данного игрока — потолок,
## которым сервер обрезает присланное клиентом число (защита от читерского
## dmg: гигантский урон = ваншот, отрицательный = «лечение» цели через минус).
## Считаем по сильнейшему шагу серии с учётом всех множителей и запасом.
func _max_melee_dmg(id: int) -> int:
	var pd: Dictionary = Net.players.get(id, {})
	# 36 — самый мощный удар (2H_Melee_Attack_Chop), 1.5 — ярость, 1.8 — крит
	var top := 36.0 * 1.5 * Quests.dmg_mult_for(pd) * 1.8 * Quests.crit_dmg_mult_for(pd)
	return int(ceil(top)) + 4  # небольшой запас на округления


func server_handle_melee(sender: int, targets: Array, dmg: int, crit: bool) -> void:
	var sn = player_nodes.get(sender)
	if sn == null or server_hp.get(sender, 0) <= 0:
		return # мёртвый/павший игрок не бьёт
	# доверяем факту удара и списку целей (их сервер перепроверяет по дистанции),
	# но не доверяем числу урона — обрезаем в разумные серверные рамки
	dmg = clampi(dmg, 1, _max_melee_dmg(sender))
	for t in targets:
		if not (t is Array) or t.size() < 2:
			continue
		if t[0] == "g":
			var g = gnomes.get(int(t[1]))
			if g != null and g.alive and not g.friendly and g.global_position.distance_to(sn.global_position) < 6.5:
				g.last_attacker = sender
				g.last_attacker_gid = 0 # игрок перебил зачёт: последним бил не наёмник
				g.server_take_damage(dmg, sn.global_position, crit)
		elif t[0] == "p" and is_pvp():
			var pid := int(t[1])
			var pn = player_nodes.get(pid)
			if pn != null and pn.global_position.distance_to(sn.global_position) < 6.5:
				server_damage_player(pid, dmg, sn.global_position, sender)


func server_damage_player(id: int, dmg: int, from_pos: Vector3, attacker: int = 0) -> void:
	var node = player_nodes.get(id)
	if node == null or server_hp.get(id, 0) <= 0 or match_over:
		return
	if in_safe_zone(node.global_position):
		return
	if node.iframes > 0:
		Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "dodge", from_pos.x, from_pos.z])
		return
	var flag := "hit"
	if node.blocking:
		var to_enemy := atan2(from_pos.x - node.global_position.x, from_pos.z - node.global_position.z)
		if absf(angle_difference(to_enemy, node.facing)) < 1.4:
			dmg = maxi(1, roundi(dmg * 0.15))
			flag = "block"
	# барьер поглощает урон
	if server_shield.get(id, 0) > 0:
		var absorb: int = mini(server_shield[id], dmg)
		server_shield[id] -= absorb
		dmg -= absorb
		if server_shield[id] <= 0:
			server_shield.erase(id)
			Net.bcast("rpc_buff", [id, "shield_end", 0.0])
		if dmg <= 0:
			Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "shield", from_pos.x, from_pos.z])
			return
	server_hp[id] = server_hp[id] - dmg
	Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), flag, from_pos.x, from_pos.z])
	if server_hp[id] <= 0:
		_server_player_defeated(id, attacker)
	elif not _second_wind_used.get(id, false) and server_hp[id] <= player_max_hp(id) * SECOND_WIND_HP_FRAC:
		# первый раз на волоске от смерти за матч — короткий шанс выровняться
		_second_wind_used[id] = true
		server_shield[id] = server_shield.get(id, 0) + 40
		Net.bcast("rpc_buff", [id, "shield", 999.0])
		Net.bcast("rpc_buff", [id, "rage", 10.0])
		Net.bcast("rpc_buff", [id, "speed", 10.0])
		Net.bcast("rpc_banner", ["ВТОРОЕ ДЫХАНИЕ!"])


func _server_player_defeated(id: int, attacker: int) -> void:
	server_hp[id] = 0
	if is_pvp():
		Net.players[id].deaths += 1
		var ktext := "гномы"
		if attacker > 0 and Net.players.has(attacker):
			Net.players[attacker].kills += 1
			ktext = Net.players[attacker].name
		Net.bcast("rpc_player_died", [id, ktext])
		Net.bcast("rpc_scores", [Net.players])
		respawn_timers[id] = 4.0
		if attacker > 0 and Net.players[attacker].kills >= PVP_TARGET:
			_server_game_over(true, "%s ПОБЕЖДАЕТ!" % Net.players[attacker].name)
		return

	# ПвЕ: в мультиплеере — нокдаун, в одиночке — смерть
	if Net.players.size() > 1:
		Net.bcast("rpc_player_downed", [id])
	else:
		Net.bcast("rpc_player_died", [id, "гномы"])
	var any_alive := false
	for pid in server_hp:
		if server_hp[pid] > 0:
			any_alive = true
			break
	if not any_alive:
		_server_game_over(false, "ОТРЯД ПАЛ В БОЮ")


## Тик поднятия (клиент шлёт, пока держит E рядом с павшим).
func server_revive_tick(reviver: int, target: int) -> void:
	if is_pvp() or match_over:
		return
	var rn = player_nodes.get(reviver)
	var tn = player_nodes.get(target)
	if rn == null or tn == null or server_hp.get(reviver, 0) <= 0 or server_hp.get(target, 1) > 0:
		return
	if rn.global_position.distance_to(tn.global_position) > 4.2:
		return
	var e: Dictionary = revive_progress.get(target, {"k": 0.0, "idle": 0.0, "by": reviver, "t": 0.0})
	# прогресс привязан ко времени, а не к числу RPC: спам пакетами не ускоряет
	# подъём (клиент честно шлёт тик раз в ~0.15 с)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(e.get("t", 0.0)) >= 0.12:
		e.k += 0.16 * Skills.revive_speed_mult(Net.players.get(reviver, {}))
		e.t = now
	e.idle = 0.0
	e.by = reviver
	revive_progress[target] = e
	if e.k >= REVIVE_TIME:
		revive_progress.erase(target)
		downed_timers.erase(target)
		server_hp[target] = player_max_hp(target) / 2
		Net.bcast("rpc_player_revived", [target, server_hp[target]])
	else:
		Net.bcast("rpc_revive_progress", [target, reviver, e.k / REVIVE_TIME])


func server_heal_player(id: int, amount: int) -> void:
	if server_hp.get(id, 0) <= 0:
		return
	server_hp[id] = mini(player_max_hp(id), server_hp[id] + amount)
	var node = player_nodes.get(id)
	var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
	Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "heal", pos.x, pos.z])


func on_player_hp(id: int, hp: int, max_hp: int, flag: String, fx: float, fz: float) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.max_hp = max_hp
		node.on_hp_event(hp, flag, Vector3(fx, 0, fz))


func on_player_died(id: int, killer_text: String) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.die()
	if id == Net.my_id and is_pvp():
		hud.center_msg(tr("Тебя одолел %s. Возрождение...") % tr(killer_text))


func on_player_downed(id: int) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.go_downed()
	if id == Net.my_id:
		hud.center_msg(tr("Ты пал. Друг может поднять тебя (%s)") % main.key_name("interact"))
	else:
		var pname: String = Net.players[id].name if Net.players.has(id) else "Друг"
		hud.add_chat("", tr("⚑ %s пал — подними его (%s)!") % [pname, main.key_name("interact")], true)


func on_player_revived(id: int, hp: int) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.on_revived(hp)
	hud.set_revive_progress(0.0)
	if id != Net.my_id and _reviver_msg_shown:
		Achievements.unlock("reviver")
	if id == Net.my_id or _reviver_msg_shown:
		hud.center_msg("")
		_reviver_msg_shown = false


func on_revive_progress(target_id: int, reviver_id: int, k: float) -> void:
	if Net.debug_log:
		print("[TEST] revive-progress rx: target=%d reviver=%d k=%.2f (me=%d)" % [target_id, reviver_id, k, Net.my_id])
	var pct := int(k * 100)
	if Net.my_id == target_id:
		var rname: String = Net.players[reviver_id].name if Net.players.has(reviver_id) else "Друг"
		hud.center_msg(tr("%s поднимает тебя... %d%%") % [rname, pct] if k > 0
			else tr("Ты пал. Друг может поднять тебя (%s)") % main.key_name("interact"))
		hud.set_revive_progress(k)
	elif Net.my_id == reviver_id:
		var tname: String = Net.players[target_id].name if Net.players.has(target_id) else "Друг"
		hud.center_msg(tr("Поднимаешь %s... %d%%") % [tname, pct] if k > 0 else "")
		hud.set_revive_progress(k)
		_reviver_msg_shown = k > 0


func on_player_respawn(id: int, x: float, z: float) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.respawn(x, z)
	hud.set_revive_progress(0.0)
	if id == Net.my_id or _reviver_msg_shown:
		hud.center_msg("")
		_reviver_msg_shown = false


func on_buff(id: int, type: String, dur: float) -> void:
	var node = player_nodes.get(id)
	if node != null:
		node.apply_buff(type, dur)
		if type != "shield_end":
			var title: String = tr(PICKUP_TYPES.get(type, {}).get("title", type))
			fx_number(node.global_position, title + "!", PICKUP_TYPES.get(type, {}).get("color", Color.WHITE))
			fx_burst(node.global_position + Vector3(0, 1, 0), PICKUP_TYPES.get(type, {}).get("color", Color.WHITE), 14)
			Sfx.play_at("pickup", node.global_position)


# ---------------------------------------------------------------------------
# Чат и голос
# ---------------------------------------------------------------------------
func on_chat(sender: int, text: String) -> void:
	var pname: String = Net.players[sender].name if Net.players.has(sender) else "???"
	hud.add_chat(pname, text)
	if Net.debug_log:
		print("[TEST] chat rx from=%d: %s" % [sender, text])


func on_voice(sender: int, data: PackedByteArray) -> void:
	Voice.receive(sender, data)


# ---------------------------------------------------------------------------
# Гномы
# ---------------------------------------------------------------------------
## Уровень врагов: по главе кампании или волне выживания.
func enemy_level() -> int:
	if is_story():
		return Net.campaign_chapter
	if is_pvp():
		return 2
	return 1 + floori(maxi(wave - 1, 0) / 2.0)


## Небольшой шанс, что обычный спавн окажется редким "золотым" гномом —
## больше хп/урона, гарантированный жирный лут, своя ачивка за убийство.
const ELITE_CHANCE := 0.07


## Домики областей, рядом с которыми есть живые игроки (оверворлд): враги
## лезут из нор там, где отряд, а не по всей огромной карте.
func _active_houses() -> Array:
	if world_areas.is_empty():
		return houses
	var out: Array = []
	for house in houses:
		var aid: String = house.get("area", "")
		for area in world_areas:
			if area.id != aid:
				continue
			for id in player_nodes:
				if server_hp.get(id, 0) <= 0:
					continue
				var pp: Vector3 = player_nodes[id].global_position
				if Vector2(pp.x - area.center.x, pp.z - area.center.z).length() < area.radius + 18.0:
					out.append(house)
					break
			break
	return out if not out.is_empty() else houses


func server_spawn_gnome(type: String) -> void:
	gnome_seq += 1
	var px: float
	var pz: float
	var ex: float
	var ez: float
	if houses.is_empty():
		# ПвП-арена: спавн у края, выход к центру
		var sp: Vector3 = spawn_points[randi() % spawn_points.size()]
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
		and not is_pvp() and enemy_level() >= 2 and randf() < ELITE_CHANCE
	Net.bcast("rpc_gnome_spawn", [gnome_seq, type, px, pz, ex, ez, enemy_level(), is_elite])
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
	gnome_seq += 1
	Net.bcast("rpc_gnome_spawn", [gnome_seq, type, pos.x, pos.z, pos.x, pos.z, lvl, elite])


func on_gnome_spawn(id: int, type: String, x: float, z: float, ex: float, ez: float, lvl: int = 1, is_elite: bool = false) -> void:
	if gnomes.has(id):
		return
	if type == "ally_mage":
		Achievements.unlock("hire_ally")
	var g := Gnome.new()
	add_child(g)
	g.setup(self, id, type, Vector3(x, 0.1, z), Vector2(ex, ez), lvl, is_elite)
	if Net.is_server:
		var factor := (1.0 + 0.5 * maxf(0, Net.players.size() - 1)) * Quests.enemy_hp_mult(lvl)
		g.hp = roundi(g.hp * factor)
		g.max_hp = g.hp
	gnomes[id] = g
	fx_burst(Vector3(x, 0.6, z), Color(0.55, 0.4, 0.25), 8)
	_animate_door_near(x, z)


func _animate_door_near(x: float, z: float) -> void:
	for house in houses:
		if Vector2(house.x - x, house.z - z).length() < 4.0:
			var hinge: Node3D = house.door
			var t := create_tween()
			t.tween_property(hinge, "rotation:y", -1.9, 0.35).set_ease(Tween.EASE_OUT)
			t.tween_interval(0.8)
			t.tween_property(hinge, "rotation:y", 0.0, 0.4)
			return


func on_gnome_batch(batch: PackedFloat32Array) -> void:
	var n := batch.size() / 6
	for i in n:
		var o := i * 6
		var g = gnomes.get(int(batch[o]))
		if g != null and g.alive:
			g.apply_net_state(batch[o + 1], batch[o + 2], batch[o + 3], int(batch[o + 4]), int(batch[o + 5]))


func on_gnome_event(id: int, ev: String, data: Array) -> void:
	var g = gnomes.get(id)
	if g != null:
		g.on_event(ev, data)


func bcast_gnome_event(gid: int, ev: String, data: Array) -> void:
	Net.bcast("rpc_gnome_event", [gid, ev, data])


func server_gnome_died(g, from_pos: Vector3, crit: bool, finisher := false) -> void:
	if g.friendly:
		# павший наёмник — без опыта, лута и зачёта, но умереть он обязан:
		# иначе остаётся «бессмертным» и бьётся с отрицательным hp
		var fdir := Vector3(g.global_position.x - from_pos.x, 0, g.global_position.z - from_pos.z)
		fdir = fdir.normalized() if fdir.length_squared() > 0.001 else Vector3.FORWARD
		bcast_gnome_event(g.gid, "die", [fdir.x, fdir.z, crit, false, false])
		return
	var killer: int = g.last_attacker
	if killer > 0 and Net.players.has(killer):
		Net.players[killer].kills += 1
	var killer_ally = gnomes.get(g.last_attacker_gid)
	if killer_ally != null and killer_ally.friendly and killer_ally.alive:
		killer_ally.grant_ally_kill()
	if not is_pvp():
		server_grant_xp_all(roundi(Quests.xp_for_gnome(g.cfg) * Quests.enemy_xp_mult(g.level) * (1.5 if g.elite else 1.0)))
	else:
		Net.bcast("rpc_scores", [Net.players])
	if is_story():
		var gold_mult := 1.0
		if killer > 0 and Net.players.has(killer):
			gold_mult = Skills.gold_mult(Net.players[killer])
		if g.elite:
			gold_mult *= 3.0
		server_gold += roundi(randi_range(1, 3) * gold_mult)
		Net.bcast("rpc_gold", [server_gold])
		_story_on_gnome_died(g)
	if not is_pvp():
		var roll := randf()
		if g.type == "king":
			pass # король ничего не роняет — он и есть награда
		elif g.elite:
			pk_seq += 1
			Net.bcast("rpc_pickup_spawn", [pk_seq, "gold_feast", g.global_position.x, g.global_position.z])
		elif roll < 0.18:
			pk_seq += 1
			Net.bcast("rpc_pickup_spawn", [pk_seq, "heal", g.global_position.x, g.global_position.z])
		elif roll < 0.28:
			pk_seq += 1
			var types := PICKUP_TYPES.keys()
			Net.bcast("rpc_pickup_spawn", [pk_seq, types[randi() % types.size()], g.global_position.x, g.global_position.z])
	var dir := Vector3(g.global_position.x - from_pos.x, 0, g.global_position.z - from_pos.z)
	dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	bcast_gnome_event(g.gid, "die", [dir.x, dir.z, crit, g.elite, finisher, g.last_attacker])


func free_gnome_local(gid: int) -> void:
	if gnomes.has(gid):
		gnomes[gid].queue_free()
		gnomes.erase(gid)


func server_request_token(gid: int) -> bool:
	# наёмники не занимают токены атак — лимит только для нападающих на игроков
	var g = gnomes.get(gid)
	if g != null and g.friendly:
		return true
	if attackers.size() >= max_attackers:
		return false
	attackers[gid] = true
	return true


func server_release_token(gid: int) -> void:
	attackers.erase(gid)


func server_alert_nearby(pos: Vector3, radius: float, source) -> void:
	for g in gnomes.values():
		if g == source or not g.alive or g.alerted:
			continue
		if g.global_position.distance_to(pos) < radius:
			g.become_alerted(false)


func _spread_slots(delta: float) -> void:
	var circlers: Array = []
	for g in gnomes.values():
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


# ---------------------------------------------------------------------------
# Волны (сервер)
# ---------------------------------------------------------------------------
func _wave_composition(w: int) -> Array:
	var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
	var k: float = diff().count
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
	if w % FINAL_WAVE == 0:
		list.append(roles.boss)
	return list


func _start_wave(w: int) -> void:
	wave = w
	spawn_queue = _wave_composition(w)
	spawn_timer = 0.5
	wave_cleared = false
	max_attackers = maxi(1, 2 + floori(w / 3.0) + maxi(0, Net.players.size() - 1) + int(diff().tokens))
	for id in server_hp:
		if server_hp[id] <= 0:
			# павшие встают с новой волной, но лишь с половиной здоровья
			server_hp[id] = player_max_hp(id) / 2
			var pos := _player_spawn_pos()
			Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
			Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "heal", pos.x, pos.y])
	revive_progress.clear()
	# каждые 2 волны — новый сундук
	chest_wave_counter += 1
	if chest_wave_counter >= 2:
		chest_wave_counter = 0
		_server_place_chests(1)
	Net.bcast("rpc_wave", [w, endless, false])


func _update_waves_pve(delta: float) -> void:
	if not spawn_queue.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0:
			spawn_timer = randf_range(0.5, 1.0)
			server_spawn_gnome(spawn_queue.pop_front())
		return
	if wave == 0:
		return
	var alive := 0
	for g in gnomes.values():
		if g.alive:
			alive += 1
	if alive > 0:
		wave_down = 0.0
		return
	if not wave_cleared:
		wave_cleared = true
		wave_down = 0.0
		if not endless and wave >= FINAL_WAVE:
			_server_game_over(true, "ПОБЕДА! Племя гномов разбито!")
			return
		Net.bcast("rpc_banner", ["ВОЛНА ЗАЧИЩЕНА"])
		for id in server_hp:
			server_heal_player(id, 15)
	wave_down += delta
	if wave_down > 3.0:
		_start_wave(wave + 1)


func _update_pvp(delta: float) -> void:
	pvp_trickle -= delta
	if pvp_trickle <= 0:
		pvp_trickle = 12.0
		var alive := 0
		for g in gnomes.values():
			if g.alive:
				alive += 1
		if alive < 4:
			var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
			var types := [roles.melee, roles.fast, roles.caster]
			for i in 2:
				server_spawn_gnome(types[randi() % 3])
	for id in respawn_timers.keys():
		respawn_timers[id] -= delta
		if respawn_timers[id] <= 0:
			respawn_timers.erase(id)
			if server_hp.has(id):
				server_hp[id] = player_max_hp(id)
				var pos := _player_spawn_pos()
				Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])


const BLEEDOUT_TIME := 40.0
var downed_timers: Dictionary = {}


func _update_revives(delta: float) -> void:
	# автоподъём: если павшего так и не подняли — встаёт сам у точки спавна
	if not is_pvp() and Net.players.size() > 1:
		for id in server_hp:
			if server_hp[id] <= 0 and player_nodes.has(id):
				downed_timers[id] = downed_timers.get(id, 0.0) + delta
				if downed_timers[id] >= BLEEDOUT_TIME:
					downed_timers.erase(id)
					revive_progress.erase(id)
					server_hp[id] = player_max_hp(id) / 2
					var pos := _player_spawn_pos()
					Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
			else:
				downed_timers.erase(id)
	for id in revive_progress.keys():
		var e: Dictionary = revive_progress[id]
		e.idle += delta
		if e.idle > 0.6: # бросили поднимать
			revive_progress.erase(id)
			Net.bcast("rpc_revive_progress", [id, e.by, 0.0])


func _server_game_over(win: bool, text: String) -> void:
	match_over = true
	Net.bcast("rpc_game_over", [win, text])
	# финал кампании (ENDING:...) — это конец, а не проигрыш: никаких авто-рестартов,
	# иначе через 6 с в кооперативе поверх концовки заново запускается финальная глава
	if text.begins_with("ENDING:"):
		restart_timer = -1.0
		return
	if Net.mode != Net.Mode.SINGLE:
		restart_timer = 6.0
	elif not win and is_story():
		restart_timer = 6.0 # в одиночном сюжете глава перезапустится сама


func _server_restart_match() -> void:
	if is_story():
		Net.bcast("rpc_chapter", [Net.campaign_chapter, Net.biome, randi()])
		return
	for id in Net.players:
		Net.players[id].kills = 0
		Net.players[id].deaths = 0
	Net.bcast("rpc_match_reset", [])
	Net.bcast("rpc_scores", [Net.players])
	match_over = false
	respawn_timers.clear()
	revive_progress.clear()
	server_shield.clear()
	attackers.clear()
	_second_wind_used.clear()
	_bounty_used.clear() # доски объявлений снова активны в новом матче
	for id in server_hp:
		server_hp[id] = player_max_hp(id)
		var pos := _player_spawn_pos()
		Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
	if is_pvp():
		Net.bcast("rpc_wave", [0, false, true]) # сигнатура rpc_wave(n, is_endless, is_pvp)
	else:
		wave = 0
		endless = false
		_start_wave(1)


func server_continue_endless() -> void:
	endless = true
	match_over = false
	_start_wave(wave + 1)


func server_restart_single() -> void:
	if is_story():
		Net.bcast("rpc_chapter", [Net.campaign_chapter, Net.biome, randi()])
		return
	for id in Net.players:
		Net.players[id].kills = 0
		Net.players[id].deaths = 0
	Net.bcast("rpc_match_reset", [])
	Net.bcast("rpc_scores", [Net.players])
	match_over = false
	endless = false
	attackers.clear()
	server_shield.clear()
	_second_wind_used.clear() # иначе «второе дыхание» не сработает до конца сессии
	_bounty_used.clear()      # доски объявлений снова активны в новом матче
	server_hp[1] = player_max_hp(1) # с учётом Живучести, не голая константа
	Net.bcast("rpc_player_respawn", [1, 0.0, 0.0])
	wave = 0
	delay(1.5, func():
		if not match_over:
			_start_wave(1))


func on_match_reset() -> void:
	for gid in gnomes.keys():
		gnomes[gid].queue_free()
	gnomes.clear()
	for fid in fireballs.keys():
		fireballs[fid].node.queue_free()
	fireballs.clear()
	for bid in bombs.keys():
		bombs[bid].node.queue_free()
	bombs.clear()
	for pid in pickups.keys():
		pickups[pid].node.queue_free()
	pickups.clear()
	for qid in qnodes.keys():
		qnodes[qid].node.queue_free()
	qnodes.clear()
	downed_timers.clear()
	match_over = false
	hud.center_msg("")


func on_daytime(t: float) -> void:
	if daynight != null:
		daynight.sync_time(t)


func on_wave(n: int, is_endless: bool, is_pvp_mode: bool) -> void:
	wave = n
	endless = is_endless
	# текст волны собирается локально — на языке игрока
	if is_pvp_mode:
		wave_text = tr("ПвП: до %d убийств") % PVP_TARGET
	elif is_endless:
		wave_text = tr("Волна %d · бесконечность") % n
	else:
		wave_text = tr("Волна %d из %d") % [n, FINAL_WAVE]
	hud.set_wave(wave_text)
	if n > 0:
		hud.banner(tr("ВОЛНА %d") % n)
		Sfx.play("wave_horn", -4.0)


func on_banner(text: String) -> void:
	hud.banner(tr(text))


func on_scores() -> void:
	hud.set_scores(Net.players, is_pvp(), Net.my_id)
	if Net.players.has(Net.my_id):
		var me: Dictionary = Net.players[Net.my_id]
		if not is_pvp():
			if me.kills >= 1:
				Achievements.unlock("first_blood")
			if me.kills >= 100:
				Achievements.unlock("monster_slayer")
		if is_pvp():
			hud.set_pvp_kills(me.kills)
		else:
			hud.set_kills(me.kills)
		if me.has("xp") and not is_pvp():
			hud.set_xp(me.level, me.xp, Quests.xp_to_next(me.level))
	# запись на диск — не чаще, чем нужно (сейв на каждый килл давал фризы)
	if Net.players.has(Net.my_id):
		_hero_dirty = true
		hud.set_stat_points(Net.players[Net.my_id].get("points", 0))
	for id in Net.players:
		var lvl: int = Net.players[id].get("level", 1)
		if _known_levels.get(id, 1) < lvl:
			var node = player_nodes.get(id)
			if node != null:
				fx_burst(node.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.3), 18)
				fx_number(node.global_position, tr("УРОВЕНЬ %d!") % lvl, Color(1.0, 0.9, 0.3))
			if id == Net.my_id:
				hud.banner(tr("УРОВЕНЬ %d!") % lvl)
				Sfx.play("victory", -6.0)
				_flush_hero_save() # левел-ап — важное событие, пишем сразу
		_known_levels[id] = lvl


func on_game_over(win: bool, text: String) -> void:
	match_over = true
	if win and not is_pvp():
		Sfx.play("victory")
		for p in player_nodes.values():
			p.play_victory()
	hud.banner(tr("ФИНАЛ КАМПАНИИ") if text.begins_with("ENDING:") else tr(text), 4.0)
	if not win and is_story():
		hud.center_msg(tr("Отряд пал. Глава начнётся заново..."))
	if main != null:
		main.show_game_over(win, text)


# ---------------------------------------------------------------------------
# Фаерболы
# ---------------------------------------------------------------------------
func server_spawn_fireball(gnome) -> void:
	if gnome.target == null:
		return
	fb_seq += 1
	var from: Vector3 = gnome.global_position + Vector3(0, 1.0, 0)
	var tpos: Vector3 = gnome.target.global_position + Vector3(0, 0.9, 0)
	var tvel := Vector3.ZERO
	if gnome.target is PlayerChar and gnome.target.is_local:
		tvel = gnome.target.velocity
	var lead := minf(from.distance_to(tpos) / 11.0, 0.8)
	tpos += Vector3(tvel.x, 0, tvel.z) * lead * 0.55
	var dir: Vector3 = (tpos - from).normalized()
	var color: Color = gnome.cfg.get("projectile_color", Color(1.0, 0.45, 0.13))
	Net.bcast("rpc_fireball", [fb_seq, from, dir, color])
	# сервер помнит, чей это снаряд (клиентам достаточно картинки)
	if fireballs.has(fb_seq):
		fireballs[fb_seq].friendly = gnome.friendly
		fireballs[fb_seq].owner = gnome.owner_id
		fireballs[fb_seq].source_gid = gnome.gid


func on_fireball(fid: int, from: Vector3, dir: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	add_child(mesh)
	mesh.global_position = from
	if fireballs.size() < 3:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 4.0
		light.omni_range = 7.0
		mesh.add_child(light)
	fireballs[fid] = {"node": mesh, "dir": dir, "life": 0.0, "color": color}
	Sfx.play_at("fireball", from)


func on_fireball_boom(fid: int, pos: Vector3) -> void:
	fx_burst(pos, Color(1.0, 0.5, 0.15), 14)
	Sfx.play_at("explode", pos)
	if fireballs.has(fid):
		fireballs[fid].node.queue_free()
		fireballs.erase(fid)


func _update_fireballs(delta: float) -> void:
	for fid in fireballs.keys():
		var fb: Dictionary = fireballs[fid]
		fb.life += delta
		fb.node.global_position += fb.dir * 11.0 * delta
		if not Net.is_server:
			continue
		var boom: bool = fb.life > 3.0 or fb.node.global_position.y < 0.05
		if fb.get("friendly", false):
			# снаряд наёмника бьёт по гномам
			for g in gnomes.values():
				if not g.alive or g.friendly:
					continue
				if fb.node.global_position.distance_to(g.global_position + Vector3(0, 0.7, 0)) < 0.9:
					g.last_attacker = fb.get("owner", 0)
					g.last_attacker_gid = fb.get("source_gid", 0)
					g.server_take_damage(14, fb.node.global_position, false)
					boom = true
					break
		else:
			for id in player_nodes:
				var p = player_nodes[id]
				if server_hp.get(id, 0) <= 0:
					continue
				if fb.node.global_position.distance_to(p.global_position + Vector3(0, 0.9, 0)) < 0.8:
					server_damage_player(id, 12, fb.node.global_position)
					boom = true
					break
			# вражеский снаряд задевает и наёмников
			if not boom:
				for g in gnomes.values():
					if not g.alive or not g.friendly:
						continue
					if fb.node.global_position.distance_to(g.global_position + Vector3(0, 0.7, 0)) < 0.9:
						g.last_attacker = 0
						g.server_take_damage(12, fb.node.global_position, false)
						boom = true
						break
		if boom:
			var pos: Vector3 = fb.node.global_position
			fireballs.erase(fid)
			fb.node.queue_free()
			Net.bcast("rpc_fireball_boom", [fid, pos])


# ---------------------------------------------------------------------------
# Предметы
# ---------------------------------------------------------------------------
func on_pickup_spawn(pid: int, type: String, x: float, z: float) -> void:
	var node: Node3D
	var color: Color
	if type == "heal":
		node = WorldGen._mushroom(self, _rng, x, z, 1.9)
		color = Color(0.55, 0.85, 0.4)
	elif ITEM_DEFS.has(type):
		# предмет инвентаря: бутылка/монеты из данжен-пака или бомба
		color = ITEM_DEFS[type].color
		var mesh_name: String = ITEM_DEFS[type].mesh
		if mesh_name != "" and models.has(mesh_name):
			node = models[mesh_name].instantiate()
			add_child(node)
			var tint: Color = ITEM_DEFS[type].tint
			if tint != Color.WHITE:
				for mi in node.find_children("*", "MeshInstance3D", true, false):
					for i in mi.get_surface_override_material_count():
						var mat = mi.get_active_material(i)
						if mat != null:
							var m2 = mat.duplicate()
							m2.albedo_color = Color(m2.albedo_color.r * tint.r, m2.albedo_color.g * tint.g, m2.albedo_color.b * tint.b, 1.0)
							mi.set_surface_override_material(i, m2)
			node.scale = Vector3.ONE * 1.6
		else:
			node = Node3D.new()
			add_child(node)
			var mesh := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			mesh.mesh = sm
			mesh.material_override = WorldGen._mat(Color(0.16, 0.16, 0.2))
			mesh.position.y = 0.25
			node.add_child(mesh)
		node.global_position = Vector3(x, 0, z)
	elif type == "greatsword":
		color = PICKUP_TYPES[type].color
		node = Node3D.new()
		add_child(node)
		var sword: Node3D = models["sword_2handed"].instantiate()
		node.add_child(sword)
		sword.rotation_degrees = Vector3(0, 0, 195) # воткнут в землю остриём
		sword.position.y = 1.15
		for mi in sword.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.global_position = Vector3(x, 0, z)
	else:
		color = PICKUP_TYPES.get(type, {}).get("color", Color.WHITE)
		node = WorldGen.crystal(self, color)
		node.global_position = Vector3(x, 0, z)
	pickups[pid] = {"node": node, "life": 0.0, "type": type}
	var final_scale: float = ITEM_DEFS[type].get("mscale", 1.6) if ITEM_DEFS.has(type) else 1.0
	node.scale = Vector3.ONE * 0.05
	var t := create_tween()
	t.tween_property(node, "scale", Vector3.ONE * final_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fx_burst(Vector3(x, 0.4, z), color, 8)


func on_pickup_taken(pid: int) -> void:
	if pickups.has(pid):
		pickups[pid].node.queue_free()
		pickups.erase(pid)


func _update_pickups(delta: float) -> void:
	for pid in pickups.keys():
		var pk: Dictionary = pickups[pid]
		pk.life += delta
		pk.node.position.y = 0.15 + sin(pk.life * 3.0) * 0.12
		pk.node.rotation.y += delta * 2.0
		if not Net.is_server:
			continue
		if pk.life < 1.0:
			continue # дать заметить, а не съедать в кадр появления
		var taken_by := 0
		for id in player_nodes:
			if server_hp.get(id, 0) <= 0:
				continue
			if pk.type == "heal" and server_hp.get(id, 0) >= player_max_hp(id):
				continue # гриб при полном здоровье не тратится
			if pk.node.global_position.distance_to(player_nodes[id].global_position) < 1.4:
				taken_by = id
				break
		if taken_by != 0:
			match pk.type:
				"heal":
					server_heal_player(taken_by, 20)
				"shield":
					server_shield[taken_by] = SHIELD_POINTS
					Net.bcast("rpc_buff", [taken_by, "shield", 999.0])
				"potion_hp", "potion_rage", "potion_speed", "bomb", "gold_feast":
					_server_grant_item(taken_by, pk.type)
				_:
					Net.bcast("rpc_buff", [taken_by, pk.type, PICKUP_TYPES[pk.type].dur])
			pickups.erase(pid)
			pk.node.queue_free()
			Net.bcast("rpc_pickup_taken", [pid])
		elif pk.life > 30.0:
			pickups.erase(pid)
			pk.node.queue_free()
			Net.bcast("rpc_pickup_taken", [pid])


# ---------------------------------------------------------------------------
# Сюжет: лагерь, НПС, квесты
# ---------------------------------------------------------------------------
const CAMP_POS := Vector3(6.0, 0.0, 6.0)
const SAFE_RADIUS := 7.0

# портал в конце главы (вместо мгновенного телепорта): открывается, когда
# рассказ закончен, переход — когда игрок сам входит в портал.
var portal_open := false
var portal_pos := Vector3.ZERO
var portal_node: Node3D = null

# найм вольных магов (сюжет): вербовщик в лагере, оплата — золото отряда
const HIRE_COST := 30
const HIRE_NPC := {"model": "Mage", "name": "Вольный маг Фырк", "tint": Color(0.72, 1.0, 0.78)}


## Сейф-зона лагеря (только сюжет): враги сюда не заходят и урон не проходит.
func in_safe_zone(pos: Vector3) -> bool:
	return is_story() and Vector2(pos.x - CAMP_POS.x, pos.z - CAMP_POS.z).length() < SAFE_RADIUS


func chapter_cfg() -> Dictionary:
	return Quests.CHAPTERS[clampi(Net.campaign_chapter - 1, 0, Quests.CHAPTERS.size() - 1)]


func _build_camp() -> void:
	# костёр
	var fire_root := Node3D.new()
	add_child(fire_root)
	fire_root.global_position = CAMP_POS
	for i in 4:
		var log_m := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.09
		lm.bottom_radius = 0.11
		lm.height = 1.0
		log_m.mesh = lm
		log_m.material_override = WorldGen._mat(Color(0.35, 0.24, 0.15))
		log_m.rotation = Vector3(PI * 0.42, i * PI * 0.5, 0)
		log_m.position.y = 0.22
		fire_root.add_child(log_m)
	fire_root.add_child(_make_fire())
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.25)
	fl.light_energy = 1.6
	fl.omni_range = 9.0
	fl.position.y = 1.0
	fire_root.add_child(fl)

	# шатёр — дом сюжетных персонажей; костёр стоит внутри, у входа
	_build_tent(CAMP_POS + Vector3(0, 0, -1.0))

	# НПС под шатром, лицом к костру
	var cfg := chapter_cfg()
	var npc_main := Npc.new()
	add_child(npc_main)
	npc_main.setup(self, cfg.npc_main, CAMP_POS + Vector3(-1.5, 0, -2.4), CAMP_POS)
	var npc_side := Npc.new()
	add_child(npc_side)
	npc_side.setup(self, cfg.npc_side, CAMP_POS + Vector3(1.5, 0, -2.6), CAMP_POS)
	# вербовщик вольных магов — сбоку, у края навеса
	var npc_hire := Npc.new()
	add_child(npc_hire)
	npc_hire.setup(self, HIRE_NPC, CAMP_POS + Vector3(2.8, 0, -0.6), CAMP_POS + Vector3(0, 0, 4))
	npcs = [npc_main, npc_side, npc_hire]
	_update_npc_markers()


## Походный шатёр: конусная крыша на шестах, открыт к костру.
func _build_tent(pos: Vector3) -> void:
	var tent := Node3D.new()
	add_child(tent)
	tent.global_position = pos

	# крыша-конус (ещё выше — с запасом даже для голов в шапках и капюшонах)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.02
	rm.bottom_radius = 3.6
	rm.height = 2.3
	rm.radial_segments = 10
	roof.mesh = rm
	roof.material_override = WorldGen._mat(Color(0.62, 0.2, 0.16))
	roof.position.y = 4.75
	tent.add_child(roof)
	# светлая оторочка по краю крыши
	var rim := MeshInstance3D.new()
	var rmm := CylinderMesh.new()
	rmm.top_radius = 3.52
	rmm.bottom_radius = 3.62
	rmm.height = 0.22
	rmm.radial_segments = 10
	rim.mesh = rmm
	rim.material_override = WorldGen._mat(Color(0.9, 0.82, 0.66))
	rim.position.y = 3.68
	tent.add_child(rim)

	const POLE_H := 3.9
	# шесты по кругу (спереди — шире, вход к костру)
	for i in 5:
		var ang := PI * 0.28 + TAU * float(i) / 5.0
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.06
		pm.bottom_radius = 0.08
		pm.height = POLE_H
		pole.mesh = pm
		pole.material_override = WorldGen._mat(Color(0.4, 0.28, 0.18))
		pole.position = Vector3(sin(ang) * 3.0, POLE_H * 0.5, cos(ang) * 3.0)
		tent.add_child(pole)

	# вымпел на макушке
	var flag := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.55, 0.3, 0.04)
	flag.mesh = fm
	flag.material_override = WorldGen._mat(Color(0.95, 0.8, 0.3))
	flag.position = Vector3(0.28, 6.0, 0)
	flag.rotation.z = -PI * 0.5
	tent.add_child(flag)

	# тёплый фонарик под крышей
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 0.9
	lamp.omni_range = 6.5
	lamp.position.y = 3.9
	tent.add_child(lamp)

	# половик под ногами у НПС — читается как обжитое место, а не голый каркас
	var rug := MeshInstance3D.new()
	var rugm := CylinderMesh.new()
	rugm.top_radius = 2.6
	rugm.bottom_radius = 2.6
	rugm.height = 0.03
	rugm.radial_segments = 10
	rug.mesh = rugm
	rug.material_override = WorldGen._mat(Color(0.5, 0.16, 0.14))
	rug.position.y = 0.02
	tent.add_child(rug)

	# растяжки от шестов к земле — придают шатру вес и объём настоящей палатки
	for i in 5:
		var ang := PI * 0.28 + TAU * float(i) / 5.0
		var top := Vector3(sin(ang) * 3.0, POLE_H - 0.35, cos(ang) * 3.0)
		var out := Vector3(sin(ang) * 4.1, 0.0, cos(ang) * 4.1)
		var dir := out - top
		var rope := MeshInstance3D.new()
		var rm2 := CylinderMesh.new()
		rm2.top_radius = 0.025
		rm2.bottom_radius = 0.025
		rm2.height = dir.length()
		rope.mesh = rm2
		rope.material_override = WorldGen._mat(Color(0.55, 0.5, 0.42))
		# по умолчанию цилиндр вытянут вдоль Y — совмещаем эту ось с направлением растяжки
		var y_axis := dir.normalized()
		var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
		if x_axis.length() < 0.01:
			x_axis = y_axis.cross(Vector3.RIGHT).normalized()
		var z_axis := x_axis.cross(y_axis).normalized()
		rope.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (top + out) * 0.5)
		tent.add_child(rope)
		var peg := MeshInstance3D.new()
		var pegm := CylinderMesh.new()
		pegm.top_radius = 0.03
		pegm.bottom_radius = 0.05
		pegm.height = 0.3
		peg.mesh = pegm
		peg.material_override = WorldGen._mat(Color(0.35, 0.3, 0.24))
		peg.position = Vector3(out.x, 0.12, out.z)
		tent.add_child(peg)


func _make_fire() -> GPUParticles3D:
	var fire := GPUParticles3D.new()
	fire.amount = 22
	fire.lifetime = 0.8
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 12.0
	fm.initial_velocity_min = 1.0
	fm.initial_velocity_max = 2.0
	fm.gravity = Vector3(0, 1.5, 0)
	fm.scale_min = 0.5
	fm.scale_max = 1.4
	fm.color = Color(1.0, 0.55, 0.15)
	fire.process_material = fm
	var fdm := SphereMesh.new()
	fdm.radius = 0.09
	fdm.height = 0.18
	fdm.radial_segments = 6
	fdm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fdm.material = fmat
	fire.draw_pass_1 = fdm
	fire.position.y = 0.35
	return fire


## Портал — конец главы: рассказ закончен, но переход происходит, когда игрок
## сам входит в мерцающее кольцо, а не мгновенным телепортом со сменой экрана.
func on_portal_spawn(x: float, z: float) -> void:
	if portal_node != null:
		return
	portal_node = Node3D.new()
	add_child(portal_node)
	portal_node.global_position = Vector3(x, 0, z)

	# каменная арка вместо голого кольца — портал стоит в настоящем дверном
	# проёме, а не левитирует посреди поляны
	var arch := WorldGen.prop_scene("dungeon/wall_arched.gltf.glb").instantiate()
	portal_node.add_child(arch)
	for mi in arch.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for side in [-1.0, 1.0]:
		var col := WorldGen.prop_scene("dungeon/pillar_decorated.gltf.glb").instantiate()
		portal_node.add_child(col)
		col.position = Vector3(side * 2.4, 0, 0.3)
		for mi in col.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.3
	tm.outer_radius = 1.7
	tm.rings = 24
	tm.ring_segments = 12
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.35, 1.0)
	rmat.emission_enabled = true
	rmat.emission = Color(0.6, 0.4, 1.0)
	rmat.emission_energy_multiplier = 1.4
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	ring.rotation.x = PI * 0.5
	ring.position.y = 1.7
	portal_node.add_child(ring)

	var swirl := GPUParticles3D.new()
	swirl.amount = 40
	swirl.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.FORWARD
	pm.emission_ring_radius = 1.6
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.05
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -1.4
	pm.radial_accel_max = -1.0
	pm.orbit_velocity_min = 0.4
	pm.orbit_velocity_max = 0.6
	pm.scale_min = 0.3
	pm.scale_max = 0.7
	pm.color = Color(0.65, 0.5, 1.0)
	swirl.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.emission_enabled = true
	smat.emission = Color(0.65, 0.5, 1.0)
	sm.material = smat
	swirl.draw_pass_1 = sm
	swirl.position.y = 1.7
	portal_node.add_child(swirl)

	var pl := OmniLight3D.new()
	pl.light_color = Color(0.6, 0.4, 1.0)
	pl.light_energy = 2.0
	pl.omni_range = 8.0
	pl.position.y = 1.7
	portal_node.add_child(pl)

	# кольцо медленно вращается — веретено портала, не статичная картинка
	var spin_tween := create_tween().set_loops()
	spin_tween.tween_property(ring, "rotation:y", TAU, 6.0).as_relative().from_current()


## Катсцена конца главы: полосы, взгляд камеры на портал/сцену и пара
## субтитров вместо мгновенной смены экрана. Чисто локальный эффект — сеть
## синхронизирует только момент запуска и сами реплики.
func on_cutscene(lines: Array, fx: float, fy: float, fz: float) -> void:
	play_cutscene(lines, Vector3(fx, fy, fz))


## Полноценная катсцена: отдельная камера (не игрока) идёт по срежиссированным
## планам — наезд и облёт точки внимания, — с жёсткой склейкой между репликами,
## а не просто взгляд игрока в сторону портала.
func play_cutscene(lines: Array, focus_pos: Vector3) -> void:
	ui_blocked = true
	hud.cutscene_start()

	var look_at_pos := focus_pos + Vector3(0, 1.3, 0)
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)

	var shots := [
		{"from": focus_pos + Vector3(7.5, 3.6, 5.5), "to": focus_pos + Vector3(4.2, 2.4, 3.0)},
		{"from": focus_pos + Vector3(-6.5, 2.6, -4.5), "to": focus_pos + Vector3(-3.2, 1.9, -2.2)},
		{"from": focus_pos + Vector3(0.5, 4.2, -7.0), "to": focus_pos + Vector3(0.2, 2.2, -3.5)},
	]
	var shot_i := 0
	for line in lines:
		var shot: Dictionary = shots[shot_i % shots.size()]
		shot_i += 1
		cam.global_position = shot.from
		cam.look_at(look_at_pos, Vector3.UP)
		cam.current = true
		# время на экране считается от длины реплики (см. Hud.cutscene_line) —
		# камера подстраивает свой наезд под тот же хронометраж
		var wait_time: float = hud.cutscene_line(tr(line))
		var cam_dur: float = clampf(wait_time * 0.55, 1.4, 2.8)
		var cam_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		cam_tween.tween_method(func(k: float):
			if is_instance_valid(cam):
				cam.global_position = shot.from.lerp(shot.to, k)
				cam.look_at(look_at_pos, Vector3.UP), 0.0, 1.0, cam_dur)
		await get_tree().create_timer(wait_time).timeout
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(cam):
		cam.queue_free()
	var pn = player_nodes.get(Net.my_id)
	if pn != null and pn.camera != null and is_instance_valid(pn.camera):
		pn.camera.current = true
	hud.cutscene_end()
	ui_blocked = false
	# катсцена могла принудительно закрыть окно характеристик — вернём захват мыши
	if pn != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func find_npc_near(pos: Vector3, radius: float) -> int:
	for i in npcs.size():
		if npcs[i].global_position.distance_to(pos) < radius:
			return i
	return -1


func find_qnode_near(pos: Vector3, radius: float) -> int:
	for id in qnodes:
		var qn: Dictionary = qnodes[id]
		if not qn.taken and qn.node.global_position.distance_to(pos) < radius:
			return id
	return 0


func _update_npc_markers() -> void:
	if npcs.is_empty():
		return
	npcs[0].set_marker("!" if q_main == 0 else ("?" if q_main == 4 else ""))
	npcs[1].set_marker("!" if q_side == -1 else ("?" if q_side == 2 else ""))


## Диалог с НПС (локально); по завершении — запрос серверу, если этап «поговорить».
func start_dialog(npc_idx: int) -> void:
	var cfg := chapter_cfg()
	var dialog_key := ""
	var advance := ""
	if npc_idx == 0:
		if q_main == 0:
			dialog_key = cfg.intro
			advance = "main"
		elif q_main == 4:
			dialog_key = cfg.done
			advance = "main"
		else:
			dialog_key = cfg.intro
	elif npc_idx == 2:
		dialog_key = "hire_offer"
		advance = "hire"
	else:
		if q_side == 2:
			dialog_key = cfg.side_talk + "_done"
			advance = "side"
		else:
			dialog_key = cfg.side_talk
			if q_side == -1:
				advance = "side"
	if dialog_key == "":
		return
	ui_blocked = true
	hud.show_dialog(Quests.DIALOGS[dialog_key], advance)


func dialog_closed(advance: String) -> void:
	ui_blocked = false
	if advance != "":
		Net.req_talk(advance)


# --- серверная логика квестов ---
func _server_story_begin() -> void:
	if not _carry_restored:
		# свежая глава; после возврата из подземелья квест уже восстановлен
		q_main = 0
		q_kills = 0
		q_side = -1
		q_side_n = 0
		boss_gid = 0
	_bcast_quest()
	max_attackers = maxi(1, 2 + maxi(0, Net.players.size() - 1) + int(diff().tokens))
	var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
	var pop: int = diff().story_pop
	for i in pop:
		var types := [roles.melee, roles.melee, roles.fast, roles.caster]
		server_spawn_gnome(types[i % types.size()])
	# вернулись из подземелья с недобитым сайд-квестом на сбор — доложить объекты
	if _carry_restored and q_side == 1:
		_server_respawn_side_qnodes()


## Осколок и подземелье: стартовая населённость данжа + босс в дальнем зале.
func _server_dungeon_begin() -> void:
	_bcast_quest()
	max_attackers = maxi(1, 2 + maxi(0, Net.players.size() - 1) + int(diff().tokens))
	var roles: Dictionary = BIOME_ENEMIES.get("night", {})  # в склепе всегда нежить
	# сундуки по комнатам
	for spot in dungeon_chest_spots:
		chest_seq += 1
		Net.bcast("rpc_chest_spawn", [chest_seq, spot.x, spot.z, randf_range(0, TAU)])
	# охрана комнат
	var pop: int = maxi(5, diff().story_pop - 2)
	var types := [roles.melee, roles.melee, roles.fast, roles.caster]
	for i in pop:
		var a := randf_range(0, TAU)
		var r := randf_range(2.0, 5.0)
		var base: Vector3 = boss_spot if i % 3 == 0 else spawn_points[0]
		# раскидываем по комнатам: треть у босса, остальные от входа вглубь
		server_spawn_gnome_at(types[i % types.size()], base + Vector3(cos(a) * r, 0, sin(a) * r), enemy_level())
	# босс ждёт в дальнем зале
	if q_main == 2:
		boss_gid = gnome_seq + 1
		server_spawn_gnome_at(roles.boss, boss_spot, enemy_level())
		Net.bcast("rpc_banner", ["ХРАНИТЕЛЬ ОСКОЛКА ЗДЕСЬ"])


## Доспавнить недостающие объекты сайд-квеста после возврата из подземелья.
func _server_respawn_side_qnodes() -> void:
	var side: Dictionary = chapter_cfg().side
	if side.get("type", "") != "collect":
		return # kill-квесты объектов не имеют
	var need: int = int(side.get("count", 0)) - q_side_n
	for i in maxi(0, need):
		_server_spawn_qnode(side.get("kind", "mushroom"))


func story_kill_target() -> int:
	return maxi(3, roundi(chapter_cfg().kill_count * diff().count))


func _bcast_quest() -> void:
	Net.bcast("rpc_quest", [q_main, q_kills, q_side, q_side_n])


func server_talk(sender: int, which: String) -> void:
	if not is_story() or match_over:
		return
	var cfg := chapter_cfg()
	if which == "main":
		if q_main == 0:
			q_main = 1
			_bcast_quest()
		elif q_main == 4:
			_server_open_portal()
	elif which == "hire":
		_server_try_hire(sender)
	elif which == "side":
		if q_side == -1:
			q_side = 1
			_bcast_quest()
			if cfg.side.type == "collect":
				for i in cfg.side.count:
					_server_spawn_qnode(cfg.side.kind)
		elif q_side == 2:
			# сдача: награда и отметка в кампании
			q_side = 3
			Net.sides_mask |= 1 << (Net.campaign_chapter - 1)
			if Net.mode != Net.Mode.CLIENT:
				Save.sides_mask = Net.sides_mask
				Save.write()
			server_grant_xp_all(Quests.XP_SIDE_REWARD)
			for id in Net.players:
				_server_grant_item(id, "bomb")
			Net.bcast("rpc_banner", ["ЗАДАНИЕ ВЫПОЛНЕНО"])
			_bcast_quest()


func _server_spawn_qnode(kind: String, at := Vector3.INF) -> void:
	qnode_seq += 1
	var pos := at
	if pos == Vector3.INF:
		for _try in 60:
			if not world_areas.is_empty():
				# оверворлд: квест-объекты внутри областей вдоль пути (не в глухом лесу)
				var area: Dictionary = world_areas[randi() % world_areas.size()]
				var aa := randf_range(0, TAU)
				var ar: float = area.radius * randf_range(0.3, 0.8)
				pos = Vector3(area.center.x + cos(aa) * ar, 0, area.center.z + sin(aa) * ar)
			else:
				var a := randf_range(0, TAU)
				var r := randf_range(10.0, WorldGen.WORLD_RADIUS - 5.0)
				pos = Vector3(cos(a) * r, 0, sin(a) * r)
			if pos.distance_to(CAMP_POS) > SAFE_RADIUS + 2.0 and _clear_of_houses(pos):
				break
	Net.bcast("rpc_qnode", [qnode_seq, kind, pos.x, pos.z])


## Найм вольного мага (сервер): проверка золота и лимита, спавн у лагеря.
func _server_try_hire(sender: int) -> void:
	if not is_story() or match_over:
		return
	var allies := 0
	for g in gnomes.values():
		if g.friendly and g.alive:
			allies += 1
	if allies >= Net.players.size() + 1:
		Net.send_sys(sender, "У Фырка кончились свободные ученики.")
		return
	if server_gold < HIRE_COST:
		Net.send_sys(sender, "Не хватает золота — маг работает по предоплате.")
		return
	server_gold -= HIRE_COST
	Net.bcast("rpc_gold", [server_gold])
	var pn = player_nodes.get(sender)
	var dir := Vector3(0, 0, 1)
	if pn != null:
		dir = pn.global_position - CAMP_POS
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, 1)
	var px: float = CAMP_POS.x + dir.x * (SAFE_RADIUS + 0.6)
	var pz: float = CAMP_POS.z + dir.z * (SAFE_RADIUS + 0.6)
	gnome_seq += 1
	Net.bcast("rpc_gnome_spawn", [gnome_seq, "ally_mage", px, pz,
		px + dir.x * 1.5, pz + dir.z * 1.5, enemy_level()])
	if gnomes.has(gnome_seq):
		gnomes[gnome_seq].owner_id = sender
	Net.bcast("rpc_sys", ["Вольный маг нанят! Он пойдёт за нанимателем."])


func on_gold(total: int) -> void:
	gold = total
	if total >= 500:
		Achievements.unlock("wealthy")
	_update_quest_hud()


func on_sys(text: String) -> void:
	hud.add_chat("", tr(text), true)


## Точка не внутри домика и не в дереве/камне/точке интереса — иначе не достать
## (или сундук окажется в текстуре объекта).
func _clear_of_houses(pos: Vector3) -> bool:
	for house in houses:
		if Vector2(house.x - pos.x, house.z - pos.z).length() < 4.5:
			return false
	for o in world_obstacles:
		if Vector2(o.x - pos.x, o.z - pos.z).length() < o.r + 1.2:
			return false
	return true


func server_qnode_take(sender: int, id: int) -> void:
	if not is_story() or match_over:
		return
	var qn: Dictionary = qnodes.get(id, {})
	if qn.is_empty() or qn.taken:
		return
	var pn = player_nodes.get(sender)
	if pn == null or pn.global_position.distance_to(qn.node.global_position) > 3.0:
		return
	match qn.kind:
		"shard":
			if q_main == 3:
				q_main = 4
				Net.bcast("rpc_qnode_taken", [id])
				Net.bcast("rpc_banner", ["ОСКОЛОК СЕРДЦА У ТЕБЯ!"])
				_bcast_quest()
		"mushroom":
			if q_side == 1:
				q_side_n += 1
				Net.bcast("rpc_qnode_taken", [id])
				_check_side_done()
				_bcast_quest()
		"bonfire":
			if q_side == 1:
				q_side_n += 1
				Net.bcast("rpc_qnode_lit", [id])
				_check_side_done()
				_bcast_quest()


func _check_side_done() -> void:
	var cfg := chapter_cfg()
	if q_side == 1 and q_side_n >= cfg.side.count:
		q_side = 2
		Net.bcast("rpc_banner", ["ВОЗВРАЩАЙСЯ В ЛАГЕРЬ"])


func _story_on_gnome_died(g) -> void:
	var cfg := chapter_cfg()
	var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
	if q_main == 1 and g.gid != boss_gid:
		q_kills += 1
		if q_kills >= story_kill_target():
			# дорога расчищена — хранитель осколка ждёт в склепе на дальнем краю
			q_main = 2
			Net.bcast("rpc_banner", ["ХРАНИТЕЛЬ ОСКОЛКА — В СКЛЕПЕ НА КРАЮ ЛЕСА"])
		_bcast_quest()
	elif q_main == 2 and g.gid == boss_gid:
		q_main = 3
		_server_spawn_qnode("shard", g.global_position)
		_bcast_quest()
	if q_side == 1 and cfg.side.type == "kill_fast" and g.type == roles.fast:
		q_side_n += 1
		_check_side_done()
		_bcast_quest()


## Портал открывается вместо мгновенного телепорта: рассказ закончен на месте,
## а переход в следующую главу — осознанный шаг игрока, а не смена экрана.
func _server_open_portal() -> void:
	if portal_open:
		return
	portal_open = true
	portal_pos = CAMP_POS + Vector3(0, 0, SAFE_RADIUS + 3.0) # запасной вариант, если не найдём место почище
	for _try in 20:
		var away := Vector2(0, 1).rotated(randf_range(0, TAU))
		var cand: Vector3 = CAMP_POS + Vector3(away.x, 0, away.y) * (SAFE_RADIUS + 3.0)
		if _clear_of_houses(cand):
			portal_pos = cand
			break
	Net.bcast("rpc_portal_spawn", [portal_pos.x, portal_pos.z])
	q_main = 5
	_bcast_quest()


func _server_chapter_complete() -> void:
	server_grant_xp_all(Quests.XP_CHAPTER_REWARD)
	match_over = true
	# катсцена портала — рассказ подводит итог главы, пока экран занят полосами и субтитрами
	var outro: Array = Quests.CHAPTER_OUTRO[Net.campaign_chapter - 1] if Net.campaign_chapter - 1 < Quests.CHAPTER_OUTRO.size() else []
	Net.bcast("rpc_cutscene", [outro, portal_pos.x, portal_pos.y, portal_pos.z])
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
		restart_timer = -1.0 # финал кампании — без авторестарта
		delay(4.8, func():
			_server_game_over(true, "ENDING:%s:%d" % [ending, done]))
		return
	var next := Net.campaign_chapter + 1
	if Net.mode != Net.Mode.CLIENT:
		Save.chapter = next
		Save.store_hero(Net.players.get(1, {}))
	var nbiome: String = Quests.CHAPTER_BIOMES[next - 1]
	var nseed := randi()
	delay(4.8, func():
		Net.bcast("rpc_chapter", [next, nbiome, nseed]))


func _update_story(delta: float) -> void:
	if portal_open:
		for id in player_nodes:
			var p = player_nodes[id]
			if server_hp.get(id, 0) > 0 and p.global_position.distance_to(portal_pos) < 2.2:
				portal_open = false
				if portal_mode == "dungeon_exit":
					_server_exit_dungeon()
				else:
					_server_chapter_complete()
				break
		return # ждём, пока игрок сам шагнёт в портал

	# --- подземелье: шипы, выход после осколка; трикл врагов не нужен ---
	if is_dungeon():
		_trap_tick -= delta
		if _trap_tick <= 0:
			_trap_tick = 0.8
			for id in player_nodes:
				if server_hp.get(id, 0) <= 0:
					continue
				var pp: Vector3 = player_nodes[id].global_position
				for t in dungeon_traps:
					if Vector2(pp.x - t.x, pp.z - t.z).length() < t.r:
						server_damage_player(id, 6, Vector3(t.x, 0, t.z))
						break
		if q_main == 4 and not portal_open and portal_node == null:
			# осколок взят — открываем портал наружу в зале босса
			portal_mode = "dungeon_exit"
			portal_open = true
			portal_pos = boss_spot
			Net.bcast("rpc_portal_spawn", [portal_pos.x, portal_pos.z])
			Net.bcast("rpc_banner", ["ПУТЬ НАРУЖУ ОТКРЫТ"])
		return

	# --- оверворлд: вход в подземелье, когда пришло время (этап 2) ---
	if q_main == 2 and dungeon_entrance != Vector3.INF:
		var near := 0
		var alive_n := 0
		for id in player_nodes:
			if server_hp.get(id, 0) <= 0:
				continue
			alive_n += 1
			if player_nodes[id].global_position.distance_to(dungeon_entrance) < 6.0:
				near += 1
		if alive_n > 0 and near == alive_n:
			_server_enter_dungeon()
			return

	story_trickle -= delta
	if story_trickle <= 0:
		story_trickle = 12.0
		var alive := 0
		for g in gnomes.values():
			if g.alive and g.gid != boss_gid and not g.friendly:
				alive += 1
		if alive < diff().story_pop:
			var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
			var types := [roles.melee, roles.fast, roles.caster]
			# пока активен сайд-квест на шустрых — они должны попадаться
			if q_side == 1 and chapter_cfg().side.type == "kill_fast":
				types = [roles.fast, roles.fast, roles.melee]
			for i in 2:
				server_spawn_gnome(types[randi() % 3])


## Вся живая группа у входа в склеп — уходим в подземелье (сервер).
func _server_enter_dungeon() -> void:
	# точку входа проносим сквозь данж: выйдя, отряд появится у крипты
	_fill_carry({"entrance_x": dungeon_entrance.x, "entrance_z": dungeon_entrance.z})
	Net.bcast("rpc_banner", ["ОТРЯД СПУСКАЕТСЯ В СКЛЕП..."])
	Net.bcast("rpc_zone", ["dungeon", randi()])


## Портал в зале босса ведёт обратно на поверхность (сервер).
func _server_exit_dungeon() -> void:
	_fill_carry({"return_x": _entrance_hint.x if _entrance_hint != Vector2.INF else CAMP_POS.x,
		"return_z": _entrance_hint.y if _entrance_hint != Vector2.INF else CAMP_POS.z})
	Net.bcast("rpc_banner", ["ОТРЯД ВЫБИРАЕТСЯ НА ПОВЕРХНОСТЬ"])
	Net.bcast("rpc_zone", ["overworld", Net.world_seed])


# --- клиентские обработчики квестов ---
func on_quest(main_st: int, kills: int, side_st: int, side_n: int) -> void:
	if q_main == 2 and main_st == 3:
		Achievements.unlock("boss_slayer")
	q_main = main_st
	q_kills = kills
	q_side = side_st
	q_side_n = side_n
	_update_npc_markers()
	_update_quest_hud()


func _update_quest_hud() -> void:
	if not is_story():
		return
	var cfg := chapter_cfg()
	var lines: Array = []
	lines.append(tr("Глава %d: %s") % [Net.campaign_chapter, tr(cfg.title)])
	match q_main:
		0: lines.append("◆ " + tr("Поговори с %s") % tr(cfg.npc_main.name))
		1: lines.append("◆ " + tr("Перебей гномов: %d/%d") % [q_kills, story_kill_target()])
		2: lines.append("◆ " + (tr("Срази вожака!") if is_dungeon() else tr("Доберись до склепа в конце дороги")))
		3: lines.append("◆ " + tr("Подбери осколок Сердца"))
		4: lines.append("◆ " + (tr("Войди в портал наружу") if is_dungeon() else tr("Вернись к %s") % tr(cfg.npc_main.name)))
		5: lines.append("◆ " + tr("Войди в портал"))
	if q_side == 1:
		lines.append("◇ " + tr(cfg.side.title) + ": %d/%d" % [q_side_n, cfg.side.count])
	elif q_side == 2:
		lines.append("◇ " + tr(cfg.side.title) + ": " + tr("Вернись к %s") % tr(cfg.npc_side.name))
	elif q_side == 3:
		lines.append("✓ " + tr(cfg.side.title))
	lines.append("◈ " + tr("Золото отряда: %d") % gold)
	hud.set_quest_lines(lines)


func on_qnode(id: int, kind: String, x: float, z: float) -> void:
	if qnodes.has(id):
		return
	var node: Node3D
	match kind:
		"shard":
			node = WorldGen.crystal(self, Color(0.9, 0.4, 1.0))
			node.scale = Vector3.ONE * 1.7
			node.global_position = Vector3(x, 0, z)
		"bonfire":
			node = Node3D.new()
			add_child(node)
			node.global_position = Vector3(x, 0, z)
			for i in 3:
				var lg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.08
				lm.bottom_radius = 0.1
				lm.height = 0.9
				lg.mesh = lm
				lg.material_override = WorldGen._mat(Color(0.35, 0.24, 0.15))
				lg.rotation = Vector3(PI * 0.42, i * TAU / 3.0, 0)
				lg.position.y = 0.2
				node.add_child(lg)
		_:
			node = WorldGen._mushroom(self, _rng, x, z, 2.2, true)
	qnodes[id] = {"node": node, "kind": kind, "taken": false}
	fx_burst(Vector3(x, 0.6, z), Color(0.9, 0.5, 1.0) if kind == "shard" else Color(0.4, 0.9, 0.8), 10)


func on_qnode_taken(id: int) -> void:
	var qn: Dictionary = qnodes.get(id, {})
	if qn.is_empty():
		return
	Sfx.play_at("pickup", qn.node.global_position)
	fx_burst(qn.node.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.5), 12)
	qn.node.queue_free()
	qnodes.erase(id)


func on_qnode_lit(id: int) -> void:
	var qn: Dictionary = qnodes.get(id, {})
	if qn.is_empty():
		return
	qn.taken = true
	qn.node.add_child(_make_fire())
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.25)
	fl.light_energy = 1.4
	fl.omni_range = 7.0
	fl.position.y = 1.0
	qn.node.add_child(fl)
	Sfx.play_at("fireball", qn.node.global_position, 0.0, 0.7)


# ---------------------------------------------------------------------------
# Опыт и уровни
# ---------------------------------------------------------------------------
func player_max_hp(id: int) -> int:
	return Quests.max_hp_for(Net.players.get(id, {}))


func server_grant_xp_all(amount: int) -> void:
	for id in Net.players:
		var pd: Dictionary = Net.players[id]
		if not pd.has("xp"):
			continue
		pd.xp += amount
		while pd.level < Quests.MAX_LEVEL and pd.xp >= Quests.xp_to_next(pd.level):
			pd.xp -= Quests.xp_to_next(pd.level)
			pd.level += 1
			pd.points = pd.get("points", 0) + 1
			# не лечим павшего (hp==0): иначе он выходит из "downed" на сервере,
			# но подняться уже нельзя, а сам встать — тоже (см. server_revive_tick)
			if server_hp.get(id, 0) > 0:
				server_hp[id] = mini(player_max_hp(id), server_hp[id] + 25)
				var node = player_nodes.get(id)
				var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
				Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "heal", pos.x, pos.z])
	Net.bcast("rpc_scores", [Net.players])


## Вложить очко характеристик (сервер).
func server_alloc_stat(id: int, stat: String) -> void:
	if not stat in ["str", "vit", "agi", "luck"]:
		return
	var pd: Dictionary = Net.players.get(id, {})
	if pd.is_empty() or pd.get("points", 0) <= 0:
		return
	pd.points -= 1
	pd[stat] = pd.get(stat, 0) + 1
	if stat == "vit" and server_hp.get(id, 0) > 0:
		server_hp[id] = mini(player_max_hp(id), server_hp[id] + 12)
		var node = player_nodes.get(id)
		var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
		Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "heal", pos.x, pos.z])
	Net.bcast("rpc_scores", [Net.players])


## Открытие узла древа навыков — та же валюта (очки), что и на характеристики.
func server_unlock_skill(id: int, skill_id: String) -> void:
	var pd: Dictionary = Net.players.get(id, {})
	if pd.is_empty() or pd.get("points", 0) <= 0:
		return
	if not Skills.can_unlock(pd, skill_id):
		return
	pd.points -= 1
	var sk: Dictionary = pd.get("skills", {})
	sk[skill_id] = true
	pd.skills = sk
	if skill_id in ["vit_1", "vit_2"] and server_hp.get(id, 0) > 0:
		server_hp[id] = mini(player_max_hp(id), server_hp[id] + 10)
		var node = player_nodes.get(id)
		var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
		Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "heal", pos.x, pos.z])
	Net.bcast("rpc_scores", [Net.players])
	Net.send_sys(id, "Новый навык открыт!")


# ---------------------------------------------------------------------------
# Сундуки
# ---------------------------------------------------------------------------
func _server_place_chests(count: int) -> void:
	if is_pvp():
		return # в ПвП сундуков нет — только честная сталь
	var placed := 0
	for _try in 60:
		if placed >= count:
			break
		var x: float
		var z: float
		if not world_areas.is_empty():
			# оверворлд: сундуки внутри областей (есть смысл исследовать каждую)
			var area: Dictionary = world_areas[randi() % world_areas.size()]
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
		for h in houses:
			if Vector2(h.x - x, h.z - z).length() < 5.0:
				ok = false
				break
		for c in chests.values():
			if Vector2(c.x - x, c.z - z).length() < 7.0:
				ok = false
				break
		if ok:
			for o in world_obstacles:
				if Vector2(o.x - x, o.z - z).length() < o.r + 1.3:
					ok = false
					break
		if ok:
			placed += 1
			chest_seq += 1
			Net.bcast("rpc_chest_spawn", [chest_seq, x, z, randf_range(0, TAU)])
	# сундуки — препятствия, появившиеся после первой запечки навсетки;
	# без перезапечки враги (сервер) шли бы напролом и «бились» о них.
	# Если самая первая запечка ещё не закончилась (сундуки при старте матча),
	# повторный вызов — ошибка; она и так подхватит уже добавленные сундуки.
	if placed > 0 and Net.is_server and nav_region != null and nav_ready:
		nav_region.bake_navigation_mesh(true)


func on_chest_spawn(cid: int, x: float, z: float, rot: float) -> void:
	if chests.has(cid):
		return
	var node: Node3D = models["chest_gold"].instantiate()
	add_child(node)
	node.global_position = Vector3(x, 0, z)
	node.rotation.y = rot
	var lid: Node3D = null
	for c in node.find_children("*", "", true, false):
		if String(c.name).to_lower().contains("lid"):
			lid = c
			break
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# коллизия, чтобы сквозь сундук нельзя было ходить
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.8, 0.8)
	shape.shape = box
	shape.position.y = 0.4
	body.add_child(shape)
	node.add_child(body)
	chests[cid] = {"node": node, "lid": lid, "opened": false, "x": x, "z": z}
	fx_burst(Vector3(x, 0.6, z), Color(1.0, 0.85, 0.4), 10)


## Ближайший неоткрытый сундук (для подсказки и открытия).
func find_chest_near(pos: Vector3, radius: float) -> int:
	for cid in chests:
		var c: Dictionary = chests[cid]
		if not c.opened and Vector2(c.x - pos.x, c.z - pos.z).length() < radius:
			return cid
	return 0


## Точки интереса — индекс в world_pois, или -1 если рядом ничего нет.
func find_poi_near(pos: Vector3, radius: float) -> int:
	for i in world_pois.size():
		var p: Dictionary = world_pois[i]
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius:
			return i
	return -1


## Осмотреть лор-деталь (руины/менгиры/гробница/поле боя) — чисто текст, локально
## у каждого клиента, снаряд не нужен: детали детерминированы сидом и одинаковы
## у всех игроков.
func start_lore(idx: int) -> void:
	if idx < 0 or idx >= world_pois.size():
		return
	var poi: Dictionary = world_pois[idx]
	var pool: Array
	match poi.kind:
		"ruins":
			pool = Quests.LORE_RUINS
		"standing_stones":
			pool = Quests.LORE_STONES
		"crypt":
			pool = Quests.LORE_CRYPT
		"battlefield":
			pool = Quests.LORE_BATTLEFIELD
		_:
			return
	var line_idx: int = (Net.world_seed + idx) % pool.size()
	var text: String = pool[line_idx]
	ui_blocked = true
	hud.show_dialog([["", text]], "")
	Achievements.unlock("lore_hunter")
	Achievements.mark_lore("%s_%d" % [poi.kind, line_idx])


const SHRINE_BLESS_CD := 45.0
const CAMPFIRE_CD := 40.0
const WELL_CD := 25.0
var _campfire_cd: Dictionary = {}  # индекс поинта -> время следующего доступного отдыха
var _well_cd: Dictionary = {}
var _bounty_used: Dictionary = {}  # индекс доски объявлений -> заказ уже забран в этом матче


## Благословение у святилища (сервер): временный баф взамен небольшого ожидания.
func server_shrine_bless(sender: int, idx: int) -> void:
	if idx < 0 or idx >= world_pois.size() or world_pois[idx].kind != "shrine":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _shrine_cd.get(idx, 0.0):
		Net.send_sys(sender, "Святилище ещё не готово благословлять снова.")
		return
	_shrine_cd[idx] = now + SHRINE_BLESS_CD
	Net.bcast("rpc_buff", [sender, "speed", PICKUP_TYPES.speed.dur])
	Net.bcast("rpc_buff", [sender, "rage", PICKUP_TYPES.rage.dur])
	Net.bcast("rpc_banner", [Quests.LORE_SHRINE_BANNER])


## Единая точка входа для интерактивных точек, требующих сервера (не чисто
## текстовый лор) — диспетчер по виду поинта.
func server_poi_interact(sender: int, idx: int) -> void:
	if idx < 0 or idx >= world_pois.size():
		return
	match world_pois[idx].kind:
		"shrine":
			server_shrine_bless(sender, idx)
		"campfire":
			server_campfire_rest(sender, idx)
		"well":
			server_well_drink(sender, idx)
		"bounty_board":
			server_bounty_read(sender, idx)


## Отдых у костра: небольшой мгновенный хил плюс короткий барьер — согревает
## перед дорогой, но слабее полноценного благословения святилища.
func server_campfire_rest(sender: int, idx: int) -> void:
	if idx < 0 or idx >= world_pois.size() or world_pois[idx].kind != "campfire":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _campfire_cd.get(idx, 0.0):
		Net.send_sys(sender, "Костёр ещё прогорает — не время греться снова.")
		return
	_campfire_cd[idx] = now + CAMPFIRE_CD
	server_heal_player(sender, roundi(player_max_hp(sender) * 0.3))
	server_shield[sender] = server_shield.get(sender, 0) + 25
	Net.bcast("rpc_buff", [sender, "shield", 20.0])
	Net.bcast("rpc_banner", [Quests.LORE_CAMPFIRE_BANNER])
	# в мире-путешествии тронутый костёр становится чекпоинтом отряда
	if not world_areas.is_empty():
		team_checkpoint = Vector2(world_pois[idx].x, world_pois[idx].z)
		Net.send_sys(sender, "Костёр запомнил вас: отряд возродится здесь.")


## Колодец: чистый хил без бафа, но чаще доступен, чем костёр или святилище.
func server_well_drink(sender: int, idx: int) -> void:
	if idx < 0 or idx >= world_pois.size() or world_pois[idx].kind != "well":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _well_cd.get(idx, 0.0):
		Net.send_sys(sender, "Колодец ещё не набрал воды.")
		return
	_well_cd[idx] = now + WELL_CD
	server_heal_player(sender, roundi(player_max_hp(sender) * 0.4))
	Net.bcast("rpc_banner", [Quests.LORE_WELL_BANNER])


## Доска объявлений: одноразовый за матч заказ на элитного гнома неподалёку.
func server_bounty_read(sender: int, idx: int) -> void:
	if idx < 0 or idx >= world_pois.size() or world_pois[idx].kind != "bounty_board":
		return
	if _bounty_used.get(idx, false):
		Net.send_sys(sender, "Награда за эту доску уже забрана.")
		return
	_bounty_used[idx] = true
	var poi: Dictionary = world_pois[idx]
	var roles: Dictionary = BIOME_ENEMIES.get(Net.biome, BIOME_ENEMIES["meadow"])
	var a := randf_range(0, TAU)
	var spawn_pos := Vector3(poi.x + cos(a) * 5.0, 0, poi.z + sin(a) * 5.0)
	server_spawn_gnome_at(roles.melee, spawn_pos, enemy_level() + 1, true)
	Net.bcast("rpc_banner", [Quests.LORE_BOUNTY_BANNER])


func server_open_chest(opener: int, cid: int) -> void:
	var c: Dictionary = chests.get(cid, {})
	if c.is_empty() or c.opened or match_over:
		return
	var pn = player_nodes.get(opener)
	if pn == null or pn.global_position.distance_to(Vector3(c.x, 0, c.z)) > 3.0:
		return
	c.opened = true
	Net.bcast("rpc_chest_opened", [cid])
	if is_story():
		server_gold += randi_range(8, 14)
		Net.bcast("rpc_gold", [server_gold])
	# лут: 2-3 предмета, В КООПЕРАТИВЕ ПОЛУЧАЮТ ВСЕ ИГРОКИ
	var total := 0
	for e in CHEST_LOOT:
		total += e[1]
	for i in randi_range(2, 3):
		var roll := randi() % total
		var type := "potion_hp"
		for e in CHEST_LOOT:
			roll -= e[1]
			if roll < 0:
				type = e[0]
				break
		if type == "crystal":
			var keys := PICKUP_TYPES.keys()
			type = keys[randi() % keys.size()]
		for id in Net.players:
			if type == "heal":
				server_heal_player(id, 20)
			elif type == "shield":
				if server_hp.get(id, 0) > 0:
					server_shield[id] = SHIELD_POINTS
					Net.bcast("rpc_buff", [id, "shield", 999.0])
			elif PICKUP_TYPES.has(type):
				if server_hp.get(id, 0) > 0:
					Net.bcast("rpc_buff", [id, type, PICKUP_TYPES[type].dur])
			else:
				_server_grant_item(id, type)


## Выдать предмет игроку (сервер): ведём авторитетное зеркало инвентаря и лишь
## затем рассылаем — чтобы применение предмета можно было проверить на сервере,
## а не верить клиенту на слово (иначе — бесконечные бомбы/пиры модифицированным
## клиентом). Логика набивки/лимита слотов совпадает с клиентской (on_item_granted).
func _server_grant_item(id: int, type: String) -> void:
	var inv: Array = server_inv.get(id, [])
	var stacked := false
	for slot in inv:
		if slot.type == type:
			slot.count += 1
			stacked = true
			break
	if not stacked:
		if inv.size() >= HOTBAR_SIZE:
			return # инвентарь полон — предмет теряется, как и на клиенте
		inv.append({"type": type, "count": 1})
	server_inv[id] = inv
	Net.bcast("rpc_item_granted", [id, type])


## Списать один предмет из серверного инвентаря; false — если его там нет.
func _server_consume_item(id: int, type: String) -> bool:
	var inv: Array = server_inv.get(id, [])
	for i in inv.size():
		if inv[i].type == type:
			inv[i].count -= 1
			if inv[i].count <= 0:
				inv.remove_at(i)
			return true
	return false


func on_chest_opened(cid: int) -> void:
	var c: Dictionary = chests.get(cid, {})
	if c.is_empty():
		return
	c.opened = true
	if c.lid != null:
		var t := create_tween()
		t.tween_property(c.lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fx_burst(Vector3(c.x, 0.8, c.z), Color(1.0, 0.9, 0.4), 16)
	Sfx.play_at("block", Vector3(c.x, 0.5, c.z), -2.0, 0.55)
	Sfx.play_at("pickup", Vector3(c.x, 0.5, c.z), 0.0, 0.8)
	# золото «забрали»: через миг модель подменяется на пустой сундук
	delay(0.9, func():
		var cc: Dictionary = chests.get(cid, {})
		if cc.is_empty() or not is_instance_valid(cc.node):
			return
		var xf: Transform3D = cc.node.global_transform
		cc.node.queue_free()
		var empty: Node3D = models["chest"].instantiate()
		add_child(empty)
		empty.global_transform = xf
		for ch in empty.find_children("*", "", true, false):
			if String(ch.name).to_lower().contains("lid"):
				ch.rotation.x = -1.9
		for mi in empty.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 0.8, 0.8)
		shape.shape = box
		shape.position.y = 0.4
		body.add_child(shape)
		empty.add_child(body)
		cc.node = empty
		cc.lid = null
		fx_burst(xf.origin + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.4), 8))
	if Net.players.size() > 1:
		hud.add_chat("", tr("⛃ Сундук открыт — добычу получил весь отряд!"), true)


# ---------------------------------------------------------------------------
# Инвентарь (хотбар локального игрока)
# ---------------------------------------------------------------------------
func on_item_granted(id: int, type: String) -> void:
	var node = player_nodes.get(id)
	if node != null:
		Sfx.play_at("pickup", node.global_position)
	if id != Net.my_id:
		return
	var title: String = tr(ITEM_DEFS.get(type, {}).get("title", type))
	for slot in inventory:
		if slot.type == type:
			slot.count += 1
			hud.set_inventory(inventory)
			hud.add_chat("", tr("+ %s") % title, true)
			return
	if inventory.size() < HOTBAR_SIZE:
		inventory.append({"type": type, "count": 1})
		hud.set_inventory(inventory)
		hud.add_chat("", tr("+ %s (клавиша %d)") % [title, inventory.size()], true)
	else:
		hud.add_chat("", tr("Инвентарь полон! %s пропал.") % title, true)


func use_item_slot(idx: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	var me = player_nodes.get(Net.my_id)
	if me == null or me.state in ["dead", "downed"]:
		return
	var slot: Dictionary = inventory[idx]
	var type: String = slot.type
	slot.count -= 1
	if slot.count <= 0:
		inventory.remove_at(idx)
	hud.set_inventory(inventory)
	var dir := Vector3(sin(me.facing), 0, cos(me.facing))
	Net.req_use_item(type, dir.x, dir.z)
	if type == "bomb":
		Sfx.play_at("swing", me.global_position)


func server_use_item(id: int, type: String, dx: float, dz: float) -> void:
	var node = player_nodes.get(id)
	if node == null or server_hp.get(id, 0) <= 0:
		return
	# предмет применяется, только если он реально есть в серверном инвентаре —
	# защита от бесконечного использования модифицированным клиентом
	if not _server_consume_item(id, type):
		return
	match type:
		"potion_hp":
			server_heal_player(id, 40)
		"gold_feast":
			# пир для всего отряда: живых лечит до отвала, павших поднимает
			for pid in Net.players:
				if server_hp.get(pid, 0) > 0:
					server_heal_player(pid, 999)
				elif not is_pvp() and player_nodes.has(pid):
					revive_progress.erase(pid)
					downed_timers.erase(pid)
					server_hp[pid] = player_max_hp(pid) / 2
					Net.bcast("rpc_player_revived", [pid, server_hp[pid]])
		"potion_rage":
			Net.bcast("rpc_buff", [id, "rage", PICKUP_TYPES["rage"].dur])
		"potion_speed":
			Net.bcast("rpc_buff", [id, "speed", PICKUP_TYPES["speed"].dur])
		"bomb":
			bomb_seq += 1
			var from: Vector3 = node.global_position + Vector3(0, 1.3, 0)
			var vel := Vector3(dx, 0, dz).normalized() * 9.0 + Vector3(0, 5.0, 0)
			Net.bcast("rpc_bomb", [bomb_seq, from, vel])


# ---------------------------------------------------------------------------
# Бомбы
# ---------------------------------------------------------------------------
func on_bomb(bid: int, from: Vector3, vel: Vector3) -> void:
	var mesh: Node3D = models["keg"].instantiate()
	mesh.scale = Vector3.ONE * 0.42
	add_child(mesh)
	for mi in mesh.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh.global_position = from
	bombs[bid] = {"node": mesh, "vel": vel, "life": 0.0}


func on_bomb_boom(bid: int, pos: Vector3) -> void:
	fx_burst(pos, Color(1.0, 0.6, 0.2), 18)
	fx_burst(pos + Vector3(0, 0.5, 0), Color(0.4, 0.4, 0.4), 12)
	Sfx.play_at("explode", pos, 6.0, 0.8)
	if player_nodes.has(Net.my_id):
		var d: float = player_nodes[Net.my_id].global_position.distance_to(pos)
		if d < 8.0:
			player_nodes[Net.my_id].add_shake(0.4 * (1.0 - d / 8.0))
	if bombs.has(bid):
		bombs[bid].node.queue_free()
		bombs.erase(bid)


func _update_bombs(delta: float) -> void:
	for bid in bombs.keys():
		var b: Dictionary = bombs[bid]
		b.life += delta
		b.vel.y -= 14.0 * delta
		b.node.global_position += b.vel * delta
		b.node.rotate_x(delta * 6.0)
		if not Net.is_server:
			continue
		if b.node.global_position.y <= 0.15 or b.life > 3.0:
			var pos: Vector3 = b.node.global_position
			pos.y = maxf(pos.y, 0.15)
			bombs.erase(bid)
			b.node.queue_free()
			Net.bcast("rpc_bomb_boom", [bid, pos])
			# АоЕ урон
			for g in gnomes.values():
				if g.alive and g.global_position.distance_to(pos) < 3.5:
					g.last_attacker = 0
					g.last_attacker_gid = 0 # бомба — не наёмник, зачёт не его
					g.server_take_damage(30, pos, true)
			if is_pvp():
				for pid in player_nodes:
					if server_hp.get(pid, 0) > 0 and player_nodes[pid].global_position.distance_to(pos) < 3.0:
						server_damage_player(pid, 25, pos)


# ---------------------------------------------------------------------------
# Эффекты
# ---------------------------------------------------------------------------
func _init_fx_pool() -> void:
	var dm := SphereMesh.new()
	dm.radius = 0.05
	dm.height = 0.1
	dm.radial_segments = 6
	dm.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.vertex_color_use_as_albedo = true
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = dmat

	for i in FX_POOL_SIZE:
		var p := GPUParticles3D.new()
		p.amount = 18
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.55
		p.emitting = false
		p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 85.0
		mat.initial_velocity_min = 2.0
		mat.initial_velocity_max = 4.5
		mat.gravity = Vector3(0, -9, 0)
		mat.scale_min = 0.6
		mat.scale_max = 1.3
		p.process_material = mat
		p.draw_pass_1 = dm
		add_child(p)
		_fx_pool.append(p)


func _prewarm_pipelines() -> void:
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	quad.mesh = qm
	var tmat := StandardMaterial3D.new()
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(1, 1, 1, 0.05)
	quad.material_override = tmat
	add_child(quad)
	quad.position = Vector3(0, 1.2, 0)
	fx_number(Vector3.ZERO, " ", Color(1, 1, 1, 0.05))
	delay(1.0, quad.queue_free)


func fx_burst(pos: Vector3, color: Color, count: int) -> void:
	var p: GPUParticles3D = _fx_pool[_fx_idx]
	_fx_idx = (_fx_idx + 1) % FX_POOL_SIZE
	p.global_position = pos
	(p.process_material as ParticleProcessMaterial).color = color
	p.amount_ratio = clampf(count / 18.0, 0.15, 1.0)
	p.restart()


func fx_number(pos: Vector3, text: String, color: Color) -> void:
	if _fx_numbers_active > 40:
		return
	_fx_numbers_active += 1
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.012
	l.outline_size = 10
	l.modulate = color
	l.font_size = 40
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(1.6, 2.1), randf_range(-0.3, 0.3))
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "global_position:y", l.global_position.y + 1.3, 0.9)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func():
		_fx_numbers_active -= 1
		l.queue_free())


# ---------------------------------------------------------------------------
# Цикл
# ---------------------------------------------------------------------------
func _flush_hero_save() -> void:
	if _hero_dirty and Net.players.has(Net.my_id):
		_hero_dirty = false
		Save.store_hero(Net.players[Net.my_id])


func _exit_tree() -> void:
	_flush_hero_save() # выход из мира/главы — сохраняемся


func _physics_process(delta: float) -> void:
	_update_fireballs(delta)
	_update_bombs(delta)
	_update_pickups(delta)
	# автосейв героя раз в 30 секунд
	_hero_save_timer -= delta
	if _hero_save_timer <= 0:
		_hero_save_timer = 30.0
		_flush_hero_save()

	if not Net.is_server:
		return

	_spread_slots(delta)
	_update_revives(delta)

	if restart_timer > 0:
		restart_timer -= delta
		if restart_timer <= 0:
			restart_timer = -1.0
			_server_restart_match()

	if match_over:
		return

	if is_pvp():
		_update_pvp(delta)
	elif is_story():
		_update_story(delta)
	else:
		_update_waves_pve(delta)

	if Net.mode == Net.Mode.HOST:
		_time_sync -= delta
		if _time_sync <= 0:
			_time_sync = 5.0
			if daynight != null:
				Net.rpc("rpc_daytime", daynight.time)
		batch_timer -= delta
		_batch_full_timer -= delta
		if batch_timer <= 0:
			batch_timer = BATCH_INTERVAL
			var full: bool = _batch_full_timer <= 0
			if full:
				_batch_full_timer = 1.0
			var batch := PackedFloat32Array()
			for gid in gnomes:
				var g = gnomes[gid]
				if not g.alive:
					continue
				# дельта: пропускаем неизменившихся (раз в секунду — полный кадр)
				var loco: int = g.loco_index()
				if not full and g.net_sent_pos.distance_squared_to(g.global_position) < 0.0009 \
						and absf(g.net_sent_rot - g.facing) < 0.03 \
						and g.net_sent_loco == loco and g.net_sent_hp == g.hp:
					continue
				g.net_sent_pos = g.global_position
				g.net_sent_rot = g.facing
				g.net_sent_loco = loco
				g.net_sent_hp = g.hp
				batch.append_array(PackedFloat32Array([
					float(gid), g.global_position.x, g.global_position.z,
					g.facing, float(loco), float(g.hp)]))
			if not batch.is_empty():
				Net.rpc("rpc_gnome_batch", batch)
