class_name ZoneManager
extends RefCounted
## Переходы зон (сервер): вход/выход подземелья и pack/unpack Net.carry —
## переносимое сквозь пересоздание мира состояние отряда.

var game # Game-владелец: сервис оперирует его состоянием и Net


func _init(game_) -> void:
	game = game_


## Упаковать переносимое состояние перед сменой зоны (сервер).
func fill_carry(extra: Dictionary = {}) -> void:
	Net.carry = {
		"gold": game.server_gold,
		"q_main": game.q_main, "q_kills": game.q_kills,
		"q_side": game.q_side, "q_side_n": game.q_side_n,
		"checkpoint_x": game.team_checkpoint.x, "checkpoint_y": game.team_checkpoint.y,
		"second_wind": game._second_wind_used.duplicate(),
	}
	for k in extra:
		Net.carry[k] = extra[k]


## Распаковать состояние после смены зоны (сервер, до спавна игроков).
func restore_carry() -> void:
	if Net.carry.is_empty():
		return
	game._carry_restored = true
	game.server_gold = int(Net.carry.get("gold", 0))
	game.q_main = int(Net.carry.get("q_main", 0))
	game.q_kills = int(Net.carry.get("q_kills", 0))
	game.q_side = int(Net.carry.get("q_side", -1))
	game.q_side_n = int(Net.carry.get("q_side_n", 0))
	game.team_checkpoint = Vector2(Net.carry.get("checkpoint_x", Vector2.INF.x), Net.carry.get("checkpoint_y", Vector2.INF.y))
	game._second_wind_used = Net.carry.get("second_wind", {})
	if Net.carry.has("return_x"):
		game.spawn_override = Vector2(Net.carry.get("return_x"), Net.carry.get("return_z"))
	if Net.carry.has("entrance_x"):
		game._entrance_hint = Vector2(Net.carry.get("entrance_x"), Net.carry.get("entrance_z"))
	Net.carry = {}
	game.delay(0.5, func():
		Net.bcast("rpc_gold", [game.server_gold])
		game._bcast_quest())


## Вся живая группа у входа в склеп — уходим в подземелье (сервер).
func server_enter_dungeon() -> void:
	# точку входа проносим сквозь данж: выйдя, отряд появится у крипты
	fill_carry({"entrance_x": game.dungeon_entrance.x, "entrance_z": game.dungeon_entrance.z})
	Net.bcast("rpc_banner", ["ОТРЯД СПУСКАЕТСЯ В СКЛЕП..."])
	Net.bcast("rpc_zone", ["dungeon", randi()])


## Портал в зале босса ведёт обратно на поверхность (сервер).
func server_exit_dungeon() -> void:
	fill_carry({"return_x": game._entrance_hint.x if game._entrance_hint != Vector2.INF else game.CAMP_POS.x,
		"return_z": game._entrance_hint.y if game._entrance_hint != Vector2.INF else game.CAMP_POS.z})
	Net.bcast("rpc_banner", ["ОТРЯД ВЫБИРАЕТСЯ НА ПОВЕРХНОСТЬ"])
	Net.bcast("rpc_zone", ["overworld", Net.world_seed])
