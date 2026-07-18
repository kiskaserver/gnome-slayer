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
var world_caches: Array = []         # тайники у тупичков дороги: сюда встают первые сундуки
var barrels: Dictionary = {}         # взрывные бочки: bid -> {x, z, node, alive}
var world_areas: Array = []          # оверворлд: [{id, kind, center, radius}]
var world_road: Array = []           # вейпоинты главной дороги
var dungeon_entrance := Vector3.INF  # точка входа в подземелье
var team_checkpoint := Vector2.INF   # чекпоинт отряда (костёр у дороги)
var boss_spot := Vector3.INF         # зал босса (в подземелье)
var dungeon_traps: Array = []        # ловушки: [{x,z,r,dmg}]
var dungeon_chest_spots: Array = []  # места сундуков в комнатах
var dungeon_secret: Dictionary = {}  # тайник за кладкой: {x,z,node,body,opened}
var dungeon_door: Dictionary = {}    # решётка зала босса: {x,z,node,body,opened}
var dungeon_miniboss_spot := Vector3.INF
var dungeon_reward_spots: Array = [] # ниша наград: пара мест «выбери один трофей»
var dungeon_theme := ""              # crypt | cave | catacombs
var miniboss_gid := 0                # страж ключа: его смерть поднимает решётку
var reward_pair: Array = []          # dids пары трофеев (взял один — второй исчез)
var spawn_override := Vector2.INF    # разовая точка спавна после смены зоны
var _entrance_hint := Vector2.INF    # где вход в склеп (пронесено сквозь данж)
var _carry_restored := false         # состояние восстановлено из Net.carry
var _trap_tick := 0.0
var portal_mode := "chapter"         # chapter | dungeon_exit
# сервисы (создаются в _ready): лавка и точки интереса
var shop_svc: ShopService
var poi_svc: PoiService
var combat: CombatRules
var spawn: SpawnDirector
var loot: LootSystem
var quest: QuestDirector
var camp: CampBuilder
var zones: ZoneManager
var tutorial: Tutorial = null    # обучение (D2): только одиночная кампания, гл. 1
var waypoint_node: Node3D = null # золотой маяк-указатель текущей цели
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

# инвентарь локального игрока: синхронизированная копия серверного
# (массив предметов Items-формата: {id, kind, rarity, aseed, count})
var inventory: Array = []
var my_equip: Dictionary = {"weapon": {}, "trinket": {}}  # своя экипировка (синк)
const INV_SIZE := 20
var item_drops: Dictionary = {}  # did -> {node, item, life}: экипировка на земле
var drop_seq := 0

# --- серверное состояние ---
var server_hp: Dictionary = {}
var server_shield: Dictionary = {}
var server_inv: Dictionary = {}    # id -> Array предметов: авторитетный инвентарь
var server_equip: Dictionary = {}  # id -> {"weapon": item|{}, "trinket": item|{}}
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


func _fill_carry(extra: Dictionary = {}) -> void:
	zones.fill_carry(extra)


func _restore_carry() -> void:
	zones.restore_carry()


func diff() -> Dictionary:
	return Quests.DIFFICULTIES.get(Net.difficulty, Quests.DIFFICULTIES["normal"])


