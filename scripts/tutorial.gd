class_name Tutorial
extends RefCounted
## Интерактивное обучение (D2): параллельная цепочка шагов «сделай действие —
## шаг зачтён» поверх первой главы. Живёт только в одиночной кампании, пока
## meta/tutorial_done не выставлен; каждый шаг ждёт настоящего действия игрока
## (хуки в симуляции/бое/интеракциях дёргают notify).

var game # Game-владелец
var active := true
var step := 0

# аккумуляторы текущих шагов
var move_d := 0.0
var cam_d := 0.0
var sprint_t := 0.0
var attacks := 0
var block_t := 0.0
var dodged := false

const STEPS := ["move", "sprint", "attack", "defense", "chest", "inventory", "stats", "item", "talk"]


func _init(game_) -> void:
	game = game_
	_show()


## Хуки из геймплея: kind — что сделал игрок, amount — величина (метры/секунды).
func notify(kind: String, amount := 1.0) -> void:
	if not active:
		return
	match kind:
		"move": move_d += amount
		"camera": cam_d += amount
		"sprint": sprint_t += amount
		"attack": attacks += 1
		"block": block_t += amount
		"dodge": dodged = true
		"chest":
			if STEPS[step] == "chest":
				_advance()
		"item":
			if STEPS[step] == "item":
				_advance()
		"talk":
			# финал: разговор со старейшиной (npc 0) у маяка
			if STEPS[step] == "talk" and amount == 0.0:
				_advance()


func tick(delta: float) -> void:
	if not active:
		return
	match STEPS[step]:
		"move":
			if move_d >= 4.0 and cam_d >= 1.2:
				_advance()
		"sprint":
			if sprint_t >= 1.2:
				_advance()
		"attack":
			if attacks >= 3:
				_advance()
		"defense":
			if block_t >= 0.8 and dodged:
				_advance()
		"inventory":
			if game.hud.is_inventory_open():
				_advance()
		"stats":
			if game.hud.is_stats_open():
				_advance()
		"talk":
			# маяк ведёт к старейшине; если НПС ещё нет (мир строится) — подождём
			if game.waypoint_node == null and not game.npcs.is_empty():
				game.set_waypoint(game.npcs[0].global_position)
	# маяк мягко вращается — заметен краем глаза
	if game.waypoint_node != null and is_instance_valid(game.waypoint_node):
		game.waypoint_node.rotation.y += delta * 2.2


func _advance() -> void:
	step += 1
	Sfx.play("pickup", -4.0)
	if step >= STEPS.size():
		_finish()
		return
	_show()


func _show() -> void:
	var key_i: String = game.main.key_name("interact")
	var text := ""
	match STEPS[step]:
		"move": text = tr("WASD — движение, мышью осмотрись по сторонам")
		"sprint": text = tr("Зажми [%s] на бегу — следи за жёлтой полосой стамины") % game.main.key_name("run")
		"attack": text = tr("Бей (%s) три раза подряд — удары складываются в серию") % game.main.key_name("attack")
		"defense": text = tr("Подержи блок (%s) и сделай перекат [%s]") % [game.main.key_name("block"), game.main.key_name("dodge")]
		"chest": text = tr("Найди сундук и открой его [%s]") % key_i
		"inventory": text = tr("Загляни в инвентарь [%s]") % game.main.key_name("inventory")
		"stats": text = tr("Открой лист персонажа [%s] — там очки и древо навыков") % game.main.key_name("stats")
		"item": text = tr("Используй предмет с пояса (клавиши 1-5)")
		"talk":
			text = tr("Иди к золотому маяку и поговори со старейшиной [%s]") % key_i
			if not game.npcs.is_empty():
				game.set_waypoint(game.npcs[0].global_position)
	game.hud.set_tutorial("%s %d/%d · %s" % [tr("ОБУЧЕНИЕ"), step + 1, STEPS.size(), text])


func _finish() -> void:
	active = false
	game.clear_waypoint()
	game.hud.set_tutorial("")
	game.hud.banner(tr("ОБУЧЕНИЕ ЗАВЕРШЕНО!"))
	Save.set_tutorial_done()


## Кнопка «Пропустить обучение» (пауза): флаг ставится, подсказки убираются.
func skip() -> void:
	if not active:
		return
	active = false
	game.clear_waypoint()
	game.hud.set_tutorial("")
	game.hud.add_chat("", tr("Обучение пропущено. Удачи!"), true)
	Save.set_tutorial_done()
