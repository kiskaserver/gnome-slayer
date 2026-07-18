class_name Gnome
extends CharacterBody3D
## Гном. На сервере — полный ИИ: машина состояний, зрение/слух, групповая
## тревога, окружение по слотам, токены атак, обход препятствий по навсетке,
## уклонения (разведчик), лечение союзников (шаман). На клиентах — марионетка.

const GRAVITY := 20.0
const SIGHT_DIST := 17.0
const SIGHT_ANGLE := 1.25
const LOCO := ["Idle", "Walking_A", "Running_A", "2H_Melee_Idle", "Idle_Combat", "Unarmed_Idle"]

# высота модели в юнитах до масштабирования — для лейблов над головой
const MODEL_HEIGHTS := {
	"Barbarian": 1.85, "Rogue_Hooded": 1.8, "Rogue": 1.8, "Mage": 2.25,
	"Skeleton_Warrior": 1.9, "Skeleton_Minion": 1.55,
	"Skeleton_Mage": 2.2, "Skeleton_Rogue": 1.8,
}

const TYPES := {
	"berserker": {
		"model": "Barbarian", "scale": 0.62, "hp": 55, "speed": 3.3, "turn": 7.0,
		"attack_range": 1.8, "attack_dmg": 15, "cd_min": 1.6, "cd_max": 2.6,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin"],
		"attack_ts": 1.15, "ring": 3.0, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"stagger": 0.45, "ranged": false, "retreats": false, "enrage_at": 0.4,
	},
	"scout": {
		"model": "Rogue_Hooded", "scale": 0.55, "hp": 26, "speed": 5.0, "turn": 10.0,
		"attack_range": 1.5, "attack_dmg": 8, "cd_min": 1.2, "cd_max": 2.0,
		"attack_anims": ["Dualwield_Melee_Attack_Stab", "Dualwield_Melee_Attack_Slice"],
		"attack_ts": 1.5, "ring": 4.4, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["Crossbow", "Throwable"],
		"stagger": 0.85, "ranged": false, "retreats": true, "enrage_at": 0.0, "dodges": true,
	},
	"shaman": {
		"model": "Mage", "scale": 0.58, "hp": 30, "speed": 2.9, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 12, "cd_min": 2.6, "cd_max": 3.8,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["1H_Wand", "Spellbook"],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
	},
	# босс финальной волны — «Вождь», земельной ярости: раз в цикл вбивает
	# оружие в землю и бьёт волной по всем, кто рядом (сигнал — долгий рёв).
	"king": {
		"model": "Barbarian", "scale": 1.05, "hp": 380, "speed": 2.6, "turn": 5.0,
		"attack_range": 2.6, "attack_dmg": 28, "cd_min": 1.8, "cd_max": 2.8,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.95, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"special": "slam", "special_cd": 9.0, "special_range": 20.0, "special_radius": 5.5, "special_dmg": 24,
		"stagger": 0.06, "ranged": false, "retreats": false, "enrage_at": 0.5,
	},
	# --- зимний лес: морозные гномы ---
	"frost_berserker": {
		"model": "Barbarian", "scale": 0.66, "hp": 72, "speed": 2.9, "turn": 6.0,
		"attack_range": 1.9, "attack_dmg": 18, "cd_min": 1.7, "cd_max": 2.7,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Spin"],
		"attack_ts": 1.05, "ring": 3.0, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"stagger": 0.35, "ranged": false, "retreats": false, "enrage_at": 0.4,
		"tint": Color(0.6, 0.8, 1.3),
	},
	"frost_shaman": {
		"model": "Mage", "scale": 0.58, "hp": 34, "speed": 2.9, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 14, "cd_min": 2.4, "cd_max": 3.6,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["1H_Wand", "Spellbook"],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
		"tint": Color(0.6, 0.8, 1.3), "projectile_color": Color(0.45, 0.8, 1.0),
	},
	# «Ледяной король» — вместо статичной ярости раз в цикл делает стремительный
	# рывок к самой дальней цели и бьёт ледяной волной по приземлению.
	"frost_king": {
		"model": "Barbarian", "scale": 1.1, "hp": 440, "speed": 2.5, "turn": 5.0,
		"attack_range": 2.7, "attack_dmg": 32, "cd_min": 1.8, "cd_max": 2.8,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.92, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": ["1H_Axe", "Offhand", "Mug", "Round_Shield"],
		"special": "charge", "special_cd": 7.5, "special_range": 22.0, "special_radius": 3.5, "special_dmg": 22,
		"stagger": 0.05, "ranged": false, "retreats": false, "enrage_at": 0.5,
		"tint": Color(0.55, 0.78, 1.35),
	},
	# --- скелеты (ночь и осень), пак KayKit Skeletons ---
	"skeleton_warrior": {
		"model": "Skeleton_Warrior", "scale": 0.85, "hp": 60, "speed": 3.1, "turn": 7.0,
		"attack_range": 1.9, "attack_dmg": 16, "cd_min": 1.5, "cd_max": 2.5,
		"attack_anims": ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab"],
		"attack_ts": 1.2, "ring": 3.0, "idle_anim": "Idle_Combat",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": [],
		"stagger": 0.4, "ranged": false, "retreats": false, "enrage_at": 0.0,
		"weapon_r": "Skeleton_Blade", "weapon_l": "Skeleton_Shield_Small_A",
	},
	"skeleton_minion": {
		"model": "Skeleton_Minion", "scale": 0.6, "hp": 18, "speed": 5.4, "turn": 10.0,
		"attack_range": 1.3, "attack_dmg": 6, "cd_min": 0.9, "cd_max": 1.7,
		"attack_anims": ["Unarmed_Melee_Attack_Punch_A", "Unarmed_Melee_Attack_Punch_B", "Unarmed_Melee_Attack_Kick"],
		"attack_ts": 1.5, "ring": 3.6, "idle_anim": "Unarmed_Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.9, "ranged": false, "retreats": false, "enrage_at": 0.0,
	},
	"skeleton_mage": {
		"model": "Skeleton_Mage", "scale": 0.8, "hp": 32, "speed": 2.8, "turn": 8.0,
		"attack_range": 14.0, "attack_dmg": 13, "cd_min": 2.5, "cd_max": 3.7,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 9.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.9, "ranged": true, "retreats": false, "enrage_at": 0.0, "heals": true,
		"weapon_r": "Skeleton_Staff", "projectile_color": Color(0.5, 1.0, 0.4),
	},
	"skeleton_rogue": {
		"model": "Skeleton_Rogue", "scale": 0.75, "hp": 28, "speed": 4.8, "turn": 10.0,
		"attack_range": 1.5, "attack_dmg": 9, "cd_min": 1.2, "cd_max": 2.0,
		"attack_anims": ["1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"],
		"attack_ts": 1.45, "ring": 4.4, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": [],
		"stagger": 0.85, "ranged": false, "retreats": true, "enrage_at": 0.0, "dodges": true,
		"weapon_r": "Skeleton_Blade",
	},
	# «Костяной король» — не бьёт сам сильнее прочих, а раз в цикл поднимает
	# из земли подкрепление: свежих скелетов-миньонов.
	"skeleton_king": {
		"model": "Skeleton_Warrior", "scale": 1.35, "hp": 400, "speed": 2.5, "turn": 5.0,
		"attack_range": 2.7, "attack_dmg": 30, "cd_min": 1.7, "cd_max": 2.7,
		"attack_anims": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin", "2H_Melee_Attack_Slice"],
		"attack_ts": 0.92, "ring": 3.4, "idle_anim": "2H_Melee_Idle",
		"hit_anim": "Hit_A", "death_anim": "Death_A",
		"hide": [],
		"special": "summon", "special_cd": 12.0, "special_range": 30.0, "special_count": 2,
		"stagger": 0.05, "ranged": false, "retreats": false, "enrage_at": 0.5,
		"weapon_r": "Skeleton_Axe", "tint": Color(0.75, 1.0, 0.85),
	},
	# --- наёмник игроков: вольный гном-маг (вербуется в лагере за золото) ---
	"ally_mage": {
		"model": "Mage", "scale": 0.58, "hp": 65, "speed": 3.8, "turn": 9.0,
		"attack_range": 15.0, "attack_dmg": 13, "cd_min": 2.0, "cd_max": 3.0,
		"attack_anims": ["Spellcast_Shoot"],
		"attack_ts": 1.2, "ring": 8.5, "idle_anim": "Idle",
		"hit_anim": "Hit_B", "death_anim": "Death_B",
		"hide": ["Spellbook"],
		"stagger": 0.8, "ranged": true, "retreats": false, "enrage_at": 0.0,
		# не просто перекрашенный вражеский маг: приглушённый бронзовый убор и
		# плащ отдельно от мантии (вместо ровного оттенка на всей модели) —
		# но без блеска и свечения, чтобы не выбиваться из общей стилистики
		"friendly": true,
		"tint_map": {
			"Hat": Color(1.05, 0.82, 0.48), "Cape": Color(1.05, 0.82, 0.48),
			"Body": Color(1.02, 1.0, 0.9), "Arm": Color(1.02, 1.0, 0.9), "Leg": Color(1.02, 1.0, 0.9),
		},
		"projectile_color": Color(0.35, 0.75, 1.0),
	},
}