func _ready() -> void:
	shop_svc = ShopService.new(self)
	poi_svc = PoiService.new(self)
	combat = CombatRules.new(self)
	spawn = SpawnDirector.new(self)
	loot = LootSystem.new(self)
	quest = QuestDirector.new(self)
	camp = CampBuilder.new(self)
	zones = ZoneManager.new(self)
	if _model_cache.is_empty():
		for m in ["Knight", "Barbarian", "Mage", "Rogue_Hooded",
				"Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Minion", "Skeleton_Rogue",
				"chest_gold", "chest", "Rogue", "keg", "bottle_A_green", "bottle_B_green", "bottle_C_brown", "coin_stack_small"]:
			_model_cache[m] = load("res://models/%s.glb" % m)
		for w in ["Skeleton_Blade", "Skeleton_Axe", "Skeleton_Staff", "Skeleton_Shield_Small_A"]:
			_model_cache[w] = load("res://models/skeleton_weapons/%s.gltf" % w)
		_model_cache["sword_2handed"] = load("res://models/adventurer_items/sword_2handed.gltf")
		for w2 in ["axe_1handed", "axe_2handed", "dagger", "sword_1handed", "crossbow_1handed", "staff", "wand"]:
			_model_cache[w2] = load("res://models/adventurer_items/%s.gltf" % w2)
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
	world_caches = data.get("caches", [])
	# бочки детерминированы сидом на всех машинах — bid совпадают без синка
	var blist: Array = data.get("barrels", [])
	for i in blist.size():
		barrels[i + 1] = {"x": blist[i].x, "z": blist[i].z, "node": blist[i].node, "alive": true}
	boss_spot = data.get("boss_spot", Vector3.INF)
	dungeon_traps = data.get("traps", [])
	dungeon_chest_spots = data.get("chest_spots", [])
	dungeon_secret = data.get("secret", {})
	dungeon_door = data.get("door", {})
	dungeon_miniboss_spot = data.get("miniboss_spot", Vector3.INF)
	dungeon_reward_spots = data.get("reward_spots", [])
	dungeon_theme = data.get("theme", "")
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
		# обучение: первый запуск одиночной кампании, пока флаг не выставлен
		if Net.mode == Net.Mode.SINGLE and Net.campaign_chapter == 1 and not Save.tutorial_done:
			tutorial = Tutorial.new(self)

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
						spawn.start_wave(1))


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
	# инвентарь/экипировка героя приезжают с ним (из сейва через регистрацию),
	# каждая позиция прогоняется через санитайзер — мусор и подделки отсеиваются
	var pd: Dictionary = Net.players.get(id, {})
	var inv: Array = []
	for raw in pd.get("inventory", []):
		var it := Items.sanitize(raw)
		if not it.is_empty() and inv.size() < INV_SIZE:
			inv.append(it)
	server_inv[id] = inv
	var eq_raw: Dictionary = pd.get("equipment", {})
	server_equip[id] = {"weapon": Items.sanitize(eq_raw.get("weapon", {})),
		"trinket": Items.sanitize(eq_raw.get("trinket", {}))}
	server_hp[id] = player_max_hp(id)
	players_meta[id] = {"color": color}
	var pname: String = Net.players[id].name
	_sync_inv(id)
	var weq: Dictionary = server_equip[id].weapon
	if not weq.is_empty():
		Net.bcast("rpc_player_equip", [id, weq.id])

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
	server_equip.erase(id)
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
# Урон и нокдаун (сервер) — правила в CombatRules (systems/combat_rules.gd)
# ---------------------------------------------------------------------------
func _max_melee_dmg(id: int) -> int:
	return combat.max_melee_dmg(id)


func server_handle_melee(sender: int, targets: Array, dmg: int, crit: bool) -> void:
	combat.server_handle_melee(sender, targets, dmg, crit)


func server_damage_player(id: int, dmg: int, from_pos: Vector3, attacker: int = 0) -> String:
	return combat.server_damage_player(id, dmg, from_pos, attacker)


func server_revive_tick(reviver: int, target: int) -> void:
	combat.server_revive_tick(reviver, target)


func server_heal_player(id: int, amount: int) -> void:
	combat.server_heal_player(id, amount)


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
		var pname: String = Net.players[id].name if Net.players.has(id) else tr("Друг")
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
		var rname: String = Net.players[reviver_id].name if Net.players.has(reviver_id) else tr("Друг")
		hud.center_msg(tr("%s поднимает тебя... %d%%") % [rname, pct] if k > 0
			else tr("Ты пал. Друг может поднять тебя (%s)") % main.key_name("interact"))
		hud.set_revive_progress(k)
	elif Net.my_id == reviver_id:
		var tname: String = Net.players[target_id].name if Net.players.has(target_id) else tr("Друг")
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
# Гномы — спавн/волны в SpawnDirector (systems/spawn_director.gd)
# ---------------------------------------------------------------------------
func enemy_level() -> int:
	return spawn.enemy_level()


func server_spawn_gnome(type: String) -> void:
	spawn.server_spawn_gnome(type)


