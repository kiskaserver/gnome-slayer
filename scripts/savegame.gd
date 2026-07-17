extends Node
## Сохранения: 3 слота. В каждом — герой (опыт/уровень/характеристики)
## и кампания (глава, сайд-квесты), плюс дата сохранения.

const SLOTS := 3

# тестовые прогоны (--test/--mp*/--shot*) живут в своих файлах,
# чтобы не портить настоящие сейвы игрока
static var _prefix := ""
static func _test_prefix() -> String:
	if _prefix == "":
		_prefix = "real_"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--test") or arg.begins_with("--mp") 					or arg.begins_with("--shot") or arg.begins_with("--screenshot") 					or arg.begins_with("--revive") or arg.begins_with("--waverespawn"):
				_prefix = "test_"
	return "" if _prefix == "real_" else "test_"

static func meta_path() -> String:
	return "user://%sslots.cfg" % _test_prefix()
const OLD_PATH := "user://save.cfg"

var active_slot := 1
var hero := {"xp": 0, "level": 1, "points": 0, "str": 0, "vit": 0, "agi": 0, "luck": 0}
var hero_skills: Dictionary = {}  # id -> true; отдельно от hero — там только int-поля
var hero_inventory: Array = []    # предметы Items-формата (id/kind/rarity/aseed/count)
var hero_equipment: Dictionary = {"weapon": {}, "trinket": {}}
var chapter := 1
var sides_mask := 0

signal slots_changed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_migrate_old()
	var meta := ConfigFile.new()
	if meta.load(meta_path()) == OK:
		active_slot = clampi(int(meta.get_value("meta", "active_slot", 1)), 1, SLOTS)
	load_slot(active_slot)


static func slot_path(i: int) -> String:
	return "user://%ssave_slot_%d.cfg" % [_test_prefix(), i]


## Старый одиночный сейв переезжает в слот 1.
func _migrate_old() -> void:
	if FileAccess.file_exists(OLD_PATH) and not FileAccess.file_exists(slot_path(1)):
		var cfg := ConfigFile.new()
		if cfg.load(OLD_PATH) == OK:
			cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system(false, true))
			cfg.save(slot_path(1))
		DirAccess.remove_absolute(OLD_PATH)


## Краткая сводка слота для карточки в меню; {} если слот пуст.
func slot_info(i: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(i)) != OK:
		return {}
	return {
		"chapter": int(cfg.get_value("campaign", "chapter", 1)),
		"sides": int(cfg.get_value("campaign", "sides_mask", 0)),
		"level": int(cfg.get_value("hero", "level", 1)),
		"xp": int(cfg.get_value("hero", "xp", 0)),
		"saved_at": str(cfg.get_value("meta", "saved_at", "")),
	}


func select_slot(i: int) -> void:
	active_slot = clampi(i, 1, SLOTS)
	var meta := ConfigFile.new()
	meta.set_value("meta", "active_slot", active_slot)
	meta.save(meta_path())
	load_slot(active_slot)
	slots_changed.emit()


func delete_slot(i: int) -> void:
	if FileAccess.file_exists(slot_path(i)):
		DirAccess.remove_absolute(slot_path(i))
	if i == active_slot:
		load_slot(active_slot) # обнулится на дефолты
	slots_changed.emit()


func load_slot(i: int) -> void:
	hero = {"xp": 0, "level": 1, "points": 0, "str": 0, "vit": 0, "agi": 0, "luck": 0}
	hero_skills = {}
	hero_inventory = []
	hero_equipment = {"weapon": {}, "trinket": {}}
	chapter = 1
	sides_mask = 0
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(i)) != OK:
		return
	for k in hero.keys():
		hero[k] = int(cfg.get_value("hero", k, hero[k]))
	var raw_skills = cfg.get_value("hero", "skills", {})
	if raw_skills is Dictionary:
		hero_skills = raw_skills
	# инвентарь/экипировка: каждая позиция через санитайзер — битый сейв не роняет игру
	var raw_inv = cfg.get_value("hero", "inventory", [])
	if raw_inv is Array:
		for raw in raw_inv:
			var it := Items.sanitize(raw)
			if not it.is_empty():
				hero_inventory.append(it)
	var raw_eq = cfg.get_value("hero", "equipment", {})
	if raw_eq is Dictionary:
		hero_equipment = {"weapon": Items.sanitize(raw_eq.get("weapon", {})),
			"trinket": Items.sanitize(raw_eq.get("trinket", {}))}
	chapter = clampi(int(cfg.get_value("campaign", "chapter", 1)), 1, Quests.CHAPTERS.size())
	sides_mask = int(cfg.get_value("campaign", "sides_mask", 0))


func write() -> void:
	var cfg := ConfigFile.new()
	for k in hero.keys():
		cfg.set_value("hero", k, hero[k])
	cfg.set_value("hero", "skills", hero_skills)
	cfg.set_value("hero", "inventory", hero_inventory)
	cfg.set_value("hero", "equipment", hero_equipment)
	cfg.set_value("campaign", "chapter", chapter)
	cfg.set_value("campaign", "sides_mask", sides_mask)
	cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system(false, true))
	cfg.save(slot_path(active_slot))
	slots_changed.emit()


## Забирает характеристики героя (навыки, инвентарь, экипировку) из сетевой записи.
func store_hero(p: Dictionary) -> void:
	for k in hero.keys():
		if p.has(k):
			hero[k] = p[k]
	if p.get("skills", {}) is Dictionary:
		hero_skills = p.get("skills", {})
	if p.get("inventory", null) is Array:
		hero_inventory = p.get("inventory").duplicate(true)
	if p.get("equipment", null) is Dictionary:
		hero_equipment = p.get("equipment").duplicate(true)
	write()


func has_campaign() -> bool:
	return chapter > 1


func reset_campaign() -> void:
	chapter = 1
	sides_mask = 0
	write()