var game: Node = null
var gid := 0
var type := ""
var cfg: Dictionary = {}
var is_sim := false

var model: Node3D = null
var anim_player: AnimationPlayer = null
var materials: Array = []
var _materials_full := false  # true, когда собраны уникальные материалы ВСЕХ поверхностей
var current_anim := ""
var one_shot_until := 0.0

var hp := 1
var max_hp := 1
var facing := 0.0
var speed_mul := 1.0
var dmg_mul := 1.0
var enraged := false
var alive := true

var state := "spawn"
var state_time := 0.0
var age := 0.0
var alerted := false
var has_token := false
var attack_timer := 0.0
var attack_dur := 0.0
var attack_did_hit := false
var attack_swinging := false
var slot_angle := 0.0
var waypoint := Vector2.ZERO
var has_waypoint := false
var idle_for := 1.0
var investigate_pos := Vector2.ZERO
var investigating := false
var shout_lock := 0.0
var dead_time := 0.0
var target: Node3D = null
var retarget_timer := 0.0
var knockback := Vector3.ZERO
var last_attacker := 0
var last_attacker_gid := 0  # какой гном нанёс смертельный удар (для прокачки наёмника)
var friendly := false  # наёмник игроков: бьёт гномов, а не рыцарей
var elite := false  # редкий "золотой" гном: больше хп/урона, гарантированный жирный лут
var owner_id := 0      # кто нанял (для следования и зачёта убийств)
var ally_kills := 0    # счётчик убийств наёмника — для его собственной прокачки
var _hire_level := 0   # уровень и hp на момент найма — база для прокачки (ленивая фиксация)
var _hire_max_hp := 0
const ALLY_KILLS_PER_LEVEL := 3
const ALLY_MAX_LEVEL := 5