func server_spawn_gnome_at(type: String, pos: Vector3, lvl := 1, elite := false) -> void:
	spawn.server_spawn_gnome_at(type, pos, lvl, elite)


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
		# экипировка: боссы роняют гарантированно, элитки — часто, обычные — редко
		var killer_luck: int = Net.players.get(killer, {}).get("luck", 0)
		var is_boss: bool = g.gid == boss_gid or g.cfg.has("special")
		if is_boss or g.elite or randf() < 0.06:
			var drop := Items.roll_drop(g.level, killer_luck, randi(), is_boss or g.elite)
			if not drop.is_empty():
				if is_boss and drop.rarity < 1:
					drop.rarity = 1 # босс не роняет серость
				server_spawn_item_drop(drop, g.global_position.x, g.global_position.z)
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


const BLEEDOUT_TIME := 40.0
var downed_timers: Dictionary = {}


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
	poi_svc.reset_bounties() # доски объявлений снова активны в новом матче
	for id in server_hp:
		server_hp[id] = player_max_hp(id)
		var pos := _player_spawn_pos()
		Net.bcast("rpc_player_respawn", [id, pos.x, pos.y])
	if is_pvp():
		Net.bcast("rpc_wave", [0, false, true]) # сигнатура rpc_wave(n, is_endless, is_pvp)
	else:
		wave = 0
		endless = false
		spawn.start_wave(1)


func server_continue_endless() -> void:
	endless = true
	match_over = false
	spawn.start_wave(wave + 1)


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
	poi_svc.reset_bounties()  # доски объявлений снова активны в новом матче
	server_hp[1] = player_max_hp(1) # с учётом Живучести, не голая константа
	Net.bcast("rpc_player_respawn", [1, 0.0, 0.0])
	wave = 0
	delay(1.5, func():
		if not match_over:
			spawn.start_wave(1))


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
	var btext: String
	if text.begins_with("ENDING:"):
		btext = tr("ФИНАЛ КАМПАНИИ")
	elif text.begins_with("PVPWIN:"):
		btext = tr("%s ПОБЕЖДАЕТ!") % text.substr(7)
	else:
		btext = tr(text)
	hud.banner(btext, 4.0)
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
const MERCHANT_NPC := {"model": "Rogue", "name": "Торговец Крамс", "tint": Color(1.0, 0.9, 0.6)}


## Сейф-зона лагеря (только сюжет): враги сюда не заходят и урон не проходит.
func in_safe_zone(pos: Vector3) -> bool:
	return is_story() and Vector2(pos.x - CAMP_POS.x, pos.z - CAMP_POS.z).length() < SAFE_RADIUS


func chapter_cfg() -> Dictionary:
	return Quests.CHAPTERS[clampi(Net.campaign_chapter - 1, 0, Quests.CHAPTERS.size() - 1)]


func _build_camp() -> void:
	camp.build_camp()


func _make_fire() -> GPUParticles3D:
	return camp.make_fire()


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
	if tutorial != null:
		tutorial.notify("talk", float(npc_idx))
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
	elif npc_idx == 3:
		# торговец: сразу лавка, без диалога
		open_shop()
		return
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


# ---------------------------------------------------------------------------
# Лавка торговца — реализация в scripts/systems/shop_service.gd
# ---------------------------------------------------------------------------
func open_shop() -> void:
	shop_svc.open_shop()


func close_shop() -> void:
	shop_svc.close_shop()


func server_buy(sender: int, stock_idx: int) -> void:
	shop_svc.server_buy(sender, stock_idx)


func server_sell(sender: int, inv_idx: int) -> void:
	shop_svc.server_sell(sender, inv_idx)


# --- серверная логика квестов ---
func _server_story_begin() -> void:
	quest.server_story_begin()


func _server_dungeon_begin() -> void:
	quest.server_dungeon_begin()


func story_kill_target() -> int:
	return quest.story_kill_target()


func _bcast_quest() -> void:
	quest.bcast_quest()


func server_talk(sender: int, which: String) -> void:
	quest.server_talk(sender, which)


func on_gold(total: int) -> void:
	gold = total
	if total >= 500:
		Achievements.unlock("wealthy")
	if hud.is_shop_open():
		hud.refresh_shop(inventory, gold)
	_update_quest_hud()


func on_sys(text: String) -> void:
	hud.add_chat("", tr(text), true)


