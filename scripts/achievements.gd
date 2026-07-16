extends Node
## Достижения — локальные, не привязаны к слоту кампании (как профиль игрока).
## Каждый клиент отслеживает их сам по событиям, которые и так до него доходят
## (счёт, рассылки квеста, спавны) — отдельная сетевая синхронизация не нужна.

signal unlocked(id: String)

const DEFS := {
	"first_blood": {"name": "Первая кровь", "desc": "Убей своего первого гнома"},
	"monster_slayer": {"name": "Гроза гномов", "desc": "Убей 100 гномов"},
	"boss_slayer": {"name": "Победитель вождя", "desc": "Срази вожака гномов"},
	"hire_ally": {"name": "Вольный маг", "desc": "Найми гнома-мага в лагере"},
	"ally_veteran": {"name": "Наставник", "desc": "Прокачай наёмника до максимума"},
	"reviver": {"name": "Спасатель", "desc": "Подними павшего товарища"},
	"wealthy": {"name": "Золотая жила", "desc": "Собери 500 золота отряда за главу"},
	"side_master": {"name": "Мастер на все руки", "desc": "Выполни все побочные задания кампании"},
	"story_complete": {"name": "Осколки собраны", "desc": "Заверши кампанию"},
	"golden_ending": {"name": "Достойный финал", "desc": "Получи лучшую концовку кампании"},
	"pvp_win": {"name": "Дуэлянт", "desc": "Победи в ПвП-поединке"},
	"lore_hunter": {"name": "Пытливый ум", "desc": "Осмотри руины или менгиры в мире"},
	"blessed": {"name": "Благословлённый", "desc": "Получи благословение у святилища"},
	"elite_hunter": {"name": "Охотник на элиту", "desc": "Срази золотого элитного гнома"},
	"bounty_board": {"name": "Свободный охотник", "desc": "Прими заказ с доски объявлений"},
	"campfire_rest": {"name": "У костра", "desc": "Погрейся у походного костра"},
	"well_wisher": {"name": "Живая вода", "desc": "Испей воды из старого колодца"},
	"finisher": {"name": "Добивающий удар", "desc": "Доверши приём по оглушённому гному"},
	"lore_master": {"name": "Хранитель памяти", "desc": "Прочитай все фрагменты лора в мире"},
}

const PATH := "user://achievements.cfg"

var unlocked_ids: Dictionary = {}
var lore_seen: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for id in DEFS:
			if bool(cfg.get_value("ach", id, false)):
				unlocked_ids[id] = true
		if cfg.has_section("lore"):
			for key in cfg.get_section_keys("lore"):
				lore_seen[key] = true


func unlock(id: String) -> void:
	if not DEFS.has(id) or unlocked_ids.get(id, false):
		return
	unlocked_ids[id] = true
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ach", id, true)
	cfg.save(PATH)
	unlocked.emit(id)


func is_unlocked(id: String) -> bool:
	return unlocked_ids.get(id, false)


func count_unlocked() -> int:
	return unlocked_ids.size()


## Отмечает конкретную строку лора как прочитанную (kind + индекс в пуле) и
## выдаёт "lore_master", когда собраны все фрагменты одной карты.
func mark_lore(key: String) -> void:
	if lore_seen.get(key, false):
		return
	lore_seen[key] = true
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("lore", key, true)
	cfg.save(PATH)
	if lore_seen.size() >= _lore_total():
		unlock("lore_master")


func lore_progress() -> Vector2i:
	return Vector2i(lore_seen.size(), _lore_total())


func _lore_total() -> int:
	return Quests.LORE_RUINS.size() + Quests.LORE_STONES.size() \
		+ Quests.LORE_CRYPT.size() + Quests.LORE_BATTLEFIELD.size()