# --- босс-паттерны: у каждого босса свой фирменный спецприём (cfg.special) ---
var special_timer := 0.0
var is_special := false
var special_phase := ""
var special_time := 0.0

# выход из домика
var emerge_target := Vector2.ZERO

# привязка к дому (оверворлд): патруль и погоня не уходят далеко от точки спавна
var home_pos := Vector3.INF
const HOME_ROAM := 16.0    # радиус патрулирования вокруг дома
const HOME_LEASH := 42.0   # дальше этого от дома врага не уводит погоня

# уклонение разведчика
var sidestep_cd := 0.0
var sidestep_dir := Vector3.ZERO

# лечение шамана
var heal_cd := 3.0
var heal_target: Node3D = null

# навигация
var nav: NavigationAgent3D = null

# марионетка
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_loco := 0


var level := 1
var level_dmg_mult := 1.0
var lvl_label: Label3D = null
var net_sent_pos := Vector3(1e9, 0, 1e9)
var net_sent_rot := 1e9
var net_sent_loco := -1
var net_sent_hp := -1

var visual: GnomeVisual
var ai: GnomeAi


func setup(g: Node, id: int, gtype: String, pos: Vector3, emerge_to := Vector2.ZERO, lvl := 1, is_elite := false) -> void:
	level = maxi(1, lvl)
	level_dmg_mult = Quests.enemy_dmg_mult(level)
	game = g
	visual = GnomeVisual.new(self)
	ai = GnomeAi.new(self)
	gid = id
	type = gtype
	cfg = TYPES[gtype]
	is_sim = Net.is_server
	name = "G%d" % id
	friendly = cfg.get("friendly", false)
	if friendly:
		alerted = true # наёмник всегда начеку
	elif game.is_story():
		# в мире-путешествии враг привязан к округе своего дома;
		# на аренах волн/ПвП поводок не нужен — там весь мир и есть округа
		home_pos = pos
	elite = is_elite and not friendly

	hp = cfg.hp
	max_hp = cfg.hp
	if elite:
		max_hp = roundi(max_hp * 1.8)
		hp = max_hp
		dmg_mul = maxf(dmg_mul, 1.35)
	attack_timer = randf_range(cfg.cd_min, cfg.cd_max)
	if cfg.has("special"):
		special_timer = cfg.get("special_cd", 9.0) * 0.6 # первый спецприём раньше — бой сразу заявляет характер босса

	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * (cfg.scale / 0.6)
	cap.height = 1.1 * (cfg.scale / 0.6)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)

	model = game.models[cfg.model].instantiate()
	model.scale = Vector3.ONE * 0.01
	add_child(model)
	anim_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim_player.playback_default_blend_time = 0.15
	for a in LOCO:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	visual.prepare_model()
	if cfg.has("weapon_r"):
		visual.attach_weapon(cfg.weapon_r, "r")
	if cfg.has("weapon_l"):
		visual.attach_weapon(cfg.weapon_l, "l")
	if cfg.has("tint"):
		visual.ensure_unique_materials()
		for m in materials:
			if m is StandardMaterial3D:
				var t: Color = cfg.tint
				m.albedo_color = Color(m.albedo_color.r * t.r, m.albedo_color.g * t.g, m.albedo_color.b * t.b, 1.0)
				if cfg.get("glow", false):
					m.emission_enabled = true
					m.emission = t
					m.emission_energy_multiplier = 0.4
	elif cfg.has("tint_map"):
		# разные части модели красим по-разному (убор/плащ отдельно от мантии) —
		# читается как свой наряд, а не перекрашенная вражеская модель
		var tmap: Dictionary = cfg.tint_map
		for mesh_inst in model.find_children("*", "MeshInstance3D", true, false):
			if not mesh_inst.visible:
				continue
			var t: Color = Color.WHITE
			var matched := false
			for key in tmap:
				if String(mesh_inst.name).contains(key):
					t = tmap[key]
					matched = true
					break
			if not matched:
				continue
			for i in mesh_inst.get_surface_override_material_count():
				var mat = mesh_inst.get_active_material(i)
				if mat == null or not (mat is StandardMaterial3D):
					continue
				var m2: StandardMaterial3D = mat.duplicate()
				m2.albedo_color = Color(m2.albedo_color.r * t.r, m2.albedo_color.g * t.g, m2.albedo_color.b * t.b, 1.0)
				if cfg.get("glow", false):
					m2.emission_enabled = true
					m2.emission = t
					m2.emission_energy_multiplier = 0.35
				mesh_inst.set_surface_override_material(i, m2)
				materials.append(m2)
	if elite:
		visual.apply_elite_glow()
	global_position = pos

	if emerge_to != Vector2.ZERO:
		emerge_target = emerge_to
		facing = atan2(emerge_to.x - pos.x, emerge_to.y - pos.z)
	else:
		facing = randf_range(0, TAU)
		emerge_target = Vector2(pos.x, pos.z)

	if level >= 2 or elite:
		visual.refresh_level_label()

	if is_sim:
		nav = NavigationAgent3D.new()
		nav.path_desired_distance = 0.7
		nav.target_desired_distance = 0.5
		nav.radius = 0.4
		add_child(nav)

	_play("Idle")