func server_qnode_take(sender: int, id: int) -> void:
	quest.server_qnode_take(sender, id)


func _story_on_gnome_died(g) -> void:
	quest.on_gnome_died(g)


func _server_open_portal() -> void:
	quest.server_open_portal()


func _server_enter_dungeon() -> void:
	zones.server_enter_dungeon()


func _server_exit_dungeon() -> void:
	zones.server_exit_dungeon()


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
	return Quests.max_hp_for(Net.players.get(id, {})) + Items.equip_hp_bonus(server_equip.get(id, {}))


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
	loot.place_chests(count)


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


## Золотой маяк-указатель: столб света и парящая стрелка над целью.
## Пригодится не только обучению — любой сценарий может подсветить точку.
func set_waypoint(pos: Vector3) -> void:
	if waypoint_node == null:
		waypoint_node = Node3D.new()
		add_child(waypoint_node)
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.16
		bm.bottom_radius = 0.34
		bm.height = 7.0
		bm.radial_segments = 8
		beam.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.85, 0.35, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.35)
		mat.emission_energy_multiplier = 1.2
		beam.mesh.material = mat
		beam.position.y = 3.5
		waypoint_node.add_child(beam)
		var arrow := MeshInstance3D.new()
		var am := PrismMesh.new()
		am.size = Vector3(0.7, 0.8, 0.7)
		arrow.mesh = am
		arrow.material_override = mat
		arrow.rotation.z = PI # остриём вниз
		arrow.position.y = 4.6
		waypoint_node.add_child(arrow)
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.85, 0.4)
		wl.light_energy = 1.0
		wl.omni_range = 6.0
		wl.position.y = 1.5
		waypoint_node.add_child(wl)
	waypoint_node.global_position = pos


func clear_waypoint() -> void:
	if waypoint_node != null and is_instance_valid(waypoint_node):
		waypoint_node.queue_free()
	waypoint_node = null


## Взрыв бочки (сервер): урон по площади обеим сторонам, цепная детонация.
func server_explode_barrel(bid: int, attacker: int = 0) -> void:
	var b: Dictionary = barrels.get(bid, {})
	if b.is_empty() or not b.alive or match_over:
		return
	b.alive = false
	Net.bcast("rpc_barrel_boom", [bid])
	var pos := Vector3(b.x, 0, b.z)
	for id in player_nodes:
		if server_hp.get(id, 0) > 0 and player_nodes[id].global_position.distance_to(pos) < 3.2:
			server_damage_player(id, 25, pos)
	for g in gnomes.values():
		if g.alive and g.global_position.distance_to(pos) < 3.6:
			g.last_attacker = attacker
			g.last_attacker_gid = 0
			g.server_take_damage(35, pos, false)
	# цепная детонация соседних бочек — с мгновением на разлёт огня
	for obid in barrels:
		var ob: Dictionary = barrels[obid]
		if ob.alive and Vector2(ob.x - b.x, ob.z - b.z).length() < 3.2:
			var chain_bid: int = obid
			delay(0.22, func(): server_explode_barrel(chain_bid, attacker))


## Бочка рванула (все машины): огонь, грохот, сама бочка исчезает.
func on_barrel_boom(bid: int) -> void:
	var b: Dictionary = barrels.get(bid, {})
	if b.is_empty():
		return
	b.alive = false
	var pos := Vector3(b.x, 0.6, b.z)
	fx_burst(pos, Color(1.0, 0.55, 0.15), 26)
	fx_burst(pos + Vector3(0, 0.5, 0), Color(0.35, 0.3, 0.28), 14)
	Sfx.play_at("explode", pos, 3.0, 0.95)
	if is_instance_valid(b.get("node")):
		b.node.queue_free()


## Рядом ли неоткрытая секретная кладка (для подсказки и интеракции).
func secret_near(pos: Vector3, radius: float) -> bool:
	if dungeon_secret.is_empty() or dungeon_secret.get("opened", false):
		return false
	return Vector2(pos.x - dungeon_secret.x, pos.z - dungeon_secret.z).length() < radius


