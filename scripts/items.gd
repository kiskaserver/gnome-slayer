class_name Items
extends RefCounted
## База предметов: классы оружия, тринкеты, рарности и аффиксы.
## Экземпляр предмета — обычный словарь (легко гонять по сети и в сейв):
##   {"id": String, "kind": "weapon"|"trinket"|"consumable",
##    "rarity": 0..3, "aseed": int, "count": int}
## Аффиксы НЕ хранятся: они детерминированно выводятся из (id, rarity, aseed) —
## сейв компактен, а подделать статы правкой сейва нельзя (сервер выводит сам).

const RARITY_NAMES := ["Обычное", "Редкое", "Эпическое", "Легендарное"]
const RARITY_COLORS := [Color(0.82, 0.82, 0.8), Color(0.35, 0.65, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.72, 0.2)]

# Классы оружия. combo — как в player.gd: {anim, dmg, range, arc, ts}.
# model — что вложить в руку (adventurer_items/*.gltf); baked — какие
# запечённые меши Knight показать; shield — показать ли запечённый щит.
const WEAPONS := {
	"sword1h": {
		"name": "Меч и щит", "model": "", "baked": "1H_Sword", "shield": true,
		"combo": [
			{"anim": "1H_Melee_Attack_Slice_Horizontal", "dmg": 14, "range": 2.6, "arc": 1.25, "ts": 1.45},
			{"anim": "1H_Melee_Attack_Slice_Diagonal", "dmg": 14, "range": 2.6, "arc": 1.25, "ts": 1.45},
			{"anim": "1H_Melee_Attack_Chop", "dmg": 26, "range": 2.9, "arc": 1.5, "ts": 1.25},
		]},
	"axe1h": {
		"name": "Топор и щит", "model": "axe_1handed", "baked": "", "shield": true,
		"combo": [
			{"anim": "1H_Melee_Attack_Chop", "dmg": 17, "range": 2.6, "arc": 1.2, "ts": 1.3},
			{"anim": "1H_Melee_Attack_Slice_Horizontal", "dmg": 17, "range": 2.6, "arc": 1.3, "ts": 1.3},
			{"anim": "1H_Melee_Attack_Chop", "dmg": 30, "range": 2.8, "arc": 1.4, "ts": 1.1},
		]},
	"dagger": {
		"name": "Кинжал", "model": "dagger", "baked": "", "shield": false,
		"combo": [
			{"anim": "1H_Melee_Attack_Slice_Horizontal", "dmg": 9, "range": 2.2, "arc": 1.1, "ts": 1.95},
			{"anim": "1H_Melee_Attack_Slice_Diagonal", "dmg": 9, "range": 2.2, "arc": 1.1, "ts": 1.95},
			{"anim": "1H_Melee_Attack_Slice_Horizontal", "dmg": 13, "range": 2.3, "arc": 1.2, "ts": 1.7},
		]},
	"sword2h": {
		"name": "Двуручный меч", "model": "", "baked": "2H_Sword", "shield": false,
		"combo": [
			{"anim": "2H_Melee_Attack_Slice", "dmg": 21, "range": 3.0, "arc": 1.6, "ts": 1.3},
			{"anim": "2H_Melee_Attack_Spin", "dmg": 21, "range": 3.2, "arc": 2.7, "ts": 1.25},
			{"anim": "2H_Melee_Attack_Chop", "dmg": 36, "range": 3.2, "arc": 1.7, "ts": 1.1},
		]},
	"axe2h": {
		"name": "Секира", "model": "axe_2handed", "baked": "", "shield": false,
		"combo": [
			{"anim": "2H_Melee_Attack_Chop", "dmg": 25, "range": 3.0, "arc": 1.5, "ts": 1.15},
			{"anim": "2H_Melee_Attack_Slice", "dmg": 25, "range": 3.1, "arc": 1.7, "ts": 1.15},
			{"anim": "2H_Melee_Attack_Chop", "dmg": 42, "range": 3.2, "arc": 1.6, "ts": 0.95},
		]},
}

const TRINKETS := {
	"ring_fang": {"name": "Кольцо клыка", "bias": "dmg"},
	"amulet_oak": {"name": "Дубовый амулет", "bias": "hp"},
	"charm_wind": {"name": "Оберег ветра", "bias": "spd"},
	"eye_raven": {"name": "Вороний глаз", "bias": "crit"},
}

# Пул аффиксов: диапазоны на рарность (min..max на КАЖДУЮ звезду рарности).
const AFFIX_POOL := {
	"dmg": {"title": "Урон", "per_r_min": 0.03, "per_r_max": 0.05, "pct": true},
	"hp": {"title": "Здоровье", "per_r_min": 5.0, "per_r_max": 9.0, "pct": false},
	"spd": {"title": "Скорость", "per_r_min": 0.02, "per_r_max": 0.03, "pct": true},
	"crit": {"title": "Шанс крита", "per_r_min": 0.015, "per_r_max": 0.025, "pct": true},
}


static func is_weapon(item: Dictionary) -> bool:
	return item.get("kind", "") == "weapon"


static func def_name(item: Dictionary) -> String:
	var id: String = item.get("id", "")
	if WEAPONS.has(id):
		return WEAPONS[id].name
	if TRINKETS.has(id):
		return TRINKETS[id].name
	return id