## Прокачка наёмного мага: за N убитых им гномов — новый уровень (сильнее и живучее).
## Вызывается только на сервере (там же, где решается судьба гнома-жертвы).
func grant_ally_kill() -> void:
	# фиксируем базу найма при первом убийстве: max_hp здесь уже с учётом
	# множителя за размер отряда (см. Game.on_gnome_spawn), а level — уровень главы
	if _hire_level == 0:
		_hire_level = level
		_hire_max_hp = max_hp
	ally_kills += 1
	# уровни считаем ОТ уровня найма, а не от 1 — иначе наёмник высокого уровня
	# первые убийства «в никуда», а max_hp не проседает ниже базового
	var new_level: int = mini(_hire_level + ALLY_MAX_LEVEL - 1, _hire_level + ally_kills / ALLY_KILLS_PER_LEVEL)
	if new_level <= level:
		return
	var steps := new_level - _hire_level
	level = new_level
	max_hp = roundi(_hire_max_hp * (1.0 + 0.18 * steps))
	hp = max_hp
	dmg_mul = 1.0 + 0.2 * steps
	var maxed: bool = steps >= ALLY_MAX_LEVEL - 1
	game.bcast_gnome_event(gid, "levelup", [level, maxed, owner_id])


func _play(anim: String, custom_speed: float = 1.0, force := false) -> float:
	if anim_player == null or not anim_player.has_animation(anim):
		return 0.0
	if current_anim == anim and not force:
		return anim_player.get_animation(anim).length / absf(custom_speed)
	current_anim = anim
	anim_player.play(anim, -1, custom_speed)
	if custom_speed != 1.0 or force:
		anim_player.seek(0.0)
	return anim_player.get_animation(anim).length / absf(custom_speed)