## Расшатать кладку (сервер): проверка дистанции, дальше — общий бродкаст.
func server_open_secret(sender: int) -> void:
	if not is_dungeon() or dungeon_secret.is_empty() or dungeon_secret.get("opened", false):
		return
	var pn = player_nodes.get(sender)
	if pn == null or not secret_near(pn.global_position, 3.2):
		return
	Net.bcast("rpc_secret_opened", [])
	Net.bcast("rpc_banner", ["ТАЙНИК ОТКРЫТ"])


## Кладка рассыпалась (все машины): убрать стену с коллайдером, перепечь навсетку.
func on_secret_opened() -> void:
	if dungeon_secret.is_empty() or dungeon_secret.get("opened", false):
		return
	dungeon_secret["opened"] = true
	fx_burst(Vector3(dungeon_secret.x, 1.2, dungeon_secret.z), Color(0.7, 0.65, 0.55), 20)
	Sfx.play_at("explode", Vector3(dungeon_secret.x, 1.0, dungeon_secret.z), -4.0, 0.7)
	if is_instance_valid(dungeon_secret.get("node")):
		dungeon_secret.node.queue_free()
	if is_instance_valid(dungeon_secret.get("body")):
		dungeon_secret.body.queue_free()
	# путь в тайник появился — врагам тоже нужно его знать
	if Net.is_server and nav_region != null and nav_ready:
		delay(0.1, func(): nav_region.bake_navigation_mesh(true))


## Решётка зала босса поднята (ключ с мини-босса) — путь к хранителю открыт.
func on_door_opened() -> void:
	if dungeon_door.is_empty() or dungeon_door.get("opened", false):
		return
	dungeon_door["opened"] = true
	fx_burst(Vector3(dungeon_door.x, 1.5, dungeon_door.z), Color(1.0, 0.85, 0.4), 18)
	Sfx.play_at("pickup", Vector3(dungeon_door.x, 1.0, dungeon_door.z), 2.0, 0.8)
	if is_instance_valid(dungeon_door.get("node")):
		dungeon_door.node.queue_free()
	if is_instance_valid(dungeon_door.get("body")):
		dungeon_door.body.queue_free()
	if Net.is_server and nav_region != null and nav_ready:
		delay(0.1, func(): nav_region.bake_navigation_mesh(true))


## Ближайший неоткрытый сундук (для подсказки и открытия).
func find_chest_near(pos: Vector3, radius: float) -> int:
	for cid in chests:
		var c: Dictionary = chests[cid]
		if not c.opened and Vector2(c.x - pos.x, c.z - pos.z).length() < radius:
			return cid
	return 0


## Точки интереса — индекс в world_pois, или -1 если рядом ничего нет.
# --- точки интереса: реализация в scripts/systems/poi_service.gd ---
func find_poi_near(pos: Vector3, radius: float) -> int:
	return poi_svc.find_poi_near(pos, radius)


func start_lore(idx: int) -> void:
	poi_svc.start_lore(idx)


func server_shrine_bless(sender: int, idx: int) -> void:
	poi_svc.server_shrine_bless(sender, idx)


func server_poi_interact(sender: int, idx: int) -> void:
	poi_svc.server_poi_interact(sender, idx)


func server_campfire_rest(sender: int, idx: int) -> void:
	poi_svc.server_campfire_rest(sender, idx)


func server_well_drink(sender: int, idx: int) -> void:
	poi_svc.server_well_drink(sender, idx)


func server_bounty_read(sender: int, idx: int) -> void:
	poi_svc.server_bounty_read(sender, idx)


func server_open_chest(opener: int, cid: int) -> void:
	loot.server_open_chest(opener, cid)


func _server_grant_item(id: int, type: String) -> void:
	loot.grant_item(id, type)


func _server_grant_equipment(id: int, item: Dictionary) -> bool:
	return loot.grant_equipment(id, item)


func _sync_inv(id: int) -> void:
	loot.sync_inv(id)


## Клиент получил свой инвентарь/экипировку от сервера.
func on_inv_sync(inv: Array, eq: Dictionary) -> void:
	inventory = inv
	my_equip = eq
	if Net.players.has(Net.my_id):
		Net.players[Net.my_id]["inventory"] = inv.duplicate(true)
		Net.players[Net.my_id]["equipment"] = eq.duplicate(true)
	hud.set_inventory(_consumables())
	if hud.is_inventory_open():
		hud.refresh_inventory(inventory, my_equip)
	if hud.is_shop_open():
		hud.refresh_shop(inventory, gold)
	var me = player_nodes.get(Net.my_id)
	if me != null:
		me.on_equip_changed(my_equip)