## Детерминированные аффиксы из (id, rarity, aseed). Сервер и клиент считают
## одинаково; в сейве лежит только тройка — статы не подделать.
static func affixes(item: Dictionary) -> Dictionary:
	var rarity: int = clampi(int(item.get("rarity", 0)), 0, 3)
	if rarity <= 0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(item.get("id", "")) + ":" + str(item.get("aseed", 0)))
	var keys: Array = AFFIX_POOL.keys()
	# тринкет со смещением: его профильный аффикс всегда первый
	var id: String = item.get("id", "")
	if TRINKETS.has(id):
		var bias: String = TRINKETS[id].bias
		keys.erase(bias)
		keys.push_front(bias)
	else:
		# перемешать детерминированно
		for i in range(keys.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = keys[i]
			keys[i] = keys[j]
			keys[j] = tmp
	var out: Dictionary = {}
	for i in mini(rarity, keys.size()):
		var k: String = keys[i]
		var pool: Dictionary = AFFIX_POOL[k]
		out[k] = rng.randf_range(pool.per_r_min, pool.per_r_max) * rarity
	return out


## Суммарные бонусы надетого: equip = {"weapon": item|{}, "trinket": item|{}}.
static func equip_dmg_mult(equip: Dictionary) -> float:
	var m := 1.0
	for slot in equip:
		var it: Dictionary = equip[slot]
		if not it.is_empty():
			m += affixes(it).get("dmg", 0.0)
	return m


static func equip_hp_bonus(equip: Dictionary) -> int:
	var b := 0.0
	for slot in equip:
		var it: Dictionary = equip[slot]
		if not it.is_empty():
			b += affixes(it).get("hp", 0.0)
	return roundi(b)


static func equip_speed_mult(equip: Dictionary) -> float:
	var m := 1.0
	for slot in equip:
		var it: Dictionary = equip[slot]
		if not it.is_empty():
			m += affixes(it).get("spd", 0.0)
	return m


static func equip_crit_bonus(equip: Dictionary) -> float:
	var b := 0.0
	for slot in equip:
		var it: Dictionary = equip[slot]
		if not it.is_empty():
			b += affixes(it).get("crit", 0.0)
	return b


## Комбо надетого оружия (или меч по умолчанию).
static func combo_for(equip: Dictionary) -> Array:
	var w: Dictionary = equip.get("weapon", {})
	var cls: Dictionary = WEAPONS.get(w.get("id", "sword1h"), WEAPONS["sword1h"])
	return cls.combo


## Дроп с врага: level влияет на шанс рарности, luck игрока — тоже.
## Возвращает {} если не повезло.
static func roll_drop(level: int, luck: int, rng_seed: int, force := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	if not force and rng.randf() > 0.16 + luck * 0.01:
		return {}
	var rarity := 0
	var r := rng.randf() - level * 0.015 - luck * 0.008
	if r < 0.03:
		rarity = 3
	elif r < 0.14:
		rarity = 2
	elif r < 0.42:
		rarity = 1
	var use_weapons := rng.randf() < 0.65
	var pool: Array = WEAPONS.keys() if use_weapons else TRINKETS.keys()
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	return {"id": id, "kind": "weapon" if use_weapons else "trinket",
		"rarity": rarity, "aseed": rng.randi(), "count": 1}


# --- лавка торговца ---
const CONSUMABLE_PRICES := {"potion_hp": 15, "bomb": 12, "potion_rage": 14, "potion_speed": 14}


## Ассортимент лавки на главу: детерминирован (seed, chapter) — сервер и клиент
## считают одинаково, по сети ассортимент гонять не нужно.
## Позиция: {"item": Dictionary, "price": int}
static func shop_stock(world_seed: int, chapter: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("shop:%d:%d" % [world_seed, chapter])
	var stock: Array = []
	for cid in CONSUMABLE_PRICES:
		stock.append({"item": {"id": cid, "kind": "consumable", "rarity": 0, "aseed": 0, "count": 1},
			"price": CONSUMABLE_PRICES[cid]})
	for i in 3:
		var it := roll_drop(chapter, 0, rng.randi(), true)
		if it.is_empty():
			continue
		it.rarity = maxi(1, it.rarity) # торговец серостью не торгует
		stock.append({"item": it, "price": 30 + it.rarity * 35 + chapter * 5})
	return stock


## Цена продажи торговцу: четверть закупочной за рарность, гроши за расходник.
static func sell_price(item: Dictionary) -> int:
	if item.get("kind", "") == "consumable":
		return 3
	return 10 + clampi(int(item.get("rarity", 0)), 0, 3) * 9


## Валидация предмета из сейва/от клиента: чужие id и мусор отбрасываются.
static func sanitize(item) -> Dictionary:
	if not (item is Dictionary):
		return {}
	var id: String = str(item.get("id", ""))
	var kind := ""
	if WEAPONS.has(id):
		kind = "weapon"
	elif TRINKETS.has(id):
		kind = "trinket"
	elif id in ["potion_hp", "potion_rage", "potion_speed", "bomb", "gold_feast"]:
		kind = "consumable"
	else:
		return {}
	return {"id": id, "kind": kind, "rarity": clampi(int(item.get("rarity", 0)), 0, 3),
		"aseed": int(item.get("aseed", 0)), "count": clampi(int(item.get("count", 1)), 1, 99)}


## Короткое описание аффиксов для тултипа (tr() делает вызывающая сторона —
## статик-функции переводить не умеют, поэтому названия переводим через TranslationServer).
static func affix_text(item: Dictionary) -> String:
	var parts: Array = []
	var af := affixes(item)
	for k in af:
		var pool: Dictionary = AFFIX_POOL[k]
		var title: String = TranslationServer.translate(pool.title)
		if pool.pct:
			parts.append("+%d%% %s" % [roundi(af[k] * 100.0), title])
		else:
			parts.append("+%d %s" % [roundi(af[k]), title])
	return ", ".join(parts)
