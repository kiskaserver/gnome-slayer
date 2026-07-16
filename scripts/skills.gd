class_name Skills
extends RefCounted
## Древо навыков: тир-2 узлы ветвятся от тир-1, которые ветвятся от базовых
## характеристик (str/vit/agi/luck). Валюта та же, что и на характеристики —
## свободные очки (hero.points). Открытые узлы хранятся в hero.skills (id -> true).

# branch — колонка дерева; req_stat/req_val — сколько очков в характеристике нужно;
# parent — какой узел того же дерева должен быть открыт раньше ("" — корень ветки).
const TREE := {
	"str_1": {"branch": "str", "tier": 1, "req_stat": "str", "req_val": 2, "parent": "",
		"name": "Силовой хват", "desc": "+8% урона в ближнем бою"},
	"str_2": {"branch": "str", "tier": 2, "req_stat": "str", "req_val": 4, "parent": "str_1",
		"name": "Свирепость", "desc": "Ещё +8% урона в ближнем бою"},
	"vit_1": {"branch": "vit", "tier": 1, "req_stat": "vit", "req_val": 2, "parent": "",
		"name": "Крепкое тело", "desc": "+6% максимального здоровья"},
	"vit_2": {"branch": "vit", "tier": 2, "req_stat": "vit", "req_val": 4, "parent": "vit_1",
		"name": "Целитель", "desc": "Поднимаешь союзников на 20% быстрее"},
	"agi_1": {"branch": "agi", "tier": 1, "req_stat": "agi", "req_val": 2, "parent": "",
		"name": "Лёгкие ноги", "desc": "+6% скорости бега"},
	"agi_2": {"branch": "agi", "tier": 2, "req_stat": "agi", "req_val": 4, "parent": "agi_1",
		"name": "Тень", "desc": "Перекат восстанавливается на 20% быстрее"},
	"luck_1": {"branch": "luck", "tier": 1, "req_stat": "luck", "req_val": 2, "parent": "",
		"name": "Удачливый", "desc": "+20% золота с убитых тобой гномов"},
	"luck_2": {"branch": "luck", "tier": 2, "req_stat": "luck", "req_val": 4, "parent": "luck_1",
		"name": "Роковой удар", "desc": "Криты наносят на 25% больше"},
}

const BRANCH_ORDER := ["str", "vit", "agi", "luck"]


static func has(p: Dictionary, id: String) -> bool:
	return p.get("skills", {}).get(id, false)


static func can_unlock(p: Dictionary, id: String) -> bool:
	var def: Dictionary = TREE.get(id, {})
	if def.is_empty() or has(p, id):
		return false
	if p.get(def.req_stat, 0) < def.req_val:
		return false
	if def.parent != "" and not has(p, def.parent):
		return false
	return true


## Множитель урона в ближнем бою от древа (складывается с бонусом str).
static func dmg_mult(p: Dictionary) -> float:
	var m := 1.0
	if has(p, "str_1"):
		m += 0.08
	if has(p, "str_2"):
		m += 0.08
	return m


static func max_hp_mult(p: Dictionary) -> float:
	# только vit_1 даёт здоровье; vit_2 — это скорость подъёма (revive_speed_mult)
	var m := 1.0
	if has(p, "vit_1"):
		m += 0.06
	return m


static func speed_mult(p: Dictionary) -> float:
	var m := 1.0
	if has(p, "agi_1"):
		m += 0.06
	return m


## Множитель к скорости перекатов (меньше — короче кулдаун), т.е. делитель времени.
static func dodge_cd_mult(p: Dictionary) -> float:
	return 0.8 if has(p, "agi_2") else 1.0


static func revive_speed_mult(p: Dictionary) -> float:
	return 1.2 if has(p, "vit_2") else 1.0


static func gold_mult(p: Dictionary) -> float:
	return 1.2 if has(p, "luck_1") else 1.0


static func crit_dmg_mult(p: Dictionary) -> float:
	return 1.25 if has(p, "luck_2") else 1.0