## Расходники в порядке инвентаря — это и есть хотбар (клавиши 1-5).
func _consumables() -> Array:
	var out: Array = []
	for it in inventory:
		if it.get("kind", "") == "consumable":
			out.append({"type": it.id, "count": it.count})
	return out.slice(0, HOTBAR_SIZE)


func server_equip_item(id: int, inv_idx: int) -> void:
	loot.server_equip_item(id, inv_idx)


func server_unequip(id: int, slot: String) -> void:
	loot.server_unequip(id, slot)


func server_drop_item(id: int, inv_idx: int) -> void:
	loot.server_drop_item(id, inv_idx)


var _shot_cd: Dictionary = {}  # id -> время последнего выстрела (серверный лимит)


## Выстрел арбалета (сервер): хитскан по направлению, урон считает сервер —
## клиент присылает лишь куда смотрит. В ПвП стрелковое пока отключено.
func server_shoot(sender: int, dx: float, dz: float) -> void:
	if is_pvp() or match_over:
		return
	var sn = player_nodes.get(sender)
	if sn == null or server_hp.get(sender, 0) <= 0:
		return
	var eq: Dictionary = server_equip.get(sender, {})
	if not Items.WEAPONS.get(eq.get("weapon", {}).get("id", ""), {}).get("ranged", false):
		return # в руках не стрелковое — читерский запрос
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_shot_cd.get(sender, 0.0)) < Items.RANGED_COOLDOWN:
		return
	_shot_cd[sender] = now
	var dir := Vector2(dx, dz)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var from := Vector2(sn.global_position.x, sn.global_position.z)
	# ближайший враг в узком коридоре вдоль луча
	var best_t := Items.RANGED_RANGE + 1.0
	var hit = null
	for g in gnomes.values():
		if not g.alive or g.friendly:
			continue
		var rel := Vector2(g.global_position.x, g.global_position.z) - from
		var t := rel.dot(dir)
		if t < 0.5 or t > Items.RANGED_RANGE:
			continue
		if (rel - dir * t).length() > 0.9 and (rel - dir * t).length() > 0.35 * g.cfg.scale * 3.0:
			continue
		if t < best_t:
			best_t = t
			hit = g
	var pd: Dictionary = Net.players.get(sender, {})
	var crit := randf() < Quests.crit_chance_for(pd) + Items.equip_crit_bonus(eq)
	var dmg_f := Items.RANGED_BASE_DMG * Quests.dmg_mult_for(pd) * Items.equip_dmg_mult(eq)
	var dmg := roundi(dmg_f * (1.8 * Quests.crit_dmg_mult_for(pd) if crit else 1.0))
	var end_t: float = best_t if hit != null else Items.RANGED_RANGE
	var to := from + dir * end_t
	Net.bcast("rpc_bolt_fx", [from.x, from.y, to.x, to.y])
	if hit != null:
		hit.last_attacker = sender
		hit.last_attacker_gid = 0
		hit.server_take_damage(dmg, sn.global_position, crit)


## Трассер болта: тонкая рейка от стрелка к цели, гаснет за мгновение.
func on_bolt_fx(x1: float, z1: float, x2: float, z2: float) -> void:
	var from := Vector3(x1, 1.2, z1)
	var to := Vector3(x2, 1.1, z2)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, from.distance_to(to))
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mesh.material_override = mat
	add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	if from.distance_squared_to(to) > 0.01:
		mesh.look_at(to, Vector3.UP)
	Sfx.play_at("fireball", from, -6.0, 1.7)
	var t := create_tween()
	t.tween_property(mesh, "scale", Vector3(0.2, 0.2, 1.0), 0.12)
	t.tween_callback(mesh.queue_free)


func _bcast_player_hp(id: int) -> void:
	if server_hp.has(id):
		server_hp[id] = mini(server_hp[id], player_max_hp(id))
		var node = player_nodes.get(id)
		var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
		Net.bcast("rpc_player_hp", [id, server_hp[id], player_max_hp(id), "sync", pos.x, pos.z])


