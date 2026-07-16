extends Node
## Сетевая сессия и все RPC игры.
## Одиночная игра = сервер без пиров. Хост = сервер + локальный игрок.
## Клиент подключается по IP:порту (проброс портов или Radmin VPN).

enum Mode { NONE, SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 7777
const GAME_VERSION := "3.0.2" # у хоста и клиента должна совпадать

var mode: int = Mode.NONE
var game_mode: String = "pve" # pve | pvp | story
var campaign_chapter := 1
var difficulty := "normal" # easy | normal | hard
var continue_campaign := false # «Продолжить» в меню
var sides_mask := 0            # выполненные сайды кампании (битовая маска, сервер)


## Новая запись игрока: базовые счётчики + герой из сохранения.
func _fresh_player(pname: String) -> Dictionary:
	var p := {"name": pname, "kills": 0, "deaths": 0}
	for k in Save.hero.keys():
		p[k] = Save.hero[k]
	p["skills"] = Save.hero_skills.duplicate()
	return p
var biome: String = "meadow"
var biome_choice: String = "random"
var my_name: String = "Рыцарь"
var world_seed: int = 0

var players: Dictionary = {}

var game: Node = null
var main: Node = null
var debug_log := false # включается тестовыми режимами

signal session_failed(reason: String)
signal session_ended(reason: String)

var is_server: bool:
	get: return mode == Mode.SINGLE or mode == Mode.HOST

var my_id: int:
	get: return multiplayer.get_unique_id()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Требует уже выставленного campaign_chapter — для сюжета биом берётся по
## текущей главе, а не всегда по первой (иначе продолжение с 3-й главы грузило
## поляну вместо зимы до первого перехода через портал).
func _resolve_biome() -> void:
	if game_mode == "story":
		var ci: int = clampi(campaign_chapter - 1, 0, Quests.CHAPTER_BIOMES.size() - 1)
		biome = Quests.CHAPTER_BIOMES[ci]
	elif biome_choice == "random":
		biome = WorldGen.BIOME_LIST[randi() % WorldGen.BIOME_LIST.size()]
	else:
		biome = biome_choice


func start_single(mode_name: String = "pve") -> void:
	mode = Mode.SINGLE
	game_mode = mode_name
	world_seed = randi()
	campaign_chapter = Save.chapter if (game_mode == "story" and continue_campaign) else 1
	sides_mask = Save.sides_mask if (game_mode == "story" and continue_campaign) else 0
	_resolve_biome()
	players = {1: _fresh_player(my_name)}


func start_host(port: int, mode_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	game_mode = mode_name
	world_seed = randi()
	campaign_chapter = Save.chapter if (game_mode == "story" and continue_campaign) else 1
	sides_mask = Save.sides_mask if (game_mode == "story" and continue_campaign) else 0
	_resolve_biome()
	players = {1: _fresh_player(my_name)}
	return OK


func start_client(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players = {}
	return OK


func shutdown(reason: String = "") -> void:
	if multiplayer.multiplayer_peer != null and mode in [Mode.HOST, Mode.CLIENT]:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players = {}
	game = null
	if reason != "":
		session_ended.emit(reason)


## Пинг (мс): клиент — до сервера, хост — худший из пингов клиентов.
## −1, если сессии нет (одиночка) или мерить не с кем.
func ping_ms() -> int:
	if multiplayer.multiplayer_peer == null:
		return -1
	if mode == Mode.CLIENT:
		var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(1)
		if peer == null:
			return -1
		return peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	if mode == Mode.HOST:
		var worst := -1
		for pid in players:
			if pid == 1:
				continue
			var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(pid)
			if peer != null:
				worst = maxi(worst, peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		return worst
	return -1


# ---------------------------------------------------------------------------
# Соединения
# ---------------------------------------------------------------------------
func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	rpc_id(id, "rpc_session_info", game_mode, world_seed, biome, GAME_VERSION, difficulty)


func _on_peer_disconnected(id: int) -> void:
	if is_server:
		players.erase(id)
		bcast("rpc_despawn_player", [id])
		bcast("rpc_scores", [players])


func _on_connection_failed() -> void:
	shutdown()
	session_failed.emit(tr("Не удалось подключиться к серверу."))


func _on_server_disconnected() -> void:
	shutdown(tr("Сервер отключился."))


# ---------------------------------------------------------------------------
# Утилиты отправки
# ---------------------------------------------------------------------------
## Широковещание от сервера (выполняется и локально — call_local).
func bcast(method: StringName, args: Array = []) -> void:
	if mode == Mode.SINGLE:
		callv(method, args)
	else:
		callv("rpc", [method] + args)


# ---------------------------------------------------------------------------
# Рукопожатие
# ---------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func rpc_session_info(gmode: String, wseed: int, wbiome: String, server_version: String, diff := "normal") -> void:
	difficulty = diff
	if server_version != GAME_VERSION:
		shutdown()
		session_failed.emit(tr("Версии игры не совпадают (сервер %s, у тебя %s).") % [server_version, GAME_VERSION])
		return
	game_mode = gmode
	world_seed = wseed
	biome = wbiome
	if main != null:
		main.enter_game()
	rpc_id(1, "rpc_register", my_name, GAME_VERSION, Save.hero, Save.hero_skills)


@rpc("any_peer", "call_remote", "reliable")
func rpc_register(pname: String, version: String, hero: Dictionary = {}, skills: Dictionary = {}) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return # уже зарегистрирован: повторная регистрация = бесплатный хил/сброс смертей
	if version != GAME_VERSION:
		rpc_id(id, "rpc_kicked", tr("Версии игры не совпадают (сервер %s, у тебя %s).") % [GAME_VERSION, version])
		await get_tree().create_timer(0.5).timeout
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var entry := {"name": pname, "kills": 0, "deaths": 0, "xp": 0, "level": 1, "points": 0, "str": 0, "vit": 0, "agi": 0, "luck": 0}
	for k in ["xp", "level", "points", "str", "vit", "agi", "luck"]:
		if hero.has(k):
			entry[k] = clampi(int(hero[k]), 0, 9999)
	entry.level = clampi(entry.level, 1, Quests.MAX_LEVEL)
	var entry_skills := {}
	for sid in skills:
		if Skills.TREE.has(sid) and skills[sid] == true:
			entry_skills[sid] = true
	entry["skills"] = entry_skills
	players[id] = entry
	if game != null:
		game.server_on_player_joined(id)
	bcast("rpc_scores", [players])


@rpc("authority", "call_remote", "reliable")
func rpc_kicked(reason: String) -> void:
	shutdown()
	session_failed.emit(reason)


# ---------------------------------------------------------------------------
# Игровые RPC — сервер -> все
# ---------------------------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func rpc_spawn_player(id: int, pname: String, x: float, z: float, color: Color) -> void:
	if game != null:
		game.on_spawn_player(id, pname, x, z, color)


@rpc("authority", "call_local", "reliable")
func rpc_despawn_player(id: int) -> void:
	if game != null:
		game.on_despawn_player(id)


@rpc("authority", "call_local", "reliable")
func rpc_gnome_spawn(id: int, type: String, x: float, z: float, ex: float, ez: float, lvl: int = 1, elite: bool = false) -> void:
	if game != null:
		game.on_gnome_spawn(id, type, x, z, ex, ez, lvl, elite)


## Пакет состояний гномов: [gid, x, z, rot, loco, hp] × N.
@rpc("authority", "call_local", "unreliable_ordered", 1)
func rpc_gnome_batch(batch: PackedFloat32Array) -> void:
	if game != null and mode == Mode.CLIENT:
		game.on_gnome_batch(batch)


@rpc("authority", "call_local", "reliable")
func rpc_gnome_event(id: int, ev: String, data: Array) -> void:
	if game != null:
		game.on_gnome_event(id, ev, data)


@rpc("authority", "call_local", "reliable")
func rpc_player_hp(id: int, hp: int, max_hp: int, flag: String, from_x: float, from_z: float) -> void:
	if game != null:
		game.on_player_hp(id, hp, max_hp, flag, from_x, from_z)


@rpc("authority", "call_local", "reliable")
func rpc_player_died(id: int, killer_text: String) -> void:
	if game != null:
		game.on_player_died(id, killer_text)


@rpc("authority", "call_local", "reliable")
func rpc_player_downed(id: int) -> void:
	if game != null:
		game.on_player_downed(id)


@rpc("authority", "call_local", "reliable")
func rpc_player_revived(id: int, hp: int) -> void:
	if game != null:
		game.on_player_revived(id, hp)


@rpc("authority", "call_local", "reliable")
func rpc_revive_progress(target_id: int, reviver_id: int, k: float) -> void:
	if game != null:
		game.on_revive_progress(target_id, reviver_id, k)


@rpc("authority", "call_local", "reliable")
func rpc_player_respawn(id: int, x: float, z: float) -> void:
	if game != null:
		game.on_player_respawn(id, x, z)


@rpc("authority", "call_local", "reliable")
func rpc_buff(id: int, type: String, dur: float) -> void:
	if game != null:
		game.on_buff(id, type, dur)


@rpc("authority", "call_local", "reliable")
func rpc_fireball(fid: int, from: Vector3, dir: Vector3, color: Color) -> void:
	if game != null:
		game.on_fireball(fid, from, dir, color)


@rpc("authority", "call_local", "reliable")
func rpc_chest_spawn(cid: int, x: float, z: float, rot: float) -> void:
	if game != null:
		game.on_chest_spawn(cid, x, z, rot)


@rpc("authority", "call_local", "reliable")
func rpc_portal_spawn(x: float, z: float) -> void:
	if game != null:
		game.on_portal_spawn(x, z)


@rpc("authority", "call_local", "reliable")
func rpc_cutscene(lines: Array, fx: float, fy: float, fz: float) -> void:
	if game != null:
		game.on_cutscene(lines, fx, fy, fz)


@rpc("authority", "call_local", "reliable")
func rpc_chest_opened(cid: int) -> void:
	if game != null:
		game.on_chest_opened(cid)


@rpc("authority", "call_local", "reliable")
func rpc_item_granted(id: int, type: String) -> void:
	if game != null:
		game.on_item_granted(id, type)


@rpc("authority", "call_local", "reliable")
func rpc_bomb(bid: int, from: Vector3, vel: Vector3) -> void:
	if game != null:
		game.on_bomb(bid, from, vel)


@rpc("authority", "call_local", "reliable")
func rpc_bomb_boom(bid: int, pos: Vector3) -> void:
	if game != null:
		game.on_bomb_boom(bid, pos)


@rpc("authority", "call_local", "reliable")
func rpc_fireball_boom(fid: int, pos: Vector3) -> void:
	if game != null:
		game.on_fireball_boom(fid, pos)


@rpc("authority", "call_local", "reliable")
func rpc_wave(n: int, is_endless: bool, is_pvp_mode: bool) -> void:
	if game != null:
		game.on_wave(n, is_endless, is_pvp_mode)


@rpc("authority", "call_local", "unreliable_ordered")
func rpc_daytime(t: float) -> void:
	if game != null and mode == Mode.CLIENT:
		game.on_daytime(t)


@rpc("authority", "call_local", "reliable")
func rpc_banner(text: String) -> void:
	if game != null:
		game.on_banner(text)


@rpc("authority", "call_local", "reliable")
func rpc_pickup_spawn(pid: int, type: String, x: float, z: float) -> void:
	if game != null:
		game.on_pickup_spawn(pid, type, x, z)


@rpc("authority", "call_local", "reliable")
func rpc_pickup_taken(pid: int) -> void:
	if game != null:
		game.on_pickup_taken(pid)


@rpc("authority", "call_local", "reliable")
func rpc_scores(p: Dictionary) -> void:
	players = p
	if game != null:
		game.on_scores()


@rpc("authority", "call_local", "reliable")
func rpc_game_over(win: bool, text: String) -> void:
	if game != null:
		game.on_game_over(win, text)


@rpc("authority", "call_local", "reliable")
func rpc_match_reset() -> void:
	if game != null:
		game.on_match_reset()


@rpc("authority", "call_local", "reliable")
func rpc_quest(main_st: int, kills: int, side_st: int, side_n: int) -> void:
	if game != null:
		game.on_quest(main_st, kills, side_st, side_n)


@rpc("authority", "call_local", "reliable")
func rpc_gold(total: int) -> void:
	if game != null:
		game.on_gold(total)


@rpc("authority", "call_local", "reliable")
func rpc_sys(text: String) -> void:
	if game != null:
		game.on_sys(text)


## Системное сообщение одному игроку (хост — себе напрямую).
func send_sys(id: int, text: String) -> void:
	if id == my_id:
		if game != null:
			game.on_sys(text)
	else:
		rpc_id(id, "rpc_sys", text)


@rpc("authority", "call_local", "reliable")
func rpc_qnode(id: int, kind: String, x: float, z: float) -> void:
	if game != null:
		game.on_qnode(id, kind, x, z)


@rpc("authority", "call_local", "reliable")
func rpc_qnode_taken(id: int) -> void:
	if game != null:
		game.on_qnode_taken(id)


@rpc("authority", "call_local", "reliable")
func rpc_qnode_lit(id: int) -> void:
	if game != null:
		game.on_qnode_lit(id)


## Переход к следующей главе кампании: мир пересоздаётся у всех.
@rpc("authority", "call_local", "reliable")
func rpc_chapter(chapter: int, wbiome: String, wseed: int) -> void:
	campaign_chapter = chapter
	biome = wbiome
	world_seed = wseed
	if main != null:
		main.goto_chapter()


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_talk(which: String) -> void:
	if game != null and is_server:
		game.server_talk(multiplayer.get_remote_sender_id(), which)


func req_talk(which: String) -> void:
	if is_server:
		if game != null:
			game.server_talk(my_id, which)
	else:
		rpc_id(1, "rpc_req_talk", which)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_stat(stat: String) -> void:
	if game != null and is_server:
		game.server_alloc_stat(multiplayer.get_remote_sender_id(), stat)


func req_stat(stat: String) -> void:
	if is_server:
		if game != null:
			game.server_alloc_stat(my_id, stat)
	else:
		rpc_id(1, "rpc_req_stat", stat)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_skill(skill_id: String) -> void:
	if game != null and is_server:
		game.server_unlock_skill(multiplayer.get_remote_sender_id(), skill_id)


func req_skill(skill_id: String) -> void:
	if is_server:
		if game != null:
			game.server_unlock_skill(my_id, skill_id)
	else:
		rpc_id(1, "rpc_req_skill", skill_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_shrine(idx: int) -> void:
	if game != null and is_server:
		game.server_shrine_bless(multiplayer.get_remote_sender_id(), idx)


func req_shrine(idx: int) -> void:
	if is_server:
		if game != null:
			game.server_shrine_bless(my_id, idx)
	else:
		rpc_id(1, "rpc_req_shrine", idx)


## Общая точка входа для новых интерактивных поинтов (костёр/колодец/доска
## объявлений) — сервер сам решает, что делать, по виду поинта.
@rpc("any_peer", "call_remote", "reliable")
func rpc_req_poi(idx: int) -> void:
	if game != null and is_server:
		game.server_poi_interact(multiplayer.get_remote_sender_id(), idx)


func req_poi(idx: int) -> void:
	if is_server:
		if game != null:
			game.server_poi_interact(my_id, idx)
	else:
		rpc_id(1, "rpc_req_poi", idx)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_qnode(id: int) -> void:
	if game != null and is_server:
		game.server_qnode_take(multiplayer.get_remote_sender_id(), id)


func req_qnode(id: int) -> void:
	if is_server:
		if game != null:
			game.server_qnode_take(my_id, id)
	else:
		rpc_id(1, "rpc_req_qnode", id)


# ---------------------------------------------------------------------------
# Состояние игрока (владелец -> все): PackedFloat32Array [x, z, rot, anim, flags]
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_player_state(pkt: PackedFloat32Array) -> void:
	if game != null:
		game.on_player_state(multiplayer.get_remote_sender_id(), pkt)


func send_player_state(pkt: PackedFloat32Array) -> void:
	if mode == Mode.HOST or mode == Mode.CLIENT:
		rpc("rpc_player_state", pkt)


# ---------------------------------------------------------------------------
# Чат и голос (любой -> все, ретрансляция через сервер)
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func rpc_chat(text: String) -> void:
	if game != null:
		game.on_chat(multiplayer.get_remote_sender_id(), text)


func send_chat(text: String) -> void:
	text = text.strip_edges().left(120)
	if text == "":
		return
	if mode == Mode.HOST or mode == Mode.CLIENT:
		rpc("rpc_chat", text)
	if game != null:
		game.on_chat(my_id, text) # локальное эхо


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func rpc_voice(data: PackedByteArray) -> void:
	if game != null:
		game.on_voice(multiplayer.get_remote_sender_id(), data)


func send_voice(data: PackedByteArray) -> void:
	if mode == Mode.HOST or mode == Mode.CLIENT:
		rpc("rpc_voice", data)


# ---------------------------------------------------------------------------
# Клиент -> сервер
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func rpc_req_melee(targets: Array, dmg: int, crit: bool) -> void:
	if game != null and is_server:
		game.server_handle_melee(multiplayer.get_remote_sender_id(), targets, dmg, crit)


func req_melee(targets: Array, dmg: int, crit: bool) -> void:
	if is_server:
		if game != null:
			game.server_handle_melee(my_id, targets, dmg, crit)
	else:
		rpc_id(1, "rpc_req_melee", targets, dmg, crit)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_revive(target_id: int) -> void:
	if game != null and is_server:
		game.server_revive_tick(multiplayer.get_remote_sender_id(), target_id)


func req_revive(target_id: int) -> void:
	if is_server:
		if game != null:
			game.server_revive_tick(my_id, target_id)
	else:
		rpc_id(1, "rpc_req_revive", target_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_open_chest(cid: int) -> void:
	if game != null and is_server:
		game.server_open_chest(multiplayer.get_remote_sender_id(), cid)


func req_open_chest(cid: int) -> void:
	if is_server:
		if game != null:
			game.server_open_chest(my_id, cid)
	else:
		rpc_id(1, "rpc_req_open_chest", cid)


@rpc("any_peer", "call_remote", "reliable")
func rpc_req_use_item(type: String, dx: float, dz: float) -> void:
	if game != null and is_server:
		game.server_use_item(multiplayer.get_remote_sender_id(), type, dx, dz)


func req_use_item(type: String, dx: float, dz: float) -> void:
	if is_server:
		if game != null:
			game.server_use_item(my_id, type, dx, dz)
	else:
		rpc_id(1, "rpc_req_use_item", type, dx, dz)
