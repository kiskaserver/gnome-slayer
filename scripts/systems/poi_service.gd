class_name PoiService
extends RefCounted
## Точки интереса: лор, святилище, костёр, колодец, доска объявлений.
## Серверные интеракции; кулдауны и одноразовые заказы живут здесь.

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


var _shrine_cd: Dictionary = {}  # индекс точки интереса -> время, когда снова можно благословить


func find_poi_near(pos: Vector3, radius: float) -> int:
	for i in game.world_pois.size():
		var p: Dictionary = game.world_pois[i]
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius:
			return i
	return -1


## Осмотреть лор-деталь (руины/менгиры/гробница/поле боя) — чисто текст, локально
## у каждого клиента, снаряд не нужен: детали детерминированы сидом и одинаковы
## у всех игроков.
func start_lore(idx: int) -> void:
	if idx < 0 or idx >= game.world_pois.size():
		return
	var poi: Dictionary = game.world_pois[idx]
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
	game.ui_blocked = true
	game.hud.show_dialog([["", text]], "")
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
	if idx < 0 or idx >= game.world_pois.size() or game.world_pois[idx].kind != "shrine":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _shrine_cd.get(idx, 0.0):
		Net.send_sys(sender, "Святилище ещё не готово благословлять снова.")
		return
	_shrine_cd[idx] = now + SHRINE_BLESS_CD
	Net.bcast("rpc_buff", [sender, "speed", Game.PICKUP_TYPES.speed.dur])
	Net.bcast("rpc_buff", [sender, "rage", Game.PICKUP_TYPES.rage.dur])
	Net.bcast("rpc_banner", [Quests.LORE_SHRINE_BANNER])


## Единая точка входа для интерактивных точек, требующих сервера (не чисто
## текстовый лор) — диспетчер по виду поинта.
func server_poi_interact(sender: int, idx: int) -> void:
	if idx < 0 or idx >= game.world_pois.size():
		return
	match game.world_pois[idx].kind:
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
	if idx < 0 or idx >= game.world_pois.size() or game.world_pois[idx].kind != "campfire":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _campfire_cd.get(idx, 0.0):
		Net.send_sys(sender, "Костёр ещё прогорает — не время греться снова.")
		return
	_campfire_cd[idx] = now + CAMPFIRE_CD
	game.server_heal_player(sender, roundi(game.player_max_hp(sender) * 0.3))
	game.server_shield[sender] = game.server_shield.get(sender, 0) + 25
	Net.bcast("rpc_buff", [sender, "shield", 20.0])
	Net.bcast("rpc_banner", [Quests.LORE_CAMPFIRE_BANNER])
	# в мире-путешествии тронутый костёр становится чекпоинтом отряда
	if not game.world_areas.is_empty():
		game.team_checkpoint = Vector2(game.world_pois[idx].x, game.world_pois[idx].z)
		Net.send_sys(sender, "Костёр запомнил вас: отряд возродится здесь.")


## Колодец: чистый хил без бафа, но чаще доступен, чем костёр или святилище.
func server_well_drink(sender: int, idx: int) -> void:
	if idx < 0 or idx >= game.world_pois.size() or game.world_pois[idx].kind != "well":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _well_cd.get(idx, 0.0):
		Net.send_sys(sender, "Колодец ещё не набрал воды.")
		return
	_well_cd[idx] = now + WELL_CD
	game.server_heal_player(sender, roundi(game.player_max_hp(sender) * 0.4))
	Net.bcast("rpc_banner", [Quests.LORE_WELL_BANNER])


## Доска объявлений: одноразовый за матч заказ на элитного гнома неподалёку.
func server_bounty_read(sender: int, idx: int) -> void:
	if idx < 0 or idx >= game.world_pois.size() or game.world_pois[idx].kind != "bounty_board":
		return
	if _bounty_used.get(idx, false):
		Net.send_sys(sender, "Награда за эту доску уже забрана.")
		return
	_bounty_used[idx] = true
	var poi: Dictionary = game.world_pois[idx]
	var roles: Dictionary = Game.BIOME_ENEMIES.get(Net.biome, Game.BIOME_ENEMIES["meadow"])
	var a := randf_range(0, TAU)
	var spawn_pos := Vector3(poi.x + cos(a) * 5.0, 0, poi.z + sin(a) * 5.0)
	game.server_spawn_gnome_at(roles.melee, spawn_pos, game.enemy_level() + 1, true)
	Net.bcast("rpc_banner", [Quests.LORE_BOUNTY_BANNER])


## Доски объявлений снова активны (новый матч/рестарт главы).
func reset_bounties() -> void:
	_bounty_used.clear()