func server_spawn_item_drop(item: Dictionary, x: float, z: float) -> void:
	loot.server_spawn_item_drop(item, x, z)


func on_item_drop(did: int, item: Dictionary, x: float, z: float) -> void:
	if item_drops.has(did):
		return
	var rarity: int = clampi(int(item.get("rarity", 0)), 0, 3)
	var node := WorldGen.crystal(self, Items.RARITY_COLORS[rarity])
	node.global_position = Vector3(x, 0, z)
	node.scale = Vector3.ONE * 1.15
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.text = tr(Items.def_name(item))
	lbl.modulate = Items.RARITY_COLORS[rarity]
	lbl.outline_size = 7
	lbl.pixel_size = 0.006
	lbl.position.y = 1.15
	node.add_child(lbl)
	item_drops[did] = {"node": node, "item": item, "life": 0.0}


func on_item_drop_taken(did: int, taker: int) -> void:
	var d: Dictionary = item_drops.get(did, {})
	if d.is_empty():
		return
	if is_instance_valid(d.node):
		fx_burst(d.node.global_position + Vector3(0, 0.6, 0), Items.RARITY_COLORS[clampi(int(d.item.get("rarity", 0)), 0, 3)], 14)
		d.node.queue_free()
	item_drops.erase(did)
	if taker == Net.my_id:
		Sfx.play("pickup")
		hud.add_chat("", tr("+ %s (%s)") % [tr(Items.def_name(d.item)), tr(Items.RARITY_NAMES[clampi(int(d.item.get("rarity", 0)), 0, 3)])], true)


func on_chest_opened(cid: int) -> void:
	var c: Dictionary = chests.get(cid, {})
	if c.is_empty():
		return
	c.opened = true
	if tutorial != null:
		tutorial.notify("chest")
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
## Уведомление о полученном расходнике (звук + строка в ленту).
## Само содержимое инвентаря приходит отдельным авторитетным синком (rpc_inv_sync).
func on_item_granted(id: int, type: String) -> void:
	var node = player_nodes.get(id)
	if node != null:
		Sfx.play_at("pickup", node.global_position)
	if id != Net.my_id:
		return
	hud.add_chat("", tr("+ %s") % tr(ITEM_DEFS.get(type, {}).get("title", type)), true)


## Клавиши 1-5: используем idx-й расходник хотбара (списание — на сервере).
func use_item_slot(idx: int) -> void:
	var bar := _consumables()
	if idx < 0 or idx >= bar.size():
		return
	var me = player_nodes.get(Net.my_id)
	if me == null or me.state in ["dead", "downed"]:
		return
	if tutorial != null:
		tutorial.notify("item")
	var type: String = bar[idx].type
	var dir := Vector3(sin(me.facing), 0, cos(me.facing))
	Net.req_use_item(type, dir.x, dir.z)
	if type == "bomb":
		Sfx.play_at("swing", me.global_position)


func server_use_item(id: int, type: String, dx: float, dz: float) -> void:
	loot.server_use_item(id, type, dx, dz)


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
			# бомба детонирует взрывные бочки поблизости
			for bbid in barrels:
				var bb: Dictionary = barrels[bbid]
				if bb.alive and Vector2(bb.x - pos.x, bb.z - pos.z).length() < 3.0:
					server_explode_barrel(bbid, 0)


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
	loot.update_pickups(delta)
	loot.update_item_drops(delta)
	if tutorial != null:
		tutorial.tick(delta)
	# автосейв героя раз в 30 секунд
	_hero_save_timer -= delta
	if _hero_save_timer <= 0:
		_hero_save_timer = 30.0
		_flush_hero_save()

	if not Net.is_server:
		return

	spawn.spread_slots(delta)
	combat.update_revives(delta)

	if restart_timer > 0:
		restart_timer -= delta
		if restart_timer <= 0:
			restart_timer = -1.0
			_server_restart_match()

	if match_over:
		return

	if is_pvp():
		spawn.update_pvp(delta)
	elif is_story():
		quest.update_story(delta)
	else:
		spawn.update_waves_pve(delta)

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