func loco_index() -> int:
	var i := LOCO.find(current_anim)
	return maxi(i, 0)


# ---------------------------------------------------------------------------
# События (приходят на все машины, включая сервер — call_local)
# ---------------------------------------------------------------------------
func on_event(ev: String, data: Array) -> void:
	visual.on_event(ev, data)


# ---------------------------------------------------------------------------
# Труп-регдолл (создаёт GnomeVisual)
# ---------------------------------------------------------------------------
var corpse: RigidBody3D = null


# ---------------------------------------------------------------------------
# Симуляция
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	age += delta
	state_time += delta

	if age < 0.35:
		model.scale = Vector3.ONE * lerpf(0.01, cfg.scale, age / 0.35)
	elif model.scale.x != cfg.scale:
		model.scale = Vector3.ONE * cfg.scale

	if state == "dead":
		dead_time += delta
		if dead_time > 2.4:
			var k := clampf((dead_time - 2.4) / 1.0, 0, 1)
			for m in materials:
				if m is StandardMaterial3D:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color.a = 1.0 - k
			if k >= 1.0:
				game.free_gnome_local(gid)
		return

	if is_sim:
		ai.sim(delta)
	else:
		_puppet(delta)
	model.rotation.y = facing


func _puppet(delta: float) -> void:
	global_position = global_position.lerp(Vector3(net_pos.x, 0, net_pos.z), minf(1.0, 12 * delta))
	facing = lerp_angle(facing, net_rot, minf(1.0, 10 * delta))
	if age > one_shot_until:
		_play(LOCO[net_loco])


func apply_net_state(x: float, z: float, rot: float, loco: int, new_hp: int) -> void:
	net_pos = Vector3(x, 0, z)
	net_rot = rot
	net_loco = loco
	hp = new_hp


# --- серверный ИИ: машина состояний, восприятие, движение — в GnomeAi ------
func become_alerted(shout: bool) -> void:
	ai.become_alerted(shout)


func server_take_damage(dmg: int, from_pos: Vector3, crit: bool) -> void:
	ai.take_damage(dmg, from_pos, crit)


func _pick_target(delta: float) -> void:
	ai.pick_target(delta)